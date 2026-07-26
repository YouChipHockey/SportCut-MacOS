//
//  SportCutModels.swift
//  Youchip-Stat
//

import Foundation
import AVFoundation

// MARK: - Session

struct SportCutSession: Identifiable, Codable {
    let id: UUID
    var name: String
    var sources: [SportCutSource]
    var playlistGroups: [SportCutPlaylistGroup]
    let createdAt: Date
    
    init(id: UUID = UUID(), name: String, sources: [SportCutSource] = [], playlistGroups: [SportCutPlaylistGroup] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.sources = sources
        self.playlistGroups = playlistGroups
        self.createdAt = createdAt
    }
    
    var allEvents: [SportCutEvent] {
        sources.flatMap { source in
            source.timelines.flatMap { line in
                line.stamps.map { stamp in
                    SportCutEvent.from(stamp: stamp, line: line, source: source)
                }
            }
        }
    }

    /// Rebuilds a playlist/table event from the current timelines so times and labels match live markup.
    func timelineResolvedEvent(for event: SportCutEvent) -> SportCutEvent {
        guard let source = sources.first(where: { $0.id == event.sourceID }) else { return event }
        for line in source.timelines {
            if let stamp = line.stamps.first(where: { $0.id == event.stampID }) {
                return SportCutEvent.from(stamp: stamp, line: line, source: source)
            }
        }
        return event
    }
}

// MARK: - Source (project or standalone video)

struct SportCutSource: Identifiable, Codable {
    let id: UUID
    var name: String
    let videoBookmark: Data
    var timelines: [TimelineLine]
    let isStandaloneVideo: Bool
    let projectID: String?
    
    var tags: [Tag]
    var tagGroups: [TagGroup]
    var labels: [Label]
    var labelGroups: [LabelGroupData]
    var timeEvents: [TimeEvent]
    
    init(id: UUID = UUID(), name: String, videoBookmark: Data, timelines: [TimelineLine], isStandaloneVideo: Bool, projectID: String? = nil, tags: [Tag] = [], tagGroups: [TagGroup] = [], labels: [Label] = [], labelGroups: [LabelGroupData] = [], timeEvents: [TimeEvent] = []) {
        self.id = id
        self.name = name
        self.videoBookmark = videoBookmark
        self.timelines = timelines
        self.isStandaloneVideo = isStandaloneVideo
        self.projectID = projectID
        self.tags = tags
        self.tagGroups = tagGroups
        self.labels = labels
        self.labelGroups = labelGroups
        self.timeEvents = timeEvents
    }
    
    /// Returns the full video duration (seconds) by quickly reading the asset. Falls back to 0 if unavailable.
    func videoDuration() -> Double {
        guard let url = resolveVideoURL() else { return 0 }
        defer { url.stopAccessingSecurityScopedResource() }
        let asset = AVAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }

    func resolveVideoURL() -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: videoBookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    /// For background export/processing on the calling thread. Pair with `url.stopAccessingSecurityScopedResource()`.
    func mediaAccessURL() -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: videoBookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }
    
    func findTag(byID id: String) -> Tag? {
        tags.first { $0.id == id }
    }
    
    func findTagGroup(forTagID tagID: String) -> TagGroup? {
        tagGroups.first { $0.tags.contains(tagID) }
    }
    
    func findLabel(byID id: String) -> Label? {
        labels.first { $0.id == id }
    }
}

// MARK: - Event (stamp with source reference)

