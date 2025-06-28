//
//  EditorView.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 05.08.2024.
//

import SwiftUI
import WebKit

struct EditorView: View {
    
    @EnvironmentObject private var viewModel: EditorViewModel
    
    var body: some View {
        SheetToolbarView(
            title: ^String.Titles.photoEditor,
            leadingView: leadingView,
            trailingView: tralingView,
            contentView: contentView,
            titleColor: Color.appSystemWhite,
            color: Color.hex_2E2E2E
        )
        .infoAlert(
            title: ^String.Titles.alertsErrorTitle,
            message: viewModel.state.errorTitle,
            show: $viewModel.state.showError
        )
        .infoAlert(
            title: ^String.Titles.fieldMapMenuInfo,
            message: viewModel.state.infoTitle,
            show: $viewModel.state.showInfo
        )
        .background(Color.hex_2E2E2E)
        .frame(minWidth: 800, minHeight: 600)
        .overlay(
            Group {
                if viewModel.state.showHUD {
                    ViewsFactory.customHUD()
                        .transition(.opacity)
                }
            }
        )
    }
    
    @ViewBuilder
    private func contentView() -> some View {
        VStack {
            if let webView = viewModel.webView {
                webView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Failed to load editor")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    @ViewBuilder
    private func tralingView() -> some View {
        HStack {
            ViewsFactory.defaultSystemImageButton(title: "", systemImage: AppImage.sfShare.rawValue, textColor: Color.appSystemWhite, background: Color.hex_4D4D4D) {
                viewModel.action.send(.share)
            }
            .background(
                SharingPicker(show: $viewModel.state.showPicker, items: [viewModel.state.inputFile])
            )
            
            ViewsFactory.defaultSystemImageButton(title: "", systemImage: "arrow.down.doc", textColor: Color.appSystemWhite, background: Color.hex_4D4D4D) {
                viewModel.action.send(.download)
            }
            
            ViewsFactory.blueBarButton(title: ^String.Titles.saveButtonTitle) {
                viewModel.action.send(.save)
            }
        }
    }
    
    @ViewBuilder
    private func leadingView() -> some View {
        
    }
    
}
