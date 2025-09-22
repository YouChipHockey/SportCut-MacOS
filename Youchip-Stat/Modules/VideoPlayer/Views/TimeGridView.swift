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
            
            // Draw major grid lines (every 5th line)
            for i in 0..<numberOfLines {
                let timePosition = Double(i) * interval
                let xPosition = (timePosition / duration) * Double(width)
                
                var path = Path()
                path.move(to: CGPoint(x: xPosition, y: 0))
                path.addLine(to: CGPoint(x: xPosition, y: height))
                
                // Different styling for major and minor lines
                let isMajorLine = i % 5 == 0
                let lineWidth: CGFloat = isMajorLine ? 1.0 : 0.5
                let opacity: Double = isMajorLine ? 0.4 : 0.2
                
                context.stroke(
                    path,
                    with: .color(Color.gray.opacity(opacity)),
                    lineWidth: lineWidth
                )
            }
            
            // Add horizontal separator lines for better visual separation
            let numberOfRows = Int(height / 30) // Assuming 30pt per row
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