struct SportCutEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let sourceID: UUID
    let stampID: UUID
    let lineID: UUID
    let mainTagID: String
    let tagName: String
    let lineName: String
    let startTime: Double
    let duration: Double
    let color: String
    let tagGroupName: String?
    let labelIDs: [String]
    let eventIDs: [String]
    /// Если задан — это не клип, а титульный слайд (заставка), встроенный в фильм плейлиста.
    var slideID: UUID? = nil

    var isSlide: Bool { slideID != nil }

    /// Синтетический источник для слайд-событий (не реальный источник сессии).
    static let slideSourceID = UUID(uuidString: "51D0E000-0000-0000-0000-000000000000")!

    /// Строит слайд-событие из слайда (для встраивания в фильм между клипами).
    static func slideEvent(from slide: SportCutSlide) -> SportCutEvent {
        SportCutEvent(
            id: UUID(),
            sourceID: slideSourceID,
            stampID: slide.id,
            lineID: slide.id,
            mainTagID: "",
            tagName: slide.title,
            lineName: "",
            startTime: 0,
            duration: slide.durationSeconds,
            color: slide.backgroundColorHex,
            tagGroupName: nil,
            labelIDs: [],
            eventIDs: [],
            slideID: slide.id
        )
    }

    static func == (lhs: SportCutEvent, rhs: SportCutEvent) -> Bool {
        lhs.stampID == rhs.stampID && lhs.sourceID == rhs.sourceID
    }
    
    static func from(stamp: TimelineStamp, line: TimelineLine, source: SportCutSource) -> SportCutEvent {
        let tag = source.findTag(byID: stamp.idTag)
        let tagGroup = source.findTagGroup(forTagID: stamp.idTag)
        return SportCutEvent(
            id: UUID(),
            sourceID: source.id,
            stampID: stamp.id,
            lineID: line.id,
            mainTagID: stamp.idTag,
            tagName: stamp.label,
            lineName: line.name,
            startTime: stamp.timeStartSeconds,
            duration: stamp.duration,
            color: tag?.color ?? stamp.colorHex,
            tagGroupName: tagGroup?.name,
            labelIDs: stamp.labelIDs,
            eventIDs: stamp.timeEvents
        )
    }
    
    func toOrganizerTag() -> OrganizerTag {
        OrganizerTag(
            stampID: stampID,
            mainTagID: mainTagID,
            lineID: lineID,
            tagName: tagName,
            lineName: lineName,
            startTime: startTime,
            duration: duration,
            color: color,
            tagGroupName: tagGroupName,
            labelIDs: labelIDs,
            eventIDs: eventIDs
        )
    }

    var hiddenKey: String {
        "\(sourceID.uuidString)|\(stampID.uuidString)"
    }
}

// MARK: - Playlist Group

struct SportCutPlaylistGroup: Identifiable, Codable {
    let id: UUID
    var name: String
    var playlists: [SportCutPlaylist]
    
    init(id: UUID = UUID(), name: String, playlists: [SportCutPlaylist] = []) {
        self.id = id
        self.name = name
        self.playlists = playlists
    }
}

// MARK: - Playlist

struct SportCutPlaylist: Identifiable, Codable {
    let id: UUID
    var name: String
    var events: [SportCutEvent]
    var isHidden: Bool
    var hiddenEventKeys: Set<String>
    var eventComments: [String: String]
    var eventDrawings: [String: [SportCutEventDrawing]]
    /// Per-event clip start time overrides (keyed by `event.hiddenKey`). Only affects playlist, not original markup.
    var eventStartOverrides: [String: Double]
    /// Per-event clip duration overrides (keyed by `event.hiddenKey`). Only affects playlist playback, not original markup.
    var eventDurationOverrides: [String: Double]
    /// Титульные слайды-заставки, вставленные между клипами (для показа в виде презентации).
    var slides: [SportCutSlide]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        events: [SportCutEvent] = [],
        isHidden: Bool = false,
        hiddenEventKeys: Set<String> = [],
        eventComments: [String: String] = [:],
        eventDrawings: [String: [SportCutEventDrawing]] = [:],
        eventStartOverrides: [String: Double] = [:],
        eventDurationOverrides: [String: Double] = [:],
        slides: [SportCutSlide] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.events = events
        self.isHidden = isHidden
        self.hiddenEventKeys = hiddenEventKeys
        self.eventComments = eventComments
        self.eventDrawings = eventDrawings
        self.eventStartOverrides = eventStartOverrides
        self.eventDurationOverrides = eventDurationOverrides
        self.slides = slides
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        events = try container.decode([SportCutEvent].self, forKey: .events)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        hiddenEventKeys = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenEventKeys) ?? []
        eventComments = try container.decodeIfPresent([String: String].self, forKey: .eventComments) ?? [:]
        // Backward compat: try array format first, then single-drawing format
        if let arr = try? container.decodeIfPresent([String: [SportCutEventDrawing]].self, forKey: .eventDrawings) {
            eventDrawings = arr ?? [:]
        } else if let single = try? container.decodeIfPresent([String: SportCutEventDrawing].self, forKey: .eventDrawings) {
            eventDrawings = (single ?? [:]).mapValues { [$0] }
        } else {
            eventDrawings = [:]
        }
        eventStartOverrides = try container.decodeIfPresent([String: Double].self, forKey: .eventStartOverrides) ?? [:]
        eventDurationOverrides = try container.decodeIfPresent([String: Double].self, forKey: .eventDurationOverrides) ?? [:]
        slides = try container.decodeIfPresent([SportCutSlide].self, forKey: .slides) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    var totalDuration: Double {
        events.reduce(0) { acc, event in acc + effectiveDuration(for: event) }
    }

    var eventCount: Int {
        events.count
    }

    /// Returns the playlist-level start time for an event (override if set, otherwise original).
    func effectiveStartTime(for event: SportCutEvent) -> Double {
        eventStartOverrides[event.hiddenKey] ?? event.startTime
    }

    /// Returns the playlist-level duration for an event (override if set, otherwise original).
    func effectiveDuration(for event: SportCutEvent) -> Double {
        eventDurationOverrides[event.hiddenKey] ?? event.duration
    }

    /// End time of the event on the source video timeline.
    func effectiveEndTime(for event: SportCutEvent) -> Double {
        effectiveStartTime(for: event) + effectiveDuration(for: event)
    }
}

