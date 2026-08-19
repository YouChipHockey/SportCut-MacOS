//
//  MarkupPlaylistPanelStore.swift
//  Youchip-Stat
//
//  Плейлисты режима просмотра прямо в окне таймлайнов разметки.
//
//  Панель — не копия кода, а те же вьюхи просмотра (`SportCutPlaylistsView`,
//  `SportCutTimelineView`), встроенные в окно разметки: иначе пришлось бы вести две ветки
//  одной и той же логики (плейлисты, ресайз клипов, дроп тегов, фильмы).
//
//  Отличие от режима просмотра одно: сессия не задана снаружи — сначала её выбирают
//  (или создают) прямо в панели.
//

import Foundation
import Combine
import AppKit

final class MarkupPlaylistPanelStore: ObservableObject {

    static let shared = MarkupPlaylistPanelStore()

    /// Что показывает нижняя зона окна таймлайнов.
    enum TimelineTab {
        case markup
        case playlist
    }

    @Published var isPanelOpen = false
    /// Выбранная сессия просмотра. nil — показываем экран выбора/создания.
    @Published private(set) var sessionID: UUID?
    @Published var timelineTab: TimelineTab = .markup
    /// Плейлист, открытый сейчас в панели — для пункта «Добавить в текущий плейлист».
    @Published var currentPlaylistID: UUID?
    /// Клипы/фильм играют в главном окне видео вместо разметки.
    @Published private(set) var isPlaybackActive = false

    /// Плеер просмотра. Живёт столько же, сколько окно разметки: его `AVPlayer` показывается
    /// в главном видео-окне, пока идёт просмотр клипов.
    let playerManager = SportCutPlayerManager()

    private var cancellables = Set<AnyCancellable>()
    /// Подпись привязок источников выбранной сессии — чтобы не переконфигурировать плеер зря.
    private var configuredSourcesSignature: String?

    private init() {
        // Любое воспроизведение из панели (клип, фильм, плейлист) переводит главное окно видео
        // в режим просмотра — отдельного вызова из каждой кнопки не нужно.
        playerManager.$currentEvent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                guard event != nil else { return }
                self.activatePlaybackIfNeeded()
            }
            .store(in: &cancellables)

