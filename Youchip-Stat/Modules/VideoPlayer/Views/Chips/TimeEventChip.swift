//
//  TimeEventChip.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct TimeEventChip: View {
    
    let event: TimeEvent
    let fontSize: CGFloat
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: fontSize))
            Text(event.name)
                .lineLimit(1)
                .font(.system(size: fontSize))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.yellow.opacity(0.3))
        .cornerRadius(8)
        .foregroundColor(.black)
    }
    
}