extension SportCutPlaylist {
    /// Текст комментария штампа в разметке: сначала текущий `TimelineDataManager`, иначе снимок в `SportCutSession`.
    static func markupComment(for event: SportCutEvent, session: SportCutSession) -> String? {
        if let line = TimelineDataManager.shared.lines.first(where: { $0.id == event.lineID }),
           let stamp = line.stamps.first(where: { $0.id == event.stampID }) {
            let t = (stamp.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        if let source = session.sources.first(where: { $0.id == event.sourceID }),
           let line = source.timelines.first(where: { $0.id == event.lineID }),
           let stamp = line.stamps.first(where: { $0.id == event.stampID }) {
            let t = (stamp.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// Переносит комментарии из разметки в `eventComments` плейлиста (режим просмотра / вотермарка).
    mutating func mergeMarkupComments(for events: [SportCutEvent], session: SportCutSession) {
        for ev in events {
            guard let text = SportCutPlaylist.markupComment(for: ev, session: session) else { continue }
            eventComments[ev.hiddenKey] = text
        }
    }
}

// MARK: - Title Slide (between playlist clips)

/// Титульный слайд-заставка, показываемый между клипами плейлиста (презентация).
struct SportCutSlide: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    /// Длительность показа, сек (по умолчанию 5).
    var durationSeconds: Double
    var backgroundColorHex: String
    var textColorHex: String
    /// Кегль заголовка в пунктах (при рендере 1080p).
    var textSize: Double
    /// Позиция среди клипов: слайд показывается ПЕРЕД клипом с этим индексом (0 = перед первым).
    var position: Int
    /// PNG-логотип, встроенный как данные (переносится вместе с сессией).
    var imageData: Data?

    init(
        id: UUID = UUID(),
        title: String = "",
        durationSeconds: Double = 5,
        backgroundColorHex: String = "1B1B1B",
        textColorHex: String = "FFFFFF",
        textSize: Double = 96,
        position: Int = 0,
        imageData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.durationSeconds = durationSeconds
        self.backgroundColorHex = backgroundColorHex
        self.textColorHex = textColorHex
        self.textSize = textSize
        self.position = position
        self.imageData = imageData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 5
        backgroundColorHex = try c.decodeIfPresent(String.self, forKey: .backgroundColorHex) ?? "1B1B1B"
        textColorHex = try c.decodeIfPresent(String.self, forKey: .textColorHex) ?? "FFFFFF"
        textSize = try c.decodeIfPresent(Double.self, forKey: .textSize) ?? 96
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
    }
}

// MARK: - Event Drawing (per playlist event)

struct SportCutEventDrawing: Codable {
    let imageName: String
    let videoTime: Double
    var displayDuration: Double
    var editorState: EditorStateSnapshot?
}

// MARK: - Playlist Event Drag Data

struct PlaylistEventDragData: Codable {
    let event: SportCutEvent
    let sourcePlaylistID: UUID
}

// MARK: - Markup → playlist drag (штампы с таймлайна разметки)

struct MarkupStampRef: Codable, Hashable {
    let lineID: UUID
    let stampID: UUID
}

/// На drop события пересобираются из текущих `TimelineDataManager` + source сессии (корректный `sourceID`).
struct MarkupStampsBatchPlaylistDragPayload: Codable {
    let markupProjectID: String
    let stampRefs: [MarkupStampRef]
}

// MARK: - Export options

enum SportCutExportType: String, CaseIterable {
    case clips
    case film
    case filmPerPlaylist
    
    var displayName: String {
        switch self {
        case .clips: return ^String.Titles.sportCutExportTypeClips
        case .film: return ^String.Titles.sportCutExportTypeFilm
        case .filmPerPlaylist: return ^String.Titles.sportCutExportTypeFilmPerPlaylist
        }
    }
}
