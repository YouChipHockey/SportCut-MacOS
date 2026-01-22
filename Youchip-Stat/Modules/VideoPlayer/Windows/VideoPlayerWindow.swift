//
//  VideoPlayerWindow.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI

// MARK: - Video Player Window (Entry Point)

struct VideoPlayerWindow: View {
    
    @StateObject private var viewModel: VideoPlayerViewModel
    @ObservedObject private var videoManager = VideoPlayerManager.shared
    
    init(id: String) {
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(videoId: id))
    }
    
    var body: some View {
        VideoPlayerView(
            viewModel: viewModel,
            videoManager: videoManager
        )
    }
}
