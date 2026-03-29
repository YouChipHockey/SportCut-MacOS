//
//  SportCutTimelineView.swift
//  Youchip-Stat
//

import SwiftUI
import UniformTypeIdentifiers

private enum SportCutBottomPane: Int, CaseIterable {
    case markup
    case table

    var title: String {
        switch self {
        case .markup: return "Разметка"
        case .table: return "Таблица"
        }
    }

    var icon: String {
        switch self {
        case .markup: return "timeline.selection"
        case .table: return "tablecells"
        }
    }
}

/// Индексы верхних вкладок источников: `-2` плейлисты, `-1` все проекты, `0..<n` проект.
private enum SportCutTimelineSourceTab {
    static let playlists = -2
    static let allProjects = -1
}

private enum SportCutTimelineLineSort: String, CaseIterable {
    case original
    case nameAsc
    case nameDesc

    var label: String {
        switch self {
        case .original: return "Как в проекте"
        case .nameAsc: return "Таймлайны А→Я"
        case .nameDesc: return "Таймлайны Я→А"
        }
    }
}

struct SportCutTimelineView: View {
    let sessionID: UUID
    @ObservedObject var playerManager: SportCutPlayerManager
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    
    @State private var bottomPane: SportCutBottomPane = .table
    @State private var selectedSourceIndex: Int = SportCutTimelineSourceTab.allProjects
    @State private var previousSelectedSourceIndex: Int = SportCutTimelineSourceTab.allProjects
    @State private var showFilterSheet = false
    @State private var showAddSourceSheet = false
    @StateObject private var filter = TimelineFilter()
    @State private var timelineScale: CGFloat = 1.0
    @GestureState private var magnifyScale: CGFloat = 1.0
    @State private var lineSort: SportCutTimelineLineSort = .original
    @State private var selectedSportStampID: UUID?
    
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
            
