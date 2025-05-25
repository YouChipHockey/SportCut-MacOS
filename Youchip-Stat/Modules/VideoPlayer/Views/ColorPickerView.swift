//
//  ColorPickerView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI
import Foundation

struct ColorPickerView: View {
    @Binding var selectedColor: Color
    @Binding var hexString: String
    @State private var isExpanded: Bool = false
    
    let basicColors: [ColorOption] = [
        ColorOption(color: .red, hex: "FF0000"),
        ColorOption(color: .orange, hex: "FFA500"),
        ColorOption(color: .yellow, hex: "FFFF00"),
        ColorOption(color: .green, hex: "00FF00"),
        ColorOption(color: .blue, hex: "0000FF"),
        ColorOption(color: .purple, hex: "800080"),
        ColorOption(color: .pink, hex: "FFC0CB"),
        ColorOption(color: .black, hex: "000000"),
        ColorOption(color: .gray, hex: "808080"),
        ColorOption(color: .white, hex: "FFFFFF")
    ]
    
    let extendedColors: [ColorOption] = [
        ColorOption(color: Color(hex: "FF4500"), hex: "FF4500"), // Color: OrangeRed
        ColorOption(color: Color(hex: "FF8C00"), hex: "FF8C00"), // Color: DarkOrange
        ColorOption(color: Color(hex: "FFD700"), hex: "FFD700"), // Color: Gold
        ColorOption(color: Color(hex: "ADFF2F"), hex: "ADFF2F"), // Color: GreenYellow
        ColorOption(color: Color(hex: "32CD32"), hex: "32CD32"), // Color: LimeGreen
        ColorOption(color: Color(hex: "008000"), hex: "008000"), // Color: Green
        ColorOption(color: Color(hex: "20B2AA"), hex: "20B2AA"), // Color: LightSeaGreen
        ColorOption(color: Color(hex: "87CEEB"), hex: "87CEEB"), // Color: SkyBlue
        ColorOption(color: Color(hex: "4169E1"), hex: "4169E1"), // Color: RoyalBlue
        ColorOption(color: Color(hex: "000080"), hex: "000080"), // Color: Navy
        ColorOption(color: Color(hex: "8A2BE2"), hex: "8A2BE2"), // Color: BlueViolet
        ColorOption(color: Color(hex: "9370DB"), hex: "9370DB"), // Color: MediumPurple
        ColorOption(color: Color(hex: "FF1493"), hex: "FF1493"), // Color: DeepPink
        ColorOption(color: Color(hex: "C71585"), hex: "C71585"), // Color: MediumVioletRed
        ColorOption(color: Color(hex: "8B4513"), hex: "8B4513"), // Color: SaddleBrown
        ColorOption(color: Color(hex: "A0522D"), hex: "A0522D"), // Color: Sienna
        ColorOption(color: Color(hex: "CD853F"), hex: "CD853F"), // Color: Peru
        ColorOption(color: Color(hex: "D2691E"), hex: "D2691E"), // Color: Chocolate
        ColorOption(color: Color(hex: "2F4F4F"), hex: "2F4F4F"), // Color: DarkSlateGray
        ColorOption(color: Color(hex: "708090"), hex: "708090")  // Color: SlateGray
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Цвет:")
                Spacer()
                Button(action: {
                    isExpanded.toggle()
                }) {
                    Text(isExpanded ? "Свернуть" : "Больше цветов")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 10) {
                ForEach(basicColors, id: \.hex) { colorOption in
                    colorCircleView(colorOption: colorOption)
                }
            }
            if isExpanded {
                Divider()
                    .padding(.vertical, 5)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 10) {
                    ForEach(extendedColors, id: \.hex) { colorOption in
                        colorCircleView(colorOption: colorOption)
                    }
                }
            }
            
            HStack {
                Text("HEX:")
                TextField("HEX:", text: $hexString)
                    .frame(width: 80)
                    .disabled(true)
            }
            
            Rectangle()
                .fill(selectedColor)
                .frame(height: 30)
                .overlay(
                    Text(hexString)
                        .foregroundColor(isDark(hexString) ? .white : .black)
                )
        }
    }
    
    @ViewBuilder
    private func colorCircleView(colorOption: ColorOption) -> some View {
        Circle()
            .fill(colorOption.color)
            .frame(width: 30, height: 30)
            .overlay(
                Circle()
                    .stroke(Color.black, lineWidth: colorOption.hex == hexString ? 2 : 0)
            )
            .overlay(
                Group {
                    if colorOption.hex == hexString {
                        Image(systemName: "checkmark")
                            .foregroundColor(isDark(colorOption.hex) ? .white : .black)
                    }
                }
            )
            .shadow(color: .gray.opacity(0.3), radius: 2, x: 1, y: 1)
            .onTapGesture {
                selectedColor = colorOption.color
                hexString = colorOption.hex
            }
    }
    
    private func isDark(_ hexString: String) -> Bool {
        guard hexString.count == 6 else { return false }
        
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16)
        let g = Double((rgb & 0x00FF00) >> 8)
        let b = Double(rgb & 0x0000FF)
        
        let brightness = (0.299*r + 0.587*g + 0.114*b)
        
        return brightness < 128
    }
}
