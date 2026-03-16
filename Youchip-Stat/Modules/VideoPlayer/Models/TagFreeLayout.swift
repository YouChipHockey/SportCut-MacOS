//
//  TagFreeLayout.swift
//  Youchip-Stat
//
//  Свободная раскладка тегов для пользовательских коллекций.
//

import Foundation
import CoreGraphics

/// Форма, в которой может отображаться тег в свободной раскладке.
enum TagFreeLayoutShape: String, Codable, CaseIterable {
    case square
    case circle
    case triangle
    case star
    case diamond
    case hexagon
    case capsule
}

/// Жирность шрифта для подписи тега.
enum TagFreeLayoutFontWeight: String, Codable, CaseIterable {
    case regular
    case medium
    case bold
}

/// Положение и внешний вид одного тега в свободной раскладке.
struct TagFreeLayoutItem: Codable, Identifiable {
    var id: String { tagId }
    
    let tagId: String
    
    /// Центр фигуры в координатах «виртуального холста».
    var center: CGPoint
    
    /// Размер фигуры в координатах «виртуального холста».
    var size: CGSize
    
    /// Поворот в градусах относительно центра.
    var rotation: Double
    
    /// Тип фигуры.
    var shape: TagFreeLayoutShape
    
    // MARK: - Visual customization
    
    var fillOpacity: Double
    var strokeColor: String?
    var strokeWidth: CGFloat
    var strokeDashed: Bool
    var textColor: String?
    var fontSize: CGFloat
    var fontWeight: TagFreeLayoutFontWeight
    var showLabel: Bool
    var cornerRadius: CGFloat
    var shadowEnabled: Bool
    var shadowIntensity: Double
    var aspectRatioLocked: Bool
    
    init(
        tagId: String,
        center: CGPoint,
        size: CGSize,
        rotation: Double,
        shape: TagFreeLayoutShape,
        fillOpacity: Double = 1.0,
        strokeColor: String? = nil,
        strokeWidth: CGFloat = 1.0,
        strokeDashed: Bool = false,
        textColor: String? = nil,
        fontSize: CGFloat = 12,
        fontWeight: TagFreeLayoutFontWeight = .medium,
        showLabel: Bool = true,
        cornerRadius: CGFloat = 8,
        shadowEnabled: Bool = true,
        shadowIntensity: Double = 0.5,
        aspectRatioLocked: Bool = false
    ) {
        self.tagId = tagId
        self.center = center
        self.size = size
        self.rotation = rotation
        self.shape = shape
        self.fillOpacity = fillOpacity
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.strokeDashed = strokeDashed
        self.textColor = textColor
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.showLabel = showLabel
        self.cornerRadius = cornerRadius
        self.shadowEnabled = shadowEnabled
        self.shadowIntensity = shadowIntensity
        self.aspectRatioLocked = aspectRatioLocked
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tagId = try c.decode(String.self, forKey: .tagId)
        center = try c.decode(CGPoint.self, forKey: .center)
        size = try c.decode(CGSize.self, forKey: .size)
        rotation = try c.decode(Double.self, forKey: .rotation)
        shape = try c.decode(TagFreeLayoutShape.self, forKey: .shape)
        fillOpacity = try c.decodeIfPresent(Double.self, forKey: .fillOpacity) ?? 1.0
        strokeColor = try c.decodeIfPresent(String.self, forKey: .strokeColor)
        strokeWidth = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 1.0
        strokeDashed = try c.decodeIfPresent(Bool.self, forKey: .strokeDashed) ?? false
        textColor = try c.decodeIfPresent(String.self, forKey: .textColor)
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 12
        fontWeight = try c.decodeIfPresent(TagFreeLayoutFontWeight.self, forKey: .fontWeight) ?? .medium
        showLabel = try c.decodeIfPresent(Bool.self, forKey: .showLabel) ?? true
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 8
        shadowEnabled = try c.decodeIfPresent(Bool.self, forKey: .shadowEnabled) ?? true
        shadowIntensity = try c.decodeIfPresent(Double.self, forKey: .shadowIntensity) ?? 0.5
        aspectRatioLocked = try c.decodeIfPresent(Bool.self, forKey: .aspectRatioLocked) ?? false
    }
}

/// Описание свободной раскладки для всей коллекции.
struct TagFreeLayout: Codable {
    var canvasWidth: CGFloat
    var canvasHeight: CGFloat
    var items: [TagFreeLayoutItem]
}
