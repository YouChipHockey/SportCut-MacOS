//
//  DrawableObject.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct DrawableObject: Identifiable {
    let id = UUID()
    let number: Int
    let type: ObjectType
    var isVisible: Bool = true
    var showNumber: Bool = false
    var positions: [CGPoint] = []
    
    // Customization properties
    var edgeColor: Color = .red
    var vertexColor: Color = .red
    var fillColor: Color = .red
    var lineStyle: LineStyle = .solid
    var glowColor: Color = .white
    var radius: CGFloat = 30
    
    init(number: Int, type: ObjectType) {
        self.number = number
        self.type = type
    }
}
