//
//  SimpleZoneView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SimpleZoneView: View {
    let object: DrawableObject
    let viewModel: PolygonEditorViewModel
    let geometry: GeometryProxy
    
    var body: some View {
        Group {
            if object.positions.count >= 3 {
                PolygonShape(points: object.positions.map { viewModel.viewPoint(fromImagePoint: $0, in: geometry.size) })
                    .fill(object.fillColor.opacity(0.3))
                    .overlay(
                        PolygonShape(points: object.positions.map { viewModel.viewPoint(fromImagePoint: $0, in: geometry.size) })
                            .stroke(object.edgeColor, style: StrokeStyle(
                                lineWidth: 2,
                                dash: object.lineStyle == .dashed ? [5, 5] : []
                            ))
                    )
            }
            // В простой зоне нет вершин после нажатия done
        }
    }
}
