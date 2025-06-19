//
//  LabelChip.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct LabelChip: View {
    
    let label: Label
    let baseColor: Color
    let fontSize: CGFloat
    
    var body: some View {
        let textColor = baseColor.isDark ? Color.white : Color.black
        let backgroundColor = baseColor.darken(by: 0.2)
        HStack(spacing: 3) {
            Image(systemName: "tag.fill")
            Text(label.name)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor)
        .cornerRadius(8)
        .foregroundColor(textColor)
        .font(.system(size: fontSize))
    }
    
}
