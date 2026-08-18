//
//  SportCutSessionManager.swift
//  Youchip-Stat
//

import Foundation
import Combine
import AVFoundation

class SportCutSessionManager: ObservableObject {
    static let shared = SportCutSessionManager()
    
    @Published var sessions: [SportCutSession] = []
    @Published var currentSession: SportCutSession?
    
    private let sessionsKey = "SportCutSessions_v1"
    
    private init() {
        loadSessions()
    }
    
    func sessionsForProject(projectID: String) -> [SportCutSession] {
        guard !projectID.isEmpty else { return [] }
        return sessions.filter { sess in
            sess.sources.contains { $0.projectID == projectID }
        }
    }

    // MARK: - CRUD

    func createSession(name: String) -> SportCutSession {
        // Создание сессии просмотра расходует 1 лимит (при неактивной лицензии). Вызывающая сторона
        // обязана заранее проверить `LicenseLimitsManager.shared.canCreateViewingSession`.
        LicenseLimitsManager.shared.consumeViewingSessionIfNeeded()
        let session = SportCutSession(name: name)
        sessions.append(session)
        saveSessions()
        return session
    }
    
    func deleteSession(_ session: SportCutSession) {
        sessions.removeAll { $0.id == session.id }
        if currentSession?.id == session.id {
            currentSession = nil
        }
        // Внутренняя папка сохранённых клипов сессии больше не нужна.
        SportCutClipCache.removeAllClips(sessionID: session.id)
        saveSessions()
    }

    func updateSession(_ session: SportCutSession) {
        updateSession(session, runClipCache: true)
    }

    /// `runClipCache: false` — для синхронизации разметки: плейлисты (а значит и их клипы)
    /// при ней не меняются, а автокэш на каждый штамп во время лайва — это лишний обход диска.
    func updateSession(_ session: SportCutSession, runClipCache: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        // Must replace the whole array: subscript assignment does not reliably
        // trigger @Published, so SwiftUI would not refresh until full re-entry.
        var next = sessions
        next[index] = session
        sessions = next
        if currentSession?.id == session.id {
            currentSession = session
        }
        saveSessions()
        guard runClipCache else { return }
        // Клипы плейлистов сохраняются автоматически (чтобы играли даже без оригинала),
        // а осиротевшие (после удаления плейлиста/группы/эпизода) — удаляются.
        SportCutClipCache.autoCacheIfNeeded(session: session)
        SportCutClipCache.pruneOrphanedClips(for: session)
    }
    
    // MARK: - Source management
    
    func addProjectSource(to session: inout SportCutSession, file: FilesFile) {
        guard let url = file.url else { return }
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }

        let timelines = file.timelines
        let tagLibrary = TagLibraryManager.shared
        let lib = Self.augmentedLibrary(
            timelines: timelines,
            tags: tagLibrary.allTags,
            tagGroups: tagLibrary.allTagGroups,
            labels: tagLibrary.allLabels,
            labelGroups: tagLibrary.allLabelGroups,
            timeEvents: tagLibrary.allTimeEvents
        )

        let source = SportCutSource(
            name: file.name,
            videoBookmark: bookmark,
            timelines: timelines,
            isStandaloneVideo: false,
            projectID: file.id,
            tags: lib.tags,
            tagGroups: lib.tagGroups,
            labels: lib.labels,
            labelGroups: lib.labelGroups,
            timeEvents: lib.timeEvents
        )

