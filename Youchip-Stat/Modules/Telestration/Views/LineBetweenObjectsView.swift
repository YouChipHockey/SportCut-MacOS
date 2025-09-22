//
//  LineBetweenObjectsView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct LineBetweenObjectsView: View {
    let object: DrawableObject
    let viewModel: PolygonEditorViewModel
    let geometry: GeometryProxy
    
    var body: some View {
        Group {
            if object.positions.count >= 2 {
                DashedLinesShape(points: object.positions.map { viewModel.viewPoint(fromImagePoint: $0, in: geometry.size) })
                    .stroke(object.edgeColor, style: StrokeStyle(
                        lineWidth: 2,
                        dash: object.lineStyle == .dashed ? [5, 5] : []
                    ))
            }
            
            ForEach(Array(object.positions.enumerated()), id: \.offset) { index, position in
                Circle()
                    .fill(object.vertexColor)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .frame(width: 30, height: 30)
                    .position(viewModel.viewPoint(fromImagePoint: position, in: geometry.size))
            }
        }
    }
}
