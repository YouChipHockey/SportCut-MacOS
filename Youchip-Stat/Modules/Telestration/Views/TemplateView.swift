//
//  TemplateView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import SwiftUI

struct TemplateView: View {
    let template: TemplateObject
    let viewModel: PolygonEditorViewModel
    let geometry: GeometryProxy
    
    var body: some View {
        let customization = template.templateCustomization
        let misalignedIndices = viewModel.getMisalignedVertices(for: template)
        
        ZStack {
            if template.templatePositions.count >= 3 {
                PolygonShape(points: template.templatePositions.map { viewModel.viewPoint(fromImagePoint: $0, in: geometry.size) })
                    .fill(customization.fillColor.opacity(0.2))
                    .overlay(
                        PolygonShape(points: template.templatePositions.map { viewModel.viewPoint(fromImagePoint: $0, in: geometry.size) })
                            .stroke(customization.edgeColor, style: StrokeStyle(
                                lineWidth: 2,
                                dash: customization.lineStyle == .dashed ? [5, 5] : []
                            ))
                    )
            }
            
            ForEach(Array(template.templatePositions.enumerated()), id: \.offset) { index, position in
                Circle()
                    .fill(customization.vertexColor)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .frame(width: 30, height: 30)
                    .position(viewModel.viewPoint(fromImagePoint: position, in: geometry.size))
            }
            
            if customization.showMisalignedVertices {
                ForEach(misalignedIndices, id: \.self) { index in
                    if index < template.originalObject.positions.count {
                        let position = template.originalObject.positions[index]
                        let viewPosition = viewModel.viewPoint(fromImagePoint: position, in: geometry.size)
                        
                        Circle()
                            .fill(customization.misalignedVertexColor.opacity(0.3))
                            .overlay(
                                Circle()
                                    .stroke(customization.misalignedVertexColor, style: StrokeStyle(lineWidth: 3, dash: [3, 3]))
                            )
                            .frame(width: 40, height: 40)
                            .position(viewPosition)
                    }
                }
            }
        }
    }
}
