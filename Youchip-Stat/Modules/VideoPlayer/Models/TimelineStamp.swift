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
    var timeStart: String
    var timeFinish: String
    var colorHex: String
    var label: String
    var isActiveForMapView: Bool?
    var labels: [String]
    var timeEvents: [String]
    var position: CGPoint?
    var color: Color {
        Color(hex: colorHex)
    }
    var startSeconds: Double {
        timeStringToSeconds(timeStart)
    }
    var finishSeconds: Double {
        timeStringToSeconds(timeFinish)
    }
    var duration: Double {
        finishSeconds - startSeconds
    }
    
    init(id: UUID = UUID(), idTag: String, primaryID: String?, timeStart: String, timeFinish: String, colorHex: String, label: String, labels: [String], timeEvents: [String] = [], position: CGPoint? = nil, isActiveForMapView: Bool? = nil) {
        self.id = id
        self.primaryID = primaryID
        self.idTag = idTag
        self.timeStart = timeStart
        self.timeFinish = timeFinish
        self.colorHex = colorHex
        self.label = label
        self.labels = labels
        self.timeEvents = timeEvents
        self.position = position
        self.isActiveForMapView = isActiveForMapView
    }
    
    static func == (lhs: TimelineStamp, rhs: TimelineStamp) -> Bool {
        lhs.id == rhs.id
    }
}
