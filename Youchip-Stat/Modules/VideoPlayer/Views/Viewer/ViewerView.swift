//
//  ViewerView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI

struct ViewerView: View {
    let videoID: String
    @StateObject private var playlistManager: PlaylistManager
    @StateObject private var videoPlaylistManager = VideoPlaylistManager()
    @StateObject private var viewerState = ViewerState()
    
    init(videoID: String) {
        self.videoID = videoID
        self._playlistManager = StateObject(wrappedValue: PlaylistManager(videoID: videoID))
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    OrganizerView(
                        playlistManager: playlistManager,
                        videoPlaylistManager: videoPlaylistManager
                    )
                    .frame(width: geometry.size.width / 3)
                    
                    Divider()
                        .frame(width: 1)
                    
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
            setupViewer()
        }
        .onDisappear {
            cleanupViewer()
        }
    }
    
    private func setupViewer() {
        playlistManager.loadPlaylists()
        playlistManager.currentPlaylistId = nil
        playlistManager.clear()
        videoPlaylistManager.stopPlayback()
    }
    
    private func cleanupViewer() {
        videoPlaylistManager.stopPlayback()
        playlistManager.clear()
    }
}

struct ViewerView_Previews: PreviewProvider {
    static var previews: some View {
        ViewerView(videoID: "preview-video-id")
            .frame(width: 1200, height: 800)
    }
}