            if selectedSourceIndex == SportCutTimelineSourceTab.playlists {
                SportCutPlaylistsTimelinePane(
                    sessionID: sessionID,
                    sourceFilter: nil,
                    playerManager: playerManager,
                    timelineScale: $timelineScale
                )
            } else {
                switch bottomPane {
                case .markup:
                    if selectedSourceIndex == SportCutTimelineSourceTab.allProjects {
                        Text(^String.Titles.sportCutSelectProjectForTimeline)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.gray.opacity(0.1))
                    } else if let source = currentSource {
                        timelineContent(source: source)
                    }
                case .table:
                    SportCutTableView(
                        sessionID: sessionID,
                        playerManager: playerManager,
                        filter: filter,
                        selectedSourceIndex: selectedSourceIndex
                    )
                }
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
        .onChange(of: selectedSourceIndex) { newIdx in
            let oldIdx = previousSelectedSourceIndex
            previousSelectedSourceIndex = newIdx
            if newIdx == SportCutTimelineSourceTab.allProjects {
                bottomPane = .table
            } else if newIdx == SportCutTimelineSourceTab.playlists {
                // Только плейлисты; нижняя панель скрыта
            } else if (oldIdx == SportCutTimelineSourceTab.allProjects || oldIdx == SportCutTimelineSourceTab.playlists),
                      newIdx >= 0 {
                bottomPane = .markup
            }
        }
    }
    
    private var controlBar: some View {
        HStack(spacing: 8) {
            sourceTabs
            
            Spacer()
            
            addAllButton
            if selectedSourceIndex != SportCutTimelineSourceTab.playlists {
                bottomPaneToggle
            }
            filterButton
            
            if selectedSourceIndex == SportCutTimelineSourceTab.playlists {
                zoomControls
            } else if bottomPane == .markup {
                Menu {
                    ForEach(SportCutTimelineLineSort.allCases, id: \.self) { mode in
                        Button(mode.label) { lineSort = mode }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10))
                        Text(lineSort.label)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)

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
                    selectedSourceIndex = SportCutTimelineSourceTab.allProjects
                    bottomPane = .table
                }) {
                    Text(^String.Titles.sportCutAllTab)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(selectedSourceIndex == SportCutTimelineSourceTab.allProjects ? Color.blue : Color.gray.opacity(0.15))
                        .foregroundColor(selectedSourceIndex == SportCutTimelineSourceTab.allProjects ? .white : .primary)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { selectedSourceIndex = SportCutTimelineSourceTab.playlists }) {
                    Text(^String.Titles.playlists)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(selectedSourceIndex == SportCutTimelineSourceTab.playlists ? Color.blue : Color.gray.opacity(0.15))
                        .foregroundColor(selectedSourceIndex == SportCutTimelineSourceTab.playlists ? .white : .primary)
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
    
    private var bottomPaneToggle: some View {
        HStack(spacing: 2) {
            let modes: [SportCutBottomPane] = selectedSourceIndex == SportCutTimelineSourceTab.allProjects ? [.table] : SportCutBottomPane.allCases
            ForEach(modes, id: \.rawValue) { pane in
                Button(action: {
                    if pane == .markup, selectedSourceIndex == SportCutTimelineSourceTab.allProjects, sources.count > 0 {
                        selectedSourceIndex = 0
                    }
                    bottomPane = pane
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: pane.icon)
                            .font(.system(size: 10))
                        Text(pane.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(bottomPane == pane ? Color.blue : Color.gray.opacity(0.1))
                    .foregroundColor(bottomPane == pane ? .white : .primary)
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
    
    private func sortedTimelineLines(_ lines: [TimelineLine]) -> [TimelineLine] {
        switch lineSort {
        case .original:
            return lines
        case .nameAsc:
            return lines.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return lines.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        }
    }

    @ViewBuilder
    private func timelineContent(source: SportCutSource) -> some View {
        let filteredLines = sortedTimelineLines(source.timelines.filter { line in
            line.stamps.contains { filter.matches(stamp: $0) }
        })
        
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
                                    sessionID: sessionID,
                                    selectedStampID: $selectedSportStampID
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
        if selectedSourceIndex == SportCutTimelineSourceTab.allProjects
            || selectedSourceIndex == SportCutTimelineSourceTab.playlists {
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
    @Binding var selectedStampID: UUID?
    
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
                    totalDuration: totalDuration,
                    gridWidth: gridWidth,
                    isSelected: selectedStampID == stamp.id,
                    onSelectStamp: { selectedStampID = stamp.id },
                    playerManager: playerManager,
                    sessionID: sessionID
                )
            }
        }
        .frame(width: gridWidth, height: 30)
    }
}

struct SportCutStampView: View {
    private enum StampResizeEdge {
        case left
        case right
    }

    let stamp: TimelineStamp
    let line: TimelineLine
    let source: SportCutSource
    let color: Color
    let stampX: CGFloat
    let stampWidth: CGFloat
    let totalDuration: Double
    let gridWidth: CGFloat
    let isSelected: Bool
    let onSelectStamp: () -> Void
    @ObservedObject var playerManager: SportCutPlayerManager
    let sessionID: UUID
    @ObservedObject var sessionManager = SportCutSessionManager.shared

    @State private var isDraggingExport = false
    @State private var resizingEdge: StampResizeEdge?
    @State private var visualOffsetX: CGFloat?
    @State private var visualWidth: CGFloat?
    @State private var maxVisualOffsetX: CGFloat?
    @State private var originalStartTime: Double = 0
    @State private var originalEndTime: Double = 0
    @State private var dragInitialOffsetX: CGFloat = 0
    @State private var dragInitialWidth: CGFloat = 0
    @State private var lastSeekTime = Date()

    private let minStampWidth: CGFloat = 30
    private let stampHeight: CGFloat = 25
    private let seekThrottle: TimeInterval = 0.033

    private var leftX: CGFloat {
        visualOffsetX ?? stampX
    }

    private var displayWidth: CGFloat {
        max(visualWidth ?? stampWidth, minStampWidth)
    }

    private var centerX: CGFloat {
        leftX + displayWidth / 2
    }

    private func createEvent() -> SportCutEvent {
        SportCutEvent.from(stamp: stamp, line: line, source: source)
    }

    private func commitResizeCleanup() {
        resizingEdge = nil
        visualWidth = nil
        visualOffsetX = nil
        maxVisualOffsetX = nil
        dragInitialOffsetX = 0
        dragInitialWidth = 0
    }

    private func throttledPreviewSeek(absoluteVideoTime: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastSeekTime) >= seekThrottle else { return }
        lastSeekTime = now
        playerManager.seekPreviewDuringResize(
            absoluteVideoTime: absoluteVideoTime,
            stampID: stamp.id,
            sourceID: source.id
        )
    }

    private var leftEdgeDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizingEdge != .left {
                    resizingEdge = .left
                    originalStartTime = stamp.timeStartSeconds
                    originalEndTime = stamp.timeFinishSeconds
                    let baseDur = originalEndTime - originalStartTime
                    dragInitialWidth = max(CGFloat(baseDur / max(totalDuration, 0.001)) * gridWidth, minStampWidth)
                    dragInitialOffsetX = CGFloat(originalStartTime / max(totalDuration, 0.001)) * gridWidth
                    maxVisualOffsetX = dragInitialOffsetX + dragInitialWidth - minStampWidth
                    visualOffsetX = dragInitialOffsetX
                    visualWidth = dragInitialWidth
                }
                let newOffsetX = dragInitialOffsetX + value.translation.width
                let newWidth = max(dragInitialWidth - value.translation.width, minStampWidth)
                guard newOffsetX >= 0, newOffsetX <= maxVisualOffsetX ?? 0 else { return }
                visualOffsetX = newOffsetX
                visualWidth = newWidth
                let t = Double(newOffsetX / max(gridWidth, 1)) * totalDuration
                throttledPreviewSeek(absoluteVideoTime: t)
            }
            .onEnded { _ in
                guard resizingEdge == .left, let ox = visualOffsetX else {
                    commitResizeCleanup()
                    return
                }
                applyLeftEdgeEnd(finalOffsetX: ox)
            }
    }

    private var rightEdgeDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizingEdge != .right {
                    resizingEdge = .right
                    originalStartTime = stamp.timeStartSeconds
                    originalEndTime = stamp.timeFinishSeconds
                    let baseDur = originalEndTime - originalStartTime
                    dragInitialWidth = max(CGFloat(baseDur / max(totalDuration, 0.001)) * gridWidth, minStampWidth)
                    dragInitialOffsetX = CGFloat(originalStartTime / max(totalDuration, 0.001)) * gridWidth
                    visualOffsetX = dragInitialOffsetX
                    visualWidth = dragInitialWidth
                }
                let newWidth = max(dragInitialWidth + value.translation.width, minStampWidth)
                guard dragInitialOffsetX + newWidth <= gridWidth else { return }
                visualWidth = newWidth
                let wPx = visualWidth ?? newWidth
                let endTime = originalStartTime + Double(wPx / max(gridWidth, 1)) * totalDuration
                throttledPreviewSeek(absoluteVideoTime: min(endTime, totalDuration))
            }
            .onEnded { _ in
                guard resizingEdge == .right, let w = visualWidth else {
                    commitResizeCleanup()
                    return
                }
                applyRightEdgeEnd(finalWidth: w)
            }
    }

    private func applyRightEdgeEnd(finalWidth: CGFloat) {
        let ratio = finalWidth / max(gridWidth, 1)
        let newDuration = max(ratio * totalDuration, 0.5)
        let newEnd = min(originalStartTime + newDuration, totalDuration)
        guard var session = sessionManager.sessions.first(where: { $0.id == sessionID }) else {
            commitResizeCleanup()
            return
        }
        SportCutSessionManager.shared.updateStampTime(
            in: &session,
            sourceID: source.id,
            lineID: line.id,
            stampID: stamp.id,
            newStart: nil,
            newEnd: newEnd
        )
        commitResizeCleanup()
    }

    private func applyLeftEdgeEnd(finalOffsetX: CGFloat) {
        let startRatio = finalOffsetX / max(gridWidth, 1)
        var finalStart = max(startRatio * totalDuration, 0)
        finalStart = min(finalStart, originalEndTime - 0.5)
        guard var session = sessionManager.sessions.first(where: { $0.id == sessionID }) else {
            commitResizeCleanup()
            return
        }
        SportCutSessionManager.shared.updateStampTime(
            in: &session,
            sourceID: source.id,
            lineID: line.id,
            stampID: stamp.id,
            newStart: finalStart,
            newEnd: nil
        )
        commitResizeCleanup()
    }

    private var borderColor: Color {
        isSelected ? Color.blue : Color.clear
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color.opacity(isDraggingExport ? 0.45 : 0.95),
                            color.opacity(isDraggingExport ? 0.35 : 0.75)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: stampHeight)
                .shadow(
                    color: color.opacity(0.35),
                    radius: isSelected ? 4 : 2,
                    x: 0,
                    y: isSelected ? 2 : 1
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: isSelected ? 2.5 : 1.5)
                )

            Text(stamp.label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 1)
                .lineLimit(1)
                .frame(width: max(displayWidth - 16, 0))
                .padding(.horizontal, 4)
        }
        .overlay(alignment: .center) {
            if isSelected {
                HStack(spacing: 0) {
                    EdgeResizeHandle(edge: TimelineLineView.ResizeEdge.left, stampHeight: stampHeight)
                        .frame(width: 8)
                        .highPriorityGesture(leftEdgeDragGesture)
                    Spacer(minLength: 0)
                    EdgeResizeHandle(edge: TimelineLineView.ResizeEdge.right, stampHeight: stampHeight)
                        .frame(width: 8)
                        .highPriorityGesture(rightEdgeDragGesture)
                }
                .frame(width: displayWidth)
            }
        }
        .frame(width: displayWidth, height: stampHeight)
        .position(x: centerX, y: 15)
        .onDrag {
            isDraggingExport = true
            let event = createEvent()
            let data = try? JSONEncoder().encode(event)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: "com.youchip.sportcutEvent", visibility: .all) { completion in
                DispatchQueue.main.async { isDraggingExport = false }
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
            guard resizingEdge == nil else { return }
            onSelectStamp()
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

// MARK: - Playlists as timelines (вкладка «Плейлисты», тот же каркас, что и разметка)

private struct SportCutPlaylistsTimelinePane: View {
    let sessionID: UUID
    /// Если задан — только события этого проекта и ось по его длительности.
    let sourceFilter: SportCutSource?
    @ObservedObject var playerManager: SportCutPlayerManager
    @Binding var timelineScale: CGFloat
    @GestureState private var magnifyScale: CGFloat = 1.0
    @State private var selectedEventKey: String?
    @ObservedObject var sessionManager = SportCutSessionManager.shared

    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }

    private func videoAxisDuration(for source: SportCutSource) -> Double {
        let d = source.timelines.flatMap(\.stamps).map(\.timeFinishSeconds).max() ?? 1.0
        return max(1.0, d)
    }

    /// Общая ось времени: максимум конца ролика среди всех источников сессии (как единая шкала).
    private func sessionAxisDuration(_ session: SportCutSession) -> Double {
        if let s = sourceFilter {
            return videoAxisDuration(for: s)
        }
        let ends = session.sources.map { src in
            src.timelines.flatMap(\.stamps).map(\.timeFinishSeconds).max() ?? 0
        }
        return max(ends.max() ?? 0, 1.0)
    }

    private func visibleEvents(in playlist: SportCutPlaylist) -> [SportCutEvent] {
        playlist.events.filter { !playlist.hiddenEventKeys.contains($0.hiddenKey) }
    }

    private func resolvedEvents(playlist: SportCutPlaylist, session: SportCutSession) -> [SportCutEvent] {
        let visible = visibleEvents(in: playlist)
        if let source = sourceFilter {
            return visible.filter { $0.sourceID == source.id }.map { session.timelineResolvedEvent(for: $0) }
        }
        return visible.map { session.timelineResolvedEvent(for: $0) }
    }

    var body: some View {
        Group {
            if let session = session {
                if session.playlistGroups.isEmpty {
                    Text(^String.Titles.sportCutNoPlaylists)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.1))
                } else {
                    let axisDuration = sessionAxisDuration(session)
                    ScrollView(.vertical) {
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Color.clear.frame(width: 180, height: 30)

                                ForEach(session.playlistGroups) { group in
                                    groupNameRow(group.name)
                                    if group.playlists.isEmpty {
                                        emptyGroupHintRow
                                    } else {
                                        ForEach(group.playlists) { playlist in
                                            playlistNameRow(playlist.name)
                                        }
                                    }
                                }
                            }

                            GeometryReader { geo in
                                let effectiveScale = timelineScale * magnifyScale
                                let gridWidth = geo.size.width * max(effectiveScale, 1.0)

                                ScrollView(.horizontal) {
                                    VStack(spacing: 0) {
                                        TimelineTimestampsHeaderView(
                                            duration: axisDuration,
                                            interval: axisDuration / (20 * effectiveScale),
                                            width: gridWidth
                                        )
                                        .frame(height: 30)

                                        ForEach(session.playlistGroups) { group in
                                            groupTimelineBand(width: gridWidth)
                                            if group.playlists.isEmpty {
                                                emptyPlaylistLine(width: gridWidth)
                                            } else {
                                                ForEach(group.playlists) { playlist in
                                                    SportCutPlaylistTimelineLineView(
                                                        events: resolvedEvents(playlist: playlist, session: session),
                                                        totalDuration: axisDuration,
                                                        gridWidth: gridWidth,
                                                        playlistID: playlist.id,
                                                        sessionID: sessionID,
                                                        playerManager: playerManager,
                                                        selectedEventKey: $selectedEventKey
                                                    )
                                                    .frame(height: 30)
                                                }
                                            }
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
            }
        }
    }

    private func groupNameRow(_ name: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
            Spacer()
        }
        .frame(width: 180, height: 30)
        .background(Color.gray.opacity(0.06))
    }

    private var emptyGroupHintRow: some View {
        HStack {
            Text(^String.Titles.sportCutNoPlaylists)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
            Spacer()
        }
        .frame(width: 180, height: 30)
    }

    private func playlistNameRow(_ name: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .padding(.horizontal, 6)
            Spacer()
        }
        .frame(width: 180, height: 30)
    }

    private func groupTimelineBand(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.gray.opacity(0.06))
                .frame(width: width, height: 30)
        }
        .frame(width: width, height: 30)
    }

    private func emptyPlaylistLine(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: width, height: 30)
        }
        .frame(width: width, height: 30)
    }
}

