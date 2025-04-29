//
//  VideoPlayerModels.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 28.04.2025.
//

// MARK: - Модели данных

import Foundation

struct Tag: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let color: String
    let defaultTimeBefore: Double
    let defaultTimeAfter: Double
    let collection: String?
    let lablesGroup: [String]
    let hotkey: String?
    let labelHotkeys: [String: String]? // Maps label ID to hotkey
}

struct TagGroup: Codable, Identifiable {
    let id: String
    let name: String
    let tags: [String]
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
    let id: String
    let name: String
    let lables: [String]
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

struct TimelineLine: Identifiable, Codable {
    var id = UUID()
    var name: String
    var stamps: [TimelineStamp] = []
}

struct FullTimelineStamp: Codable {
    let id: UUID
    let timeStart: String
    let timeFinish: String
    let tag: Tag
    let labels: [Label]
    let timeEvents: [TimeEvent]
}

struct FullTimelineLine: Codable {
    let id: UUID
    let name: String
    let stamps: [FullTimelineStamp]
}

enum TagCollection {
    case standard
    case user(name: String)
}
