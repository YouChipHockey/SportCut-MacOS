//
//  ObjectHighlightCustomization.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import SwiftUI

struct ObjectHighlightCustomization: View {
    @ObservedObject var viewModel: PolygonEditorViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(^String.Titles.color)
                Spacer()
                ColorPicker("", selection: $viewModel.currentCustomization.edgeColor)
                    .frame(width: 40, height: 30)
            }
            
            HStack {
                Text(^String.Titles.glowColor)
                Spacer()
                ColorPicker("", selection: $viewModel.currentCustomization.glowColor)
                    .frame(width: 40, height: 30)
            }
            
            HStack {
                Text(^String.Titles.radius)
                Spacer()
                Slider(value: $viewModel.currentCustomization.radius, in: 20...100, step: 5)
                    .frame(width: 120)
                Text("\(Int(viewModel.currentCustomization.radius))")
                    .frame(width: 30)
            }
        }
    }
}
