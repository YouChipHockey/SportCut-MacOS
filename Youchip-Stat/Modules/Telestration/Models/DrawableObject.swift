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
    
    var edgeColor: Color = .red
    var vertexColor: Color = .red
    var fillColor: Color = .red
    var lineStyle: LineStyle = .solid
    var glowColor: Color = .white
    var glowOpacity: Double = 0.5 // Прозрачность для «выделения объекта» (0.5 = 50%)
    var radius: CGFloat = 30
    var curveHeight: CGFloat = 0.0 // Высота центра параболы для закругленной стрелки
    
    init(number: Int, type: ObjectType) {
        self.number = number
        self.type = type
    }
}
