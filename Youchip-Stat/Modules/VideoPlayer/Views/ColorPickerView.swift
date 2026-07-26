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
        // Reds
        ColorOption(color: Color(hex: "FFCDD2"), hex: "FFCDD2"),
        ColorOption(color: Color(hex: "EF9A9A"), hex: "EF9A9A"),
        ColorOption(color: Color(hex: "E57373"), hex: "E57373"),
        ColorOption(color: Color(hex: "F44336"), hex: "F44336"),
        ColorOption(color: Color(hex: "E53935"), hex: "E53935"),
        ColorOption(color: Color(hex: "C62828"), hex: "C62828"),
        ColorOption(color: Color(hex: "B71C1C"), hex: "B71C1C"),
        ColorOption(color: Color(hex: "FF4500"), hex: "FF4500"), // OrangeRed

        // Oranges & ambers
        ColorOption(color: Color(hex: "FFCCBC"), hex: "FFCCBC"),
        ColorOption(color: Color(hex: "FFAB91"), hex: "FFAB91"),
        ColorOption(color: Color(hex: "FF7043"), hex: "FF7043"),
        ColorOption(color: Color(hex: "FF5722"), hex: "FF5722"),
        ColorOption(color: Color(hex: "FF8C00"), hex: "FF8C00"), // DarkOrange
        ColorOption(color: Color(hex: "FB8C00"), hex: "FB8C00"),
        ColorOption(color: Color(hex: "EF6C00"), hex: "EF6C00"),
        ColorOption(color: Color(hex: "FFB300"), hex: "FFB300"), // Amber

        // Yellows
        ColorOption(color: Color(hex: "FFF59D"), hex: "FFF59D"),
        ColorOption(color: Color(hex: "FFEE58"), hex: "FFEE58"),
        ColorOption(color: Color(hex: "FDD835"), hex: "FDD835"),
        ColorOption(color: Color(hex: "FFD700"), hex: "FFD700"), // Gold
        ColorOption(color: Color(hex: "F9A825"), hex: "F9A825"),
        ColorOption(color: Color(hex: "F57F17"), hex: "F57F17"),

        // Limes & greens
        ColorOption(color: Color(hex: "ADFF2F"), hex: "ADFF2F"), // GreenYellow
        ColorOption(color: Color(hex: "DCE775"), hex: "DCE775"),
        ColorOption(color: Color(hex: "C0CA33"), hex: "C0CA33"),
        ColorOption(color: Color(hex: "AED581"), hex: "AED581"),
        ColorOption(color: Color(hex: "81C784"), hex: "81C784"),
        ColorOption(color: Color(hex: "4CAF50"), hex: "4CAF50"),
        ColorOption(color: Color(hex: "32CD32"), hex: "32CD32"), // LimeGreen
        ColorOption(color: Color(hex: "2E7D32"), hex: "2E7D32"),
        ColorOption(color: Color(hex: "008000"), hex: "008000"), // Green
        ColorOption(color: Color(hex: "1B5E20"), hex: "1B5E20"),

        // Teals & cyans
        ColorOption(color: Color(hex: "80CBC4"), hex: "80CBC4"),
        ColorOption(color: Color(hex: "26A69A"), hex: "26A69A"),
        ColorOption(color: Color(hex: "20B2AA"), hex: "20B2AA"), // LightSeaGreen
        ColorOption(color: Color(hex: "00897B"), hex: "00897B"),
        ColorOption(color: Color(hex: "00695C"), hex: "00695C"),
        ColorOption(color: Color(hex: "00BCD4"), hex: "00BCD4"), // Cyan
        ColorOption(color: Color(hex: "0097A7"), hex: "0097A7"),

        // Blues
        ColorOption(color: Color(hex: "87CEEB"), hex: "87CEEB"), // SkyBlue
        ColorOption(color: Color(hex: "4FC3F7"), hex: "4FC3F7"),
        ColorOption(color: Color(hex: "29B6F6"), hex: "29B6F6"),
        ColorOption(color: Color(hex: "2196F3"), hex: "2196F3"),
        ColorOption(color: Color(hex: "1E88E5"), hex: "1E88E5"),
        ColorOption(color: Color(hex: "4169E1"), hex: "4169E1"), // RoyalBlue
        ColorOption(color: Color(hex: "1565C0"), hex: "1565C0"),
        ColorOption(color: Color(hex: "0D47A1"), hex: "0D47A1"),
        ColorOption(color: Color(hex: "000080"), hex: "000080"), // Navy

        // Indigos & purples
        ColorOption(color: Color(hex: "7986CB"), hex: "7986CB"),
        ColorOption(color: Color(hex: "3F51B5"), hex: "3F51B5"), // Indigo
        ColorOption(color: Color(hex: "283593"), hex: "283593"),
        ColorOption(color: Color(hex: "9370DB"), hex: "9370DB"), // MediumPurple
        ColorOption(color: Color(hex: "8A2BE2"), hex: "8A2BE2"), // BlueViolet
        ColorOption(color: Color(hex: "9C27B0"), hex: "9C27B0"),
        ColorOption(color: Color(hex: "7B1FA2"), hex: "7B1FA2"),
        ColorOption(color: Color(hex: "4A148C"), hex: "4A148C"),

        // Pinks & magentas
        ColorOption(color: Color(hex: "F8BBD0"), hex: "F8BBD0"),
        ColorOption(color: Color(hex: "F06292"), hex: "F06292"),
        ColorOption(color: Color(hex: "EC407A"), hex: "EC407A"),
        ColorOption(color: Color(hex: "FF1493"), hex: "FF1493"), // DeepPink
        ColorOption(color: Color(hex: "C71585"), hex: "C71585"), // MediumVioletRed
        ColorOption(color: Color(hex: "AD1457"), hex: "AD1457"),

        // Browns
        ColorOption(color: Color(hex: "D7CCC8"), hex: "D7CCC8"),
        ColorOption(color: Color(hex: "BCAAA4"), hex: "BCAAA4"),
        ColorOption(color: Color(hex: "CD853F"), hex: "CD853F"), // Peru
        ColorOption(color: Color(hex: "D2691E"), hex: "D2691E"), // Chocolate
        ColorOption(color: Color(hex: "A0522D"), hex: "A0522D"), // Sienna
        ColorOption(color: Color(hex: "8B4513"), hex: "8B4513"), // SaddleBrown
        ColorOption(color: Color(hex: "5D4037"), hex: "5D4037"),

        // Neutrals
        ColorOption(color: Color(hex: "ECEFF1"), hex: "ECEFF1"),
        ColorOption(color: Color(hex: "B0BEC5"), hex: "B0BEC5"),
        ColorOption(color: Color(hex: "708090"), hex: "708090"), // SlateGray
        ColorOption(color: Color(hex: "607D8B"), hex: "607D8B"),
        ColorOption(color: Color(hex: "455A64"), hex: "455A64"),
        ColorOption(color: Color(hex: "2F4F4F"), hex: "2F4F4F"), // DarkSlateGray
        ColorOption(color: Color(hex: "263238"), hex: "263238")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(^String.Titles.fieldMapDetailColor)
                Spacer()
                Button(action: {
                    isExpanded.toggle()
                }) {
                    Text(isExpanded ? ^String.Titles.collapse : ^String.Titles.moreColors)
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

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 10) {
                        ForEach(extendedColors, id: \.hex) { colorOption in
                            colorCircleView(colorOption: colorOption)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: 220)
            }
            
            HStack {
                Text(^String.Titles.hEX)
                TextField(^String.Titles.hEX, text: $hexString)
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
