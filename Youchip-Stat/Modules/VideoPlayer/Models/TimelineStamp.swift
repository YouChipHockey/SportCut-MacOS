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

struct TimelineStamp: Identifiable, Codable, Equatable {
    let id: UUID
    var idTag: String
    let primaryID: String?
    var timeStartSeconds: Double
    var timeFinishSeconds: Double
    var colorHex: String
    var label: String
    var isActiveForMapView: Bool?
    var labels: [String]
    var timeEvents: [String]
    var position: CGPoint?
    var color: Color {
        Color(hex: colorHex)
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
    
    init(id: UUID = UUID(), idTag: String, primaryID: String?, timeStartSeconds: Double, timeFinishSeconds: Double, timeStartString: String? = nil, timeFinishString: String? = nil, colorHex: String, label: String, labels: [String], timeEvents: [String] = [], position: CGPoint? = nil, isActiveForMapView: Bool? = nil) {
        self.id = id
        self.primaryID = primaryID
        self.idTag = idTag
        self.colorHex = colorHex
        self.label = label
        self.labels = labels
        self.timeEvents = timeEvents
        self.position = position
        self.isActiveForMapView = isActiveForMapView
        
        self.timeStartSeconds = timeStartSeconds
        self.timeFinishSeconds = timeFinishSeconds
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
