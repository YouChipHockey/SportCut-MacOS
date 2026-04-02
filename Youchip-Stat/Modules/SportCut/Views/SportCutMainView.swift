//
//  SportCutMainView.swift
//  Youchip-Stat
//

import SwiftUI
import AppKit

struct SportCutMainView: View {
    @StateObject private var playerManager = SportCutPlayerManager()
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    
    let sessionID: UUID
    
    @State private var showPlaylistPanel = true
    @State private var showTimelinePanel = true
    @State private var leftPanelWidth: CGFloat = 300
    @State private var topAreaHeightRatio: CGFloat = 0.55
    @State private var dragStartLeftPanelWidth: CGFloat?
    @State private var dragStartTopAreaHeightRatio: CGFloat?

    private let minLeftPanelWidth: CGFloat = 250
    private let maxLeftPanelWidth: CGFloat = 700
    private let minTopAreaHeight: CGFloat = 240
    private let minBottomAreaHeight: CGFloat = 180
    
    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }
    
    var body: some View {
        GeometryReader { geometry in
            if let session = session {
                let availableHeight = geometry.size.height
                let currentTopHeight = showTimelinePanel
                    ? max(minTopAreaHeight, min(availableHeight - minBottomAreaHeight, availableHeight * topAreaHeightRatio))
                    : availableHeight

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        if showPlaylistPanel {
                            SportCutPlaylistsView(
                                sessionID: sessionID,
                                playerManager: playerManager
                            )
                            .frame(width: leftPanelWidth)
                            
                            resizeHandle(.vertical, totalHeight: availableHeight)
                        }
                        
                        SportCutVideoPlayerView(
                            playerManager: playerManager,
                            showPlaylistPanel: $showPlaylistPanel,
                            showTimelinePanel: $showTimelinePanel
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: currentTopHeight)
                    
                    if showTimelinePanel {
                        resizeHandle(.horizontal, totalHeight: availableHeight)
                        
                        SportCutTimelineView(
                            sessionID: sessionID,
                            playerManager: playerManager
                        )
                        .frame(maxHeight: .infinity)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .sportCutTogglePlayPause)) { _ in
                    guard !playerManager.isEditorMode else { return }
                    if Self.isSportCutTextInputActive() { return }
                    playerManager.togglePlayPause()
                }
                .onAppear {
                    playerManager.sessionID = sessionID
                    playerManager.configure(sources: session.sources)
                    playerManager.setupTimeObserver()
                    playerManager.startDrawingCheckTimer()
                    if let playlistID = WindowsManager.shared.consumePendingSportCutAutoplayPlaylistID() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            guard let s = sessionManager.sessions.first(where: { $0.id == sessionID }) else { return }
                            for group in s.playlistGroups {
                                if let playlist = group.playlists.first(where: { $0.id == playlistID }) {
                                    let visible = playlist.events.filter { !playlist.hiddenEventKeys.contains($0.hiddenKey) }
                                    guard !visible.isEmpty else { return }
                                    playerManager.sessionID = sessionID
                                    playerManager.playPlaylist(visible, playlistID: playlist.id)
                                    return
                                }
                            }
                        }
                    }
                }
                .onChange(of: session.sources.count) { _ in
                    if let session = self.session {
                        playerManager.configure(sources: session.sources)
                    }
                }
                .onDisappear {
                    playerManager.stopPlayback()
                    playerManager.removeTimeObserver()
                    playerManager.stopDrawingCheckTimer()
                }
            } else {
                VStack {
                    Text(^String.Titles.sportCutSessionNotFound)
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private enum ResizeAxis {
        case vertical
        case horizontal
    }

    @ViewBuilder
    private func resizeHandle(_ axis: ResizeAxis, totalHeight: CGFloat) -> some View {
        switch axis {
        case .vertical:
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 5)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let start = dragStartLeftPanelWidth ?? leftPanelWidth
                            if dragStartLeftPanelWidth == nil {
                                dragStartLeftPanelWidth = leftPanelWidth
                            }
                            let next = start + value.translation.width
                            let clamped = min(max(next, minLeftPanelWidth), maxLeftPanelWidth)
                            updateWithoutAnimation {
                                leftPanelWidth = clamped
                            }
                        }
                        .onEnded { _ in
                            dragStartLeftPanelWidth = nil
                        }
                )
                .onHover { isHovering in
                    if isHovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        case .horizontal:
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 5)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard totalHeight > 0 else { return }
                            if dragStartTopAreaHeightRatio == nil {
                                dragStartTopAreaHeightRatio = topAreaHeightRatio
                            }
                            let startRatio = dragStartTopAreaHeightRatio ?? topAreaHeightRatio
                            let topHeight = max(
                                minTopAreaHeight,
                                min(totalHeight - minBottomAreaHeight, (totalHeight * startRatio) + value.translation.height)
                            )
                            updateWithoutAnimation {
                                topAreaHeightRatio = topHeight / totalHeight
                            }
                        }
                        .onEnded { _ in
                            dragStartTopAreaHeightRatio = nil
                        }
                )
                .onHover { isHovering in
                    if isHovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
    }

    private func updateWithoutAnimation(_ block: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            block()
        }
    }

    private static func isSportCutTextInputActive() -> Bool {
        guard let window = NSApp.keyWindow else { return false }
        var responder: NSResponder? = window.firstResponder
        while let cur = responder {
            if cur is NSTextView { return true }
            if cur is NSTextField { return true }
            let name = NSStringFromClass(type(of: cur))
            if name.contains("TextInput"), name.contains("SwiftUI") { return true }
            responder = cur.nextResponder
        }
        return false
    }
}
