//
//  LineWithArrowView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct LineWithArrowView: View {
    let object: DrawableObject
    let viewModel: PolygonEditorViewModel
    let geometry: GeometryProxy
    
    var body: some View {
        Group {
            if object.positions.count >= 2 {
                // Рисуем линию между точками
                DashedLinesShape(points: object.positions.map { viewModel.viewPoint(fromImagePoint: $0, in: geometry.size) })
                    .stroke(object.edgeColor, style: StrokeStyle(
                        lineWidth: 2,
                        dash: object.lineStyle == .dashed ? [5, 5] : []
                    ))
                
                // Рисуем стрелку на конце линии
                if let lastPoint = object.positions.last,
                   let secondLastPoint = object.positions.count >= 2 ? object.positions[object.positions.count - 2] : nil {
                    ArrowHeadShape(
                        startPoint: viewModel.viewPoint(fromImagePoint: secondLastPoint, in: geometry.size),
                        endPoint: viewModel.viewPoint(fromImagePoint: lastPoint, in: geometry.size)
                    )
                    .fill(object.edgeColor)
                }
            }
            
            // Вершины (кроме последней, так как там стрелка)
            ForEach(Array(object.positions.dropLast().enumerated()), id: \.offset) { index, position in
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

struct ArrowHeadShape: Shape {
    let startPoint: CGPoint
    let endPoint: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Вычисляем направление стрелки
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let angle = atan2(dy, dx)
        
        // Размер стрелки
        let arrowLength: CGFloat = 15
        let arrowWidth: CGFloat = 10
        
        // Вычисляем точки стрелки
        let arrowPoint1 = CGPoint(
            x: endPoint.x - arrowLength * cos(angle) + arrowWidth * cos(angle + .pi / 2),
            y: endPoint.y - arrowLength * sin(angle) + arrowWidth * sin(angle + .pi / 2)
        )
        let arrowPoint2 = CGPoint(
            x: endPoint.x - arrowLength * cos(angle) + arrowWidth * cos(angle - .pi / 2),
            y: endPoint.y - arrowLength * sin(angle) + arrowWidth * sin(angle - .pi / 2)
        )
        
        path.move(to: endPoint)
        path.addLine(to: arrowPoint1)
        path.addLine(to: arrowPoint2)
        path.closeSubpath()
        
        return path
    }
}
