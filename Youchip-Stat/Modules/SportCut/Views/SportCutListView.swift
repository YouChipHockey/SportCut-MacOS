//
//  SportCutListView.swift
//  Youchip-Stat
//

import SwiftUI

struct SportCutListView: View {
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    @ObservedObject private var limits = LicenseLimitsManager.shared
    @State private var showCreateSheet = false
    @State private var sessionToDelete: SportCutSession?
    @State private var showDeleteAlert = false
    @State private var searchText = ""
    
    private var filteredSessions: [SportCutSession] {
        if searchText.isEmpty {
            return sessionManager.sessions
        }
        return sessionManager.sessions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            if filteredSessions.isEmpty {
                emptyStateView
            } else {
                sessionsGridView
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showCreateSheet) {
            SportCutCreateSessionView(
                onCreated: { session in
                    showCreateSheet = false
                    openSession(session)
                },
                onCancel: {
                    showCreateSheet = false
                }
            )
        }
        .alert(^String.Titles.sportCutDeleteSessionQuestion, isPresented: $showDeleteAlert) {
            Button(^String.Titles.cancelButtonTitle, role: .cancel) {
                sessionToDelete = nil
            }
            Button(^String.Titles.deleteButtonTitle, role: .destructive) {
                if let session = sessionToDelete {
                    sessionManager.deleteSession(session)
                    sessionToDelete = nil
                }
            }
        } message: {
            if let session = sessionToDelete {
                Text(String.Titles.sportCutSessionWillBeDeleted.format(session.name))
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                    
                    TextField(^String.Titles.sportCutSearchSessions, text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                
                Button(action: { showCreateSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                        Text(^String.Titles.sportCutNewSession)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: .blue.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)

            // Лимит режима просмотра (только без активной лицензии).
            if !limits.isLicenseActive {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    Text(String(format: ^String.Titles.viewingSessionsLimit,
                                limits.remainingViewingSessions, limits.maxFreeViewingSessions))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
    
    private var sessionsGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 250), spacing: 20, alignment: .top)],
                spacing: 20
            ) {
                ForEach(filteredSessions) { session in
                    SessionCardView(
                        session: session,
                        onOpen: { openSession(session) },
                        onDelete: {
                            sessionToDelete = session
                            showDeleteAlert = true
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(^String.Titles.sportCutNoSessions)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(^String.Titles.sportCutCreateSessionHint)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showCreateSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text(^String.Titles.sportCutCreateSessionButton)
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(10)
                .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func openSession(_ session: SportCutSession) {
        WindowsManager.shared.sportCutWindow?.close()
        WindowsManager.shared.sportCutWindow = nil
        let controller = SportCutWindowController(session: session)
        WindowsManager.shared.sportCutWindow = controller
        controller.showWindow(nil)
        HotKeyManager.shared.resumeKeyboardMonitoring()
    }
}

struct SessionCardView: View {
    let session: SportCutSession
    let onOpen: () -> Void
    let onDelete: () -> Void
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: session.createdAt)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Menu {
                        Button(^String.Titles.sportCutOpen) { onOpen() }
                        Divider()
                        Button(^String.Titles.deleteButtonTitle, role: .destructive) { onDelete() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Text(session.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "film")
                            .font(.system(size: 10))
                        Text("\(session.sources.count)")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 10))
                        Text("\(session.playlistGroups.flatMap(\.playlists).count)")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
                
                Text(formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .onTapGesture { onOpen() }
        .contextMenu {
            Button(^String.Titles.sportCutOpen) { onOpen() }
            Divider()
            Button(^String.Titles.deleteButtonTitle, role: .destructive) { onDelete() }
        }
    }
}
