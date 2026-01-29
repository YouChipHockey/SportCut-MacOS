//
//  TemplateCustomizationSheet.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import SwiftUI

struct TemplateCustomizationSheet: View {
    @ObservedObject var viewModel: PolygonEditorViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            if let template = viewModel.pendingTemplate {
                Text("\(^String.Titles.templateCustomization) \(template.formationName)")
                    .font(.headline)
                
                VStack(spacing: 12) {
                    HStack {
                        Text(^String.Titles.edgeColor)
                        Spacer()
                        ColorPicker("", selection: $viewModel.currentTemplateCustomization.edgeColor)
                            .frame(width: 40, height: 30)
                    }
                    
                    HStack {
                        Text(^String.Titles.vertexColor)
                        Spacer()
                        ColorPicker("", selection: $viewModel.currentTemplateCustomization.vertexColor)
                            .frame(width: 40, height: 30)
                    }
                    
                    HStack {
                        Text(^String.Titles.fillColor)
                        Spacer()
                        ColorPicker("", selection: $viewModel.currentTemplateCustomization.fillColor)
                            .frame(width: 40, height: 30)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(^String.Titles.lineType)
                        Picker("", selection: $viewModel.currentTemplateCustomization.lineStyle) {
                            ForEach(LineStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 120)
                    }
                    
                    Divider()
                    
                    Toggle(^String.Titles.showMisalignedVertices, isOn: $viewModel.currentTemplateCustomization.showMisalignedVertices)
                    
                    if viewModel.currentTemplateCustomization.showMisalignedVertices {
                        HStack {
                            Text(^String.Titles.warningColor)
                            Spacer()
                            ColorPicker("", selection: $viewModel.currentTemplateCustomization.misalignedVertexColor)
                                .frame(width: 40, height: 30)
                        }
                        
                        HStack {
                            Text(^String.Titles.discrepancyThreshold)
                            Spacer()
                            Slider(value: $viewModel.currentTemplateCustomization.misalignmentThreshold, in: 10...50, step: 5)
                                .frame(width: 120)
                            Text("\(Int(viewModel.currentTemplateCustomization.misalignmentThreshold))px")
                                .frame(width: 40)
                        }
                    }
                }
                
                HStack {
                    Button(^String.Titles.cancel) {
                        viewModel.cancelTemplateCreation()
                        presentationMode.wrappedValue.dismiss()
                    }
                    
                    Button(^String.Titles.apply) {
                        viewModel.confirmTemplateCreation()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .frame(width: 400)
    }
}