        // Источники сессии плееру отдаём мы: окна просмотра здесь нет, а без них он не найдёт
        // медиа события. Пересобираем при смене привязок — например когда лайв дописался и у
        // источника появился файл вместо пустой закладки.
        SportCutSessionManager.shared.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configurePlayerSourcesIfNeeded() }
            .store(in: &cancellables)
    }

    private func configurePlayerSourcesIfNeeded(force: Bool = false) {
        guard let sessionID,
              let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else {
            configuredSourcesSignature = nil
            return
        }
        let signature = session.sources
            .map { "\($0.id.uuidString):\($0.videoBookmark.count)" }
            .joined(separator: "|")
        guard force || signature != configuredSourcesSignature else { return }
        configuredSourcesSignature = signature
        playerManager.configure(sources: session.sources)
    }

    // MARK: - Панель

    func togglePanel() {
        if isPanelOpen {
            closePanel()
        } else {
            openPanel()
        }
    }

    func openPanel() {
        guard !isPanelOpen else { return }
        // В ЛАЙВЕ панель не открываем — единая точка запрета (кнопка в шапке таймлайнов тоже
        // выключена). Панель играет клипы плейлиста прямо в окне видео, а там идёт живая запись.
        guard !VideoPlayerManager.shared.isLiveMode else { return }
        isPanelOpen = true
        // Наблюдатель времени двигает плейлист по клипам и рисует прогресс — в просмотре его
        // ставит `SportCutMainView`, здесь окна просмотра нет, ставим сами.
        playerManager.setupTimeObserver()
        playerManager.startDrawingCheckTimer()
        configurePlayerSourcesIfNeeded(force: true)
        startLiveSegmentRefreshIfNeeded()
    }

    func closePanel() {
        returnToMarkup()
        playerManager.removeTimeObserver()
        playerManager.stopDrawingCheckTimer()
        stopLiveSegmentRefreshIfNeeded()
        isPanelOpen = false
        timelineTab = .markup
    }

    /// В лайве клипы играются из склейки уже записанных сегментов (как пересмотр), а сегменты
    /// закрываются ротацией. Пока панель открыта, крутим ту же ротацию, что и пересмотр, —
    /// иначе свежая разметка попадала бы в клип с задержкой до 30 секунд (тик резервной копии).
    private func startLiveSegmentRefreshIfNeeded() {
        guard WindowsManager.shared.isLiveSession else { return }
        LiveStreamManager.shared.startReviewRefresher()
    }

    private func stopLiveSegmentRefreshIfNeeded() {
        guard WindowsManager.shared.isLiveSession else { return }
        // Пересмотр открыт — ротация нужна ему, не трогаем.
        guard !VideoPlayerManager.shared.isReviewMode else { return }
        LiveStreamManager.shared.stopReviewRefresher()
    }

    /// Выход из проекта разметки — панель не должна пережить закрытие окон.
    func resetForProjectClose() {
        returnToMarkup()
        playerManager.removeTimeObserver()
        playerManager.stopDrawingCheckTimer()
        stopLiveSegmentRefreshIfNeeded()
        isPanelOpen = false
        configuredSourcesSignature = nil
        sessionID = nil
        currentPlaylistID = nil
        timelineTab = .markup
    }

    /// Выбор сессии просмотра: дальше в панели открываются её плейлисты.
    func select(sessionID: UUID) {
        self.sessionID = sessionID
        playerManager.sessionID = sessionID
        currentPlaylistID = nil
        configuredSourcesSignature = nil
        configurePlayerSourcesIfNeeded(force: true)
    }

    /// Назад к выбору/созданию сессии — с выходом из просмотра клипов.
    func backToSessionSelection() {
        returnToMarkup()
        sessionID = nil
        currentPlaylistID = nil
        timelineTab = .markup
    }

    /// Сессию удалили извне — панель не должна остаться с «висящим» id.
    func dropSessionIfMissing() {
        guard let id = sessionID else { return }
        guard !SportCutSessionManager.shared.sessions.contains(where: { $0.id == id }) else { return }
        backToSessionSelection()
    }

    // MARK: - Воспроизведение в окне разметки

    private func activatePlaybackIfNeeded() {
        guard !isPlaybackActive else { return }
        VideoPlayerManager.shared.player?.pause()
        isPlaybackActive = true
    }

    /// Возврат к обычному видео разметки: клипы останавливаются, окно снова показывает проект.
    func returnToMarkup() {
        guard isPlaybackActive else { return }
        playerManager.stopPlayback()
        isPlaybackActive = false
    }

    /// Пользователь вернулся к разметке действием (кликнул тег, поставил новый) — не кнопкой.
    func returnToMarkupOnMarkupInteraction() {
        returnToMarkup()
    }

    // MARK: - Сессии

    /// Сессии просмотра, в которых уже есть текущий проект разметки.
    func sessionsForCurrentProject() -> [SportCutSession] {
        let projectID = currentProjectID
        guard !projectID.isEmpty else { return [] }
        return SportCutSessionManager.shared.sessionsForProject(projectID: projectID)
    }

    /// id текущего проекта разметки (во время лайва — id живой сессии).
    var currentProjectID: String {
        let windows = WindowsManager.shared
        if windows.isLiveSession, let liveId = windows.liveVideoId { return liveId }
        return windows.currentVideoId
    }

    /// Создаёт сессию просмотра с текущим проектом и сразу её открывает.
    /// Тот же путь, что «Просмотр → новая сессия», только без открытия отдельного окна.
    @discardableResult
    func createSessionForCurrentProject() -> SportCutSession? {
        guard LicenseLimitsManager.shared.canCreateViewingSession else { return nil }
        let manager = SportCutSessionManager.shared
        let windows = WindowsManager.shared

        var session: SportCutSession
        if windows.isLiveSession, let liveId = windows.liveVideoId {
            let name = windows.liveFileName ?? ""
            session = manager.createSession(name: name)
            manager.addLiveProjectSource(
                to: &session,
                projectID: liveId,
                name: name,
                timelines: TimelineDataManager.shared.lines
            )
        } else {
            guard let file = VideoFilesManager.shared.files.first(where: { $0.videoData.id == windows.currentVideoId }) else {
                return nil
            }
            session = manager.createSession(name: file.name)
            manager.addProjectSource(to: &session, file: file)
        }

        if session.playlistGroups.isEmpty {
            manager.addPlaylistGroup(to: &session, name: ^String.Titles.sportCutDefaultGroupName)
        }
        select(sessionID: session.id)
        return session
    }

    // MARK: - Перенос тегов в текущий плейлист

    /// Можно ли положить теги в открытый плейлист прямо сейчас.
    var canAddToCurrentPlaylist: Bool {
        isPanelOpen && sessionID != nil && currentPlaylistID != nil
    }

    // MARK: - Выбор плейлиста (лист «Добавить в плейлист…»)

    /// Что кладём в плейлист: конкретный тег (с учётом ⌘-пачки, если он в неё входит) или
    /// только текущую ⌘-выборку (из плашки массового выбора).
    enum AddToPlaylistSource {
        case stamp(line: TimelineLine, stamp: TimelineStamp)
        case selection
    }

    /// Один плейлист текущей сессии — для списка в листе выбора.
    struct PlaylistOption: Identifiable {
        let id: UUID
        let groupIndex: Int
        let groupName: String
        let name: String
        let eventCount: Int
    }

    /// Есть ли выбранная в панели сессия просмотра, куда можно класть теги.
    var hasSelectedSession: Bool { sessionID != nil }

    /// Имя выбранной сессии (для шапки листа).
    var selectedSessionName: String? {
        guard let sessionID else { return nil }
        return SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID })?.name
    }

    /// Плейлисты выбранной сессии (плоско, по всем группам).
    func playlistsForCurrentSession() -> [PlaylistOption] {
        guard let sessionID,
              let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return [] }
        var result: [PlaylistOption] = []
        for (gi, group) in session.playlistGroups.enumerated() {
            for playlist in group.playlists {
                result.append(PlaylistOption(
                    id: playlist.id,
                    groupIndex: gi,
                    groupName: group.name,
                    name: playlist.name,
                    eventCount: playlist.events.count
                ))
            }
        }
        return result
    }

    /// Разрешает источник в события просмотра для текущей сессии.
    private func resolveEvents(for source: AddToPlaylistSource, sessionID: UUID) -> [SportCutEvent]? {
        let windows = WindowsManager.shared
        switch source {
        case let .stamp(line, stamp):
            guard let payload = windows.makeMarkupPlaylistDragPayload(line: line, stamp: stamp) else { return nil }
            return windows.resolveMarkupPlaylistEvents(payload: payload, sessionID: sessionID)
        case .selection:
            guard let data = windows.encodeMarkupPlaylistDragDataForSelectionOnly(),
                  let payload = try? JSONDecoder().decode(MarkupStampsBatchPlaylistDragPayload.self, from: data) else { return nil }
            return windows.resolveMarkupPlaylistEvents(payload: payload, sessionID: sessionID)
        }
    }

    /// Кладёт источник в существующий плейлист выбранной сессии.
    func addToExistingPlaylist(source: AddToPlaylistSource, playlistID: UUID) {
        guard let sessionID,
              let events = resolveEvents(for: source, sessionID: sessionID), !events.isEmpty,
              let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
              let groupIndex = session.playlistGroups.firstIndex(where: { group in
                  group.playlists.contains { $0.id == playlistID }
              }),
              let playlist = session.playlistGroups[groupIndex].playlists.first(where: { $0.id == playlistID })
        else { return }
        WindowsManager.shared.insertMarkupEventsIntoSportCutPlaylist(
            events: events,
            sessionID: sessionID,
            groupIndex: groupIndex,
            playlistID: playlistID,
            at: playlist.events.count
        )
    }

    /// Создаёт новый плейлист в выбранной сессии и сразу кладёт туда источник.
    func addToNewPlaylist(source: AddToPlaylistSource, name: String?) {
        guard let sessionID else { return }
        let manager = SportCutSessionManager.shared
        guard var session = manager.sessions.first(where: { $0.id == sessionID }) else { return }
        if session.playlistGroups.isEmpty {
            manager.addPlaylistGroup(to: &session, name: ^String.Titles.sportCutDefaultGroupName)
        }
        guard var session2 = manager.sessions.first(where: { $0.id == sessionID }) else { return }
        let groupIndex = session2.playlistGroups.count - 1
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        manager.addPlaylist(to: &session2, groupIndex: groupIndex, name: (trimmed?.isEmpty == false) ? trimmed : nil)
        guard let session3 = manager.sessions.first(where: { $0.id == sessionID }),
              groupIndex < session3.playlistGroups.count,
              let newPlaylist = session3.playlistGroups[groupIndex].playlists.last else { return }
        addToExistingPlaylist(source: source, playlistID: newPlaylist.id)
        currentPlaylistID = newPlaylist.id
    }

    /// Кладёт штамп (или всю ⌘-пачку, если кликнутый штамп в неё входит) в открытый плейлист.
    func addStampsToCurrentPlaylist(line: TimelineLine, stamp: TimelineStamp) {
        guard let sessionID, let playlistID = currentPlaylistID else { return }
        let windows = WindowsManager.shared
        guard let payload = windows.makeMarkupPlaylistDragPayload(line: line, stamp: stamp),
              let events = windows.resolveMarkupPlaylistEvents(payload: payload, sessionID: sessionID),
              !events.isEmpty else { return }
        guard let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
              let groupIndex = session.playlistGroups.firstIndex(where: { group in
                  group.playlists.contains { $0.id == playlistID }
              }),
              let playlist = session.playlistGroups[groupIndex].playlists.first(where: { $0.id == playlistID })
        else { return }

        windows.insertMarkupEventsIntoSportCutPlaylist(
            events: events,
            sessionID: sessionID,
            groupIndex: groupIndex,
            playlistID: playlistID,
            at: playlist.events.count
        )
    }
}
