//
//  CurvedArrowCustomization.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 1/26/26.
//

import SwiftUI

struct CurvedArrowCustomization: View {
    @ObservedObject var viewModel: PolygonEditorViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(^String.Titles.lineColor)
                Spacer()
                ColorPicker("", selection: $viewModel.currentCustomization.edgeColor)
                    .frame(width: 40, height: 30)
            }
            
            HStack {
                Text(^String.Titles.vertexColor)
                Spacer()
                ColorPicker("", selection: $viewModel.currentCustomization.vertexColor)
                    .frame(width: 40, height: 30)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(^String.Titles.lineType)
                Picker("", selection: $viewModel.currentCustomization.lineStyle) {
                    ForEach(LineStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 120)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.curvedArrowHeightLabel)
                    .font(.subheadline)
                
                HStack {
                    Slider(value: $viewModel.currentCustomization.curveHeight, in: -300...300)
                    Text("\(Int(viewModel.currentCustomization.curveHeight))")
                        .frame(width: 50)
                        .font(.caption)
                }
            }
        }
    }
}
