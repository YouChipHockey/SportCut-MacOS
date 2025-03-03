//
//  VideosView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import SwiftUI

struct VideosView: View {
    
    @EnvironmentObject private var viewModel: VideosViewModel
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 20)], spacing: 20) {
                ForEach(viewModel.state.files, id: \.url) { file in
                    VideoThumbnailView(file: file, viewModel: viewModel)
                }
            }
            .padding()
        }
        .frame(minWidth: 650, minHeight: 600)
        .background(Color.appSystemGray)
        .navigationTitle(^String.Root.rootVideosTitle)
        .overlay(loadingOverlay)
        .toolbar {
            ViewsFactory.whiteBarButton(title: ^String.Videos.addVideoTitle) {
                viewModel.action.send(.openFiles)
            }
        }
        .infoAlert(
            title: ^String.Alerts.alertsErrorTitle,
            message: viewModel.state.errorTitle,
            show: $viewModel.state.showError
        )
        .cloudFilesAlerts(
            showFilesDownloadAlert: $viewModel.state.showFilesDownloadAlert,
            showFilesDownloadingAlert: $viewModel.state.showFilesDownloadingAlert,
            downloadFiles: {
                viewModel.action.send(.downloadFiles)
            }
        )
    }
    
    private var loadingOverlay: some View {
        Group {
            if viewModel.state.showHUD {
                ViewsFactory.customHUD()
                    .transition(.opacity)
            }
        }
    }
}
