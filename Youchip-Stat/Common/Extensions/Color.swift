//
//  Color.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 05.03.2025.
//

import SwiftUI

extension Color {
    static func random() -> Color {
        Color(
            red:   .random(in: 0...1),
            green: .random(in: 0...1),
            blue:  .random(in: 0...1)
        )
    }
    
    var isDark: Bool {
            #if os(macOS)
            // Для macOS
            let nativeColor = NSColor(self)
            guard let convertedColor = nativeColor.usingColorSpace(.deviceRGB) else {
                return false
            }
            let red = convertedColor.redComponent
            let green = convertedColor.greenComponent
            let blue = convertedColor.blueComponent
            #else
            // Для iOS
            let nativeColor = UIColor(self)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            nativeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            #endif

            // Формула для относительной яркости (W3C)
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            return luminance < 0.5
        }
}
