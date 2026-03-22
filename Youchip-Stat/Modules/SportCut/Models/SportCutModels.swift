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
    
    func resolveVideoURL() -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: videoBookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
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
            color: tag?.color ?? "FFFFFF",
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
    let createdAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        events: [SportCutEvent] = [],
        isHidden: Bool = false,
        hiddenEventKeys: Set<String> = [],
        eventComments: [String: String] = [:],
        eventDrawings: [String: [SportCutEventDrawing]] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.events = events
        self.isHidden = isHidden
        self.hiddenEventKeys = hiddenEventKeys
        self.eventComments = eventComments
        self.eventDrawings = eventDrawings
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
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    var totalDuration: Double {
        events.reduce(0) { $0 + $1.duration }
    }
    
    var eventCount: Int {
        events.count
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

// MARK: - Export options

enum SportCutExportType: String, CaseIterable {
    case clips
    case film
    case filmPerPlaylist
    
    var displayName: String {
        switch self {
        case .clips: return "Клипы"
        case .film: return "Фильм"
        case .filmPerPlaylist: return "Фильм для каждого плейлиста"
        }
    }
}
