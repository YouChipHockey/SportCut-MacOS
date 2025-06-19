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
            Rectangle()
                .fill(Color.gray.opacity(0.05))
                .frame(width: width, height: 30)
            ForEach(0..<(Int(duration / interval) + 1), id: \.self) { i in
                let timePosition = Double(i) * interval
                let xPosition = (timePosition / duration) * Double(width)
                
                Text(secondsToTimeString(timePosition))
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .position(x: CGFloat(xPosition), y: 5)
            }
        }
        .frame(width: width, height: 30)
    }
    
}
