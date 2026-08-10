//
//  VideoPlayerModels.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 28.04.2025.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct Tag: Identifiable, Codable, Equatable {
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
    /// Id карты (PlayField), которую использует этот тег при разметке. nil = первая карта коллекции (обратная совместимость).
    /// Оставлено для совместимости со старыми коллекциями; актуальный список — в `mapFieldIds`.
    var mapFieldId: String? = nil
    /// Ids карт (PlayField), на которых нужно отметить точку для этого тега. Пусто/nil —
    /// используется `mapFieldId`, а если и он пуст — первая карта коллекции.
    var mapFieldIds: [String]? = nil

    /// Эффективный список карт тега: сперва `mapFieldIds`, затем одиночный `mapFieldId`.
    /// Пустой список означает «первая карта коллекции» (обратная совместимость).
    var resolvedMapFieldIds: [String] {
        if let ids = mapFieldIds, !ids.isEmpty { return ids }
        if let single = mapFieldId, !single.isEmpty { return [single] }
        return []
    }
}

extension Tag {
    static func syntheticDrawingTag(for stamp: TimelineStamp) -> Tag? {
        guard stamp.idTag.hasPrefix("screenshot_"), !stamp.label.isEmpty else { return nil }
        return Tag(
            id: stamp.idTag,
            primaryID: nil,
            name: stamp.label,
            description: "",
            color: "808080",
            defaultTimeBefore: 3.0,
            defaultTimeAfter: 3.0,
            collection: nil,
            lablesGroup: [],
            hotkey: nil,
            labelHotkeys: nil,
            mapEnabled: nil,
            isInterval: nil
        )
    }
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

struct LanguageCollectionItem: Codable {
    /// Уникальное имя папки/ресурса коллекции (напр. "Football_fr"), по нему грузятся JSON.
    let folder: String
    /// Отображаемое имя на языке коллекции (напр. «Football»).
    let name: String
}

struct LanguageCollection: Codable {
    let language: String
    /// Старый формат: имя папки == отображаемому имени.
    let names: [String]?
    /// Новый формат: папка и отображаемое имя разделены (чтобы имена папок не конфликтовали).
    let items: [LanguageCollectionItem]?

    /// Нормализованный список (folder, name) независимо от формата файла.
    var resolvedItems: [LanguageCollectionItem] {
        if let items { return items }
        if let names { return names.map { LanguageCollectionItem(folder: $0, name: $0) } }
        return []
    }
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

struct Label: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let description: String
}

struct LabelGroupData: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var lables: [String]
}

extension Array where Element == LabelGroupData {

    var sortedByName: [LabelGroupData] {
        sorted(by: { $0.name < $1.name })
    }

}

extension LabelGroupData {
    /// true, если у группы «настоящее» имя: непустое и не равное её id.
    /// Синтетические группы (реконструированные для импортированных видео без коллекции)
    /// именуются своим id — такие не показываются в фильтре как отдельные группы.
    var isNameResolved: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != id
    }

    /// Имя для подписей (таблица/экспорт/вотермарка): обобщённое «Лейблы», если имя не резолвится.
    var labelGroupDisplayName: String {
        isNameResolved ? name : (^String.Titles.sportCutLabels)
    }
}

struct LabelGroupsData: Codable {
    let labelGroups: [LabelGroupData]
}

struct LabelsData: Codable {
    let labels: [Label]
}

struct TimeEvent: Codable, Identifiable, Hashable {
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
    case screenshots
    /// Экспорт таймлайна «Рисунки» как фильм или плейлист с картинками (каждый тег = рисунок с наложением).
    case drawingsTimeline
}

struct ExportSegment {
    let stamp: TimelineStamp
    let tagName: String
    let timeRange: CMTimeRange
    let lineName: String?
    let groupName: String?
    let labelGroupName: String?
    let selectedLabel: Label?
    let stampId: UUID? // ID of the stamp this segment was created from
}

struct ExportSegmentOrganaizer {
    let timeRange: CMTimeRange
    let tagName: String
    let tagId: String
    let stampId: UUID
    let groupName: String
    let labels: [Label]
    let eventIDs: [String]
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

struct FullLabelWithGroup: Codable, Equatable, Hashable {
    let id: String
    let name: String
    let description: String
    let lableGroupId: String
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
    let tags: [FullTagWithGroup]
    let labels: [FullLabelWithGroup]
    let timeEvents: [TimeEvent]
    let position: CGPoint?
}

struct FullTimelineLine: Codable {
    let id: UUID
    let name: String
    let stamps: [FullTimelineStamp]
}

struct PlayField: Codable, Identifiable {
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

enum CollectionTagLibraryDisplayMode: String, Codable, CaseIterable, Equatable {
    case grouped
    case free

    var localizedTitle: String {
        switch self {
        case .grouped:
            ^String.Titles.freeTagModeGrouped
        case .free:
            ^String.Titles.freeTagModeFree
        }
    }
}

struct CollectionBookmark: Codable, Hashable, Equatable {
    let id: String
    let name: String
    let tagGroupsBookmark: Data
    let tagsBookmark: Data
    let labelGroupsBookmark: Data
    let labelsBookmark: Data
    let timeEventsBookmark: Data
    let playFieldBookmark: Data?
    
    init(
        id: String,
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
        
        name = try container.decode(String.self, forKey: .name)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? name
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
    
}

struct StampDragInfo: Codable {
    let lineID: UUID
    let stampID: UUID
}
