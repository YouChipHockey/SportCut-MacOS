//
//  ObjectHighlightView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ObjectHighlightView: View {
    let object: DrawableObject
    let viewModel: PolygonEditorViewModel
    let geometry: GeometryProxy
    
    var body: some View {
        Group {
            if let position = object.positions.first {
                let viewPosition = viewModel.viewPoint(fromImagePoint: position, in: geometry.size)
                
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                object.glowColor.opacity(0.9 * object.glowOpacity),
                                object.glowColor.opacity(0.6 * object.glowOpacity),
                                object.glowColor.opacity(0.3 * object.glowOpacity),
                                Color.clear
                            ]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: object.radius, height: object.radius * 2)
                    .position(CGPoint(x: viewPosition.x, y: viewPosition.y - object.radius))
                    .blur(radius: 2)
                
                Ellipse()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                object.edgeColor.opacity(0.8 * object.glowOpacity),
                                object.edgeColor.opacity(0.6 * object.glowOpacity),
                                object.edgeColor.opacity(0.4 * object.glowOpacity)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: object.radius * 0.7
                        )
                    )
                    .overlay(
                        Ellipse()
                            .stroke(object.edgeColor.opacity(object.glowOpacity), lineWidth: 2)
                    )
                    .frame(width: object.radius, height: object.radius * 0.6)
                    .position(viewPosition)
            }
        }
    }
}
