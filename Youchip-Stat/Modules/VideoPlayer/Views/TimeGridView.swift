//
//  TimeGridView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct TimeGridView: View {
    
    let duration: Double
    let interval: Double
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        Canvas { context, size in
            let numberOfLines = Int(duration / interval) + 1
            for i in 0..<numberOfLines {
                let timePosition = Double(i) * interval
                let xPosition = (timePosition / duration) * Double(width)
                var path = Path()
                path.move(to: CGPoint(x: xPosition, y: 0))
                path.addLine(to: CGPoint(x: xPosition, y: height))
                context.stroke(
                    path,
                    with: .color(Color.gray.opacity(0.3)),
                    lineWidth: 1.0
                )
            }
        }
        .frame(width: width, height: height)
    }
    
}
