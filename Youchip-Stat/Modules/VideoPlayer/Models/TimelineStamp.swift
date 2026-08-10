//
//  TimelineStamp.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct StampTagRef: Codable, Equatable, Hashable {
    let id: String
    let tagGroupId: String
}

/// Позиция тега на конкретной карте (PlayField). Один штамп может нести несколько позиций —
/// по одной на каждую карту, к которой привязан тег (ставятся за один штамп, а не по штампу на карту).
struct StampMapPosition: Codable, Equatable, Hashable {
    /// Id карты (PlayField). nil = первая/основная карта коллекции (обратная совместимость).
    var mapFieldId: String?
    var position: CGPoint
}

struct TimelineStamp: Identifiable, Codable, Equatable {
    let id: UUID
    var tagRefs: [StampTagRef]
    let primaryID: String?
    var timeStartSeconds: Double
    var timeFinishSeconds: Double
    var colorHex: String
    var label: String
    var isActiveForMapView: Bool?
    var labels: [FullLabelWithGroup]
    var timeEvents: [String]
    /// Позиции тега по картам. Обычно 0 или 1; для тега, привязанного к нескольким картам,
    /// — по одной точке на каждую карту (все в одном штампе).
    var mapPositions: [StampMapPosition]
    var comment: String?

    /// Обратная совместимость: одиночная позиция = первая из `mapPositions`.
    var position: CGPoint? { mapPositions.first?.position }
    /// Обратная совместимость: id карты первой позиции. nil = первая карта коллекции.
    var mapFieldId: String? { mapPositions.first?.mapFieldId }

    /// Позиция для конкретной карты (по её id).
    func position(forFieldId fieldId: String) -> CGPoint? {
        mapPositions.first(where: { $0.mapFieldId == fieldId })?.position
    }

    /// Ставит/обновляет позицию на конкретной карте, не трогая остальные карты.
    mutating func setPosition(_ position: CGPoint, forFieldId fieldId: String?) {
        if let idx = mapPositions.firstIndex(where: { $0.mapFieldId == fieldId }) {
            mapPositions[idx].position = position
        } else {
            mapPositions.append(StampMapPosition(mapFieldId: fieldId, position: position))
        }
    }

    /// Обновляет основную (первую) позицию; если позиций нет — создаёт одну без привязки к карте.
    mutating func setPrimaryPosition(_ position: CGPoint) {
        if mapPositions.isEmpty {
            mapPositions = [StampMapPosition(mapFieldId: nil, position: position)]
        } else {
            mapPositions[0].position = position
        }
    }

    var color: Color {
        Color(hex: colorHex)
    }
    
    var idTags: [String] {
        tagRefs.map(\.id)
    }
    
    var idTag: String {
        get { tagRefs.first?.id ?? "" }
        set {
            if tagRefs.isEmpty {
                tagRefs = [StampTagRef(id: newValue, tagGroupId: "")]
            } else {
                tagRefs[0] = StampTagRef(id: newValue, tagGroupId: tagRefs[0].tagGroupId)
            }
        }
    }
    
    var labelIDs: [String] {
        labels.map(\.id)
    }
    
    var timeStartString: String {
        secondsToTimeString(timeStartSeconds)
    }
    var timeFinishString: String {
        secondsToTimeString(timeStartSeconds)
    }
    var duration: Double {
        timeFinishSeconds - timeStartSeconds
    }
    
    init(id: UUID = UUID(), tagRefs: [StampTagRef], primaryID: String?, timeStartSeconds: Double, timeFinishSeconds: Double, timeStartString: String? = nil, timeFinishString: String? = nil, colorHex: String, label: String, labels: [FullLabelWithGroup], timeEvents: [String] = [], position: CGPoint? = nil, isActiveForMapView: Bool? = nil, comment: String? = nil, mapFieldId: String? = nil, mapPositions: [StampMapPosition]? = nil) {
        self.id = id
        self.primaryID = primaryID
        self.tagRefs = tagRefs
        self.colorHex = colorHex
        self.label = label
        self.labels = labels
        self.timeEvents = timeEvents
        self.isActiveForMapView = isActiveForMapView
        self.comment = comment

        // Приоритет у массива позиций; иначе — миграция из одиночных position/mapFieldId.
        if let mapPositions {
            self.mapPositions = mapPositions
        } else if let position {
            self.mapPositions = [StampMapPosition(mapFieldId: mapFieldId, position: position)]
        } else {
            self.mapPositions = []
        }

        self.timeStartSeconds = timeStartSeconds
        self.timeFinishSeconds = timeFinishSeconds
    }

