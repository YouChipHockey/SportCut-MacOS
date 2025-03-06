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
}
