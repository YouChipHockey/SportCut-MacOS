//
//  TimelineTimestampsHeaderView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct TimelineTimestampsHeaderView: View {
    
    let duration: Double
    let interval: Double
    let width: CGFloat
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Modern gradient background matching button blocks
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.gray.opacity(0.05),
                    Color.gray.opacity(0.02)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: width, height: 30)
            
            // Subtle border
            Rectangle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                .frame(width: width, height: 30)
            
            // Time markers with improved styling
            ForEach(0..<(Int(duration / interval) + 1), id: \.self) { i in
                let timePosition = Double(i) * interval
                let xPosition = (timePosition / duration) * Double(width)
                
                VStack(spacing: 2) {
                    // Main time label
                    Text(secondsToTimeString(timePosition))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.1))
                                .padding(.horizontal, -2)
                                .padding(.vertical, -1)
                        )
                    
                    // Subtle tick mark
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 1, height: 4)
                }
                .position(x: CGFloat(xPosition), y: 15)
            }
        }
        .frame(width: width, height: 30)
    }
    
}