    enum CodingKeys: String, CodingKey {
        case id, tagRefs, idTags, idTag, tagGroupId, primaryID, timeStartSeconds, timeFinishSeconds
        case colorHex, label, isActiveForMapView, labels, timeEvents, position, comment, mapFieldId
        case mapPositions
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tagRefs, forKey: .tagRefs)
        try container.encodeIfPresent(primaryID, forKey: .primaryID)
        try container.encode(timeStartSeconds, forKey: .timeStartSeconds)
        try container.encode(timeFinishSeconds, forKey: .timeFinishSeconds)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(isActiveForMapView, forKey: .isActiveForMapView)
        try container.encode(labels, forKey: .labels)
        try container.encode(timeEvents, forKey: .timeEvents)
        try container.encode(mapPositions, forKey: .mapPositions)
        // Дублируем первую точку в старые ключи — чтобы файлы читались и старыми версиями приложения.
        try container.encodeIfPresent(position, forKey: .position)
        try container.encodeIfPresent(mapFieldId, forKey: .mapFieldId)
        try container.encodeIfPresent(comment, forKey: .comment)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        primaryID = try container.decodeIfPresent(String.self, forKey: .primaryID)
        timeStartSeconds = try container.decode(Double.self, forKey: .timeStartSeconds)
        timeFinishSeconds = try container.decode(Double.self, forKey: .timeFinishSeconds)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        label = try container.decode(String.self, forKey: .label)
        isActiveForMapView = try container.decodeIfPresent(Bool.self, forKey: .isActiveForMapView)
        timeEvents = try container.decodeIfPresent([String].self, forKey: .timeEvents) ?? []
        comment = try container.decodeIfPresent(String.self, forKey: .comment)

        // Новый формат — массив; иначе миграция из одиночной точки (position + mapFieldId).
        if let positions = try? container.decode([StampMapPosition].self, forKey: .mapPositions) {
            mapPositions = positions
        } else {
            let legacyPosition = try container.decodeIfPresent(CGPoint.self, forKey: .position)
            let legacyFieldId = try container.decodeIfPresent(String.self, forKey: .mapFieldId)
            if let legacyPosition {
                mapPositions = [StampMapPosition(mapFieldId: legacyFieldId, position: legacyPosition)]
            } else {
                mapPositions = []
            }
        }

        if let refs = try? container.decode([StampTagRef].self, forKey: .tagRefs) {
            tagRefs = refs
        } else if let stringTags = try? container.decode([String].self, forKey: .idTags) {
            let stampGroupId = (try? container.decodeIfPresent(String.self, forKey: .tagGroupId)) ?? ""
            tagRefs = stringTags.map { StampTagRef(id: $0, tagGroupId: stampGroupId) }
        } else if let singleTag = try? container.decode(String.self, forKey: .idTag) {
            let stampGroupId = (try? container.decodeIfPresent(String.self, forKey: .tagGroupId)) ?? ""
            tagRefs = [StampTagRef(id: singleTag, tagGroupId: stampGroupId)]
        } else {
            tagRefs = []
        }
        
        if let fullLabels = try? container.decode([FullLabelWithGroup].self, forKey: .labels) {
            labels = fullLabels
        } else if let labelIDs = try? container.decode([String].self, forKey: .labels) {
            labels = labelIDs.map { FullLabelWithGroup(id: $0, name: "", description: "", lableGroupId: "") }
        } else {
            labels = []
        }
    }
    
    static func == (lhs: TimelineStamp, rhs: TimelineStamp) -> Bool {
        lhs.id == rhs.id
            && lhs.tagRefs == rhs.tagRefs
            && lhs.primaryID == rhs.primaryID
            && lhs.timeStartSeconds == rhs.timeStartSeconds
            && lhs.timeFinishSeconds == rhs.timeFinishSeconds
            && lhs.colorHex == rhs.colorHex
            && lhs.label == rhs.label
            && lhs.isActiveForMapView == rhs.isActiveForMapView
            && lhs.labels == rhs.labels
            && lhs.timeEvents == rhs.timeEvents
            && lhs.mapPositions == rhs.mapPositions
            && lhs.comment == rhs.comment
    }
    
    /// Порядковый номер среди всех экземпляров того же тега по времени начала (раньше по времени → меньший номер).
    func chronologicalOrdinalAmongSameTag(in lines: [TimelineLine]) -> Int {
        let peers = lines.flatMap(\.stamps).filter { $0.idTag == idTag }
        let sorted = peers.sorted {
            if $0.timeStartSeconds != $1.timeStartSeconds {
                return $0.timeStartSeconds < $1.timeStartSeconds
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard let idx = sorted.firstIndex(where: { $0.id == id }) else { return 1 }
        return idx + 1
    }
}

extension Array where Element == TimelineStamp {
    var sortedByStartTime: [TimelineStamp] {
        self.sorted { $0.timeStartSeconds < $1.timeStartSeconds }
    }
}
