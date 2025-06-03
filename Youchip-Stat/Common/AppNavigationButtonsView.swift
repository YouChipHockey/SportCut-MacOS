//
//  AppNavigationButtonsView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 5/27/25.
//

import SwiftUI

struct AppNavigationButtonsView: View {
    
    let back: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Button(
                action: back,
                label: {
                    AppImage.sfChevronLeft.systemImage
                        .renderingMode(.template)
                }
            )
            Button(
                action: {
                    // no implementation
                },
                label: {
                    AppImage.sfChevronRight.systemImage
                        .renderingMode(.template)
                }
            )
            .disabled(true)
        }
        .font(.sFProText(ofSize: 16))
        .foregroundColor(.appSystemGray)
        .buttonStyle(PlainButtonStyle())
    }
    
}
