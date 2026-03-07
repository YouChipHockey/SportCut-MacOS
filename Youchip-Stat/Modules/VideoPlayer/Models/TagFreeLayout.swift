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
}

/// Положение и внешний вид одного тега в свободной раскладке.
struct TagFreeLayoutItem: Codable, Identifiable {
    /// Используем id тега как стабильный идентификатор.
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
}

/// Описание свободной раскладки для всей коллекции.
struct TagFreeLayout: Codable {
    /// Ширина виртуального холста (в условных единицах).
    var canvasWidth: CGFloat
    
    /// Высота виртуального холста (в условных единицах).
    var canvasHeight: CGFloat
    
    /// Набор элементов для всех тегов коллекции.
    var items: [TagFreeLayoutItem]
}

