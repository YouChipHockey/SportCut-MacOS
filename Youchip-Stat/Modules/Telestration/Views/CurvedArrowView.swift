//
//  CurvedArrowView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 1/26/26.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct CurvedArrowView: View {
    let object: DrawableObject
    let viewModel: PolygonEditorViewModel
    let geometry: GeometryProxy
    
    // Вычисляем контрольную точку на основе curveHeight
    private func computeControlPoint(start: CGPoint, end: CGPoint, curveHeight: CGFloat) -> CGPoint {
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        
        // Вычисляем перпендикулярный вектор к линии
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        
        if length == 0 {
            return CGPoint(x: midX, y: midY)
        }
        
        // Перпендикулярный вектор (повернутый на 90 градусов)
        let perpX = -dy / length
        let perpY = dx / length
        
        // Контрольная точка смещена перпендикулярно на curveHeight
        return CGPoint(
            x: midX + perpX * curveHeight,
            y: midY + perpY * curveHeight
        )
    }
    
    var body: some View {
        Group {
            if object.positions.count >= 2 {
                let startPoint = viewModel.viewPoint(fromImagePoint: object.positions[0], in: geometry.size)
                let endPoint = viewModel.viewPoint(fromImagePoint: object.positions[1], in: geometry.size)
                
                // Вычисляем контрольную точку на основе curveHeight
                let controlPoint = computeControlPoint(
                    start: object.positions[0],
                    end: object.positions[1],
                    curveHeight: object.curveHeight
                )
                let controlPointView = viewModel.viewPoint(fromImagePoint: controlPoint, in: geometry.size)
                
                // Рисуем кривую Bezier стрелку
                CurvedArrowShape(
                    startPoint: startPoint,
                    endPoint: endPoint,
                    controlPoint: controlPointView
                )
                .stroke(object.edgeColor, style: StrokeStyle(
                    lineWidth: 2,
                    dash: object.lineStyle == .dashed ? [5, 5] : []
                ))
                
                // Рисуем стрелку на конце кривой
                CurvedArrowHeadShape(
                    startPoint: startPoint,
                    endPoint: endPoint,
                    controlPoint: controlPointView
                )
                .fill(object.edgeColor)
                
                // Показываем только начальную точку (конечная точка скрыта, так как там стрелка)
                Circle()
                    .fill(object.vertexColor)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .frame(width: 30, height: 30)
                    .position(startPoint)
            }
        }
    }
}

struct CurvedArrowShape: Shape {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let controlPoint: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: startPoint)
        // Квадратичная кривая Bezier с одной контрольной точкой
        path.addQuadCurve(to: endPoint, control: controlPoint)
        return path
    }
}

struct CurvedArrowHeadShape: Shape {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let controlPoint: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Вычисляем направление стрелки в конечной точке кривой
        // Для квадратичной кривой Bezier: B(t) = (1-t)²P₀ + 2(1-t)tP₁ + t²P₂
        // Производная: B'(t) = 2(1-t)(P₁-P₀) + 2t(P₂-P₁)
        // В конечной точке (t=1): B'(1) = 2(P₂-P₁) = 2(endPoint - controlPoint)
        let t: CGFloat = 0.95 // Близко к концу для более точного направления
        let curvePoint = CGPoint(
            x: pow(1-t, 2) * startPoint.x + 2 * (1-t) * t * controlPoint.x + pow(t, 2) * endPoint.x,
            y: pow(1-t, 2) * startPoint.y + 2 * (1-t) * t * controlPoint.y + pow(t, 2) * endPoint.y
        )
        
        // Вычисляем направление стрелки
        let dx = endPoint.x - curvePoint.x
        let dy = endPoint.y - curvePoint.y
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
