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
            let d = max(duration, 0.000_001)
            var gridInterval = max(interval, 0.000_001)
            var lineCount = Int(ceil(d / gridInterval)) + 1
            let maxLines = 550
            while lineCount > maxLines {
                gridInterval *= 1.35
                lineCount = Int(ceil(d / gridInterval)) + 1
            }
            let numberOfLines = max(1, lineCount)
            for i in 0..<numberOfLines {
                let timePosition = Double(i) * gridInterval
                let xPosition = (timePosition / d) * Double(width)
                
                var path = Path()
                path.move(to: CGPoint(x: xPosition, y: 0))
                path.addLine(to: CGPoint(x: xPosition, y: height))
                
                let isMajorLine = i % 5 == 0
                let lineWidth: CGFloat = isMajorLine ? 1.0 : 0.5
                let opacity: Double = isMajorLine ? 0.4 : 0.2
                
                context.stroke(
                    path,
                    with: .color(Color.gray.opacity(opacity)),
                    lineWidth: lineWidth
                )
            }
            
            let numberOfRows = Int(height / 30)
            for i in 1..<numberOfRows {
                let yPosition = CGFloat(i) * 30
                var path = Path()
                path.move(to: CGPoint(x: 0, y: yPosition))
                path.addLine(to: CGPoint(x: width, y: yPosition))
                context.stroke(
                    path,
                    with: .color(Color.gray.opacity(0.15)),
                    lineWidth: 0.5
                )
            }
        }
        .frame(width: width, height: height)
    }
    
}
