//
//  NSColor+Convenience.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 26.06.2024.
//

import SwiftUI

extension NSColor {
    
    func adjustBrightness(by amount: CGFloat) -> NSColor? {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        self.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        b = max(0, min(1, b + amount))
        return NSColor(hue: h, saturation: s, brightness: b, alpha: a)
    }
    
}
