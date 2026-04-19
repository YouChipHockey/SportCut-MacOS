//
//  SportCutPlaylistsView.swift
//  Youchip-Stat
//

import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

private struct PlaylistOrderDragData: Codable {
    let playlistID: UUID
}

struct SportCutPlaylistsView: View {
    let sessionID: UUID
    @ObservedObject var playerManager: SportCutPlayerManager
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    
    @State private var selectedGroupIndex = 0
    @State private var selectedPlaylistID: UUID?
    @State private var showNewPlaylistSheet = false
    @State private var showNewGroupSheet = false
    @State private var showRenameSheet = false
    @State private var renamingPlaylistID: UUID?
    @State private var showExportSheet = false
    @State private var showDeleteAlert = false
    @State private var playlistToDelete: UUID?
    @State private var trashTargeted = false
    /// -1 = все источники; иначе индекс в `session.sources` — только события этого проекта в списках и мини-таймлайне.
    @State private var playlistSourceFilterIndex = -1
    
    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }
    
    private var currentGroup: SportCutPlaylistGroup? {
        guard let session = session, selectedGroupIndex < session.playlistGroups.count else { return nil }
        return session.playlistGroups[selectedGroupIndex]
    }

    private var playlistSourceFilterID: UUID? {
        guard let session = session,
              playlistSourceFilterIndex >= 0,
              playlistSourceFilterIndex < session.sources.count else { return nil }
        return session.sources[playlistSourceFilterIndex].id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            playlistsContent
            Divider()
            groupSelector
            trashDropZone
        }
        .sheet(isPresented: $showNewPlaylistSheet) { newPlaylistSheet }
        .sheet(isPresented: $showNewGroupSheet) { newGroupSheet }
        .sheet(isPresented: $showRenameSheet) { renamePlaylistSheet }
        .sheet(isPresented: $showExportSheet) {
            SportCutExportSheet(sessionID: sessionID, playerManager: playerManager)
        }
        .alert(^String.Titles.sportCutDeletePlaylistQuestion, isPresented: $showDeleteAlert) {
            Button(^String.Titles.cancelButtonTitle, role: .cancel) { playlistToDelete = nil }
            Button(^String.Titles.deleteButtonTitle, role: .destructive) {
                if let id = playlistToDelete {
                    deletePlaylist(id)
                    playlistToDelete = nil
                }
            }
        }
        .onChange(of: playerManager.currentPlaylistID) { newID in
            if let newID = newID {
                selectedPlaylistID = newID
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Text(^String.Titles.playlists)
                .font(.system(size: 14, weight: .semibold))
            if let session = session, session.sources.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        playlistSourceTab(title: ^String.Titles.sportCutAllTab, index: -1)
                        ForEach(Array(session.sources.enumerated()), id: \.element.id) { index, source in
                            playlistSourceTab(title: source.name, index: index)
                        }
                    }
                }
                .frame(maxWidth: 220)
            }
            Spacer()
            Button(action: { showNewPlaylistSheet = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .help(^String.Titles.sportCutNewPlaylistHelp)
            
            Button(action: { showExportSheet = true }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .help(^String.Titles.sportCutExportPlaylists)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func playlistSourceTab(title: String, index: Int) -> some View {
        Button(action: { playlistSourceFilterIndex = index }) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(playlistSourceFilterIndex == index ? Color.blue : Color.gray.opacity(0.12))
                .foregroundColor(playlistSourceFilterIndex == index ? .white : .primary)
                .cornerRadius(5)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Group Selector
    
    private var groupSelector: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if let session = session {
                        ForEach(Array(session.playlistGroups.enumerated()), id: \.element.id) { index, group in
                            Button(action: { selectedGroupIndex = index }) {
                                Text(group.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(selectedGroupIndex == index ? Color.blue : Color.gray.opacity(0.15))
                                    .foregroundColor(selectedGroupIndex == index ? .white : .primary)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contextMenu {
                                if session.playlistGroups.count > 1 {
                                    Button(^String.Titles.sportCutDeleteGroup, role: .destructive) {
                                        deleteGroup(at: index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Button(action: { showNewGroupSheet = true }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help(^String.Titles.sportCutNewGroupHelp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    // MARK: - Playlists Content
    
    private var playlistsContent: some View {
        ScrollView {
            if let group = currentGroup {
                if group.playlists.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 28))
                            .foregroundColor(.gray)
                        Text(^String.Titles.sportCutNoPlaylists)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(^String.Titles.sportCutDragEventsHint)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(group.playlists.enumerated()), id: \.element.id) { index, playlist in
                            SportCutPlaylistCardView(
                                playlist: playlist,
                                sessionID: sessionID,
                                groupIndex: selectedGroupIndex,
                                sourceFilterID: playlistSourceFilterID,
                                canMoveUp: index > 0,
                                canMoveDown: index < group.playlists.count - 1,
                                isActive: selectedPlaylistID == playlist.id,
                                isCurrentlyPlaying: playerManager.playlistPlaybackActive && playerManager.currentPlaylistID == playlist.id && playerManager.isPlaying,
                                playerManager: playerManager,
                                onSelect: {
                                    let nextID = (selectedPlaylistID == playlist.id) ? nil : playlist.id
                                    selectedPlaylistID = nextID
                                    playerManager.currentPlaylistID = nextID
                                },
                                onPlay: { playPlaylist(playlist) },
                                onPlayAsFilm: { playPlaylistAsFilm(playlist) },
                                onDuplicate: { duplicatePlaylist(playlist) },
                                onRename: {
                                    renamingPlaylistID = playlist.id
                                    showRenameSheet = true
                                },
                                onDelete: {
                                    playlistToDelete = playlist.id
                                    showDeleteAlert = true
                                },
                                onToggleHidden: { toggleHidden(playlist) },
                                onMoveUp: { movePlaylist(playlist.id, direction: -1) },
                                onMoveDown: { movePlaylist(playlist.id, direction: 1) },
                                onReorderDrop: { draggedID in
                                    movePlaylist(draggedID, before: playlist.id)
                                }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
        .onDrop(of: [.data], isTargeted: nil) { providers in
            handleExternalDrop(providers: providers)
            return true
        }
    }
    
    // MARK: - Trash Drop Zone
    
    private var trashDropZone: some View {
        VStack(spacing: 2) {
            Divider()
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                Text(^String.Titles.sportCutDragToDelete)
                    .font(.system(size: 10))
            }
            .foregroundColor(trashTargeted ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(trashTargeted ? Color.red.opacity(0.8) : Color.red.opacity(0.05))
            .cornerRadius(4)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .onDrop(of: [.data], isTargeted: $trashTargeted) { providers in
            handleTrashDrop(providers: providers)
            return true
        }
    }
    
    // MARK: - Actions
    
    /// Кнопка в шапке карточки: для уже активного этого плейлиста — пауза/продолжить; иначе старт с первого клипа как фильм.
    private func playPlaylist(_ playlist: SportCutPlaylist) {
        selectedPlaylistID = playlist.id
        playerManager.sessionID = sessionID

        if playerManager.playlistPlaybackActive,
           playerManager.currentPlaylistID == playlist.id {
            playerManager.togglePlayPause()
            return
        }

        let visible = visibleEvents(in: playlist)
        guard !visible.isEmpty else { return }
        playerManager.currentPlaylistID = playlist.id
        playerManager.playPlaylist(visible, startIndex: 0, playlistID: playlist.id, playbackKind: .singleFilm)
    }

    /// Перезапуск плейлиста как склеенного фильма с начала.
    private func playPlaylistAsFilm(_ playlist: SportCutPlaylist) {
        selectedPlaylistID = playlist.id
        playerManager.sessionID = sessionID
        let visible = visibleEvents(in: playlist)
        guard !visible.isEmpty else { return }
        playerManager.currentPlaylistID = playlist.id
        playerManager.playPlaylist(visible, startIndex: 0, playlistID: playlist.id, playbackKind: .singleFilm)
    }
    
    private func duplicatePlaylist(_ playlist: SportCutPlaylist) {
        guard var session = session else { return }
        guard let playlistIdx = session.playlistGroups[selectedGroupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        SportCutSessionManager.shared.duplicatePlaylist(in: &session, groupIndex: selectedGroupIndex, playlistIndex: playlistIdx)
    }
    
    private func deletePlaylist(_ id: UUID) {
        guard var session = session else { return }
        session.playlistGroups[selectedGroupIndex].playlists.removeAll { $0.id == id }
        sessionManager.updateSession(session)
        if selectedPlaylistID == id {
            selectedPlaylistID = nil
            playerManager.stopPlayback()
        }
    }
    
    private func deleteGroup(at index: Int) {
        guard var session = session else { return }
        guard index < session.playlistGroups.count else { return }
        guard session.playlistGroups.count > 1 else { return }
        session.playlistGroups.remove(at: index)
        sessionManager.updateSession(session)
        if selectedGroupIndex >= session.playlistGroups.count {
            selectedGroupIndex = max(0, session.playlistGroups.count - 1)
        }
        selectedPlaylistID = nil
        playerManager.stopPlayback()
    }

    private func toggleHidden(_ playlist: SportCutPlaylist) {
        guard var session = session else { return }
        guard let idx = session.playlistGroups[selectedGroupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        session.playlistGroups[selectedGroupIndex].playlists[idx].isHidden.toggle()
        sessionManager.updateSession(session)
        playerManager.handlePlaylistVisibilityChange(session: session, playlistID: playlist.id)
    }

    private func movePlaylist(_ playlistID: UUID, direction: Int) {
        guard var session = session else { return }
        guard selectedGroupIndex < session.playlistGroups.count else { return }
        var playlists = session.playlistGroups[selectedGroupIndex].playlists
        guard let currentIndex = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let newIndex = currentIndex + direction
        guard newIndex >= 0 && newIndex < playlists.count else { return }
        let item = playlists.remove(at: currentIndex)
        playlists.insert(item, at: newIndex)
        session.playlistGroups[selectedGroupIndex].playlists = playlists
        sessionManager.updateSession(session)
    }

    private func movePlaylist(_ draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        guard var session = session else { return }
        guard selectedGroupIndex < session.playlistGroups.count else { return }
        var playlists = session.playlistGroups[selectedGroupIndex].playlists
        guard let from = playlists.firstIndex(where: { $0.id == draggedID }),
              let targetOriginal = playlists.firstIndex(where: { $0.id == targetID }) else { return }

        let dragged = playlists.remove(at: from)
        let target = playlists.firstIndex(where: { $0.id == targetID }) ?? max(0, targetOriginal - (from < targetOriginal ? 1 : 0))
        playlists.insert(dragged, at: target)

        session.playlistGroups[selectedGroupIndex].playlists = playlists
        sessionManager.updateSession(session)
    }

    private func visibleEvents(in playlist: SportCutPlaylist) -> [SportCutEvent] {
        playlist.events.filter { !playlist.hiddenEventKeys.contains($0.hiddenKey) }
    }
    
    private func handleExternalDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
                guard let data = data else { return }
                if let _ = try? JSONDecoder().decode(PlaylistEventDragData.self, from: data) {
                    return
                }
                if let payload = try? JSONDecoder().decode(MarkupStampsBatchPlaylistDragPayload.self, from: data),
                   let events = WindowsManager.shared.resolveMarkupPlaylistEvents(payload: payload, sessionID: self.sessionID),
                   !events.isEmpty {
                    DispatchQueue.main.async {
                        guard var session = self.session else { return }
                        guard self.selectedGroupIndex < session.playlistGroups.count else { return }
                        if session.playlistGroups[self.selectedGroupIndex].playlists.isEmpty {
                            session.playlistGroups[self.selectedGroupIndex].playlists.append(
                                SportCutPlaylist(name: "\(1)")
                            )
                        }
                        let lastIdx = session.playlistGroups[self.selectedGroupIndex].playlists.count - 1
                        let pid = session.playlistGroups[self.selectedGroupIndex].playlists[lastIdx].id
                        WindowsManager.shared.appendEventsToSportCutPlaylist(
                            events: events,
                            sessionID: self.sessionID,
                            groupIndex: self.selectedGroupIndex,
                            playlistID: pid
                        )
                    }
                    return
                }
                // Handle batch of events from SportCut timeline bulk selection
                if let events = try? JSONDecoder().decode([SportCutEvent].self, from: data), !events.isEmpty {
                    DispatchQueue.main.async {
                        guard var session = self.session else { return }
                        guard self.selectedGroupIndex < session.playlistGroups.count else { return }
                        if session.playlistGroups[self.selectedGroupIndex].playlists.isEmpty {
                            session.playlistGroups[self.selectedGroupIndex].playlists.append(
                                SportCutPlaylist(name: "\(1)")
                            )
                        }
                        let lastIdx = session.playlistGroups[self.selectedGroupIndex].playlists.count - 1
                        for event in events {
                            if !session.playlistGroups[self.selectedGroupIndex].playlists[lastIdx].events.contains(event) {
                                session.playlistGroups[self.selectedGroupIndex].playlists[lastIdx].events.append(event)
                                session.playlistGroups[self.selectedGroupIndex].playlists[lastIdx].mergeMarkupComments(for: [event], session: session)
                            }
                        }
                        self.sessionManager.updateSession(session)
                    }
                    return
                }
                guard let event = try? JSONDecoder().decode(SportCutEvent.self, from: data) else { return }
                DispatchQueue.main.async {
                    guard var session = self.session else { return }
                    guard self.selectedGroupIndex < session.playlistGroups.count else { return }
                    if session.playlistGroups[self.selectedGroupIndex].playlists.isEmpty {
                        session.playlistGroups[self.selectedGroupIndex].playlists.append(
                            SportCutPlaylist(name: "\(1)")
                        )
                    }
                    let lastIdx = session.playlistGroups[self.selectedGroupIndex].playlists.count - 1
                    if !session.playlistGroups[self.selectedGroupIndex].playlists[lastIdx].events.contains(event) {
                        session.playlistGroups[self.selectedGroupIndex].playlists[lastIdx].events.append(event)
                        session.playlistGroups[self.selectedGroupIndex].playlists[lastIdx].mergeMarkupComments(for: [event], session: session)
                        self.sessionManager.updateSession(session)
                    }
                }
            }
        }
    }
    
    private func handleTrashDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
                guard let data = data,
                      let dragData = try? JSONDecoder().decode(PlaylistEventDragData.self, from: data) else { return }
                DispatchQueue.main.async {
                    guard var session = self.session else { return }
                    for gi in session.playlistGroups.indices {
                        if let pi = session.playlistGroups[gi].playlists.firstIndex(where: { $0.id == dragData.sourcePlaylistID }) {
                            session.playlistGroups[gi].playlists[pi].events.removeAll { $0 == dragData.event }
                            sessionManager.updateSession(session)
                            return
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Sheets
    
    private var newPlaylistSheet: some View {
        SportCutNameInputSheet(title: ^String.Titles.sportCutNewPlaylist, placeholder: ^String.Titles.sportCutNameOptional) { name in
            guard var session = session else { return }
            SportCutSessionManager.shared.addPlaylist(to: &session, groupIndex: selectedGroupIndex, name: name.isEmpty ? nil : name)
            showNewPlaylistSheet = false
        } onCancel: {
            showNewPlaylistSheet = false
        }
    }
    
    private var newGroupSheet: some View {
        SportCutNameInputSheet(title: ^String.Titles.sportCutNewGroup, placeholder: ^String.Titles.sportCutGroupNamePlaceholder) { name in
            guard var session = session else { return }
            let groupName = name.isEmpty ? String.Titles.sportCutGroupPrefix.format(session.playlistGroups.count + 1) : name
            SportCutSessionManager.shared.addPlaylistGroup(to: &session, name: groupName)
            selectedGroupIndex = session.playlistGroups.count - 1
            showNewGroupSheet = false
        } onCancel: {
            showNewGroupSheet = false
        }
    }
    
    private var renamePlaylistSheet: some View {
        SportCutNameInputSheet(title: ^String.Titles.sportCutRenamePlaylist, placeholder: ^String.Titles.sportCutNewNamePlaceholder) { name in
            guard var session = session, let id = renamingPlaylistID else { return }
            if let idx = session.playlistGroups[selectedGroupIndex].playlists.firstIndex(where: { $0.id == id }) {
                session.playlistGroups[selectedGroupIndex].playlists[idx].name = name
                sessionManager.updateSession(session)
            }
            showRenameSheet = false
        } onCancel: {
            showRenameSheet = false
        }
    }
}

// MARK: - Playlist Card

struct SportCutPlaylistCardView: View {
    let playlist: SportCutPlaylist
    let sessionID: UUID
    let groupIndex: Int
    /// If set, only events from this markup source are listed and shown on the mini timeline.
    let sourceFilterID: UUID?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let isActive: Bool
    let isCurrentlyPlaying: Bool
    @ObservedObject var playerManager: SportCutPlayerManager
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onPlayAsFilm: () -> Void
    let onDuplicate: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onToggleHidden: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onReorderDrop: (UUID) -> Void
    
    @State private var cardDropTargeted = false
    @State private var dragOverIndex: Int?
    @State private var commentEditorState: EventCommentEditorState?
    
    private var cardBG: Color {
        if cardDropTargeted { return Color.blue.opacity(0.15) }
        if isActive { return Color.blue.opacity(0.08) }
        return Color.gray.opacity(0.05)
    }
    
    private var cardBorder: Color {
        if cardDropTargeted { return Color.blue }
        if isActive { return Color.blue.opacity(0.3) }
        return Color.gray.opacity(0.2)
    }

    // Keep event highlight active even when paused.
    private var isCurrentPlaylistSelectedForEventHighlight: Bool {
        playerManager.currentPlaylistID == playlist.id && playerManager.currentPlaylistIndex >= 0
    }

    private func passesSourceFilter(_ event: SportCutEvent) -> Bool {
        guard let fid = sourceFilterID else { return true }
        return event.sourceID == fid
    }

    private var visibleEvents: [SportCutEvent] {
        playlist.events.filter { !playlist.hiddenEventKeys.contains($0.hiddenKey) && passesSourceFilter($0) }
    }

    /// Full playlist indices + events for rows when a source filter is active.
    private var displayEventRows: [(index: Int, event: SportCutEvent)] {
        playlist.events.enumerated().compactMap { i, e in
            guard passesSourceFilter(e) else { return nil }
            return (i, e)
        }
    }

    private var miniTimelineEvents: [SportCutEvent] {
        playlist.events.filter { passesSourceFilter($0) }
    }

    private var miniTimelineTotalDuration: Double {
        miniTimelineEvents.reduce(0) { $0 + playlist.effectiveDuration(for: $1) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            cardHeader
            
            if !miniTimelineEvents.isEmpty {
                miniTimeline
            }
            
            if isActive {
                eventList
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(cardBG))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: cardDropTargeted ? 2 : 1))
        .opacity(playlist.isHidden ? 0.4 : 1.0)
        .contextMenu { cardContextMenu }
        .onDrag {
            let data = try! JSONEncoder().encode(PlaylistOrderDragData(playlistID: playlist.id))
            return NSItemProvider(item: data as NSData, typeIdentifier: UTType.data.identifier)
        }
        .onDrop(of: [.data], isTargeted: $cardDropTargeted) { providers in
            handleCardDrop(providers: providers, insertAt: nil)
            return true
        }
        .sheet(item: $commentEditorState) { editor in
            SportCutEventCommentSheet(
                title: editor.event.tagName,
                initialComment: editor.comment
            ) { text in
                saveEventComment(event: editor.event, comment: text)
            } onCancel: {
                commentEditorState = nil
            }
        }
    }
    
    // MARK: - Card Header
    
    private var cardHeader: some View {
        HStack(spacing: 6) {
            Button(action: onToggleHidden) {
                Image(systemName: playlist.isHidden ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 11))
                    .foregroundColor(playlist.isHidden ? .secondary : .blue.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
            .help(playlist.isHidden ? ^String.Titles.sportCutShowPlaylist : ^String.Titles.sportCutHidePlaylist)
            
            Text(playlist.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture { onSelect() }
            
            Spacer()
            
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(canMoveUp ? .secondary : .gray.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canMoveUp)
            .help(^String.Titles.sportCutMoveUp)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(canMoveDown ? .secondary : .gray.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canMoveDown)
            .help(^String.Titles.sportCutMoveDown)
            
            if isPlayingClipsMode {
                Button(action: onPlayAsFilm) {
                    Image(systemName: "film")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help(^String.Titles.sportCutPlayAsFilm)
            }

            Button(action: onPlay) {
                Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(isCurrentlyPlaying ? .orange : .blue)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    /// Плейлист сейчас проигрывается по клипам (не как фильм).
    private var isPlayingClipsMode: Bool {
        playerManager.playlistPlaybackActive
            && playerManager.currentPlaylistID == playlist.id
            && playerManager.playlistPlaybackKind == .sequentialClips
    }
    
    // MARK: - Mini Timeline (visual only)
    
    private var miniTimeline: some View {
        GeometryReader { geo in
            let totalDuration = max(miniTimelineTotalDuration, 0.01)
            let w = geo.size.width

            ZStack(alignment: .leading) {
                // Timeline bar with clipped white marker lines
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(Array(miniTimelineEvents.enumerated()), id: \.1.hiddenKey) { _, event in
                            let effectiveDur = playlist.effectiveDuration(for: event)
                            let ratio = totalDuration > 0 ? effectiveDur / totalDuration : 1.0 / Double(max(miniTimelineEvents.count, 1))
                            // Scale down if segments would exceed available width
                            let rawW = w * CGFloat(ratio)
                            let totalRaw = w // already proportional; enforce min via scale
                            let segW = max(rawW, 2)
                            let isCurrent = playerManager.currentPlaylistID == playlist.id && playerManager.currentEvent == event
                            let isHidden = playlist.hiddenEventKeys.contains(event.hiddenKey)

                            Rectangle()
                                .fill(Color(hex: event.color).opacity(isHidden ? 0.2 : (isCurrent ? 1.0 : 0.7)))
                                .frame(width: segW)
                                .overlay(Rectangle().stroke(isCurrent ? Color.white : Color.clear, lineWidth: 1))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard let start = visibleEvents.firstIndex(of: event) else { return }
                                    playerManager.sessionID = sessionID
                                    playerManager.playPlaylist(visibleEvents, startIndex: start, playlistID: playlist.id)
                                }
                        }
                    }
                    .frame(width: w, alignment: .leading)

                    drawingMarkerLines(totalWidth: w, totalDuration: miniTimelineTotalDuration)
                }
                .frame(width: w, height: 14)
                .cornerRadius(3)
                .clipped()

                // Drawing icons above the timeline
                drawingMarkerIcons(totalWidth: w, totalDuration: miniTimelineTotalDuration)
            }
            .frame(width: w, height: 14)
            .clipped()
        }
        .frame(height: 14)
        .clipped()
    }

    /// White vertical lines (full height, inside clipped timeline bar)
    private func drawingMarkerLines(totalWidth: CGFloat, totalDuration: Double) -> some View {
        let markers = drawingMarkerPositions(totalWidth: totalWidth, totalDuration: totalDuration)
        return ForEach(markers) { marker in
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 14)
                .offset(x: marker.offset)
                .allowsHitTesting(false)
        }
    }

    /// Pencil icons above the timeline bar (outside clipped region)
    private func drawingMarkerIcons(totalWidth: CGFloat, totalDuration: Double) -> some View {
        let markers = drawingMarkerPositions(totalWidth: totalWidth, totalDuration: totalDuration)
        return ForEach(markers) { marker in
            Image(systemName: "pencil.tip.crop.circle")
                .font(.system(size: 9))
                .foregroundColor(.green)
                .offset(x: marker.offset - 5, y: -12)
                .onTapGesture {
                    navigateToDrawing(marker)
                }
                .contextMenu {
                    Button(^String.Titles.sportCutEditDrawing) {
                        playerManager.sessionID = sessionID
                        playerManager.editExistingDrawing(
                            drawing: marker.drawing,
                            event: marker.event,
                            visiblePlaylistEvents: visibleEvents,
                            playlistID: playlist.id
                        )
                    }
                    Button(^String.Titles.sportCutDeleteDrawing, role: .destructive) {
                        playerManager.deleteDrawing(marker.drawing)
                    }
                }
        }
    }

    private func navigateToDrawing(_ marker: DrawingMarker) {
        guard let start = visibleEvents.firstIndex(of: marker.event) else { return }
        let event = marker.event
        // Пересчёт: drawing.videoTime — локальное в оригинальном клипе → локальное в effective клипе
        let absDrawingTime = event.startTime + marker.drawing.videoTime
        let effectiveStart = playlist.effectiveStartTime(for: event)
        let effectiveLocalTime = absDrawingTime - effectiveStart
        playerManager.sessionID = sessionID
        playerManager.playPlaylist(visibleEvents, startIndex: start, playlistID: playlist.id, autoPlayAfterLoad: false) {
            let seekTime = CMTime(seconds: max(0, effectiveLocalTime), preferredTimescale: 600)
            playerManager.player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func drawingMarkerPositions(totalWidth: CGFloat, totalDuration: Double) -> [DrawingMarker] {
        guard totalDuration > 0 else { return [] }
        var markers: [DrawingMarker] = []
        var accumulatedTime: Double = 0
        for event in miniTimelineEvents {
            let drawings = playlist.eventDrawings[event.hiddenKey] ?? []
            let effectiveDur = playlist.effectiveDuration(for: event)
            let effectiveStart = playlist.effectiveStartTime(for: event)
            let originalStart = event.startTime

            for drawing in drawings {
                // drawing.videoTime — локальное время относительно оригинального клипа
                let absDrawingTime = originalStart + drawing.videoTime
                // Проверяем что рисунок попадает в текущие effective границы клипа
                let effectiveEnd = effectiveStart + effectiveDur
                guard absDrawingTime >= effectiveStart && absDrawingTime <= effectiveEnd else { continue }
                // Локальное время в новом клипе
                let localT = absDrawingTime - effectiveStart
                let absTime = accumulatedTime + localT
                let x = totalWidth * (absTime / totalDuration)
                markers.append(DrawingMarker(offset: x, drawing: drawing, event: event))
            }
            accumulatedTime += effectiveDur
        }
        return markers
    }
    
    // MARK: - Event List (interactive: drag, reorder, delete)
    
    private var eventList: some View {
        ScrollView {
        VStack(spacing: 2) {
            ForEach(displayEventRows, id: \.event.hiddenKey) { row in
                let index = row.index
                let event = row.event
                let isCurrent = playerManager.currentPlaylistID == playlist.id && playerManager.currentEvent == event
                let isDropTarget = dragOverIndex == index
                let isHidden = playlist.hiddenEventKeys.contains(event.hiddenKey)
                
                PlaylistEventRowView(
                    event: event,
                    index: index,
                    canMoveUp: index > 0,
                    canMoveDown: index < playlist.events.count - 1,
                    isCurrent: isCurrent,
                    isHidden: isHidden,
                    isDropTarget: isDropTarget,
                    hasDrawing: !(playlist.eventDrawings[event.hiddenKey] ?? []).isEmpty,
                    onAddDrawing: {
                        playerManager.sessionID = sessionID
                        playerManager.captureNewDrawingForPlaylistClip(
                            event: event,
                            visiblePlaylistEvents: visibleEvents,
                            playlistID: playlist.id
                        )
                    },
                    onTap: {
                        guard let start = visibleEvents.firstIndex(of: event) else { return }
                        playerManager.sessionID = sessionID
                        playerManager.playPlaylist(visibleEvents, startIndex: start, playlistID: playlist.id)
                    },
                    onDelete: {
                        removeEvent(at: index)
                    },
                    onComment: {
                        openCommentEditor(for: event)
                    },
                    hasComment: hasComment(for: event),
                    onToggleHidden: {
                        toggleEventHidden(at: index)
                    },
                    onMoveUp: {
                        moveEvent(index: index, direction: -1)
                    },
                    onMoveDown: {
                        moveEvent(index: index, direction: 1)
                    },
                    dragProvider: {
                        let dragData = PlaylistEventDragData(event: event, sourcePlaylistID: playlist.id)
                        let data = try! JSONEncoder().encode(dragData)
                        return NSItemProvider(item: data as NSData, typeIdentifier: UTType.data.identifier)
                    }
                )
                .onDrop(of: [.data], delegate: EventReorderDropDelegate(
                    targetIndex: index,
                    playlist: playlist,
                    sessionID: sessionID,
                    groupIndex: groupIndex,
                    dragOverIndex: $dragOverIndex
                ))
            }
        }
        .padding(.top, 4)
        }
        .frame(maxHeight: 220)
    }

    // MARK: - Context Menu
    
    @ViewBuilder
    private var cardContextMenu: some View {
        Button(^String.Titles.sportCutPlayAction) { onPlay() }
        Button(^String.Titles.sportCutDuplicate) { onDuplicate() }
        Button(^String.Titles.sportCutRenameAction) { onRename() }
        Divider()
        Button(^String.Titles.sportCutMoveUp) { onMoveUp() }
            .disabled(!canMoveUp)
        Button(^String.Titles.sportCutMoveDown) { onMoveDown() }
            .disabled(!canMoveDown)
        Divider()
        Button(playlist.isHidden ? ^String.Titles.sportCutShowPlaylist : ^String.Titles.sportCutHidePlaylist) { onToggleHidden() }
        Divider()
        Button(^String.Titles.deleteButtonTitle, role: .destructive) { onDelete() }
    }
    
    // MARK: - Drop Handling
    
    private func handleCardDrop(providers: [NSItemProvider], insertAt: Int?) {
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
                guard let data = data else { return }
                DispatchQueue.main.async {
                    if let orderData = try? JSONDecoder().decode(PlaylistOrderDragData.self, from: data) {
                        onReorderDrop(orderData.playlistID)
                    } else if let dragData = try? JSONDecoder().decode(PlaylistEventDragData.self, from: data) {
                        movePlaylistEvent(dragData: dragData, toIndex: insertAt)
                    } else if let payload = try? JSONDecoder().decode(MarkupStampsBatchPlaylistDragPayload.self, from: data),
                              let events = WindowsManager.shared.resolveMarkupPlaylistEvents(payload: payload, sessionID: sessionID),
                              !events.isEmpty {
                        WindowsManager.shared.insertMarkupEventsIntoSportCutPlaylist(
                            events: events,
                            sessionID: sessionID,
                            groupIndex: groupIndex,
                            playlistID: playlist.id,
                            at: insertAt ?? playlist.events.count
                        )
                    } else if let events = try? JSONDecoder().decode([SportCutEvent].self, from: data),
                              !events.isEmpty {
                        appendExternalEvents(events, at: insertAt)
                    } else if let event = try? JSONDecoder().decode(SportCutEvent.self, from: data) {
                        appendExternalEvent(event, at: insertAt)
                    }
                }
            }
        }
    }
    
    private func movePlaylistEvent(dragData: PlaylistEventDragData, toIndex: Int?) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        let hk = dragData.event.hiddenKey
        var carriedComment: String?
        for gi in session.playlistGroups.indices {
            if let pi = session.playlistGroups[gi].playlists.firstIndex(where: { $0.id == dragData.sourcePlaylistID }) {
                carriedComment = session.playlistGroups[gi].playlists[pi].eventComments[hk]
                session.playlistGroups[gi].playlists[pi].events.removeAll { $0 == dragData.event }
                session.playlistGroups[gi].playlists[pi].eventComments.removeValue(forKey: hk)
                break
            }
        }
        
        if let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) {
            let targetIdx = toIndex ?? session.playlistGroups[groupIndex].playlists[pi].events.count
            let clamped = min(targetIdx, session.playlistGroups[groupIndex].playlists[pi].events.count)
            session.playlistGroups[groupIndex].playlists[pi].events.insert(dragData.event, at: clamped)
            if let c = carriedComment, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.playlistGroups[groupIndex].playlists[pi].eventComments[hk] = c
            }
        }
        
        SportCutSessionManager.shared.updateSession(session)
    }
    
    private func appendExternalEvent(_ event: SportCutEvent, at index: Int?) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        
        if let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) {
            if !session.playlistGroups[groupIndex].playlists[pi].events.contains(event) {
                let targetIdx = index ?? session.playlistGroups[groupIndex].playlists[pi].events.count
                let clamped = min(targetIdx, session.playlistGroups[groupIndex].playlists[pi].events.count)
                session.playlistGroups[groupIndex].playlists[pi].events.insert(event, at: clamped)
                session.playlistGroups[groupIndex].playlists[pi].mergeMarkupComments(for: [event], session: session)
                SportCutSessionManager.shared.updateSession(session)
            }
        }
    }

    private func appendExternalEvents(_ events: [SportCutEvent], at index: Int?) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        guard let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) else { return }

        var destinationPlaylist = session.playlistGroups[groupIndex].playlists[pi]
        var insertIndex = min(max(index ?? destinationPlaylist.events.count, 0), destinationPlaylist.events.count)
        var insertedEvents: [SportCutEvent] = []

        for event in events where !destinationPlaylist.events.contains(event) {
            destinationPlaylist.events.insert(event, at: insertIndex)
            insertIndex += 1
            insertedEvents.append(event)
        }

        guard !insertedEvents.isEmpty else { return }
        destinationPlaylist.mergeMarkupComments(for: insertedEvents, session: session)
        session.playlistGroups[groupIndex].playlists[pi] = destinationPlaylist
        SportCutSessionManager.shared.updateSession(session)
    }
    
    private func removeEvent(at index: Int) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        if let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) {
            guard index < session.playlistGroups[groupIndex].playlists[pi].events.count else { return }
            let removed = session.playlistGroups[groupIndex].playlists[pi].events.remove(at: index)
            session.playlistGroups[groupIndex].playlists[pi].hiddenEventKeys.remove(removed.hiddenKey)
            session.playlistGroups[groupIndex].playlists[pi].eventComments.removeValue(forKey: removed.hiddenKey)
            if let drawings = session.playlistGroups[groupIndex].playlists[pi].eventDrawings.removeValue(forKey: removed.hiddenKey) {
                let folder = SportCutPlayerManager.drawingsFolder(sessionID: sessionID)
                for drawing in drawings {
                    try? FileManager.default.removeItem(at: folder.appendingPathComponent(drawing.imageName))
                }
            }
            SportCutSessionManager.shared.updateSession(session)
        }
    }

    private func openCommentEditor(for event: SportCutEvent) {
        guard let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        guard let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        let comment = session.playlistGroups[groupIndex].playlists[pi].eventComments[event.hiddenKey] ?? ""
        commentEditorState = EventCommentEditorState(event: event, comment: comment)
    }

    private func saveEventComment(event: SportCutEvent, comment: String) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        guard let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            session.playlistGroups[groupIndex].playlists[pi].eventComments.removeValue(forKey: event.hiddenKey)
        } else {
            session.playlistGroups[groupIndex].playlists[pi].eventComments[event.hiddenKey] = trimmed
        }
        SportCutSessionManager.shared.updateSession(session)
        commentEditorState = nil
    }

    private func hasComment(for event: SportCutEvent) -> Bool {
        guard let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return false }
        guard let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) else { return false }
        let comment = session.playlistGroups[groupIndex].playlists[pi].eventComments[event.hiddenKey] ?? ""
        return !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func toggleEventHidden(at index: Int) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        guard let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        guard index >= 0, index < session.playlistGroups[groupIndex].playlists[pi].events.count else { return }
        let event = session.playlistGroups[groupIndex].playlists[pi].events[index]
        let key = event.hiddenKey
        if session.playlistGroups[groupIndex].playlists[pi].hiddenEventKeys.contains(key) {
            session.playlistGroups[groupIndex].playlists[pi].hiddenEventKeys.remove(key)
        } else {
            session.playlistGroups[groupIndex].playlists[pi].hiddenEventKeys.insert(key)
        }
        SportCutSessionManager.shared.updateSession(session)
        playerManager.handleEventVisibilityChange(session: session, playlistID: playlist.id, changedEvent: event)
    }

    private func moveEvent(index: Int, direction: Int) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        guard let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        var events = session.playlistGroups[groupIndex].playlists[pi].events
        let newIndex = index + direction
        guard index >= 0, index < events.count, newIndex >= 0, newIndex < events.count else { return }
        let item = events.remove(at: index)
        events.insert(item, at: newIndex)
        session.playlistGroups[groupIndex].playlists[pi].events = events
        SportCutSessionManager.shared.updateSession(session)

        // Keep active-event highlight bound to the same event after reorder.
        if playerManager.currentPlaylistID == playlist.id {
            let activeIndex = playerManager.currentPlaylistIndex
            guard activeIndex >= 0 else { return }

            if activeIndex == index {
                // Moved the active event itself.
                playerManager.currentPlaylistIndex = newIndex
            } else if direction == -1, activeIndex == newIndex {
                // Active event was swapped down by moved item.
                playerManager.currentPlaylistIndex = activeIndex + 1
            } else if direction == 1, activeIndex == newIndex {
                // Active event was swapped up by moved item.
                playerManager.currentPlaylistIndex = activeIndex - 1
            }
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Playlist Event Row

struct PlaylistEventRowView: View {
    let event: SportCutEvent
    let index: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let isCurrent: Bool
    let isHidden: Bool
    let isDropTarget: Bool
    let hasDrawing: Bool
    let onAddDrawing: () -> Void
    let onTap: () -> Void
    let onDelete: () -> Void
    let onComment: () -> Void
    let hasComment: Bool
    let onToggleHidden: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let dragProvider: () -> NSItemProvider
    
    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleHidden) {
                Image(systemName: isHidden ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isHidden ? .secondary : .blue.opacity(0.8))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: onComment) {
                Image(systemName: hasComment ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 10))
                    .foregroundColor(hasComment ? .orange : .secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: onAddDrawing) {
                Image(systemName: "pencil.tip.crop.circle")
                    .font(.system(size: 10))
                    .foregroundColor(hasDrawing ? .green : .secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .help(^String.Titles.sportCutCreateDrawing)

            Circle()
                .fill(Color(hex: event.color))
                .frame(width: 8, height: 8)
            
            Text(event.tagName)
                .font(.system(size: 11, weight: isCurrent ? .bold : .regular))
                .lineLimit(1)
                .foregroundColor(isCurrent ? .blue : .primary)
            
            Spacer()
            
            Text(formatDuration(event.duration))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)

            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(canMoveUp ? .secondary : .gray.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canMoveUp)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(canMoveDown ? .secondary : .gray.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canMoveDown)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .opacity(isHidden ? 0.45 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isCurrent ? Color.blue.opacity(0.12) : Color.clear)
        )
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(Color.blue)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onDrag(dragProvider)
        .contextMenu {
            Button(hasComment ? ^String.Titles.sportCutEditComment : ^String.Titles.sportCutAddComment) { onComment() }
            Button(^String.Titles.sportCutCreateDrawing) { onAddDrawing() }
            Button(isHidden ? ^String.Titles.sportCutShowEvent : ^String.Titles.sportCutHideEvent) { onToggleHidden() }
            Divider()
            Button(^String.Titles.sportCutMoveUp) { onMoveUp() }
                .disabled(!canMoveUp)
            Button(^String.Titles.sportCutMoveDown) { onMoveDown() }
                .disabled(!canMoveDown)
            Divider()
            Button(^String.Titles.sportCutDeleteFromPlaylist, role: .destructive) { onDelete() }
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct DrawingMarker: Identifiable {
    let offset: CGFloat
    let drawing: SportCutEventDrawing
    let event: SportCutEvent
    var id: String { drawing.imageName }
}

private struct EventCommentEditorState: Identifiable {
    let event: SportCutEvent
    let comment: String
    var id: String { event.hiddenKey }
}

struct SportCutEventCommentSheet: View {
    let title: String
    let initialComment: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(^String.Titles.sportCutComment)
                .font(.headline)
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)

            TextEditor(text: $text)
                .font(.system(size: 12))
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )

            HStack {
                Button(^String.Titles.cancelButtonTitle) { onCancel() }
                    .buttonStyle(PlainButtonStyle())
                Spacer()
                Button(^String.Titles.saveButtonTitle) { onSave(text) }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.blue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380, height: 230)
        .onAppear {
            text = initialComment
            HotKeyManager.shared.isEnabled = false
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 36 else { return event }
                if event.modifierFlags.contains(.shift) { return event }
                onSave(text)
                return nil
            }
        }
        .onDisappear {
            HotKeyManager.shared.isEnabled = true
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            keyMonitor = nil
        }
    }
}

// MARK: - Reorder Drop Delegate

struct EventReorderDropDelegate: DropDelegate {
    let targetIndex: Int
    let playlist: SportCutPlaylist
    let sessionID: UUID
    let groupIndex: Int
    @Binding var dragOverIndex: Int?
    
    func dropEntered(info: DropInfo) {
        dragOverIndex = targetIndex
    }
    
    func dropExited(info: DropInfo) {
        if dragOverIndex == targetIndex {
            dragOverIndex = nil
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        dragOverIndex = nil
        
        for provider in info.itemProviders(for: [.data]) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
                guard let data = data else { return }
                DispatchQueue.main.async {
                    if let dragData = try? JSONDecoder().decode(PlaylistEventDragData.self, from: data) {
                        performMoveEvent(dragData: dragData)
                    } else if let payload = try? JSONDecoder().decode(MarkupStampsBatchPlaylistDragPayload.self, from: data),
                              let events = WindowsManager.shared.resolveMarkupPlaylistEvents(payload: payload, sessionID: sessionID),
                              !events.isEmpty {
                        WindowsManager.shared.insertMarkupEventsIntoSportCutPlaylist(
                            events: events,
                            sessionID: sessionID,
                            groupIndex: groupIndex,
                            playlistID: playlist.id,
                            at: targetIndex
                        )
                    } else if let events = try? JSONDecoder().decode([SportCutEvent].self, from: data),
                              !events.isEmpty {
                        performInsertEvents(events)
                    } else if let event = try? JSONDecoder().decode(SportCutEvent.self, from: data) {
                        performInsertEvent(event)
                    }
                }
            }
        }
        return true
    }
    
    private func performMoveEvent(dragData: PlaylistEventDragData) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        let hk = dragData.event.hiddenKey
        var carriedComment: String?
        for gi in session.playlistGroups.indices {
            if let pi = session.playlistGroups[gi].playlists.firstIndex(where: { $0.id == dragData.sourcePlaylistID }) {
                carriedComment = session.playlistGroups[gi].playlists[pi].eventComments[hk]
                session.playlistGroups[gi].playlists[pi].events.removeAll { $0 == dragData.event }
                session.playlistGroups[gi].playlists[pi].eventComments.removeValue(forKey: hk)
                break
            }
        }
        
        if let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) {
            let clamped = min(targetIndex, session.playlistGroups[groupIndex].playlists[pi].events.count)
            session.playlistGroups[groupIndex].playlists[pi].events.insert(dragData.event, at: clamped)
            if let c = carriedComment, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.playlistGroups[groupIndex].playlists[pi].eventComments[hk] = c
            }
        }
        
        SportCutSessionManager.shared.updateSession(session)
    }
    
    private func performInsertEvent(_ event: SportCutEvent) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        
        if let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) {
            if !session.playlistGroups[groupIndex].playlists[pi].events.contains(event) {
                let clamped = min(targetIndex, session.playlistGroups[groupIndex].playlists[pi].events.count)
                session.playlistGroups[groupIndex].playlists[pi].events.insert(event, at: clamped)
                session.playlistGroups[groupIndex].playlists[pi].mergeMarkupComments(for: [event], session: session)
                SportCutSessionManager.shared.updateSession(session)
            }
        }
    }

    private func performInsertEvents(_ events: [SportCutEvent]) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        guard let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlist.id }) else { return }

        var destinationPlaylist = session.playlistGroups[groupIndex].playlists[pi]
        var insertIndex = min(max(targetIndex, 0), destinationPlaylist.events.count)
        var insertedEvents: [SportCutEvent] = []

        for event in events where !destinationPlaylist.events.contains(event) {
            destinationPlaylist.events.insert(event, at: insertIndex)
            insertIndex += 1
            insertedEvents.append(event)
        }

        guard !insertedEvents.isEmpty else { return }
        destinationPlaylist.mergeMarkupComments(for: insertedEvents, session: session)
        session.playlistGroups[groupIndex].playlists[pi] = destinationPlaylist
        SportCutSessionManager.shared.updateSession(session)
    }
}

// MARK: - Name Input Sheet

struct SportCutNameInputSheet: View {
    let title: String
    let placeholder: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    @State private var name = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
            
            TextField(placeholder, text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit { onSave(name) }
            
            HStack {
                Button(^String.Titles.cancelButtonTitle) { onCancel() }
                    .buttonStyle(PlainButtonStyle())
                Spacer()
                Button(^String.Titles.alertsOkTitle) { onSave(name) }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.blue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 350, height: 150)
    }
}
