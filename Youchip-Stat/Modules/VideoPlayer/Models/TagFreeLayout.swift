//
//  TagFreeLayout.swift
//  Youchip-Stat
//
//  Свободная раскладка тегов и лейблов для пользовательских коллекций.
//

import Foundation
import CoreGraphics

// MARK: - Shape / Font

/// Форма, в которой может отображаться кнопка в свободной раскладке.
enum TagFreeLayoutShape: String, Codable, CaseIterable {
    case square
    case circle
    case triangle
    case star
    case diamond
    case hexagon
    case capsule
}

/// Жирность шрифта для подписи кнопки.
enum TagFreeLayoutFontWeight: String, Codable, CaseIterable {
    case regular
    case medium
    case bold
}

// MARK: - Item

/// Положение и внешний вид одного элемента (тега или лейбла) в свободной раскладке.
struct TagFreeLayoutItem: Codable, Identifiable {

    // MARK: Identity

    /// Идентификатор тега или лейбла. Хранится в JSON под ключом "elementId";
    /// для обратной совместимости читается также из "tagId".
    var elementId: String

    /// Тип элемента (.tag или .label). Старые элементы без поля считаются тегами.
    var kind: CanvasButtonKind

    /// Изначальная видимость кнопки. Runtime может её оверрайдить.
    var isVisible: Bool

    /// Составной идентификатор для использования в наборах: "kind:elementId".
    var id: String { "\(kind.rawValue):\(elementId)" }

    // MARK: Layout

    /// Центр фигуры в координатах «виртуального холста».
    var center: CGPoint

    /// Размер фигуры в координатах «виртуального холста».
    var size: CGSize

    /// Поворот в градусах относительно центра.
    var rotation: Double

    /// Тип фигуры.
    var shape: TagFreeLayoutShape

    // MARK: Visual customization

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

    // MARK: Init

    init(
        elementId: String,
        kind: CanvasButtonKind = .tag,
        isVisible: Bool = true,
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
        self.elementId = elementId
        self.kind = kind
        self.isVisible = isVisible
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

    // MARK: Codable (backward compatible)

    enum CodingKeys: String, CodingKey {
        case elementId, tagId   // tagId is the legacy key
        case kind, isVisible
        case center, size, rotation, shape
        case fillOpacity, strokeColor, strokeWidth, strokeDashed
        case textColor, fontSize, fontWeight, showLabel
        case cornerRadius, shadowEnabled, shadowIntensity, aspectRatioLocked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Backward compat: prefer elementId, fall back to tagId
        if let eid = try c.decodeIfPresent(String.self, forKey: .elementId) {
            elementId = eid
        } else {
            elementId = try c.decode(String.self, forKey: .tagId)
        }
        kind = try c.decodeIfPresent(CanvasButtonKind.self, forKey: .kind) ?? .tag
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
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

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(elementId, forKey: .elementId)
        try c.encode(kind, forKey: .kind)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(center, forKey: .center)
        try c.encode(size, forKey: .size)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(shape, forKey: .shape)
        try c.encode(fillOpacity, forKey: .fillOpacity)
        try c.encodeIfPresent(strokeColor, forKey: .strokeColor)
        try c.encode(strokeWidth, forKey: .strokeWidth)
        try c.encode(strokeDashed, forKey: .strokeDashed)
        try c.encodeIfPresent(textColor, forKey: .textColor)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(fontWeight, forKey: .fontWeight)
        try c.encode(showLabel, forKey: .showLabel)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(shadowEnabled, forKey: .shadowEnabled)
        try c.encode(shadowIntensity, forKey: .shadowIntensity)
        try c.encode(aspectRatioLocked, forKey: .aspectRatioLocked)
    }
}

// MARK: - Layout

/// Описание свободной раскладки для всей коллекции.
struct TagFreeLayout: Codable {
    var canvasWidth: CGFloat
    var canvasHeight: CGFloat
    var items: [TagFreeLayoutItem]
    /// Связки клавиш. Отсутствует в старых файлах — декодируется как [].
    var bindings: [KeyBinding]

    init(canvasWidth: CGFloat, canvasHeight: CGFloat, items: [TagFreeLayoutItem], bindings: [KeyBinding] = []) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.items = items
        self.bindings = bindings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canvasWidth = try c.decode(CGFloat.self, forKey: .canvasWidth)
        canvasHeight = try c.decode(CGFloat.self, forKey: .canvasHeight)
        items = try c.decode([TagFreeLayoutItem].self, forKey: .items)
        bindings = try c.decodeIfPresent([KeyBinding].self, forKey: .bindings) ?? []
    }
}

extension TagFreeLayout {
    /// Прямоугольник, охватывающий все элементы (с учётом их размеров и поворота не учитываем),
    /// расширенный на padding со всех сторон. nil, если элементов нет.
    /// Холст редактора «бесконечный» (расширяется по контенту), а библиотека обрезается по этому прямоугольнику.
    func contentRect(padding: CGFloat = 0) -> CGRect? {
        guard !items.isEmpty else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for item in items {
            minX = min(minX, item.center.x - item.size.width / 2)
            minY = min(minY, item.center.y - item.size.height / 2)
            maxX = max(maxX, item.center.x + item.size.width / 2)
            maxY = max(maxY, item.center.y + item.size.height / 2)
        }
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + 2 * padding,
            height: (maxY - minY) + 2 * padding
        )
    }
}
