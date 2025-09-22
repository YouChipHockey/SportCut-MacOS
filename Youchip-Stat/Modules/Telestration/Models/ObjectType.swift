//
//  ObjectType.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

enum ObjectType: String, CaseIterable {
    case zoneBetweenObjects = "zone_between_objects"
    case lineBetweenObjects = "line_between_objects"
    case objectHighlight = "object_highlight"
    case simpleZone = "simple_zone"
    
    var displayName: String {
        switch self {
        case .zoneBetweenObjects:
            return "Зона между объектами"
        case .lineBetweenObjects:
            return "Линия между объектами"
        case .objectHighlight:
            return "Выделение объекта"
        case .simpleZone:
            return "Обычная зона"
        }
    }
}
