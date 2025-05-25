//
//  MarkupMode.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import Foundation

enum MarkupMode: String, Codable {
    case standard
    case tagBased
    
    static var current: MarkupMode {
        get {
            guard let storedMode = UserDefaults.standard.string(forKey: "appMarkupMode") else {
                return .standard
            }
            return MarkupMode(rawValue: storedMode) ?? .standard
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appMarkupMode")
            NotificationCenter.default.post(name: .markupModeChanged, object: newValue)
        }
    }
}
