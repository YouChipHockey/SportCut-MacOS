//
//  ObjectListItem.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ObjectListItem: View {
    let object: DrawableObject
    let viewModel: PolygonEditorViewModel
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(object.number).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(object.type.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if !object.isVisible {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 4) {
                    switch object.type {
                    case .zoneBetweenObjects, .simpleZone:
                        Circle()
                            .fill(object.fillColor)
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(object.edgeColor)
                            .frame(width: 12, height: 12)
                        if object.type == .zoneBetweenObjects {
                            Circle()
                                .fill(object.vertexColor)
                                .frame(width: 12, height: 12)
                        }
                    case .lineBetweenObjects:
                        Circle()
                            .fill(object.edgeColor)
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(object.vertexColor)
                            .frame(width: 12, height: 12)
                    case .objectHighlight:
                        Circle()
                            .fill(object.edgeColor)
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(object.glowColor)
                            .frame(width: 12, height: 12)
                    }
                    
                    Text(object.lineStyle.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(object.isVisible ? Color.clear : Color.gray.opacity(0.1))
        .cornerRadius(4)
        .contextMenu {
            Button(object.isVisible ? ^String.Titles.hide : ^String.Titles.show) {
                viewModel.toggleObjectVisibility(object)
            }
            
            Button(object.showNumber ? ^String.Titles.hideNumber : ^String.Titles.showNumber) {
                viewModel.toggleObjectNumberVisibility(object)
            }
            
            Divider()
            
                                            Button(^String.Titles.delete, role: .destructive) {
                                 viewModel.deleteObject(object)
                             }
                             
                             if object.type != .objectHighlight && object.positions.count >= 4 && object.positions.count <= 8 {
                                 Divider()
                                 
                                 Button(^String.Titles.apply) {
                                     viewModel.showFormationSelection(for: object)
                                 }
                             }
                         }
                     }
                 }

struct Vertex: Identifiable, Equatable {
    let id = UUID()
    var position: CGPoint
    var size: CGFloat

    init(position: CGPoint, size: CGFloat = 30) {
        self.position = position
        self.size = size
    }

    static func == (lhs: Vertex, rhs: Vertex) -> Bool {
        lhs.id == rhs.id
    }
}
