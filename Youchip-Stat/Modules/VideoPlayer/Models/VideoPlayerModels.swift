//
//  VideoPlayerModels.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 28.04.2025.
//

// MARK: - Модели данных

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct Tag: Identifiable, Codable {
    var id: String
    let primaryID: String?
    var name: String
    var description: String
    var color: String
    var defaultTimeBefore: Double
    var defaultTimeAfter: Double
    var collection: String?
    var lablesGroup: [String]
    var hotkey: String?
    var labelHotkeys: [String: String]?
    var mapEnabled: Bool?
    var isInterval: Bool?
}

struct PlayFieldData: Codable {
    let field: PlayField
    
    init(field: PlayField) {
        self.field = field
    }
}

struct TagGroup: Codable, Identifiable {
    var id: String
    var name: String
    var tags: [String]
}

struct NamesData: Codable {
    var names: [String]
}

struct LanguageCollection: Codable {
    let language: String
    let names: [String]
}

struct LanguageCollectionsData: Codable {
    let collections: [LanguageCollection]
}

struct TagsData: Codable {
    let tags: [Tag]
}

struct TagGroupsData: Codable {
    let tagGroups: [TagGroup]
}

struct Label: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
}

struct LabelGroupData: Codable, Identifiable {
    var id: String
    var name: String
    var lables: [String]
}

struct LabelGroupsData: Codable {
    let labelGroups: [LabelGroupData]
}

struct LabelsData: Codable {
    let labels: [Label]
}

struct TimeEvent: Codable, Identifiable {
    let id: String
    let name: String
}

struct TimeEventsData: Codable {
    let events: [TimeEvent]
}

enum ExportMode { case film, playlist }

enum CutsExportType {
    case currentTimeline
    case allTimelines
    case tag(selectedTag: Tag)
    case timeEvent(selectedEvent: TimeEvent)
    case label(selectedLabel: Label) 
    case tagWithLabels(selectedTag: Tag, selectedLabels: [Label])
    case labelWithTags(selectedLabel: Label, selectedTags: [Tag])
}

struct ExportSegment {
    let timeRange: CMTimeRange
    let lineName: String?
    let tagName: String
    let groupName: String?
    let labels: [Label]?
    let labelGroupName: String?
    let selectedLabel: Label?
}

struct ExportSegmentOrganaizer {
    let timeRange: CMTimeRange
    let tagName: String
    let groupName: String
    let labels: [Label]
}

struct TimelineLine: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var stamps: [TimelineStamp] = []
    var tagIdForMode: String = ""
    
    static func == (lhs: TimelineLine, rhs: TimelineLine) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.stamps == rhs.stamps &&
               lhs.tagIdForMode == rhs.tagIdForMode
    }
}

struct FullLabelWithGroup: Codable {
    let id: String
    let name: String
    let description: String
    let group: LabelGroupInfo?
}

enum ActiveAlert: Identifiable {
    case fieldChange
    case fieldDelete
    
    var id: Int {
        switch self {
        case .fieldChange: return 0
        case .fieldDelete: return 1
        }
    }
}

struct LabelGroupInfo: Codable {
    let id: String
    let name: String
}

struct TagGroupInfo: Codable {
    let id: String
    let name: String
}

struct FullTagWithGroup: Codable {
    let id: String
    let primaryID: String?
    let name: String
    let description: String
    let color: String
    let defaultTimeBefore: Double
    let defaultTimeAfter: Double
    let collection: String
    let hotkey: String?
    let labelHotkeys: [String: String]?
    let group: TagGroupInfo?
}

struct FullTimelineStamp: Codable {
    let id: UUID
    let timeStart: String
    let timeFinish: String
    let tag: FullTagWithGroup
    let labels: [FullLabelWithGroup]
    let timeEvents: [TimeEvent]
    let position: CGPoint?
}

struct FullTimelineLine: Codable {
    let id: UUID
    let name: String
    let stamps: [FullTimelineStamp]
}

struct PlayField: Codable {
    let id: String
    var name: String
    var imagePath: String
    var width: Double
    var height: Double
    var imageBookmark: Data?
}

enum TagCollection {
    case standard
    case user(name: String)
    
    var name: String? {
        switch self {
        case .standard:
            return nil
        case .user(let name):
            return name
        }
    }
}

struct TagButtonViewModel {
    let tag: Tag
    let displayText: String
    
    init(tag: Tag) {
        self.tag = tag
        if let hotkey = tag.hotkey, !hotkey.isEmpty {
            self.displayText = "\(tag.name)\n[\(hotkey)]"
        } else {
            self.displayText = tag.name
        }
    }
}

struct ColorOption {
    let color: Color
    let hex: String
}

struct CollectionBookmark: Codable, Hashable {
    let id: UUID
    let name: String
    let tagGroupsBookmark: Data
    let tagsBookmark: Data
    let labelGroupsBookmark: Data
    let labelsBookmark: Data
    let timeEventsBookmark: Data
    let playFieldBookmark: Data?
    
    init(
        id: UUID = UUID(),
        name: String,
        tagGroupsBookmark: Data,
        tagsBookmark: Data,
        labelGroupsBookmark: Data,
        labelsBookmark: Data,
        timeEventsBookmark: Data,
        playFieldBookmark: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.tagGroupsBookmark = tagGroupsBookmark
        self.tagsBookmark = tagsBookmark
        self.labelGroupsBookmark = labelGroupsBookmark
        self.labelsBookmark = labelsBookmark
        self.timeEventsBookmark = timeEventsBookmark
        self.playFieldBookmark = playFieldBookmark
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case tagGroupsBookmark
        case tagsBookmark
        case labelGroupsBookmark
        case labelsBookmark
        case timeEventsBookmark
        case playFieldBookmark
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        tagGroupsBookmark = try container.decode(Data.self, forKey: .tagGroupsBookmark)
        tagsBookmark = try container.decode(Data.self, forKey: .tagsBookmark)
        labelGroupsBookmark = try container.decode(Data.self, forKey: .labelGroupsBookmark)
        labelsBookmark = try container.decode(Data.self, forKey: .labelsBookmark)
        timeEventsBookmark = try container.decode(Data.self, forKey: .timeEventsBookmark)
        playFieldBookmark = try container.decodeIfPresent(Data.self, forKey: .playFieldBookmark)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CollectionBookmark, rhs: CollectionBookmark) -> Bool {
        return lhs.id == rhs.id
    }
}

struct StampDragInfo: Codable {
    let lineID: UUID
    let stampID: UUID
}
