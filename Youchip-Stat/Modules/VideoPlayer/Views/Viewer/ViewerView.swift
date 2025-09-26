//
//  ViewerView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI

struct ViewerView: View {
    @StateObject private var playlistManager = PlaylistManager()
    @StateObject private var videoPlaylistManager = VideoPlaylistManager()
    @StateObject private var viewerState = ViewerState()
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top section: Organizer and Video
                HStack(spacing: 0) {
                    // Left: Organizer (1/3 of width)
                    OrganizerView(
                        playlistManager: playlistManager,
                        videoPlaylistManager: videoPlaylistManager
                    )
                    .frame(width: geometry.size.width / 3)
                    
                    Divider()
                        .frame(width: 1)
                    
                    // Right: Video (2/3 of width)
                    ViewerVideoView(
                        playlistManager: videoPlaylistManager,
                        organizer: playlistManager
                    )
                    .frame(width: (geometry.size.width * 2) / 3)
                    .background(Color.black.opacity(0.05))
                }
                .frame(height: (geometry.size.height * 2.6) / 4)
                
                Divider()
                    .frame(height: 1)
                    .background(Color.gray.opacity(0.3))
                
                // Bottom section: Timelines (increased by 15%)
                ViewerTimelineView(
                    organizer: playlistManager,
                    playlistManager: videoPlaylistManager
                )
                .frame(height: (geometry.size.height * 1.4) / 4)
                .background(Color.gray.opacity(0.2))
            }
        }
        .background(Color.gray.opacity(0.2))
        .onAppear {
            // Инициализация при открытии окна
            setupViewer()
        }
        .onDisappear {
            // Очистка при закрытии окна
            cleanupViewer()
        }
    }
    
    private func setupViewer() {
        // Настройка начального состояния
        playlistManager.clear()
        videoPlaylistManager.stopPlayback()
    }
    
    private func cleanupViewer() {
        // Очистка ресурсов
        videoPlaylistManager.stopPlayback()
        playlistManager.clear()
    }
}

// MARK: - Preview
struct ViewerView_Previews: PreviewProvider {
    static var previews: some View {
        ViewerView()
            .frame(width: 1200, height: 800)
    }
}