/// Одна строка таймлайна плейлиста: только события из плейлиста, визу как у `SportCutTimelineLineView`.
private struct SportCutPlaylistTimelineLineView: View {
    let events: [SportCutEvent]
    let totalDuration: Double
    let gridWidth: CGFloat
    let playlistID: UUID
    let sessionID: UUID
    @ObservedObject var playerManager: SportCutPlayerManager
    @Binding var selectedEventKey: String?

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: gridWidth, height: 30)

            ForEach(events.indices, id: \.self) { index in
                let event = events[index]
                let td = max(totalDuration, 0.001)
                let startRatio = event.startTime / td
                let durationRatio = max(event.duration, 0.01) / td
                let stampWidth = max(durationRatio * gridWidth, 4)
                let stampX = CGFloat(startRatio) * gridWidth

                SportCutPlaylistEventStripView(
                    event: event,
                    color: Color(hex: event.color),
                    stampX: stampX,
                    stampWidth: stampWidth,
                    isSelected: selectedEventKey == event.hiddenKey,
                    onTap: {
                        selectedEventKey = event.hiddenKey
                        playerManager.sessionID = sessionID
                        playerManager.playPlaylist(events, startIndex: index, playlistID: playlistID)
                    }
                )
            }
        }
        .frame(width: gridWidth, height: 30)
    }
}

private struct SportCutPlaylistEventStripView: View {
    let event: SportCutEvent
    let color: Color
    let stampX: CGFloat
    let stampWidth: CGFloat
    let isSelected: Bool
    let onTap: () -> Void

    private var displayW: CGFloat {
        max(stampWidth, 4)
    }

    var body: some View {
        ZStack(alignment: .center) {
            Rectangle()
                .fill(color.opacity(0.7))
                .overlay(
                    Rectangle()
                        .stroke(isSelected ? Color.white : color, lineWidth: isSelected ? 2 : 1)
                )
            Text(event.tagName)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 1)
                .lineLimit(1)
                .frame(width: max(displayW - 8, 0))
                .padding(.horizontal, 2)
        }
        .frame(width: displayW, height: 24)
        .position(x: stampX + displayW / 2, y: 15)
        .onTapGesture(perform: onTap)
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
