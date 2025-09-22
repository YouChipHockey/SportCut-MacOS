//
//  TemplateObject.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct TemplateObject: Identifiable {
    let id = UUID()
    let formationName: String
    let originalObject: DrawableObject
    let templatePositions: [CGPoint]
    var templateCustomization = TemplateCustomization()
    var isVisible: Bool = true
    
    var displayName: String {
        return "Шаблон - \(formationName)"
    }
}

struct TemplateCustomization {
    var edgeColor: Color = .blue
    var vertexColor: Color = .green
    var fillColor: Color = .cyan
    var lineStyle: LineStyle = .dashed
    var showMisalignedVertices: Bool = true
    var misalignmentThreshold: CGFloat = 20 // pixels
    var misalignedVertexColor: Color = .red
}
