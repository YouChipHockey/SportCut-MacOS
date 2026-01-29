//
//  ObjectView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ObjectView: View {
    let object: DrawableObject
    let viewModel: PolygonEditorViewModel
    let geometry: GeometryProxy
    
    var body: some View {
        ZStack {
            switch object.type {
            case .zoneBetweenObjects:
                ZoneBetweenObjectsView(object: object, viewModel: viewModel, geometry: geometry)
            case .lineBetweenObjects:
                LineBetweenObjectsView(object: object, viewModel: viewModel, geometry: geometry)
            case .lineWithArrow:
                LineWithArrowView(object: object, viewModel: viewModel, geometry: geometry)
            case .curvedArrow:
                CurvedArrowView(object: object, viewModel: viewModel, geometry: geometry)
            case .objectHighlight:
                ObjectHighlightView(object: object, viewModel: viewModel, geometry: geometry)
            case .simpleZone:
                SimpleZoneView(object: object, viewModel: viewModel, geometry: geometry)
            }
            
            if object.showNumber, let firstPosition = object.positions.first {
                Text("\(object.number)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 24, height: 24)
                    )
                    .position(
                        CGPoint(
                            x: viewModel.viewPoint(fromImagePoint: firstPosition, in: geometry.size).x,
                            y: viewModel.viewPoint(fromImagePoint: firstPosition, in: geometry.size).y - 30
                        )
                    )
            }
        }
    }
}

struct ZoneBetweenObjectsView: View {
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
