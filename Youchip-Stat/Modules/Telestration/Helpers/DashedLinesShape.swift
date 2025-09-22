//
//  DashedLinesShape.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import SwiftUI

struct DashedLinesShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        
        for i in 0..<(points.count - 1) {
            path.move(to: points[i])
            path.addLine(to: points[i + 1])
        }
        
        return path
    }
}
