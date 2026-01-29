//
//  PolygonEditorView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct PolygonEditorView: View {
    @EnvironmentObject var viewModel: PolygonEditorViewModel
    @Environment(\.presentationMode) var presentationMode

    @State private var exportPayload: ExportPayload?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    viewModel.showingTypeSelection = true
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text(^String.Titles.addObject)
                    }
                }
                .disabled(viewModel.isCreatingObject)

                if viewModel.isCreatingObject {
                    Button(^String.Titles.done) {
                        viewModel.finishCreatingObject()
                    }
                    .disabled(viewModel.tempVertices.isEmpty)
                    
                    Button(^String.Titles.cancel) {
                        viewModel.cancelObjectCreation()
                    }
                }

                Spacer()

                Button(^String.Titles.clearAll) {
                    viewModel.clearAllObjects()
                }
                .disabled(viewModel.objects.isEmpty)

                                 Button(^String.Titles.export) {
                     if let exported = viewModel.exportImage() {
                         exportPayload = ExportPayload(image: exported)
                     }
                 }
                 .disabled(viewModel.objects.isEmpty && viewModel.templateObjects.isEmpty)

                Button(^String.Titles.close) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding()
            
            HStack(spacing: 0) {
                GeometryReader { geometry in
                    ZStack {
                        Image(nsImage: viewModel.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                         ForEach(viewModel.objects.filter { $0.isVisible }) { object in
                             ObjectView(object: object, viewModel: viewModel, geometry: geometry)
                         }
                         
                         ForEach(viewModel.templateObjects.filter { $0.isVisible }) { template in
                             TemplateView(template: template, viewModel: viewModel, geometry: geometry)
                         }
                        
                        if viewModel.isCreatingObject {
                            ForEach(Array(viewModel.tempVertices.enumerated()), id: \.offset) { index, position in
                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 20, height: 20)
                                    .position(viewModel.viewPoint(fromImagePoint: position, in: geometry.size))
                            }
                            
                            if let objectType = viewModel.currentObjectType {
                                switch objectType {
                                case .zoneBetweenObjects, .simpleZone:
                                    if viewModel.tempVertices.count >= 3 {
                                        PolygonShape(points: viewModel.tempVertices.map { viewModel.viewPoint(fromImagePoint: $0, in: geometry.size) })
                                            .fill(Color.red.opacity(0.2))
                                            .overlay(
                                                PolygonShape(points: viewModel.tempVertices.map { viewModel.viewPoint(fromImagePoint: $0, in: geometry.size) })
                                                    .stroke(Color.red, lineWidth: 2)
                                            )
                                    } else {
                                        EmptyView()
                                    }
                                case .lineBetweenObjects:
                                    if viewModel.tempVertices.count >= 2 {
                                        DashedLinesShape(points: viewModel.tempVertices.map { viewModel.viewPoint(fromImagePoint: $0, in: geometry.size) })
                                            .stroke(Color.red, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                                    } else {
                                        EmptyView()
                                    }
                                case .lineWithArrow:
                                    if viewModel.tempVertices.count >= 2 {
                                        DashedLinesShape(points: viewModel.tempVertices.map { viewModel.viewPoint(fromImagePoint: $0, in: geometry.size) })
                                            .stroke(Color.red, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                                    } else {
                                        EmptyView()
                                    }
                                case .curvedArrow:
                                    if viewModel.tempVertices.count >= 2 {
                                        let startPoint = viewModel.tempVertices[0]
                                        let endPoint = viewModel.tempVertices[1]
                                        
                                        // Вычисляем контрольную точку на основе curveHeight
                                        let midX = (startPoint.x + endPoint.x) / 2
                                        let midY = (startPoint.y + endPoint.y) / 2
                                        let dx = endPoint.x - startPoint.x
                                        let dy = endPoint.y - startPoint.y
                                        let length = sqrt(dx * dx + dy * dy)
                                        
                                        let controlPoint: CGPoint = {
                                            if length > 0 {
                                                let perpX = -dy / length
                                                let perpY = dx / length
                                                return CGPoint(
                                                    x: midX + perpX * viewModel.currentCustomization.curveHeight,
                                                    y: midY + perpY * viewModel.currentCustomization.curveHeight
                                                )
                                            } else {
                                                return CGPoint(x: midX, y: midY)
                                            }
                                        }()
                                        
                                        let startPointView = viewModel.viewPoint(fromImagePoint: startPoint, in: geometry.size)
                                        let endPointView = viewModel.viewPoint(fromImagePoint: endPoint, in: geometry.size)
                                        let controlPointView = viewModel.viewPoint(fromImagePoint: controlPoint, in: geometry.size)
                                        
                                        ZStack {
                                            CurvedArrowShape(startPoint: startPointView, endPoint: endPointView, controlPoint: controlPointView)
                                                .stroke(Color.red, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                                            
                                            CurvedArrowHeadShape(startPoint: startPointView, endPoint: endPointView, controlPoint: controlPointView)
                                                .fill(Color.red)
                                        }
                                    } else {
                                        EmptyView()
                                    }
                                case .objectHighlight:
                                    EmptyView()
                                }
                            }
                        }
                        
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        if viewModel.isCreatingObject {
                                            let loc = value.location
                                            let imgPoint = viewModel.imagePoint(fromViewPoint: loc, in: geometry.size)
                                            viewModel.addVertex(at: imgPoint)
                                        }
                                    }
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color.gray.opacity(0.1))
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(^String.Titles.objects)
                        .font(.headline)
                        .padding()
                    
                                         ScrollView {
                         LazyVStack(spacing: 8) {
                             ForEach(viewModel.objects) { object in
                                 ObjectListItem(object: object, viewModel: viewModel)
                             }
                             
                             if !viewModel.templateObjects.isEmpty {
                                 Divider()
                                     .padding(.vertical, 8)
                                 
                                 ForEach(viewModel.templateObjects) { template in
                                     TemplateListItem(template: template, viewModel: viewModel)
                                 }
                             }
                         }
                         .padding(.horizontal)
                     }
                    
                    Spacer()
                }
                .frame(width: 250)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
                 .sheet(isPresented: $viewModel.showingTypeSelection) {
             ObjectTypeSelectionSheet(viewModel: viewModel)
         }
         .sheet(isPresented: $viewModel.showingCustomization) {
             ObjectCustomizationSheet(viewModel: viewModel)
         }
         .sheet(isPresented: $viewModel.showingFormationSelection) {
             FormationSelectionSheet(viewModel: viewModel)
         }
         .sheet(isPresented: $viewModel.showingTemplateCustomization) {
             TemplateCustomizationSheet(viewModel: viewModel)
         }
         .sheet(item: $exportPayload) { payload in
             ExportSheet(image: payload.image)
         }
    }
}
