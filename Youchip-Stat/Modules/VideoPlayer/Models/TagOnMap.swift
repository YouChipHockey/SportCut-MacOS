//
//  TagOnMap.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct TagOnMap: Identifiable, Hashable {
    let id: String
    let stampId: UUID
    let lineId: UUID
    let name: String
    let colorHex: String
    let timeStart: String
    let timeFinish: String
    let position: CGPoint
    let isActiveForMapView: Bool
    var number: Int = 0
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: TagOnMap, rhs: TagOnMap) -> Bool {
        lhs.id == rhs.id
    }
}
