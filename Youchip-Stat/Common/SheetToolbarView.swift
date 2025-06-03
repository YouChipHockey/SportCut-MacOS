//
//  SheetToolbarView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 5/27/25.
//

import SwiftUI

struct SheetToolbarView<LeadingView: View, TrailingView: View, ContentView: View>: View {
    
    let title: String
    let color: Color
    let titleColor: Color
    let isNeedDivider: Bool
    let leadingView: () -> LeadingView
    let trailingView: () -> TrailingView
    let contentView: () -> ContentView
    
    private let toolbarHeight: CGFloat = 52
    
    init(
        title: String,
        @ViewBuilder leadingView: @escaping () -> LeadingView,
        @ViewBuilder trailingView: @escaping () -> TrailingView = EmptyView.init,
        @ViewBuilder contentView: @escaping () -> ContentView,
        titleColor: Color = Color.appSystemBlack,
        color: Color = Color.hex_FBFBFB,
        isNeedDivider: Bool = true
    ) {
        self.leadingView = leadingView
        self.title = title
        self.trailingView = trailingView
        self.contentView = contentView
        self.titleColor = titleColor
        self.color = color
        self.isNeedDivider = isNeedDivider
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leadingView()
                    .padding(.trailing, 18)
                Text(title)
                    .foregroundStyle(titleColor)
                    .font(.sFProTextSemibold(ofSize: 15))
                Spacer()
                trailingView()
            }
            .frame(height: toolbarHeight)
            .frame(maxWidth: .infinity)
            .padding(.leading, 22)
            .padding(.trailing, 12)
            .background(color)
            .overlay {
                if isNeedDivider {
                    Divider()
                        .frame(height: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            contentView()
        }
    }
    
}
