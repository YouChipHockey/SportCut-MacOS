//
//  FootballFormation.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct FootballFormation {
    let id = UUID()
    let name: String
    let playerCount: Int
    let positions: [CGPoint] // Normalized positions (0.0-1.0)
    let category: String
    
    static let formations: [FootballFormation] = [
        // 4 игрока
        FootballFormation(name: "Квадрат", playerCount: 4, positions: [
            CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.7, y: 0.3),
            CGPoint(x: 0.7, y: 0.7), CGPoint(x: 0.3, y: 0.7)
        ], category: "Оборона"),
        
        FootballFormation(name: "Ромб", playerCount: 4, positions: [
            CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.7, y: 0.5),
            CGPoint(x: 0.5, y: 0.8), CGPoint(x: 0.3, y: 0.5)
        ], category: "Атака"),
        
        FootballFormation(name: "Линия", playerCount: 4, positions: [
            CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.4, y: 0.5),
            CGPoint(x: 0.6, y: 0.5), CGPoint(x: 0.8, y: 0.5)
        ], category: "Оборона"),
        
        FootballFormation(name: "Треугольник+1", playerCount: 4, positions: [
            CGPoint(x: 0.5, y: 0.3), CGPoint(x: 0.7, y: 0.6),
            CGPoint(x: 0.5, y: 0.8), CGPoint(x: 0.3, y: 0.6)
        ], category: "Атака"),
        
        // 5 игроков
        FootballFormation(name: "W-формация", playerCount: 5, positions: [
            CGPoint(x: 0.4, y: 0.2), CGPoint(x: 0.6, y: 0.2),
            CGPoint(x: 0.8, y: 0.4), CGPoint(x: 0.5, y: 0.6),
            CGPoint(x: 0.2, y: 0.4)
        ], category: "Атака"),
        
        FootballFormation(name: "Пентагон", playerCount: 5, positions: [
            CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.8, y: 0.4),
            CGPoint(x: 0.7, y: 0.8), CGPoint(x: 0.3, y: 0.8),
            CGPoint(x: 0.2, y: 0.4)
        ], category: "Универсал"),
        
        FootballFormation(name: "Стрела", playerCount: 5, positions: [
            CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.7, y: 0.4),
            CGPoint(x: 0.6, y: 0.7), CGPoint(x: 0.4, y: 0.7),
            CGPoint(x: 0.3, y: 0.4)
        ], category: "Атака"),
        
        FootballFormation(name: "Крест", playerCount: 5, positions: [
            CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.7, y: 0.5),
            CGPoint(x: 0.5, y: 0.8), CGPoint(x: 0.3, y: 0.5),
            CGPoint(x: 0.5, y: 0.5)
        ], category: "Универсал"),
        
        // 6 игроков
        FootballFormation(name: "Гексагон", playerCount: 6, positions: [
            CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.7, y: 0.35),
            CGPoint(x: 0.7, y: 0.65), CGPoint(x: 0.5, y: 0.8),
            CGPoint(x: 0.3, y: 0.65), CGPoint(x: 0.3, y: 0.35)
        ], category: "Универсал"),
        
        FootballFormation(name: "2-2-2", playerCount: 6, positions: [
            CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.7, y: 0.3),
            CGPoint(x: 0.7, y: 0.5), CGPoint(x: 0.7, y: 0.7),
            CGPoint(x: 0.3, y: 0.7), CGPoint(x: 0.3, y: 0.5)
        ], category: "Оборона"),
        
        FootballFormation(name: "Звезда", playerCount: 6, positions: [
            CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.7, y: 0.4),
            CGPoint(x: 0.6, y: 0.7), CGPoint(x: 0.4, y: 0.7),
            CGPoint(x: 0.3, y: 0.4), CGPoint(x: 0.5, y: 0.55)
        ], category: "Атака"),
        
        FootballFormation(name: "Двойной треугольник", playerCount: 6, positions: [
            CGPoint(x: 0.4, y: 0.3), CGPoint(x: 0.6, y: 0.3),
            CGPoint(x: 0.7, y: 0.7), CGPoint(x: 0.5, y: 0.8),
            CGPoint(x: 0.3, y: 0.7), CGPoint(x: 0.5, y: 0.45)
        ], category: "Атака"),
        
        // 7 игроков
        FootballFormation(name: "3-2-2", playerCount: 7, positions: [
            CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.5, y: 0.3),
            CGPoint(x: 0.8, y: 0.3), CGPoint(x: 0.65, y: 0.55),
            CGPoint(x: 0.7, y: 0.8), CGPoint(x: 0.3, y: 0.8),
            CGPoint(x: 0.35, y: 0.55)
        ], category: "Универсал"),
        
        FootballFormation(name: "V-формация", playerCount: 7, positions: [
            CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.7, y: 0.4),
            CGPoint(x: 0.8, y: 0.6), CGPoint(x: 0.65, y: 0.8),
            CGPoint(x: 0.35, y: 0.8), CGPoint(x: 0.2, y: 0.6),
            CGPoint(x: 0.3, y: 0.4)
        ], category: "Атака"),
        
        FootballFormation(name: "Цветок", playerCount: 7, positions: [
            CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.7, y: 0.35),
            CGPoint(x: 0.7, y: 0.65), CGPoint(x: 0.5, y: 0.8),
            CGPoint(x: 0.3, y: 0.65), CGPoint(x: 0.3, y: 0.35),
            CGPoint(x: 0.5, y: 0.5)
        ], category: "Универсал"),
        
        FootballFormation(name: "Стрелка", playerCount: 7, positions: [
            CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.7, y: 0.35),
            CGPoint(x: 0.8, y: 0.5), CGPoint(x: 0.6, y: 0.75),
            CGPoint(x: 0.4, y: 0.75), CGPoint(x: 0.2, y: 0.5),
            CGPoint(x: 0.3, y: 0.35)
        ], category: "Атака"),
        
        // 8 игроков
        FootballFormation(name: "3-3-2", playerCount: 8, positions: [
            CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.5, y: 0.3),
            CGPoint(x: 0.8, y: 0.3), CGPoint(x: 0.8, y: 0.55),
            CGPoint(x: 0.65, y: 0.8), CGPoint(x: 0.35, y: 0.8),
            CGPoint(x: 0.2, y: 0.55), CGPoint(x: 0.5, y: 0.55)
        ], category: "Универсал"),
        
        FootballFormation(name: "Октагон", playerCount: 8, positions: [
            CGPoint(x: 0.5, y: 0.15), CGPoint(x: 0.75, y: 0.25),
            CGPoint(x: 0.85, y: 0.5), CGPoint(x: 0.75, y: 0.75),
            CGPoint(x: 0.5, y: 0.85), CGPoint(x: 0.25, y: 0.75),
            CGPoint(x: 0.15, y: 0.5), CGPoint(x: 0.25, y: 0.25)
        ], category: "Оборона"),
        
        FootballFormation(name: "Двойной ромб", playerCount: 8, positions: [
            CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.7, y: 0.35),
            CGPoint(x: 0.8, y: 0.65), CGPoint(x: 0.65, y: 0.8),
            CGPoint(x: 0.35, y: 0.8), CGPoint(x: 0.2, y: 0.65),
            CGPoint(x: 0.3, y: 0.35), CGPoint(x: 0.5, y: 0.5)
        ], category: "Атака"),
        
        FootballFormation(name: "Крепость", playerCount: 8, positions: [
            CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.5, y: 0.2),
            CGPoint(x: 0.8, y: 0.2), CGPoint(x: 0.8, y: 0.5),
            CGPoint(x: 0.8, y: 0.8), CGPoint(x: 0.5, y: 0.8),
            CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.2, y: 0.5)
        ], category: "Оборона")
    ]
}
