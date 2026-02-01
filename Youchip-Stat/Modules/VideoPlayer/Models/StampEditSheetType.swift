//
//  StampEditSheetType.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 21.12.2025.
//

enum StampEditSheetType: String, Identifiable {
    case lables
    case timeEvents
    
    var id: String { rawValue }
}
