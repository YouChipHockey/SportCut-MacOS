//
//  PieChartView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI

struct PieChartView: View {
    let statistics: [TagStatistics]
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2
            let angles = calculateAngles(for: statistics)
            
            ZStack {
                ForEach(0..<statistics.count, id: \.self) { index in
                    let startAngle = angles[index].start
                    let endAngle = angles[index].end
                    
                    Path { path in
                        path.move(to: center)
                        path.addArc(center: center, radius: radius, startAngle: Angle(degrees: startAngle), endAngle: Angle(degrees: endAngle), clockwise: false)
                        path.closeSubpath()
                    }
                    .fill(statistics[index].color)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func calculateAngles(for statistics: [TagStatistics]) -> [(start: Double, end: Double)] {
        var currentStartAngle: Double = 0.0
        var angles: [(start: Double, end: Double)] = []
        
        for stat in statistics {
            let angle = (stat.percentage / 100) * 360.0
            let endAngle = currentStartAngle + angle
            angles.append((start: currentStartAngle, end: endAngle))
            currentStartAngle = endAngle
        }
        
        return angles
    }
}
