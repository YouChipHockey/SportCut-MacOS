//
//  MirroredVideoWindow.swift
//  Youchip-Stat
//
//  Duplicate video surface: same AVPlayer or same live preview session as the source window.
//

import SwiftUI
import AVKit
import AVFoundation

// MARK: - Markup session (VideoPlayerManager)

struct MirrorMarkupVideoContentView: View {
    @ObservedObject private var videoManager = VideoPlayerManager.shared
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if videoManager.isLiveMode {
                DirectCameraPreviewView()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if let player = videoManager.player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(^String.Titles.videoPlayerVideoNotLoaded)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Viewer (playlist player)

struct MirrorViewerVideoContentView: View {
    @ObservedObject var playlistManager: VideoPlaylistManager
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let player = playlistManager.mirrorPlayer {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(^String.Titles.noVideoToPlay)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
