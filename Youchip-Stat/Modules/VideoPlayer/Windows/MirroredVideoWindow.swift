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

// MARK: - SportCut (multi-source player)

struct MirrorSportCutVideoContentView: View {
    @ObservedObject var playerManager: SportCutPlayerManager
    @ObservedObject private var sessionManager = SportCutSessionManager.shared

    private var currentPlaylistComment: String? {
        guard let sessionID = playerManager.sessionID,
              let playlistID = playerManager.currentPlaylistID,
              let event = playerManager.currentEvent,
              let session = sessionManager.sessions.first(where: { $0.id == sessionID }),
              let playlist = session.playlistGroups.flatMap(\.playlists).first(where: { $0.id == playlistID }) else { return nil }
        let raw = playlist.eventComments[event.hiddenKey] ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var eventDataWatermarkText: String? {
        guard let event = playerManager.currentEvent else { return nil }
        let labels = playerManager.currentEventLabelNames
        if labels.isEmpty {
            return event.tagName
        }
        return "\(event.tagName) • \(labels.joined(separator: ", "))"
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: playerManager.player)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if playerManager.showEventDataWatermark, let eventDataText = eventDataWatermarkText {
                VStack {
                    Text(eventDataText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(8)
                        .padding(.top, 14)
                        .padding(.horizontal, 16)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if playerManager.showCommentsWatermark, let comment = currentPlaylistComment {
                VStack {
                    Spacer()
                    Text(comment)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(8)
                        .padding(.bottom, 18)
                        .padding(.horizontal, 16)
                }
                .allowsHitTesting(false)
            }

            if playerManager.isShowingDrawing, let drawingImage = playerManager.displayedDrawingImage {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Image(nsImage: drawingImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .zIndex(10)
            }
        }
    }
}
