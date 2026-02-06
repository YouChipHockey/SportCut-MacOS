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
    let id: UUID
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
    var curveHeight: CGFloat = 0.0 // Высота центра параболы для закругленной стрелки (используется, если controlPoint == nil)
    /// Явная контрольная точка для закруглённой стрелки; при заданной точке изгиб может быть произвольным (2D). Если nil — контрольная точка вычисляется из curveHeight (движение только по перпендикуляру).
    var controlPoint: CGPoint? = nil
    var strokeWidth: CGFloat = 2.0 // Толщина линии для закругленной стрелки
    
    init(number: Int, type: ObjectType) {
        self.id = UUID()
        self.number = number
        self.type = type
    }
    
    /// Копия с новым id (для вставки из буфера).
    init(copying other: DrawableObject) {
        self.id = UUID()
        self.number = other.number
        self.type = other.type
        self.isVisible = other.isVisible
        self.showNumber = other.showNumber
        self.positions = other.positions
        self.edgeColor = other.edgeColor
        self.vertexColor = other.vertexColor
        self.fillColor = other.fillColor
        self.lineStyle = other.lineStyle
        self.glowColor = other.glowColor
        self.glowOpacity = other.glowOpacity
        self.radius = other.radius
        self.curveHeight = other.curveHeight
        self.controlPoint = other.controlPoint
        self.strokeWidth = other.strokeWidth
    }
}
