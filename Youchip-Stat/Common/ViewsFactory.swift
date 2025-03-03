//
//  ViewsFactory.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import SwiftUI

class ViewsFactory {
    
    @ViewBuilder
    static func lineDivider(isVertical: Bool = true, width: CGFloat = 1, color: Color = Color.appSystemGray5.opacity(0.1)) -> some View {
        Divider()
            .background(color)
            .foregroundStyle(color)
            .frame(width: isVertical ? width : nil, height: isVertical ? nil : width)
    }
    
    @ViewBuilder
    static func slidebarButton() -> some View {
        Button {
            NSApp.keyWindow?.firstResponder?.tryToPerform(
                #selector(NSSplitViewController.toggleSidebar(_:)), with: nil
            )
        } label: {
            Label("Toggle sidebar", systemImage: "sidebar.left")
        }
    }
    
    @ViewBuilder
    static func customHUD(color: Color = Color.appSystemGray) -> some View {
        VStack {
            Spacer()
            ProgressView()
                .accentColor(color)
                .progressViewStyle(.circular)
                .scaleEffect(2.0)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.4))
        .edgesIgnoringSafeArea(.all)
    }
    
    @ViewBuilder
    static func defaultBackBarButton(completion: @escaping () -> Void) -> some View {
        Button {
            completion()
        } label: {
            Label(^String.ButtonTitles.previousButtonTitle, systemImage: AppImage.sfChevronLeft.rawValue)
        }
    }
    
    @ViewBuilder
    static func defaultSystemImageButton(title: String, systemImage: String, textColor: Color = Color.appSystemBlack, background: Color = Color.appSystemWhite, completion: @escaping () -> Void) -> some View {
        Button(action: {
            completion()
        }) {
            HStack(spacing: 5) {
                Text(Image(systemName: systemImage))
                    .foregroundColor(textColor)
                if title != "" {
                    Text(title)
                        .foregroundColor(textColor)
                }
            }
            .frame(height: 22, alignment: .center)
            .padding(EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7))
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        //        .frame(maxWidth: .infinity)
        .buttonStyle(PlainButtonStyle())
        .shadow(radius: 2)
    }
    
    @ViewBuilder
    static func whiteBarButton(title: String, completion: @escaping () -> Void) -> some View {
        Button(action: {
            completion()
        }) {
            HStack(spacing: 5) {
                Text(title)
                    .foregroundColor(Color.appSystemBlack)
            }
            .frame(height: 22, alignment: .center)
            .padding(EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7))
            .background(Color.appSystemWhite)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        //        .frame(maxWidth: .infinity)
        .buttonStyle(PlainButtonStyle())
        .shadow(radius: 2)
    }
    
    @ViewBuilder
    static func blueBarButton(title: String, completion: @escaping () -> Void) -> some View {
        Button(action: {
            completion()
        }) {
            HStack(spacing: 5) {
                Text(title)
                    .foregroundColor(Color.appSystemWhite)
            }
            .frame(height: 22, alignment: .center)
            .padding(EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7))
            .background(Color.hex_007AFF)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        //        .frame(maxWidth: .infinity)
        .buttonStyle(PlainButtonStyle())
        .shadow(radius: 2)
    }
    
}
