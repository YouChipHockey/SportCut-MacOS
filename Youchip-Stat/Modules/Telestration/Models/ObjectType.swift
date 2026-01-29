//
//  ObjectType.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

enum ObjectType: String, CaseIterable {
    case zoneBetweenObjects = "zone_between_objects"
    case lineBetweenObjects = "line_between_objects"
    case lineWithArrow = "line_with_arrow"
    case curvedArrow = "curved_arrow"
    case objectHighlight = "object_highlight"
    case simpleZone = "simple_zone"
    
    var displayName: String {
        switch self {
        case .zoneBetweenObjects:
            return ^String.Titles.zoneBetweenObjects
        case .lineBetweenObjects:
            return ^String.Titles.lineBetweenObjects
        case .lineWithArrow:
            return ^String.Titles.lineWithArrow
        case .curvedArrow:
            return ^String.Titles.curvedArrow
        case .objectHighlight:
            return ^String.Titles.objectHighlight
        case .simpleZone:
            return ^String.Titles.simpleZone
        }
    }
}
