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
    var position: CGPoint?
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
    
    init(id: UUID = UUID(), tagRefs: [StampTagRef], primaryID: String?, timeStartSeconds: Double, timeFinishSeconds: Double, timeStartString: String? = nil, timeFinishString: String? = nil, colorHex: String, label: String, labels: [FullLabelWithGroup], timeEvents: [String] = [], position: CGPoint? = nil, isActiveForMapView: Bool? = nil) {
        self.id = id
        self.primaryID = primaryID
        self.tagRefs = tagRefs
        self.colorHex = colorHex
        self.label = label
        self.labels = labels
        self.timeEvents = timeEvents
        self.position = position
        self.isActiveForMapView = isActiveForMapView
        
        self.timeStartSeconds = timeStartSeconds
        self.timeFinishSeconds = timeFinishSeconds
    }
    
    enum CodingKeys: String, CodingKey {
        case id, tagRefs, idTags, idTag, tagGroupId, primaryID, timeStartSeconds, timeFinishSeconds
        case colorHex, label, isActiveForMapView, labels, timeEvents, position
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
        try container.encodeIfPresent(position, forKey: .position)
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
        position = try container.decodeIfPresent(CGPoint.self, forKey: .position)
        
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
    }
}

extension Array where Element == TimelineStamp {
    var sortedByStartTime: [TimelineStamp] {
        self.sorted { $0.timeStartSeconds < $1.timeStartSeconds }
    }
}
