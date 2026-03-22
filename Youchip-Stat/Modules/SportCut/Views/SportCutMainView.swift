//
//  SportCutMainView.swift
//  Youchip-Stat
//

import SwiftUI

struct SportCutMainView: View {
    @StateObject private var playerManager = SportCutPlayerManager()
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    
    let sessionID: UUID
    
    @State private var showPlaylistPanel = true
    @State private var showTimelinePanel = true
    @State private var leftPanelWidth: CGFloat = 300
    
    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }
    
    var body: some View {
        GeometryReader { geometry in
            if let session = session {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        if showPlaylistPanel {
                            SportCutPlaylistsView(
                                sessionID: sessionID,
                                playerManager: playerManager
                            )
                            .frame(width: max(leftPanelWidth, 250))
                            
                            Divider()
                                .frame(width: 1)
                        }
                        
                        SportCutVideoPlayerView(
                            playerManager: playerManager,
                            showPlaylistPanel: $showPlaylistPanel,
                            showTimelinePanel: $showTimelinePanel
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: showTimelinePanel ? geometry.size.height * 0.55 : geometry.size.height)
                    
                    if showTimelinePanel {
                        Divider()
                            .frame(height: 1)
                            .background(Color.gray.opacity(0.3))
                        
                        SportCutTimelineView(
                            sessionID: sessionID,
                            playerManager: playerManager
                        )
                        .frame(height: geometry.size.height * 0.45)
                    }
                }
                .onAppear {
                    playerManager.sessionID = sessionID
                    playerManager.configure(sources: session.sources)
                    playerManager.setupTimeObserver()
                    playerManager.startDrawingCheckTimer()
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
}
