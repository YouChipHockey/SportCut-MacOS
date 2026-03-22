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
        if labels.isEmpty { return event.tagName }
        return "\(event.tagName) • \(labels.joined(separator: ", "))"
    }

    private var hasDrawings: Bool {
        !playerManager.currentEventDrawings().isEmpty
    }

    private var isPlaylistEvent: Bool {
        playerManager.currentPlaylistID != nil && playerManager.currentEvent != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if playerManager.isEditorMode {
                editorModeView
            } else {
                headerView
                Divider()
                videoContentView
                Divider()
                controlsView
            }
        }
    }
    
    // MARK: - Normal Mode Header
    
    private var headerView: some View {
        HStack(spacing: 8) {
            Button(action: { showPlaylistPanel.toggle() }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
                    .foregroundColor(showPlaylistPanel ? .blue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help(^String.Titles.sportCutShowHidePlaylists)
            
            Button(action: { showTimelinePanel.toggle() }) {
                Image(systemName: showTimelinePanel ? "rectangle.bottomhalf.filled" : "rectangle.bottomhalf.inset.filled")
                    .font(.system(size: 14))
                    .foregroundColor(showTimelinePanel ? .blue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help(^String.Titles.sportCutShowHideEvents)
            
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
            .help(^String.Titles.sportCutFullscreen)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.05))
    }
    
    // MARK: - Video Content
    
    private var videoContentView: some View {
        ZStack {
            VideoPlayer(player: playerManager.player)
                .background(Color.black)

            if playerManager.showEventDataWatermark, let text = eventDataWatermarkText {
                VStack {
                    Text(text)
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
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: drawingImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture {
                                playerManager.hideDrawingOverlay()
                            }
                        Button(action: { playerManager.hideDrawingOverlay() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .zIndex(10)
            }
            
            if playerManager.currentEvent == nil {
                VStack(spacing: 12) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text(^String.Titles.sportCutSelectEventToPlay)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.7))
            }
        }
    }
    
    // MARK: - Controls
    
    private var controlsView: some View {
        HStack(spacing: 12) {
            Button(action: { playerManager.seek(by: -10) }) {
                Image(systemName: "gobackward.10").font(.system(size: 14))
            }.buttonStyle(PlainButtonStyle()).help(^String.Titles.sportCutSeekBack10)
            
            Button(action: { playerManager.seek(by: -5) }) {
                Image(systemName: "gobackward.5").font(.system(size: 14))
            }.buttonStyle(PlainButtonStyle()).help(^String.Titles.sportCutSeekBack5)
            
            Button(action: { playerManager.seek(by: -2) }) {
                Text("-2").font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.gray.opacity(0.2)).cornerRadius(4)
            }.buttonStyle(PlainButtonStyle()).help(^String.Titles.sportCutSeekBack2)
            
            Button(action: { playerManager.togglePlayPause() }) {
                Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28)).foregroundColor(.blue)
            }.buttonStyle(PlainButtonStyle())
            
            Button(action: { playerManager.seek(by: 2) }) {
                Text("+2").font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.gray.opacity(0.2)).cornerRadius(4)
            }.buttonStyle(PlainButtonStyle()).help(^String.Titles.sportCutSeekForward2)
            
            Button(action: { playerManager.seek(by: 5) }) {
                Image(systemName: "goforward.5").font(.system(size: 14))
            }.buttonStyle(PlainButtonStyle()).help(^String.Titles.sportCutSeekForward5)
            
            Button(action: { playerManager.seek(by: 10) }) {
                Image(systemName: "goforward.10").font(.system(size: 14))
            }.buttonStyle(PlainButtonStyle()).help(^String.Titles.sportCutSeekForward10)

            speedMenu

            if isPlaylistEvent {
                Button(action: {
                    playerManager.captureFrameForEditor()
                }) {
                    Image(systemName: hasDrawings ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                        .font(.system(size: 14))
                        .foregroundColor(hasDrawings ? .orange : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(^String.Titles.sportCutCreateDrawing)
            }

            Button(action: { playerManager.showEventDataWatermark.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "tag").font(.system(size: 10))
                    Image(systemName: playerManager.showEventDataWatermark ? "eye.fill" : "eye.slash.fill").font(.system(size: 10))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.gray.opacity(0.2)).cornerRadius(4)
                .foregroundColor(playerManager.showEventDataWatermark ? .blue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help(playerManager.showEventDataWatermark ? ^String.Titles.sportCutHideEventWatermark : ^String.Titles.sportCutShowEventWatermark)

            Button(action: { playerManager.showCommentsWatermark.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble").font(.system(size: 10))
                    Image(systemName: playerManager.showCommentsWatermark ? "eye.fill" : "eye.slash.fill").font(.system(size: 10))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.gray.opacity(0.2)).cornerRadius(4)
                .foregroundColor(playerManager.showCommentsWatermark ? .blue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help(playerManager.showCommentsWatermark ? ^String.Titles.sportCutHideComments : ^String.Titles.sportCutShowComments)
            
            Spacer()
            
            Text(formatTime(playerManager.currentTime))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
    }

    // MARK: - Editor Mode

    private var editorModeView: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    EditorToolsPanel(drawingState: playerManager.editorDrawingState) { tool in
                        playerManager.editorDrawingState.currentTool = tool
                    }
                }
                .frame(minWidth: 180)
                Divider()
                editorCanvasView
                Divider()
                EditorSettingsPanel(drawingState: playerManager.editorDrawingState)
                    .frame(width: 180)
            }
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 12) {
            Text(^String.Titles.sportCutDrawing)
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Button(^String.Titles.cancelButtonTitle) {
                playerManager.cancelEditor()
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.secondary)
            .keyboardShortcut(.escape, modifiers: [])

            Button(^String.Titles.saveButtonTitle) {
                playerManager.saveDrawing()
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.blue)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
    }

    private var editorCanvasView: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if let screenshot = playerManager.tempScreenshotImage {
                    let imgSize = screenshot.size
                    let displaySize = calculateDisplaySize(imageSize: imgSize, containerSize: geo.size)
                    
                    Image(nsImage: screenshot)
                        .resizable()
                        .scaledToFit()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .overlay(
                            DrawingCanvasView(drawingState: playerManager.editorDrawingState)
                                .frame(width: displaySize.width, height: displaySize.height)
                        )
                        .onAppear {
                            playerManager.editorDrawingState.updateViewSize(displaySize)
                        }
                        .onChange(of: displaySize) { newSize in
                            playerManager.editorDrawingState.updateViewSize(newSize)
                        }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
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
                Image(systemName: "speedometer").font(.system(size: 10))
                Text("\(playerManager.playbackSpeed, specifier: "%.1f")x")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.gray.opacity(0.2)).cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func toggleFullscreen() {
        if let window = NSApp.keyWindow { window.toggleFullScreen(nil) }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func calculateDisplaySize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0 && imageSize.height > 0 else { return containerSize }
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let ratio = min(widthRatio, heightRatio)
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    }
}
