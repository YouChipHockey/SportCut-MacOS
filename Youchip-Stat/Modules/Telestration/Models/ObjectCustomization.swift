//
//  ObjectCustomization.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import SwiftUI

struct ObjectCustomization {
    var edgeColor: Color = .red
    var vertexColor: Color = .red
    var fillColor: Color = .red
    var lineStyle: LineStyle = .solid
    var glowColor: Color = .white
    var glowOpacity: Double = 0.5 // Прозрачность для «выделения объекта» (0.5 = 50%)
    var radius: CGFloat = 30
    var curveHeight: CGFloat = 0.0 // Высота центра параболы для закругленной стрелки (0 = прямая линия, >0 = изгиб вверх, <0 = изгиб вниз)
    var strokeWidth: CGFloat = 2.0 // Толщина линии для закругленной стрелки
}
