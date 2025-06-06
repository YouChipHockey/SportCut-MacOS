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

struct Tag: Codable, Identifiable {
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
}

struct ExportSegment {
    let timeRange: CMTimeRange
    let lineName: String?
    let tagName: String
    let groupName: String?
}

struct TimelineLine: Identifiable, Codable {
    var id = UUID()
    var name: String
    var stamps: [TimelineStamp] = []
    var tagIdForMode: String = ""
}

struct FullLabelWithGroup: Codable {
    let id: String
    let name: String
    let description: String
    let group: LabelGroupInfo?
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
}

enum TagCollection {
    case standard
    case user(name: String)
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

struct CollectionBookmark: Codable {
    let name: String
    let tagGroupsBookmark: Data
    let tagsBookmark: Data
    let labelGroupsBookmark: Data
    let labelsBookmark: Data
    let timeEventsBookmark: Data
}

struct StampDragInfo: Codable {
    let lineID: UUID
    let stampID: UUID
}
