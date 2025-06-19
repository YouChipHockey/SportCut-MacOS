//
//  Color.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 05.03.2025.
//

import SwiftUI

extension Color {
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func darken(by amount: CGFloat) -> Color {
        let uiColor = NSColor(self)
        guard let adjustedColor = uiColor.adjustBrightness(by: -amount) else {
            return self
        }
        return Color(adjustedColor)
    }
    
    static func random() -> Color {
        Color(
            red:   .random(in: 0...1),
            green: .random(in: 0...1),
            blue:  .random(in: 0...1)
        )
    }
    
    var isDark: Bool {
            #if os(macOS)
            let nativeColor = NSColor(self)
            guard let convertedColor = nativeColor.usingColorSpace(.deviceRGB) else {
                return false
            }
            let red = convertedColor.redComponent
            let green = convertedColor.greenComponent
            let blue = convertedColor.blueComponent
            #else
            let nativeColor = UIColor(self)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            nativeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            #endif

            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            return luminance < 0.5
        }
}
