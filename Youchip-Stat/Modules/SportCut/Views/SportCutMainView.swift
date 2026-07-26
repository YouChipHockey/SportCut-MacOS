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
    /// Базовые значения, зафиксированные в начале перетаскивания разделителей.
    @State private var dragStartLeftWidth: CGFloat?
    @State private var dragStartTopHeight: CGFloat?

    private let minTopAreaHeight: CGFloat = 240
    private let minBottomAreaHeight: CGFloat = 180
    private let minLeftPanelWidth: CGFloat = 220
    private let minPlayerWidth: CGFloat = 360
    
    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }
    
    var body: some View {
        GeometryReader { geometry in
            if let session = session {
                let availableHeight = geometry.size.height
                let maxLeftWidth = max(minLeftPanelWidth, geometry.size.width - minPlayerWidth)
                let clampedLeftWidth = min(leftPanelWidth, maxLeftWidth)
                let currentTopHeight = showTimelinePanel
                    ? max(minTopAreaHeight, min(availableHeight - minBottomAreaHeight, availableHeight * topAreaHeightRatio))
                    : availableHeight

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        /// Панель всегда в иерархии (ширина 0 при скрытии), иначе при редакторе рисунка сбрасывается выбор группы/плейлиста.
                        SportCutPlaylistsView(
                            sessionID: sessionID,
                            playerManager: playerManager
                        )
                        .frame(width: showPlaylistPanel ? clampedLeftWidth : 0)
                        .clipped()
                        .allowsHitTesting(showPlaylistPanel)

                        if showPlaylistPanel {
                            playlistResizeHandle(maxWidth: maxLeftWidth)
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
                        timelineResizeHandle(availableHeight: availableHeight, currentTopHeight: currentTopHeight)
                    }

                    SportCutTimelineView(
                        sessionID: sessionID,
                        playerManager: playerManager
                    )
                    .frame(maxHeight: showTimelinePanel ? .infinity : 0)
                    .clipped()
                    .allowsHitTesting(showTimelinePanel)
                }
                .onReceive(NotificationCenter.default.publisher(for: .sportCutTogglePlayPause)) { _ in
                    guard !playerManager.isEditorMode else { return }
                    playerManager.togglePlayPause()
                }
                .onReceive(NotificationCenter.default.publisher(for: .sportCutSeekBackward)) { _ in
                    guard !playerManager.isEditorMode else { return }
                    playerManager.seek(by: -3)
                }
                .onReceive(NotificationCenter.default.publisher(for: .sportCutSeekForward)) { _ in
                    guard !playerManager.isEditorMode else { return }
                    playerManager.seek(by: 3)
                }
                .onReceive(NotificationCenter.default.publisher(for: .sportCutStepFrameBackward)) { _ in
                    guard !playerManager.isEditorMode else { return }
                    playerManager.stepFrame(forward: false)
                }
                .onReceive(NotificationCenter.default.publisher(for: .sportCutStepFrameForward)) { _ in
                    guard !playerManager.isEditorMode else { return }
                    playerManager.stepFrame(forward: true)
                }
                .onAppear {
                    playerManager.sessionID = sessionID
                    playerManager.configure(sources: session.sources)
                    playerManager.setupTimeObserver()
                    playerManager.startDrawingCheckTimer()
                    WindowsManager.shared.registerActiveSportCut(sessionID: sessionID, playerManager: playerManager)
                    if let playlistID = WindowsManager.shared.consumePendingSportCutAutoplayPlaylistID() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            guard let s = sessionManager.sessions.first(where: { $0.id == sessionID }) else { return }
                            for group in s.playlistGroups {
                                if let playlist = group.playlists.first(where: { $0.id == playlistID }) {
                                    let visible = playlist.events.filter { !playlist.hiddenEventKeys.contains($0.hiddenKey) }
                                    guard !visible.isEmpty else { return }
                                    playerManager.sessionID = sessionID
                                    playerManager.playPlaylist(visible, playlistID: playlist.id, playbackKind: .singleFilm)
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
                    WindowsManager.shared.unregisterActiveSportCut(sessionID: sessionID)
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

    // MARK: - Resize handles

    /// Вертикальный разделитель между панелью плейлистов и плеером — тянется по горизонтали.
    private func playlistResizeHandle(maxWidth: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1)
            Color.clear
                .frame(width: 10)
                .contentShape(Rectangle())
        }
        .frame(width: 10)
        .onHover { hovering in
            if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            // Глобальная система координат: перемещение считается от экрана, а не от самого
            // разделителя (который двигается при ресайзе) — иначе получается рывками.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartLeftWidth == nil { dragStartLeftWidth = leftPanelWidth }
                    let base = dragStartLeftWidth ?? leftPanelWidth
                    leftPanelWidth = min(max(base + value.translation.width, minLeftPanelWidth), maxWidth)
                }
                .onEnded { _ in dragStartLeftWidth = nil }
        )
    }

    /// Горизонтальный разделитель между верхней областью (плеер/плейлисты) и таймлайном — тянется по вертикали.
    private func timelineResizeHandle(availableHeight: CGFloat, currentTopHeight: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
            Color.clear
                .frame(height: 10)
                .contentShape(Rectangle())
        }
        .frame(height: 10)
        .onHover { hovering in
            if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            // Глобальная система координат — стабильное следование за курсором без рывков.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartTopHeight == nil { dragStartTopHeight = currentTopHeight }
                    let base = dragStartTopHeight ?? currentTopHeight
                    let newHeight = min(max(base + value.translation.height, minTopAreaHeight), availableHeight - minBottomAreaHeight)
                    if availableHeight > 0 {
                        topAreaHeightRatio = newHeight / availableHeight
                    }
                }
                .onEnded { _ in dragStartTopHeight = nil }
        )
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
