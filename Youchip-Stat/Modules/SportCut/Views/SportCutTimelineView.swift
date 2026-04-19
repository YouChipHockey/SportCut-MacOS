//
//  SportCutTimelineView.swift
//  Youchip-Stat
//

import SwiftUI
import UniformTypeIdentifiers

/// Верхняя граница зума шкалы SportCut: иначе слишком много подписей/лейаута при ресайзе окна.
private let sportCutTimelineMaxScale: CGFloat = 40

/// Край тега, который меняется колёсиком.
private enum PlaylistResizeEdge: String {
    case left = "L"
    case right = "R"
}

/// Уникальный ключ выделения тега на таймлайне плейлиста: плейлист + позиция в плейлисте.
private struct PlaylistEventSelectionKey: Equatable {
    let playlistID: UUID
    let eventIndex: Int
}

/// Manages local event monitor for Esc key to deselect playlist event.
private final class PlaylistTimelineEventMonitor: ObservableObject {
    private var keyMonitor: Any?
    var onEsc: (() -> Void)?
    var lastSelection: PlaylistEventSelectionKey?

    func start() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.lastSelection != nil {
                self?.onEsc?()
                return nil
            }
            return event
        }
    }

    func stop() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    deinit { stop() }
}

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
    /// Cmd+Click multi-selection of stamps for batch drag to playlists.
    @State private var bulkSelectedStampIDs: Set<UUID> = []
    /// Cached video durations by source ID, loaded once.
    @State private var sourceVideoDurations: [UUID: Double] = [:]
    
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
                    selectedPlaylistID: playerManager.currentPlaylistID,
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
                        selectedSourceIndex: selectedSourceIndex,
                        bulkSelectedStampIDs: $bulkSelectedStampIDs
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
            loadSourceDurationIfNeeded(sourceIndex: newIdx)
        }
        .onAppear {
            loadSourceDurationIfNeeded(sourceIndex: selectedSourceIndex)
        }
    }

    private func loadSourceDurationIfNeeded(sourceIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < sources.count else { return }
        let source = sources[sourceIndex]
        guard sourceVideoDurations[source.id] == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let dur = source.videoDuration()
            if dur > 0 {
                DispatchQueue.main.async {
                    sourceVideoDurations[source.id] = dur
                }
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
            
            Button { timelineScale = min(sportCutTimelineMaxScale, timelineScale + 0.5) } label: {
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

        return VStack(spacing: 0) {
            if !bulkSelectedStampIDs.isEmpty {
                bulkSelectionBar(source: source, filteredLines: filteredLines)
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Click on line name = select all stamps in this line
                            let stampIDs = Set(line.stamps.map(\.id))
                            if bulkSelectedStampIDs.isSuperset(of: stampIDs) {
                                bulkSelectedStampIDs.subtract(stampIDs)
                            } else {
                                bulkSelectedStampIDs.formUnion(stampIDs)
                            }
                        }
                    }
                }
                
                GeometryReader { geo in
                    let effectiveScale = timelineScale * magnifyScale
                    let stampMax = source.timelines.flatMap(\.stamps).map(\.timeFinishSeconds).max() ?? 1.0
                    let fullVideoDuration = sourceVideoDurations[source.id] ?? stampMax
                    let totalDuration = max(1.0, max(fullVideoDuration, stampMax))
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
                                    selectedStampID: $selectedSportStampID,
                                    bulkSelectedStampIDs: $bulkSelectedStampIDs
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
                    timelineScale = min(sportCutTimelineMaxScale, max(1.0, timelineScale * value))
                }
        )
        } // end VStack wrapping selection bar + ScrollView
    }
    
    private func bulkSelectionBar(source: SportCutSource, filteredLines: [TimelineLine]) -> some View {
        let allStamps = filteredLines.flatMap(\.stamps)
        let selected = allStamps.filter { bulkSelectedStampIDs.contains($0.id) }
        let totalSeconds = selected.reduce(0.0) { $0 + max(0.0, $1.duration) }
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        let ms = Int((totalSeconds.truncatingRemainder(dividingBy: 1.0)) * 1000)
        let durationStr = String(format: "%02d:%02d.%03d", minutes, seconds, ms)

        return HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(^String.Titles.sportCutBulkSelectedCount + ": \(selected.count)")
                .font(.system(size: 11, weight: .semibold))
            Text(^String.Titles.sportCutBulkTotalDuration + ": \(durationStr)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Button(^String.Titles.sportCutBulkClearSelection) {
                bulkSelectedStampIDs.removeAll()
            }
            .font(.system(size: 11))
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .onDrag {
            let events: [SportCutEvent] = selected.compactMap { stamp in
                guard let line = filteredLines.first(where: { $0.stamps.contains(where: { $0.id == stamp.id }) }) else { return nil }
                return SportCutEvent.from(stamp: stamp, line: line, source: source)
            }
            let data = try? JSONEncoder().encode(events)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.data.identifier, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
            return provider
        }
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
                        if let raw = stamp.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                            session.playlistGroups[groupIdx].playlists[playlistIdx].eventComments[event.hiddenKey] = raw
                        }
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
    @Binding var bulkSelectedStampIDs: Set<UUID>

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
                let color = Color(hex: tag?.color ?? stamp.colorHex)

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
                    isBulkSelected: bulkSelectedStampIDs.contains(stamp.id),
                    onSelectStamp: { selectedStampID = stamp.id },
                    onToggleBulkSelect: {
                        if bulkSelectedStampIDs.contains(stamp.id) {
                            bulkSelectedStampIDs.remove(stamp.id)
                        } else {
                            bulkSelectedStampIDs.insert(stamp.id)
                        }
                    },
                    bulkSelectedStampIDs: bulkSelectedStampIDs,
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
    let isBulkSelected: Bool
    let onSelectStamp: () -> Void
    let onToggleBulkSelect: () -> Void
    let bulkSelectedStampIDs: Set<UUID>
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

    private func formatStampTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1.0)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
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
        if isBulkSelected { return Color.green }
        if isSelected { return Color.blue }
        return Color.clear
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
        .frame(width: displayWidth, height: stampHeight)
        .position(x: centerX, y: 15)
        .onDrag {
            isDraggingExport = true

            // If this stamp is part of bulk selection, drag all selected stamps
            let data: Data?
            if isBulkSelected, bulkSelectedStampIDs.count > 1 {
                let allStamps = source.timelines.flatMap { ln in
                    ln.stamps.filter { bulkSelectedStampIDs.contains($0.id) }.map { (stamp: $0, line: ln) }
                }.sorted { $0.stamp.timeStartSeconds < $1.stamp.timeStartSeconds }
                let events = allStamps.map { SportCutEvent.from(stamp: $0.stamp, line: $0.line, source: source) }
                data = try? JSONEncoder().encode(events)
            } else {
                let event = createEvent()
                data = try? JSONEncoder().encode(event)
            }

            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.data.identifier, visibility: .all) { completion in
                DispatchQueue.main.async { isDraggingExport = false }
                completion(data, nil)
                return nil
            }
            return provider
        }
        .help("\(stamp.label) — \(formatStampTime(stamp.timeStartSeconds))–\(formatStampTime(stamp.timeFinishSeconds)) (\(formatStampTime(stamp.duration)))")
        .onTapGesture {
            let commandDown = NSEvent.modifierFlags.contains(.command)
            if commandDown {
                onToggleBulkSelect()
            } else {
                onSelectStamp()
                let event = createEvent()
                playerManager.playEvent(event)
            }
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
            if let raw = stamp.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                session.playlistGroups[0].playlists[lastIdx].eventComments[event.hiddenKey] = raw
            }
            sessionManager.updateSession(session)
        }
    }
}

