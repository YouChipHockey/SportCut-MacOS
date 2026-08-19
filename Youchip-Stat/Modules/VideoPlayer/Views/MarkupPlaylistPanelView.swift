//
//  MarkupPlaylistPanelView.swift
//  Youchip-Stat
//
//  Правая панель окна таймлайнов разметки: плейлисты режима просмотра.
//  Сама плитка плейлистов — та же `SportCutPlaylistsView`, что и в просмотре; здесь только
//  экран выбора/создания сессии просмотра поверх неё и шапка возврата.
//

import SwiftUI

struct MarkupPlaylistPanelView: View {

    @ObservedObject private var store = MarkupPlaylistPanelStore.shared
    @ObservedObject private var sessionManager = SportCutSessionManager.shared
    @ObservedObject private var limits = LicenseLimitsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let sessionID = store.sessionID,
               sessionManager.sessions.contains(where: { $0.id == sessionID }) {
                SportCutPlaylistsView(
                    sessionID: sessionID,
                    playerManager: store.playerManager,
                    onSelectedPlaylistChanged: { store.currentPlaylistID = $0 }
                )
            } else {
                sessionPicker
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: sessionManager.sessions.map(\.id)) { _ in
            store.dropSessionIfMissing()
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 8) {
            if store.sessionID != nil {
                Button(action: { store.backToSessionSelection() }) {
                    SwiftUI.Label(^String.Titles.markupPlaylistsBackToSessions, systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help(^String.Titles.markupPlaylistsBackToSessions)
            } else {
                Text(^String.Titles.markupPlaylistsTitle)
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            if store.isPlaybackActive {
                Button(action: { store.returnToMarkup() }) {
                    SwiftUI.Label(^String.Titles.markupPlaylistsReturnToMarkup, systemImage: "arrow.uturn.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .help(^String.Titles.markupPlaylistsReturnToMarkup)
            }

            Button(action: { store.closePanel() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(^String.Titles.closeButtonTitle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Выбор / создание сессии просмотра

    private var sessionPicker: some View {
        let sessions = store.sessionsForCurrentProject()
        return VStack(alignment: .leading, spacing: 12) {
            Text(^String.Titles.markupPlaylistsPickSession)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if sessions.isEmpty {
                Text(^String.Titles.markupPlaylistsNoSessions)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(sessions, id: \.id) { session in
                            Button(action: { store.select(sessionID: session.id) }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                        Text(String(format: ^String.Titles.markupPlaylistsSessionSubtitle,
                                                    session.playlistGroups.reduce(0) { $0 + $1.playlists.count }))
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button(action: { store.createSessionForCurrentProject() }) {
                SwiftUI.Label(^String.Titles.viewingNewSession, systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!limits.canCreateViewingSession)

            if !limits.canCreateViewingSession {
                Text(^String.Titles.viewingLimitReachedMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(12)
    }
}
