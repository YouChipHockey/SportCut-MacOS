//
//  LineBetweenObjectsCustomization.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import SwiftUI

struct LineBetweenObjectsCustomization: View {
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
            
            HStack {
                Text(^String.Titles.lineType)
                Spacer()
                Picker("", selection: $viewModel.currentCustomization.lineStyle) {
                    ForEach(LineStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 120)
            }
        }
    }
}