// MARK: - Playlists as timelines (вкладка «Плейлисты»: каждый плейлист — своя строка, теги последовательно)

private struct SportCutPlaylistsTimelinePane: View {
    let sessionID: UUID
    let sourceFilter: SportCutSource?
    let selectedPlaylistID: UUID?
    @ObservedObject var playerManager: SportCutPlayerManager
    @Binding var timelineScale: CGFloat
    @State private var selection: PlaylistEventSelectionKey?
    @State private var resizeEdge: PlaylistResizeEdge = .right
    @StateObject private var eventMonitor = PlaylistTimelineEventMonitor()
    @ObservedObject var sessionManager = SportCutSessionManager.shared

    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }

    private var allPlaylists: [SportCutPlaylist] {
        session?.playlistGroups.flatMap(\.playlists) ?? []
    }

    private func visibleEvents(in playlist: SportCutPlaylist) -> [SportCutEvent] {
        var events = playlist.events.filter { !playlist.hiddenEventKeys.contains($0.hiddenKey) }
        if let source = sourceFilter {
            events = events.filter { $0.sourceID == source.id }
        }
        return events
    }

    private func clearSelection() {
        selection = nil
        eventMonitor.lastSelection = nil
    }

    var body: some View {
        Group {
            if let session = session {
                if allPlaylists.isEmpty {
                    Text(^String.Titles.sportCutNoPlaylists)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.1))
                } else {
                    playlistsTimelinesBody(session: session)
                }
            }
        }
        .onAppear {
            setupEventMonitor()
            eventMonitor.start()
        }
        .onDisappear {
            eventMonitor.stop()
        }
    }

    /// Применяет дельту (сек) к текущему выделенному тегу по текущему краю. Возвращает seek-время для preview.
    private func applyEdgeDelta(_ deltaSec: Double) {
        guard let sel = selection, let session = session else { return }
        let playlistID = sel.playlistID
        guard let gi = session.playlistGroups.firstIndex(where: { $0.playlists.contains(where: { $0.id == playlistID }) }),
              let pi = session.playlistGroups[gi].playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let playlist = session.playlistGroups[gi].playlists[pi]
        let events = playlist.events.filter { !playlist.hiddenEventKeys.contains($0.hiddenKey) }
        guard sel.eventIndex < events.count else { return }
        let event = events[sel.eventIndex]

        let source = session.sources.first { $0.id == event.sourceID }
        let videoDur = source?.videoDuration() ?? 0
        let maxVideoDur = videoDur > 0 ? videoDur : max(event.startTime + event.duration * 3, 60)

        let curStart = playlist.effectiveStartTime(for: event)
        let curDuration = playlist.effectiveDuration(for: event)
        let curEnd = curStart + curDuration

        var updated = session
        var seekTime: Double = 0

        switch resizeEdge {
        case .left:
            let newStart = curStart + deltaSec
            let clampedStart = max(0, min(newStart, curEnd - 1.0))
            guard abs(clampedStart - curStart) > 0.001 else { return }
            let newDuration = curEnd - clampedStart
            updated.playlistGroups[gi].playlists[pi].eventStartOverrides[event.hiddenKey] = clampedStart
            updated.playlistGroups[gi].playlists[pi].eventDurationOverrides[event.hiddenKey] = newDuration
            seekTime = clampedStart
        case .right:
            let newEnd = curEnd + deltaSec
            let clampedEnd = max(curStart + 1.0, min(newEnd, maxVideoDur))
            guard abs(clampedEnd - curEnd) > 0.001 else { return }
            let newDuration = clampedEnd - curStart
            updated.playlistGroups[gi].playlists[pi].eventDurationOverrides[event.hiddenKey] = newDuration
            seekTime = clampedEnd
        }

        sessionManager.updateSession(updated)
        playerManager.seekPreviewForPlaylistResize(absoluteVideoTime: seekTime, sourceID: event.sourceID)
    }

    private func resetEventOverrides(playlistID: UUID, event: SportCutEvent) {
        guard var session = session else { return }
        guard let gi = session.playlistGroups.firstIndex(where: { $0.playlists.contains(where: { $0.id == playlistID }) }),
              let pi = session.playlistGroups[gi].playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        session.playlistGroups[gi].playlists[pi].eventStartOverrides.removeValue(forKey: event.hiddenKey)
        session.playlistGroups[gi].playlists[pi].eventDurationOverrides.removeValue(forKey: event.hiddenKey)
        sessionManager.updateSession(session)
    }

    private func setupEventMonitor() {
        eventMonitor.onEsc = {
            DispatchQueue.main.async {
                self.clearSelection()
            }
        }
    }

    @ViewBuilder
    private func playlistsTimelinesBody(session: SportCutSession) -> some View {
        let playlists = allPlaylists.filter { !visibleEvents(in: $0).isEmpty }
        if playlists.isEmpty {
            Text(^String.Titles.sportCutNoEvents)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.1))
        } else {
            GeometryReader { outerGeo in
                let timelineWidth = max(outerGeo.size.width - 180, 100)

                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 16)
                        ForEach(playlists) { playlist in
                            HStack(spacing: 0) {
                                HStack {
                                    Text(playlist.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(2)
                                        .padding(.horizontal, 6)
                                    Spacer()
                                }
                                .frame(width: 180)

                                SportCutPlaylistSequentialRowView(
                                    playlist: playlist,
                                    events: visibleEvents(in: playlist),
                                    gridWidth: timelineWidth,
                                    sessionID: sessionID,
                                    playerManager: playerManager,
                                    selection: $selection,
                                    resizeEdge: $resizeEdge,
                                    onCommitResize: { edge, deltaSec in
                                        applyEdgeDelta(deltaSec)
                                    },
                                    onReset: { event in
                                        resetEventOverrides(playlistID: playlist.id, event: event)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .onChange(of: selection) { newSel in
                eventMonitor.lastSelection = newSel
            }
        }
    }
}

/// Одна строка — один плейлист. Теги последовательно, пропорционально длительности, во всю ширину.
private struct SportCutPlaylistSequentialRowView: View {
    let playlist: SportCutPlaylist
    let events: [SportCutEvent]
    let gridWidth: CGFloat
    let sessionID: UUID
    @ObservedObject var playerManager: SportCutPlayerManager
    @Binding var selection: PlaylistEventSelectionKey?
    @Binding var resizeEdge: PlaylistResizeEdge
    var onCommitResize: (_ edge: PlaylistResizeEdge, _ deltaSec: Double) -> Void = { _, _ in }
    var onReset: (SportCutEvent) -> Void = { _ in }

    private let gapPx: CGFloat = 3
    private let minStripW: CGFloat = 24

    /// Пиксельная дельта drag'а (raw translation.width). Положительная = вправо.
    @State private var dragTranslation: CGFloat = 0
    /// Край, который сейчас тянут.
    @State private var draggingEdge: PlaylistResizeEdge?
    /// Throttle: время последнего seek preview.
    @State private var lastSeekDate: Date = .distantPast

    private var hasSelectionInRow: Bool {
        guard let sel = selection else { return false }
        return sel.playlistID == playlist.id
    }

    private var rowHeight: CGFloat {
        hasSelectionInRow ? 46 : 30
    }

    /// sec/px для пересчёта пиксельной дельты в секунды.
    private var secPerPixel: Double {
        let total = events.map { playlist.effectiveDuration(for: $0) }.reduce(0, +)
        guard gridWidth > 0, total > 0 else { return 1 }
        return total / Double(gridWidth)
    }

    /// Clamp drag так, чтобы не уйти за 0, за видео, за другой край (min 1 сек).
    private func clampedDragPx(edge: PlaylistResizeEdge, event: SportCutEvent, rawPx: CGFloat) -> CGFloat {
        let effStart = playlist.effectiveStartTime(for: event)
        let effDur = playlist.effectiveDuration(for: event)
        let effEnd = effStart + effDur
        let spp = secPerPixel

        let session = SportCutSessionManager.shared.sessions.first { $0.id == sessionID }
        let source = session?.sources.first { $0.id == event.sourceID }
        let videoDur = source?.videoDuration() ?? 0
        let maxTime = videoDur > 0 ? videoDur : max(effEnd * 3, 60)

        switch edge {
        case .left:
            // Тянем left handle: translation > 0 = вправо = start увеличивается = ширина уменьшается
            let deltaSec = Double(rawPx) * spp
            let newStart = effStart + deltaSec
            let clamped = max(0, min(newStart, effEnd - 1.0))
            return CGFloat((clamped - effStart) / spp)
        case .right:
            // Тянем right handle: translation > 0 = вправо = end увеличивается = ширина увеличивается
            let deltaSec = Double(rawPx) * spp
            let newEnd = effEnd + deltaSec
            let clamped = max(effStart + 1.0, min(newEnd, maxTime))
            return CGFloat((clamped - effEnd) / spp)
        }
    }

    @ViewBuilder
    private func stripForEvent(at index: Int, widths: [CGFloat]) -> some View {
        let event = events[index]
        let stripW = index < widths.count ? widths[index] : minStripW
        let selKey = PlaylistEventSelectionKey(playlistID: playlist.id, eventIndex: index)
        let isSelected = selection == selKey
        let effStart = playlist.effectiveStartTime(for: event)
        let effDur = playlist.effectiveDuration(for: event)
        let spp = secPerPixel

        let times = visualTimes(effStart: effStart, effDur: effDur, isSelected: isSelected, event: event)

        SportCutPlaylistStripView(
            event: event,
            effectiveStart: times.start,
            effectiveEnd: times.end,
            stripWidth: stripW,
            isSelected: isSelected,
            isDragging: isSelected && draggingEdge != nil,
            onTap: {
                selection = selKey
                playerManager.sessionID = sessionID
                playerManager.playPlaylist(events, startIndex: index, playlistID: playlist.id)
            },
            onEdgeDragChanged: { edge, translationX in
                if draggingEdge == nil { draggingEdge = edge; resizeEdge = edge }
                let clampedPx = clampedDragPx(edge: edge, event: event, rawPx: translationX)
                withAnimation(.linear(duration: 0.06)) {
                    dragTranslation = clampedPx
                }
                // Throttle seek preview — не чаще 12 fps, чтобы не нагружать AVPlayer
                let now = Date()
                if now.timeIntervalSince(lastSeekDate) >= 0.08 {
                    lastSeekDate = now
                    let seekSec = edge == .left
                        ? effStart + Double(clampedPx) * spp
                        : effStart + effDur + Double(clampedPx) * spp
                    playerManager.seekPreviewForPlaylistResize(
                        absoluteVideoTime: max(0, seekSec),
                        sourceID: event.sourceID
                    )
                }
            },
            onEdgeDragEnded: { edge, translationX in
                let clampedPx = clampedDragPx(edge: edge, event: event, rawPx: translationX)
                let deltaSec = Double(clampedPx) * spp
                // Сначала сбрасываем drag state, потом commit — layout плавно перестроится по модели
                withAnimation(.easeOut(duration: 0.2)) {
                    dragTranslation = 0
                    draggingEdge = nil
                }
                onCommitResize(edge, deltaSec)
            },
            onDeselect: {
                selection = nil
                dragTranslation = 0
                draggingEdge = nil
            },
            onReset: {
                onReset(event)
            },
            hasOverrides: playlist.eventStartOverrides[event.hiddenKey] != nil || playlist.eventDurationOverrides[event.hiddenKey] != nil
        )
    }

    private func visualTimes(effStart: Double, effDur: Double, isSelected: Bool, event: SportCutEvent) -> (start: Double, end: Double) {
        guard isSelected, let edge = draggingEdge else {
            return (effStart, effStart + effDur)
        }
        let clampedPx = clampedDragPx(edge: edge, event: event, rawPx: dragTranslation)
        let spp = secPerPixel
        if edge == .left {
            return (effStart + Double(clampedPx) * spp, effStart + effDur)
        } else {
            return (effStart, effStart + effDur + Double(clampedPx) * spp)
        }
    }

    /// Текущие ширины с учётом drag.
    private func currentWidths(usableWidth: CGFloat) -> [CGFloat] {
        let base = computeStripWidths(usableWidth: usableWidth)
        guard let sel = selection, sel.playlistID == playlist.id,
              let edge = draggingEdge, sel.eventIndex < base.count else {
            return base
        }
        return computeDragWidths(baseWidths: base, usableWidth: usableWidth, selIdx: sel.eventIndex, edge: edge, deltaPx: dragTranslation)
    }

    /// Пропорциональные ширины по effective длительностям. Сумма == usableWidth.
    private func computeStripWidths(usableWidth: CGFloat) -> [CGFloat] {
        let count = events.count
        guard count > 0 else { return [] }
        let durations = events.map { playlist.effectiveDuration(for: $0) }
        let total = durations.reduce(0, +)
        guard total > 0 else {
            return Array(repeating: max(usableWidth / CGFloat(count), minStripW), count: count)
        }
        var widths = durations.map { max(usableWidth * CGFloat($0 / total), minStripW) }
        // Нормализация
        let sum = widths.reduce(CGFloat(0), +)
        if abs(sum - usableWidth) > 0.5 && sum > 0 {
            let scale = usableWidth / sum
            for i in 0..<count { widths[i] *= scale }
        }
        return widths
    }

    /// Ширины с учётом drag'а: selected тег +/- delta, affected теги поглощают остаток.
    /// Сумма ширин всегда == usableWidth.
    private func computeDragWidths(baseWidths: [CGFloat], usableWidth: CGFloat, selIdx: Int, edge: PlaylistResizeEdge, deltaPx: CGFloat) -> [CGFloat] {
        var widths = baseWidths
        let count = widths.count
        guard count > 1 else { return widths }

        // Affected теги — со стороны resize edge
        let affectedIndices: [Int] = edge == .left
            ? Array(0..<selIdx)
            : Array((selIdx + 1)..<count)
        // Unaffected — с другой стороны (не меняются)
        let unaffectedIndices: [Int] = edge == .left
            ? Array((selIdx + 1)..<count)
            : Array(0..<selIdx)

        // Считаем, сколько пикселей занимают unaffected (они зафиксированы)
        let unaffectedTotal = unaffectedIndices.reduce(CGFloat(0)) { $0 + widths[$1] }

        // Новая ширина selected
        let selDelta: CGFloat = edge == .left ? -deltaPx : deltaPx
        let maxSelW = usableWidth - unaffectedTotal - CGFloat(affectedIndices.count) * minStripW
        let newSelW = max(min(widths[selIdx] + selDelta, maxSelW), minStripW)
        widths[selIdx] = newSelW

        // Affected забирают остаток
        let affectedAvailable = usableWidth - unaffectedTotal - newSelW
        let affectedOldTotal = affectedIndices.reduce(CGFloat(0)) { $0 + widths[$1] }

        if affectedOldTotal > 0 && !affectedIndices.isEmpty {
            for i in affectedIndices {
                widths[i] = max(widths[i] / affectedOldTotal * affectedAvailable, minStripW)
            }
        } else if !affectedIndices.isEmpty {
            let each = max(affectedAvailable / CGFloat(affectedIndices.count), minStripW)
            for i in affectedIndices { widths[i] = each }
        }

        // Нормализация: гарантируем что сумма == usableWidth
        let currentTotal = widths.reduce(CGFloat(0), +)
        if abs(currentTotal - usableWidth) > 0.5 && currentTotal > 0 {
            let scale = usableWidth / currentTotal
            for i in 0..<count { widths[i] *= scale }
        }

        return widths
    }

    private let rightPadding: CGFloat = 8

    var body: some View {
        let totalGap = gapPx * CGFloat(max(events.count - 1, 0))
        let usableWidth = max(gridWidth - totalGap - rightPadding, CGFloat(events.count) * minStripW)
        let widths = currentWidths(usableWidth: usableWidth)

        HStack(spacing: gapPx) {
            ForEach(Array(events.indices), id: \.self) { index in
                stripForEvent(at: index, widths: widths)
            }
            Spacer(minLength: rightPadding)
        }
        .frame(height: rowHeight)
        .animation(.easeInOut(duration: 0.15), value: hasSelectionInRow)
        .animation(.linear(duration: 0.06), value: dragTranslation)
    }
}

/// Визуальный элемент тега на таймлайне плейлиста.
/// Ресайз — через drag handles на краях (как EdgeResizeHandle в TimelineLineView).
/// Во время drag обновляется только визуальная ширина (@State в row), модель — при отпускании.
private struct SportCutPlaylistStripView: View {
    let event: SportCutEvent
    let effectiveStart: Double
    let effectiveEnd: Double
    let stripWidth: CGFloat
    let isSelected: Bool
    let isDragging: Bool
    let onTap: () -> Void
    let onEdgeDragChanged: (_ edge: PlaylistResizeEdge, _ translationX: CGFloat) -> Void
    let onEdgeDragEnded: (_ edge: PlaylistResizeEdge, _ translationX: CGFloat) -> Void
    let onDeselect: () -> Void
    let onReset: () -> Void
    let hasOverrides: Bool

    private let handleW: CGFloat = 8
    private let handleH: CGFloat = 20

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1.0)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: event.color).opacity(isSelected ? 0.95 : 0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.white : Color(hex: event.color).opacity(0.3), lineWidth: isSelected ? 2.5 : 1)
                )
            Text(event.tagName)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 1)
                .lineLimit(1)
                .padding(.horizontal, 12)

            if isSelected {
                HStack(spacing: 0) {
                    // Left edge handle
                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .overlay(Rectangle().stroke(Color.orange, lineWidth: 1.5))
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .frame(width: handleW, height: handleH)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    onEdgeDragChanged(.left, value.translation.width)
                                }
                                .onEnded { value in
                                    onEdgeDragEnded(.left, value.translation.width)
                                }
                        )

                    Spacer()

                    // Right edge handle
                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .overlay(Rectangle().stroke(Color.blue, lineWidth: 1.5))
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .frame(width: handleW, height: handleH)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    onEdgeDragChanged(.right, value.translation.width)
                                }
                                .onEnded { value in
                                    onEdgeDragEnded(.right, value.translation.width)
                                }
                        )
                }
                .frame(width: stripWidth)
            }
        }
        .frame(width: stripWidth, height: 24)
        .contentShape(Rectangle())
        .help("\(event.tagName) — \(formatTime(effectiveStart))–\(formatTime(effectiveEnd))")
        .onTapGesture(perform: onTap)
        .overlay(alignment: .top) {
            if isSelected {
                HStack {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .onTapGesture { onDeselect() }

                        if hasOverrides {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.yellow)
                                .onTapGesture { onReset() }
                        }

                        Text(formatTime(effectiveStart))
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.7))
                            .cornerRadius(3)
                    }
                    .fixedSize()

                    Spacer()

                    Text(formatTime(effectiveEnd))
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.7))
                        .cornerRadius(3)
                        .fixedSize()
                }
                .offset(y: -16)
            }
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
