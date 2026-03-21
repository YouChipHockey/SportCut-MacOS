//
//  SportCutVideoPlayerView.swift
//  Youchip-Stat
//

import SwiftUI
import AVKit

struct SportCutVideoPlayerView: View {
    @ObservedObject var playerManager: SportCutPlayerManager
    @ObservedObject private var sessionManager = SportCutSessionManager.shared
    @Binding var showPlaylistPanel: Bool
    @Binding var showTimelinePanel: Bool
    @State private var isFullscreen = false

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
        VStack(spacing: 0) {
            headerView
            Divider()
            videoContentView
            Divider()
            controlsView
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 8) {
            Button(action: { showPlaylistPanel.toggle() }) {
                Image(systemName: showPlaylistPanel ? "sidebar.left" : "sidebar.left")
                    .font(.system(size: 14))
                    .foregroundColor(showPlaylistPanel ? .blue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Показать/скрыть плейлисты")
            
            Button(action: { showTimelinePanel.toggle() }) {
                Image(systemName: showTimelinePanel ? "rectangle.bottomhalf.filled" : "rectangle.bottomhalf.inset.filled")
                    .font(.system(size: 14))
                    .foregroundColor(showTimelinePanel ? .blue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Показать/скрыть события")
            
            if let event = playerManager.currentEvent {
                Text("— \(event.tagName)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if !playerManager.currentEventLabelNames.isEmpty {
                Text("• \(playerManager.currentEventLabelNames.joined(separator: ", "))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            Button(action: {
                WindowsManager.shared.toggleSportCutMirrorVideoWindow(playerManager: playerManager)
            }) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help(^String.Titles.videoMirrorToggleHelp)
            
            Button(action: toggleFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Полный экран")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.05))
    }
    
    private var videoContentView: some View {
        ZStack {
            VideoPlayer(player: playerManager.player)
                .background(Color.black)

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
            
            if playerManager.currentEvent == nil {
                VStack(spacing: 12) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text("Выберите событие для воспроизведения")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.7))
            }
            
        }
    }
    
    private var controlsView: some View {
        HStack(spacing: 12) {
            Button(action: { playerManager.seek(by: -10) }) {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
            .help("-10 сек")
            
            Button(action: { playerManager.seek(by: -5) }) {
                Image(systemName: "gobackward.5")
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
            .help("-5 сек")
            
            Button(action: { playerManager.seek(by: -2) }) {
                Text("-2")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .help("-2 сек")
            
            Button(action: { playerManager.togglePlayPause() }) {
                Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: { playerManager.seek(by: 2) }) {
                Text("+2")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .help("+2 сек")
            
            Button(action: { playerManager.seek(by: 5) }) {
                Image(systemName: "goforward.5")
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
            .help("+5 сек")
            
            Button(action: { playerManager.seek(by: 10) }) {
                Image(systemName: "goforward.10")
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
            .help("+10 сек")

            speedMenu

            Button(action: { playerManager.showEventDataWatermark.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.system(size: 10))
                    Image(systemName: playerManager.showEventDataWatermark ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
                .foregroundColor(playerManager.showEventDataWatermark ? .blue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help(playerManager.showEventDataWatermark ? "Скрыть вотермарк события" : "Показать вотермарк события")

            Button(action: { playerManager.showCommentsWatermark.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10))
                    Image(systemName: playerManager.showCommentsWatermark ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
                .foregroundColor(playerManager.showCommentsWatermark ? .blue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help(playerManager.showCommentsWatermark ? "Скрыть комментарии" : "Показать комментарии")
            
            Spacer()
            
            Text(formatTime(playerManager.currentTime))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
    }
    
    private var speedMenu: some View {
        Menu {
            ForEach([0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 5.0], id: \.self) { speed in
                Button(action: { playerManager.changePlaybackSpeed(to: speed) }) {
                    HStack {
                        Text("\(speed, specifier: "%.2f")x")
                        if playerManager.playbackSpeed == speed {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "speedometer")
                    .font(.system(size: 10))
                Text("\(playerManager.playbackSpeed, specifier: "%.1f")x")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func toggleFullscreen() {
        if let window = NSApp.keyWindow {
            window.toggleFullScreen(nil)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
