//
//  SportCutTimelineView.swift
//  Youchip-Stat
//

import SwiftUI
import UniformTypeIdentifiers

struct SportCutTimelineView: View {
    let sessionID: UUID
    @ObservedObject var playerManager: SportCutPlayerManager
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    
    @State private var displayMode: TimelineDisplayMode = .timeline
    @State private var selectedSourceIndex: Int = -1 // -1 = all tab
    @State private var showFilterSheet = false
    @State private var showAddSourceSheet = false
    @StateObject private var filter = TimelineFilter()
    @State private var timelineScale: CGFloat = 1.0
    @GestureState private var magnifyScale: CGFloat = 1.0
    
    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }
    
    private var sources: [SportCutSource] {
        session?.sources ?? []
    }
    
    private var currentSource: SportCutSource? {
        guard selectedSourceIndex >= 0, selectedSourceIndex < sources.count else { return nil }
        return sources[selectedSourceIndex]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            
            if displayMode == .timeline {
                if selectedSourceIndex == -1 {
                    Text(^String.Titles.sportCutSelectProjectForTimeline)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.1))
                } else if let source = currentSource {
                    timelineContent(source: source)
                }
            } else {
                SportCutTableView(
                    sessionID: sessionID,
                    playerManager: playerManager,
                    filter: filter,
                    selectedSourceIndex: selectedSourceIndex
                )
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            sportCutFilterSheet
        }
        .sheet(isPresented: $showAddSourceSheet) {
            SportCutAddSourceSheet(sessionID: sessionID) {
                showAddSourceSheet = false
            }
        }
        .background(Color.gray.opacity(0.1))
    }
    
    private var controlBar: some View {
        HStack(spacing: 8) {
            sourceTabs
            
            Spacer()
            
            addAllButton
            displayModeToggle
            filterButton
            
            if displayMode == .timeline {
                zoomControls
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    private var sourceTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(action: {
                    selectedSourceIndex = -1
                    if displayMode == .timeline { displayMode = .table }
                }) {
                    Text(^String.Titles.sportCutAllTab)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(selectedSourceIndex == -1 ? Color.blue : Color.gray.opacity(0.15))
                        .foregroundColor(selectedSourceIndex == -1 ? .white : .primary)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                addSourceButton
                
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    Button(action: { selectedSourceIndex = index }) {
                        Text(source.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(selectedSourceIndex == index ? Color.blue : Color.gray.opacity(0.15))
                            .foregroundColor(selectedSourceIndex == index ? .white : .primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        Button(^String.Titles.sportCutDeleteFromSession, role: .destructive) {
                            removeSource(source)
                        }
                    }
                }
            }
        }
    }
    
    private var addAllButton: some View {
        Button(action: addAllFilteredEvents) {
            HStack(spacing: 4) {
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.system(size: 11))
                Text(^String.Titles.sportCutAddAll)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.2))
            .foregroundColor(.green)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var displayModeToggle: some View {
        HStack(spacing: 2) {
            ForEach(TimelineDisplayMode.allCases, id: \.self) { mode in
                Button(action: {
                    if mode == .timeline && selectedSourceIndex == -1 && sources.count > 0 {
                        selectedSourceIndex = 0
                    }
                    displayMode = mode
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 10))
                        Text(mode.localizedName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(displayMode == mode ? Color.blue : Color.gray.opacity(0.1))
                    .foregroundColor(displayMode == mode ? .white : .primary)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var filterButton: some View {
        Button(action: { showFilterSheet = true }) {
            HStack(spacing: 4) {
                Image(systemName: filter.hasActiveFilters() ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11))
                Text(^String.Titles.sportCutFilterTitle)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(filter.hasActiveFilters() ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .foregroundColor(filter.hasActiveFilters() ? .blue : .primary)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { timelineScale = max(1.0, timelineScale - 0.5) } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(PlainButtonStyle())
            
            Text(String(format: "%.1fx", timelineScale))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            Button { timelineScale += 0.5 } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var addSourceButton: some View {
        Button(action: { showAddSourceSheet = true }) {
            Image(systemName: "plus.circle")
                .font(.system(size: 14))
                .foregroundColor(.blue)
        }
        .buttonStyle(PlainButtonStyle())
        .help(^String.Titles.sportCutAddVideoOrProject)
    }
    
    @ViewBuilder
    private func timelineContent(source: SportCutSource) -> some View {
        let filteredLines = source.timelines.filter { line in
            line.stamps.contains { filter.matches(stamp: $0) }
        }
        
        ScrollView(.vertical) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(width: 180, height: 30)
                    
                    ForEach(filteredLines) { line in
                        HStack {
                            Text(line.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(2)
                                .padding(.horizontal, 6)
                            Spacer()
                        }
                        .frame(width: 180, height: 30)
                    }
                }
                
                GeometryReader { geo in
                    let effectiveScale = timelineScale * magnifyScale
                    let duration = source.timelines.flatMap(\.stamps).map(\.timeFinishSeconds).max() ?? 1.0
                    let totalDuration = max(1.0, duration)
                    let gridWidth = geo.size.width * max(effectiveScale, 1.0)
                    
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            TimelineTimestampsHeaderView(
                                duration: totalDuration,
                                interval: totalDuration / (20 * effectiveScale),
                                width: gridWidth
                            )
                            .frame(height: 30)
                            
                            ForEach(filteredLines) { line in
                                SportCutTimelineLineView(
                                    line: line,
                                    source: source,
                                    totalDuration: totalDuration,
                                    gridWidth: gridWidth,
                                    filter: filter,
                                    playerManager: playerManager,
                                    sessionID: sessionID
                                )
                                .frame(height: 30)
                            }
                        }
                        .frame(width: gridWidth)
                    }
                }
            }
        }
        .gesture(
            MagnificationGesture()
                .updating($magnifyScale) { state, gestureState, _ in
                    gestureState = max(1.0, state)
                }
                .onEnded { value in
                    timelineScale = max(1.0, timelineScale * value)
                }
        )
    }
    
    private var sportCutFilterSheet: some View {
        SportCutFilterSheet(sessionID: sessionID, filter: filter, selectedSourceIndex: selectedSourceIndex)
    }
    
    private func removeSource(_ source: SportCutSource) {
        guard var session = session else { return }
        if selectedSourceIndex >= 0, selectedSourceIndex < session.sources.count, session.sources[selectedSourceIndex].id == source.id {
            selectedSourceIndex = max(session.sources.count - 2, -1)
        } else if selectedSourceIndex >= session.sources.count - 1 {
            selectedSourceIndex = max(session.sources.count - 2, -1)
        }
        SportCutSessionManager.shared.removeSource(from: &session, sourceID: source.id)
    }
    
    private func addAllFilteredEvents() {
        guard var session = session else { return }
        guard !session.playlistGroups.isEmpty else { return }
        
        let sourcesToProcess: [SportCutSource]
        if selectedSourceIndex == -1 {
            sourcesToProcess = sources
        } else if let source = currentSource {
            sourcesToProcess = [source]
        } else {
            return
        }
        
        for source in sourcesToProcess {
            for line in source.timelines {
                for stamp in line.stamps where filter.matches(stamp: stamp) {
                    let event = SportCutEvent.from(stamp: stamp, line: line, source: source)
                    let groupIdx = 0
                    if session.playlistGroups[groupIdx].playlists.isEmpty {
                        session.playlistGroups[groupIdx].playlists.append(
                            SportCutPlaylist(name: "1")
                        )
                    }
                    let playlistIdx = session.playlistGroups[groupIdx].playlists.count - 1
                    if !session.playlistGroups[groupIdx].playlists[playlistIdx].events.contains(event) {
                        session.playlistGroups[groupIdx].playlists[playlistIdx].events.append(event)
                    }
                }
            }
        }
        
        sessionManager.updateSession(session)
    }
}

// MARK: - Timeline Line View

struct SportCutTimelineLineView: View {
    let line: TimelineLine
    let source: SportCutSource
    let totalDuration: Double
    let gridWidth: CGFloat
    @ObservedObject var filter: TimelineFilter
    @ObservedObject var playerManager: SportCutPlayerManager
    let sessionID: UUID
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: gridWidth, height: 30)
            
            ForEach(line.stamps.filter { filter.matches(stamp: $0) }) { stamp in
                let startRatio = stamp.timeStartSeconds / totalDuration
                let durationRatio = stamp.duration / totalDuration
                let stampWidth = max(durationRatio * gridWidth, 4)
                let stampX = startRatio * gridWidth
                
                let tag = source.findTag(byID: stamp.idTag)
                let color = Color(hex: tag?.color ?? "FFFFFF")
                
                SportCutStampView(
                    stamp: stamp,
                    line: line,
                    source: source,
                    color: color,
                    stampX: stampX,
                    stampWidth: stampWidth,
                    playerManager: playerManager,
                    sessionID: sessionID
                )
            }
        }
        .frame(width: gridWidth, height: 30)
    }
}

struct SportCutStampView: View {
    let stamp: TimelineStamp
    let line: TimelineLine
    let source: SportCutSource
    let color: Color
    let stampX: CGFloat
    let stampWidth: CGFloat
    @ObservedObject var playerManager: SportCutPlayerManager
    let sessionID: UUID
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    
    @State private var isDragging = false
    
    private func createEvent() -> SportCutEvent {
        SportCutEvent.from(stamp: stamp, line: line, source: source)
    }
    
    var body: some View {
        Rectangle()
            .fill(color.opacity(isDragging ? 0.5 : 0.7))
            .overlay(
                Rectangle()
                    .stroke(color, lineWidth: 1)
            )
            .frame(width: max(stampWidth, 2), height: 24)
            .position(x: stampX + stampWidth / 2, y: 15)
            .overlay(
                Text(stamp.label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 1)
                    .lineLimit(1)
                    .frame(width: max(stampWidth - 4, 0), height: 20)
                    .position(x: stampX + stampWidth / 2, y: 15)
            )
            .onDrag {
                isDragging = true
                let event = createEvent()
                let data = try? JSONEncoder().encode(event)
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: "com.youchip.sportcutEvent", visibility: .all) { completion in
                    DispatchQueue.main.async { isDragging = false }
                    completion(data, nil)
                    return nil
                }
                provider.registerDataRepresentation(forTypeIdentifier: "public.data", visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
                return provider
            }
            .onTapGesture {
                let event = createEvent()
                playerManager.playEvent(event)
            }
            .contextMenu {
                Button(^String.Titles.sportCutPlayAction) {
                    playerManager.playEvent(createEvent())
                }
                Button(^String.Titles.sportCutAddToPlaylist) {
                    addToCurrentPlaylist()
                }
            }
    }
    
    private func addToCurrentPlaylist() {
        guard var session = sessionManager.sessions.first(where: { $0.id == sessionID }) else { return }
        guard !session.playlistGroups.isEmpty else { return }
        
        let event = createEvent()
        if session.playlistGroups[0].playlists.isEmpty {
            session.playlistGroups[0].playlists.append(SportCutPlaylist(name: "1"))
        }
        let lastIdx = session.playlistGroups[0].playlists.count - 1
        if !session.playlistGroups[0].playlists[lastIdx].events.contains(event) {
            session.playlistGroups[0].playlists[lastIdx].events.append(event)
            sessionManager.updateSession(session)
        }
    }
}

// MARK: - Add Source Sheet

struct SportCutAddSourceSheet: View {
    let sessionID: UUID
    let onDone: () -> Void
    
    @ObservedObject private var sessionManager = SportCutSessionManager.shared
    @State private var showProjectPicker = false
    
    private var filesManager: VideoFilesManager { VideoFilesManager.shared }
    
    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }
    
    private var availableFiles: [FilesFile] {
        guard let session = session else { return filesManager.files }
        let existingProjectIDs = Set(session.sources.compactMap(\.projectID))
        return filesManager.files.filter { !existingProjectIDs.contains($0.videoData.id) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(^String.Titles.sportCutAddSources)
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            Divider()
            
            VStack(spacing: 16) {
                addProjectSection
                addVideoSection
                currentSourcesList
            }
            .padding(20)
            
            Spacer()
            
            Divider()
            
            HStack {
                Spacer()
                Button(^String.Titles.done) { onDone() }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.blue)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 500, height: 450)
        .sheet(isPresented: $showProjectPicker) {
            ProjectPickerSheet(
                availableFiles: availableFiles,
                onAdd: { files in
                    guard var session = session else { return }
                    for file in files {
                        SportCutSessionManager.shared.addProjectSource(to: &session, file: file)
                    }
                    showProjectPicker = false
                },
                onCancel: { showProjectPicker = false }
            )
        }
    }
    
    private var addProjectSection: some View {
        HStack(spacing: 12) {
            Button(action: { showProjectPicker = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 14))
                    Text(^String.Titles.sportCutAddMarkupProject)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(availableFiles.isEmpty)
            
            Spacer()
        }
    }
    
    private var addVideoSection: some View {
        HStack(spacing: 12) {
            Button(action: addVideoFiles) {
                HStack(spacing: 6) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 14))
                    Text(^String.Titles.sportCutAddVideoFile)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
        }
    }
    
    private var currentSourcesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(^String.Titles.sportCutCurrentSources)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            if let session = session {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(session.sources) { source in
                            HStack(spacing: 8) {
                                Image(systemName: source.isStandaloneVideo ? "video" : "film")
                                    .font(.system(size: 11))
                                    .foregroundColor(source.isStandaloneVideo ? .green : .blue)
                                
                                Text(source.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                let eventCount = source.timelines.flatMap(\.stamps).count
                                Text(String.Titles.sportCutEventsCount.format(eventCount))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.gray.opacity(0.06))
                            .cornerRadius(5)
                        }
                    }
                }
            }
        }
    }
    
    private func addVideoFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.title = ^String.Titles.sportCutSelectVideoFiles
        
        if panel.runModal() == .OK {
            guard var session = session else { return }
            for url in panel.urls {
                SportCutSessionManager.shared.addVideoSource(to: &session, url: url)
            }
        }
    }
}