        session.sources.append(source)
        updateSession(session)
    }

    /// Builds a tag/label library snapshot for a SportCut source, augmenting the current
    /// global pool with synthetic entries derived from the timeline stamps themselves.
    ///
    /// Markup imported from other tools (Nacsport / SportCut / Sportscode XML, etc.) may reference
    /// tags and labels whose collection was never installed locally. Those entities are
    /// still fully described inline on each stamp (`stamp.label`, `stamp.labels`), so we
    /// reconstruct them here. This is purely additive: anything already present in the
    /// pool wins, we only fill the gaps — so exporting cuts by tag or label works even
    /// with no collection, without changing behavior when the collection *is* present.
    static func augmentedLibrary(
        timelines: [TimelineLine],
        tags: [Tag],
        tagGroups: [TagGroup],
        labels: [Label],
        labelGroups: [LabelGroupData],
        timeEvents: [TimeEvent]
    ) -> (tags: [Tag], tagGroups: [TagGroup], labels: [Label], labelGroups: [LabelGroupData], timeEvents: [TimeEvent]) {
        var tagsById = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var labelsById = Dictionary(labels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var labelGroupsById = Dictionary(labelGroups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Preserve the original ordering so appended synthetic entries stay stable.
        var tagOrder = tags.map(\.id)
        var labelOrder = labels.map(\.id)
        var labelGroupOrder = labelGroups.map(\.id)

        for line in timelines {
            for stamp in line.stamps {
                // Tags: the stamp carries the display name of its main tag inline.
                for ref in stamp.tagRefs where tagsById[ref.id] == nil {
                    tagsById[ref.id] = Tag(
                        id: ref.id,
                        primaryID: stamp.primaryID,
                        name: stamp.label,
                        description: "",
                        color: stamp.colorHex,
                        defaultTimeBefore: 0,
                        defaultTimeAfter: 0,
                        collection: nil,
                        lablesGroup: [],
                        hotkey: nil,
                        labelHotkeys: nil,
                        mapEnabled: false,
                        isInterval: true
                    )
                    tagOrder.append(ref.id)
                }

                // Labels: `FullLabelWithGroup` embeds the name/description and group id.
                for lbl in stamp.labels {
                    if labelsById[lbl.id] == nil, !lbl.name.isEmpty {
                        labelsById[lbl.id] = Label(id: lbl.id, name: lbl.name, description: lbl.description)
                        labelOrder.append(lbl.id)
                    }
                    let gid = lbl.lableGroupId
                    guard !gid.isEmpty, labelsById[lbl.id] != nil else { continue }
                    if var group = labelGroupsById[gid] {
                        if !group.lables.contains(lbl.id) {
                            group.lables.append(lbl.id)
                            labelGroupsById[gid] = group
                        }
                    } else {
                        // Имя настоящей группы неизвестно (импорт без коллекции) — именуем группу
                        // её id, чтобы фильтр (hasResolvedName) не показывал её как отдельную «Лейблы».
                        // В подписях таблицы/экспорта/вотермарки используется labelGroupDisplayName.
                        labelGroupsById[gid] = LabelGroupData(id: gid, name: gid, lables: [lbl.id])
                        labelGroupOrder.append(gid)
                    }
                }
            }
        }

        return (
            tags: tagOrder.compactMap { tagsById[$0] },
            tagGroups: tagGroups,
            labels: labelOrder.compactMap { labelsById[$0] },
            labelGroups: labelGroupOrder.compactMap { labelGroupsById[$0] },
            timeEvents: timeEvents
        )
    }

    func addVideoSource(to session: inout SportCutSession, url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        
        let videoName = url.deletingPathExtension().lastPathComponent
        let tagID = UUID().uuidString
        let lineID = UUID()
        
        let fakeTag = Tag(
            id: tagID,
            primaryID: nil,
            name: videoName,
            description: "",
            color: "4A90D9",
            defaultTimeBefore: 0,
            defaultTimeAfter: 0,
            collection: nil,
            lablesGroup: [],
            hotkey: nil,
            labelHotkeys: nil,
            mapEnabled: nil,
            isInterval: nil
        )
        
        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        
        let stamp = TimelineStamp(
            id: UUID(),
            tagRefs: [StampTagRef(id: tagID, tagGroupId: "")],
            primaryID: nil,
            timeStartSeconds: 0,
            timeFinishSeconds: duration > 0 ? duration : 3600,
            colorHex: "4A90D9",
            label: videoName,
            labels: [],
            timeEvents: []
        )
        
        let timeline = TimelineLine(
            id: lineID,
            name: videoName,
            stamps: [stamp],
            tagIdForMode: tagID
        )
        
        let source = SportCutSource(
            name: videoName,
            videoBookmark: bookmark,
            timelines: [timeline],
            isStandaloneVideo: true,
            tags: [fakeTag],
            tagGroups: [],
            labels: [],
            labelGroups: [],
            timeEvents: []
        )
        
        session.sources.append(source)
        updateSession(session)
    }
    
    func removeSource(from session: inout SportCutSession, sourceID: UUID) {
        session.sources.removeAll { $0.id == sourceID }
        updateSession(session)
    }

    /// Refreshes timelines and tag library snapshot for a markup project source (live markup → SportCut).
    func syncProjectSource(from file: FilesFile, in session: inout SportCutSession) {
        guard let idx = session.sources.firstIndex(where: { $0.projectID == file.id }) else { return }
        let old = session.sources[idx]
        let tagLibrary = TagLibraryManager.shared
        let lib = Self.augmentedLibrary(
            timelines: file.timelines,
            tags: tagLibrary.allTags,
            tagGroups: tagLibrary.allTagGroups,
            labels: tagLibrary.allLabels,
            labelGroups: tagLibrary.allLabelGroups,
            timeEvents: tagLibrary.allTimeEvents
        )
        session.sources[idx] = SportCutSource(
            id: old.id,
            name: file.name,
            videoBookmark: old.videoBookmark,
            timelines: file.timelines,
            isStandaloneVideo: false,
            projectID: file.id,
            tags: lib.tags,
            tagGroups: lib.tagGroups,
            labels: lib.labels,
            labelGroups: lib.labelGroups,
            timeEvents: lib.timeEvents
        )
        updateSession(session)
    }

    func updateStampTime(in session: inout SportCutSession, sourceID: UUID, lineID: UUID, stampID: UUID, newStart: Double?, newEnd: Double?) {
        guard let si = session.sources.firstIndex(where: { $0.id == sourceID }),
              let li = session.sources[si].timelines.firstIndex(where: { $0.id == lineID }),
              let sti = session.sources[si].timelines[li].stamps.firstIndex(where: { $0.id == stampID }) else { return }
        var stamp = session.sources[si].timelines[li].stamps[sti]
        let previousStart = stamp.timeStartSeconds
        let previousFinish = stamp.timeFinishSeconds
        if let newStart {
            stamp.timeStartSeconds = min(newStart, stamp.timeFinishSeconds - 0.5)
        }
        if let newEnd {
            stamp.timeFinishSeconds = max(newEnd, stamp.timeStartSeconds + 0.5)
        }
        // Штамп счётчика: под новую длину доводим и его показания, сохраняя темп.
        if var info = stamp.clockInfo {
            info.rescale(
                oldStart: previousStart,
                oldFinish: previousFinish,
                newStart: stamp.timeStartSeconds,
                newFinish: stamp.timeFinishSeconds
            )
            stamp.clockInfo = info
        }
        session.sources[si].timelines[li].stamps[sti] = stamp
        let lineID = session.sources[si].timelines[li].id
        pushTimelinesToMarkupModel(session: session, sourceIndex: si, editedStampID: stamp.id, editedLineID: lineID)
        updateSession(session)
    }

    /// Тот же путь хранения, что у `TimelineDataManager.updateTimelines` + немедленная запись на диск.
    private func pushTimelinesToMarkupModel(
        session: SportCutSession,
        sourceIndex: Int,
        editedStampID: UUID,
        editedLineID: UUID
    ) {
        let source = session.sources[sourceIndex]
        guard let projectID = source.projectID else { return }
        TimelineDataManager.shared.persistProjectTimelinesForMarkupModel(
            source.timelines,
            videoId: projectID,
            editedStampID: editedStampID,
            editedLineID: editedLineID
        )
    }
    
    // MARK: - Playlist management
    
    func addPlaylistGroup(to session: inout SportCutSession, name: String) {
        let group = SportCutPlaylistGroup(name: name)
        session.playlistGroups.append(group)
        updateSession(session)
    }
    
    func addPlaylist(to session: inout SportCutSession, groupIndex: Int, name: String?) {
        guard groupIndex < session.playlistGroups.count else { return }
        let playlistCount = session.playlistGroups[groupIndex].playlists.count
        let playlistName = name ?? "\(playlistCount + 1)"
        let playlist = SportCutPlaylist(name: playlistName)
        session.playlistGroups[groupIndex].playlists.append(playlist)
        updateSession(session)
    }
    
    func duplicatePlaylist(in session: inout SportCutSession, groupIndex: Int, playlistIndex: Int) {
        guard groupIndex < session.playlistGroups.count,
              playlistIndex < session.playlistGroups[groupIndex].playlists.count else { return }
        
        let original = session.playlistGroups[groupIndex].playlists[playlistIndex]
        let copy = SportCutPlaylist(
            name: "\(original.name) (копия)",
            events: original.events
        )
        session.playlistGroups[groupIndex].playlists.insert(copy, after: playlistIndex)
        updateSession(session)
    }

    // MARK: - Slides (title cards between clips)

    /// Находит плейлист по id в любой группе и применяет мутацию.
    private func mutatePlaylist(in session: inout SportCutSession, playlistID: UUID, _ body: (inout SportCutPlaylist) -> Void) {
        for gi in session.playlistGroups.indices {
            if let pi = session.playlistGroups[gi].playlists.firstIndex(where: { $0.id == playlistID }) {
                body(&session.playlistGroups[gi].playlists[pi])
                updateSession(session)
                return
            }
        }
    }

    func addSlide(in session: inout SportCutSession, playlistID: UUID, slide: SportCutSlide) {
        mutatePlaylist(in: &session, playlistID: playlistID) { $0.slides.append(slide) }
    }

    func updateSlide(in session: inout SportCutSession, playlistID: UUID, slide: SportCutSlide) {
        mutatePlaylist(in: &session, playlistID: playlistID) { playlist in
            if let idx = playlist.slides.firstIndex(where: { $0.id == slide.id }) {
                playlist.slides[idx] = slide
            }
        }
    }

    func removeSlide(in session: inout SportCutSession, playlistID: UUID, slideID: UUID) {
        mutatePlaylist(in: &session, playlistID: playlistID) { $0.slides.removeAll { $0.id == slideID } }
    }

    /// Перемещает плейлист в другую группу (сохраняя все его события/комментарии/рисунки).
    func movePlaylist(in session: inout SportCutSession, playlistID: UUID, toGroupIndex: Int) {
        guard toGroupIndex >= 0, toGroupIndex < session.playlistGroups.count else { return }
        guard let sourceGroupIndex = session.playlistGroups.firstIndex(where: {
            $0.playlists.contains(where: { $0.id == playlistID })
        }) else { return }
        guard sourceGroupIndex != toGroupIndex,
              let playlistIndex = session.playlistGroups[sourceGroupIndex].playlists.firstIndex(where: { $0.id == playlistID }) else { return }

        let playlist = session.playlistGroups[sourceGroupIndex].playlists.remove(at: playlistIndex)
        session.playlistGroups[toGroupIndex].playlists.append(playlist)
        updateSession(session)
    }

    // MARK: - Persistence
    
    private func saveSessions() {
        do {
            let data = try JSONEncoder().encode(sessions)
            UserDefaults.standard.set(data, forKey: sessionsKey)
        } catch {
            print("SportCutSessionManager: Failed to save sessions: \(error)")
        }
    }
    
    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey) else { return }
        do {
            sessions = try JSONDecoder().decode([SportCutSession].self, from: data)
        } catch {
            sessions = []
            print("SportCutSessionManager: Failed to load sessions: \(error)")
        }
    }
}

private extension Array {
    mutating func insert(_ element: Element, after index: Int) {
        if index + 1 >= count {
            append(element)
        } else {
            insert(element, at: index + 1)
        }
    }
}
