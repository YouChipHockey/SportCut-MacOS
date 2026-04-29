//
//  SportCutTimelineView.swift
//  Youchip-Stat
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import AppKit

/// Верхняя граница зума шкалы SportCut: иначе слишком много подписей/лейаута при ресайзе окна.
private let sportCutTimelineMaxScale: CGFloat = 40

/// Минимальная ширина штампа на шкале разметки (px); ширина по длительности, как в основном таймлайне плеера.
private let sportCutMarkupMinStampWidthPx: CGFloat = 4

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

/// Состояние редактора комментария для тега в таймлайне плейлиста.
private struct TimelineCommentEditorState: Identifiable {
    let event: SportCutEvent
    let playlistID: UUID
    let comment: String
    var id: String { "\(playlistID.uuidString)_\(event.hiddenKey)" }
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

    /// Как `ViewerTimelineView.calculateTimeGridInterval` — шаг сетки совпадает с режимом разметки в плеере.
    private func sportCutMarkupTimeGridInterval(scale: CGFloat, totalDuration: Double) -> Double {
        let baseCount = 20 * max(scale, 1.0)
        let baseInterval = totalDuration / baseCount
        return max(0.5, baseInterval)
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
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.gray.opacity(0.05),
                            Color.gray.opacity(0.02)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 180, height: 30, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                    )
                    
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
                .padding(.trailing, 5)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                GeometryReader { geo in
                    let effectiveScale = timelineScale * magnifyScale
                    let stampMax = source.timelines.flatMap(\.stamps).map(\.timeFinishSeconds).max() ?? 1.0
                    let fullVideoDuration = sourceVideoDurations[source.id] ?? stampMax
                    let totalDuration = max(1.0, max(fullVideoDuration, stampMax))
                    let gridWidth = geo.size.width * max(effectiveScale, 1.0)
                    let gridInterval = sportCutMarkupTimeGridInterval(scale: effectiveScale, totalDuration: totalDuration)
                    let timeGridHeight = 30 * CGFloat(filteredLines.count + 1)
                    
                    ScrollView(.horizontal) {
                        ZStack(alignment: .topLeading) {
                            TimeGridView(
                                duration: totalDuration,
                                interval: gridInterval,
                                width: gridWidth,
                                height: timeGridHeight
                            )
                            
                            VStack(spacing: 0) {
                                TimelineTimestampsHeaderView(
                                    duration: totalDuration,
                                    interval: gridInterval,
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
                            .padding(.bottom, 15)

                            SportCutMarkupPlayheadView(
                                sourceID: source.id,
                                totalDuration: totalDuration,
                                gridWidth: gridWidth,
                                playheadHeight: timeGridHeight,
                                playerManager: playerManager
                            )
                        }
                        .coordinateSpace(name: "sportCutMarkupTimeline")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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

// MARK: - Markup playhead (как `TimelinePlayheadView` в плеере)

/// Белая линия + «головка», hit-area 16 pt, drag → seek по абсолютному времени на исходнике.
private struct SportCutMarkupPlayheadView: View {
    let sourceID: UUID
    let totalDuration: Double
    let gridWidth: CGFloat
    let playheadHeight: CGFloat
    @ObservedObject var playerManager: SportCutPlayerManager

    @State private var dragging = false
    @State private var scrubVisualX: CGFloat = 0
    @State private var wasPlayingBeforeScrub = false
    /// Пиксельные границы текущего клипа на шкале (фиксируются в начале drag).
    @State private var dragClipXPxMinMax: (lo: CGFloat, hi: CGFloat)?

    private let hitWidth: CGFloat = 16
    /// Hit-testing only on the ruler row so the stem does not steal clicks / context menus from stamps on lines below (same height as `TimelineTimestampsHeaderView`).
    private var playheadDragHitHeight: CGFloat { min(playheadHeight, 30) }

    private func xFromAbsoluteTime(_ abs: Double) -> CGFloat {
        guard totalDuration > 0, gridWidth > 0 else { return 0 }
        let p = CGFloat(abs / totalDuration) * gridWidth
        return max(0, min(p, gridWidth))
    }

    private func lockedPlaybackX() -> CGFloat? {
        guard let abs = playerManager.absoluteVideoTimelineTime(forSourceID: sourceID) else { return nil }
        return xFromAbsoluteTime(abs)
    }

    private func displayX() -> CGFloat? {
        if dragging { return scrubVisualX }
        return lockedPlaybackX()
    }

    private func clampLocationX(_ x: CGFloat) -> CGFloat {
        max(0, min(x, gridWidth))
    }

    private func clipXPxBounds() -> (lo: CGFloat, hi: CGFloat)? {
        guard let b = playerManager.currentClipAbsoluteTimeBounds(forSourceID: sourceID) else { return nil }
        let x0 = xFromAbsoluteTime(b.start)
        let x1 = xFromAbsoluteTime(b.end)
        return (min(x0, x1), max(x0, x1))
    }

    private func clampDragXToCurrentClip(_ x: CGFloat) -> CGFloat {
        let full = clampLocationX(x)
        if let r = dragClipXPxMinMax ?? clipXPxBounds() {
            return max(r.lo, min(full, r.hi))
        }
        return full
    }

    var body: some View {
        let canInteract = lockedPlaybackX() != nil || dragging
        let pauseDriver = !dragging && !playerManager.isPlaying && lockedPlaybackX() == nil
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: pauseDriver)) { _ in
            if let px = displayX() {
                ZStack(alignment: .top) {
                    PlayheadStemWithGrabHead(stemWidth: 2, headBaseWidth: 12, compact: false)
                        .frame(width: hitWidth, height: playheadHeight)
                        .allowsHitTesting(false)

                    Color.clear
                        .frame(width: hitWidth, height: playheadDragHitHeight)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            NSCursor.setHiddenUntilMouseMoves(false)
                            if hovering {
                                NSCursor.openHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("sportCutMarkupTimeline"))
                                .onChanged { value in
                                    if !dragging {
                                        dragging = true
                                        wasPlayingBeforeScrub = playerManager.isPlaying
                                        if wasPlayingBeforeScrub { playerManager.pause() }
                                        dragClipXPxMinMax = clipXPxBounds()
                                        scrubVisualX = lockedPlaybackX() ?? clampDragXToCurrentClip(value.startLocation.x)
                                    }
                                    scrubVisualX = clampDragXToCurrentClip(value.location.x)
                                }
                                .onEnded { _ in
                                    let x = scrubVisualX
                                    dragging = false
                                    dragClipXPxMinMax = nil
                                    var absT = Double(x / max(gridWidth, 1)) * totalDuration
                                    if let b = playerManager.currentClipAbsoluteTimeBounds(forSourceID: sourceID) {
                                        absT = min(max(absT, b.start), b.end)
                                    }
                                    playerManager.seekToAbsoluteTimeOnSourceTimeline(absT, sourceID: sourceID)
                                    if wasPlayingBeforeScrub { playerManager.play() }
                                }
                        )
                }
                .frame(width: hitWidth, height: playheadHeight, alignment: .top)
                .offset(x: px - (hitWidth / 2 - 1))
                .transaction { $0.animation = nil }
            }
        }
        .allowsHitTesting(canInteract)
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
                let stampWidth = max(durationRatio * gridWidth, sportCutMarkupMinStampWidthPx)
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

    private let stampHeight: CGFloat = 25
    private let seekThrottle: TimeInterval = 0.033

    private var leftX: CGFloat {
        visualOffsetX ?? stampX
    }

    private var displayWidth: CGFloat {
        max(visualWidth ?? stampWidth, sportCutMarkupMinStampWidthPx)
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
                    dragInitialWidth = max(CGFloat(baseDur / max(totalDuration, 0.001)) * gridWidth, sportCutMarkupMinStampWidthPx)
                    dragInitialOffsetX = CGFloat(originalStartTime / max(totalDuration, 0.001)) * gridWidth
                    maxVisualOffsetX = dragInitialOffsetX + dragInitialWidth - sportCutMarkupMinStampWidthPx
                    visualOffsetX = dragInitialOffsetX
                    visualWidth = dragInitialWidth
                }
                let newOffsetX = dragInitialOffsetX + value.translation.width
                let newWidth = max(dragInitialWidth - value.translation.width, sportCutMarkupMinStampWidthPx)
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
                    dragInitialWidth = max(CGFloat(baseDur / max(totalDuration, 0.001)) * gridWidth, sportCutMarkupMinStampWidthPx)
                    dragInitialOffsetX = CGFloat(originalStartTime / max(totalDuration, 0.001)) * gridWidth
                    visualOffsetX = dragInitialOffsetX
                    visualWidth = dragInitialWidth
                }
                let newWidth = max(dragInitialWidth + value.translation.width, sportCutMarkupMinStampWidthPx)
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
        .contextMenu {
            Button(^String.Titles.sportCutPlayAction) {
                playerManager.playEvent(createEvent())
            }
            Button(^String.Titles.sportCutAddToPlaylist) {
                addToCurrentPlaylist()
            }
        }
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
    @State private var commentEditorState: TimelineCommentEditorState?

    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }

    private var allPlaylists: [SportCutPlaylist] {
        session?.playlistGroups.flatMap(\.playlists) ?? []
    }

    /// Returns all events for the timeline — hidden events are shown dimmed, not excluded.
    private func visibleEvents(in playlist: SportCutPlaylist) -> [SportCutEvent] {
        var events = playlist.events
        if let source = sourceFilter {
            events = events.filter { $0.sourceID == source.id }
        }
        return events
    }

    private func clearSelection() {
        selection = nil
        eventMonitor.lastSelection = nil
    }

    // MARK: - Timeline event actions

    private func findGroupPlaylist(playlistID: UUID) -> (gi: Int, pi: Int)? {
        guard let session = session else { return nil }
        for (gi, group) in session.playlistGroups.enumerated() {
            if let pi = group.playlists.firstIndex(where: { $0.id == playlistID }) {
                return (gi, pi)
            }
        }
        return nil
    }

    private func toggleEventHidden(playlistID: UUID, event: SportCutEvent) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
              let (gi, pi) = findGroupPlaylist(playlistID: playlistID) else { return }
        let key = event.hiddenKey
        if session.playlistGroups[gi].playlists[pi].hiddenEventKeys.contains(key) {
            session.playlistGroups[gi].playlists[pi].hiddenEventKeys.remove(key)
        } else {
            session.playlistGroups[gi].playlists[pi].hiddenEventKeys.insert(key)
        }
        SportCutSessionManager.shared.updateSession(session)
        playerManager.handleEventVisibilityChange(session: session, playlistID: playlistID, changedEvent: event)
    }

    private func openCommentEditor(playlistID: UUID, event: SportCutEvent) {
        guard let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
              let (gi, pi) = findGroupPlaylist(playlistID: playlistID) else { return }
        let comment = session.playlistGroups[gi].playlists[pi].eventComments[event.hiddenKey] ?? ""
        commentEditorState = TimelineCommentEditorState(event: event, playlistID: playlistID, comment: comment)
    }

    private func saveEventComment(event: SportCutEvent, playlistID: UUID, comment: String) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
              let (gi, pi) = findGroupPlaylist(playlistID: playlistID) else { return }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            session.playlistGroups[gi].playlists[pi].eventComments.removeValue(forKey: event.hiddenKey)
        } else {
            session.playlistGroups[gi].playlists[pi].eventComments[event.hiddenKey] = trimmed
        }
        SportCutSessionManager.shared.updateSession(session)
        commentEditorState = nil
    }

    private func deleteEvent(playlistID: UUID, event: SportCutEvent) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
              let (gi, pi) = findGroupPlaylist(playlistID: playlistID) else { return }
        guard let idx = session.playlistGroups[gi].playlists[pi].events.firstIndex(of: event) else { return }
        session.playlistGroups[gi].playlists[pi].events.remove(at: idx)
        session.playlistGroups[gi].playlists[pi].hiddenEventKeys.remove(event.hiddenKey)
        session.playlistGroups[gi].playlists[pi].eventComments.removeValue(forKey: event.hiddenKey)
        SportCutSessionManager.shared.updateSession(session)
    }

    private func moveEventInPlaylist(playlistID: UUID, event: SportCutEvent, direction: Int) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
              let (gi, pi) = findGroupPlaylist(playlistID: playlistID) else { return }
        var events = session.playlistGroups[gi].playlists[pi].events
        guard let idx = events.firstIndex(of: event) else { return }
        let newIdx = idx + direction
        guard newIdx >= 0, newIdx < events.count else { return }
        let item = events.remove(at: idx)
        events.insert(item, at: newIdx)
        session.playlistGroups[gi].playlists[pi].events = events
        SportCutSessionManager.shared.updateSession(session)
    }

    private func handleTimelineDrop(dragData: PlaylistEventDragData, toPlaylistID: UUID, toIndex: Int) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        let hk = dragData.event.hiddenKey
        var carriedComment: String?
        var carriedDrawings: [SportCutEventDrawing]?
        // Remove from source playlist
        for gi in session.playlistGroups.indices {
            if let pi = session.playlistGroups[gi].playlists.firstIndex(where: { $0.id == dragData.sourcePlaylistID }) {
                carriedComment = session.playlistGroups[gi].playlists[pi].eventComments[hk]
                carriedDrawings = session.playlistGroups[gi].playlists[pi].eventDrawings[hk]
                session.playlistGroups[gi].playlists[pi].events.removeAll { $0 == dragData.event }
                session.playlistGroups[gi].playlists[pi].eventComments.removeValue(forKey: hk)
                break
            }
        }
        // Insert into target playlist
        for gi in session.playlistGroups.indices {
            if let pi = session.playlistGroups[gi].playlists.firstIndex(where: { $0.id == toPlaylistID }) {
                let clamped = min(toIndex, session.playlistGroups[gi].playlists[pi].events.count)
                session.playlistGroups[gi].playlists[pi].events.insert(dragData.event, at: clamped)
                if let c = carriedComment { session.playlistGroups[gi].playlists[pi].eventComments[hk] = c }
                if let d = carriedDrawings { session.playlistGroups[gi].playlists[pi].eventDrawings[hk] = d }
                break
            }
        }
        SportCutSessionManager.shared.updateSession(session)
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
        .sheet(item: $commentEditorState) { state in
            SportCutEventCommentSheet(
                title: state.event.tagName,
                initialComment: state.comment,
                onSave: { text in saveEventComment(event: state.event, playlistID: state.playlistID, comment: text) },
                onCancel: { commentEditorState = nil }
            )
        }
    }

    /// Применяет дельту (сек) к текущему выделенному тегу по текущему краю.
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
        switch resizeEdge {
        case .left:
            let newStart = curStart + deltaSec
            let clampedStart = max(0, min(newStart, curEnd - 1.0))
            guard abs(clampedStart - curStart) > 0.001 else { return }
            let newDuration = curEnd - clampedStart
            updated.playlistGroups[gi].playlists[pi].eventStartOverrides[event.hiddenKey] = clampedStart
            updated.playlistGroups[gi].playlists[pi].eventDurationOverrides[event.hiddenKey] = newDuration
        case .right:
            let newEnd = curEnd + deltaSec
            let clampedEnd = max(curStart + 1.0, min(newEnd, maxVideoDur))
            guard abs(clampedEnd - curEnd) > 0.001 else { return }
            let newDuration = clampedEnd - curStart
            updated.playlistGroups[gi].playlists[pi].eventDurationOverrides[event.hiddenKey] = newDuration
        }

        sessionManager.updateSession(updated)
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
                                    },
                                    onToggleHidden: { event in
                                        toggleEventHidden(playlistID: playlist.id, event: event)
                                    },
                                    onComment: { event in
                                        openCommentEditor(playlistID: playlist.id, event: event)
                                    },
                                    onDelete: { event in
                                        deleteEvent(playlistID: playlist.id, event: event)
                                    },
                                    onMoveEvent: { event, direction in
                                        moveEventInPlaylist(playlistID: playlist.id, event: event, direction: direction)
                                    },
                                    onDrop: { dragData, toIndex in
                                        handleTimelineDrop(dragData: dragData, toPlaylistID: playlist.id, toIndex: toIndex)
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

// MARK: - Row Layout Types

private struct PlaylistRowLayout: Identifiable {
    let id: Int
    let eventIndices: [Int]
    let xOffsets: [CGFloat]
}

private struct PlayheadRowPosition: Equatable {
    let rowIndex: Int
    let x: CGFloat
}

/// Один плейлист. Теги фиксированной ширины (5px/сек), переносятся на следующие строки.
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
    var onToggleHidden: (SportCutEvent) -> Void = { _ in }
    var onComment: (SportCutEvent) -> Void = { _ in }
    var onDelete: (SportCutEvent) -> Void = { _ in }
    var onMoveEvent: (_ event: SportCutEvent, _ direction: Int) -> Void = { _, _ in }
    var onDrop: (_ dragData: PlaylistEventDragData, _ toIndex: Int) -> Void = { _, _ in }

    private let gapPx: CGFloat = 3
    private let minStripW: CGFloat = 24
    private let pixelsPerSecond: CGFloat = 5.0
    private let stripHeight: CGFloat = 24
    private let rowPitch: CGFloat = 30

    /// Пиксельная дельта drag'а (raw translation.width). Положительная = вправо.
    @State private var dragTranslation: CGFloat = 0
    /// Край, который сейчас тянут.
    @State private var draggingEdge: PlaylistResizeEdge?
    /// Throttle: время последнего seek preview.
    @State private var lastSeekDate: Date = .distantPast
    /// Immediate visual override: set to the target position before a seek starts, cleared in the
    /// seek completion handler. Prevents the "flash-back" caused by player.currentTime()
    /// returning the old value while an async seek is still in flight.
    @State private var seekLockPos: PlayheadRowPosition? = nil
    /// Absolute source timeline time captured at resize start; restored after commit.
    @State private var resizeRestoreAbsoluteTime: Double? = nil
    @State private var resizeRestoreSourceID: UUID? = nil

    private var hasSelectionInRow: Bool {
        guard let sel = selection else { return false }
        return sel.playlistID == playlist.id
    }

    /// Фиксированный масштаб: 1 секунда = pixelsPerSecond пикселей.
    private var secPerPixel: Double { 1.0 / Double(pixelsPerSecond) }

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

    /// Slightly smooth right-edge translation to reduce micro-jitter while handle itself moves.
    private func smoothedDragPx(edge: PlaylistResizeEdge, targetPx: CGFloat, isDragStart: Bool) -> CGFloat {
        guard edge == .right, !isDragStart else { return targetPx }
        let smoothingFactor: CGFloat = 0.6
        return dragTranslation + (targetPx - dragTranslation) * smoothingFactor
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
        let drawings = playlist.eventDrawings[event.hiddenKey] ?? []
        let isHidden = playlist.hiddenEventKeys.contains(event.hiddenKey)
        let hasComment = !(playlist.eventComments[event.hiddenKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let times = visualTimes(effStart: effStart, effDur: effDur, isSelected: isSelected, event: event)

        SportCutPlaylistStripView(
            event: event,
            effectiveStart: times.start,
            effectiveEnd: times.end,
            stripWidth: stripW,
            isSelected: isSelected,
            isDragging: isSelected && draggingEdge != nil,
            isHidden: isHidden,
            hasComment: hasComment,
            canMoveLeft: index > 0,
            canMoveRight: index < events.count - 1,
            drawings: drawings,
            sourcePlaylistID: playlist.id,
            eventIndex: index,
            onTap: { fraction in
                selection = selKey
                let localTime = Double(fraction) * effDur
                // Compute playhead row-position and lock it there immediately so there's
                // no flash-back while the async seek settles.
                let baseW = baseTagWidths()
                let availW = gridWidth - rightPadding
                let rows = computeRows(widths: baseW, availableWidth: availW)
                seekLockPos = eventRowPosition(eventIndex: index, fraction: CGFloat(fraction), widths: baseW, rows: rows)
                performSeek(to: event, localTime: localTime) {
                    seekLockPos = nil  // release when player has settled
                }
            },
            onEdgeDragChanged: { edge, translationX in
                let isDragStart = draggingEdge == nil
                if isDragStart {
                    draggingEdge = edge
                    resizeEdge = edge
                    resizeRestoreSourceID = event.sourceID
                    resizeRestoreAbsoluteTime = playerManager.absoluteVideoTimelineTime(forSourceID: event.sourceID)
                }
                let clampedPx = clampedDragPx(edge: edge, event: event, rawPx: translationX)
                // Keep left edge fully synchronous, but lightly smooth right edge updates.
                dragTranslation = smoothedDragPx(edge: edge, targetPx: clampedPx, isDragStart: isDragStart)
                // Throttle seek preview — не чаще 12 fps, чтобы не нагружать AVPlayer
                let now = Date()
                if now.timeIntervalSince(lastSeekDate) >= 0.08 {
                    lastSeekDate = now
                    let previewPx = dragTranslation
                    let seekSec = edge == .left
                        ? effStart + Double(previewPx) * spp
                        : effStart + effDur + Double(previewPx) * spp
                    playerManager.seekPreviewForPlaylistResize(
                        absoluteVideoTime: max(0, seekSec),
                        sourceID: event.sourceID
                    )
                }
            },
            onEdgeDragEnded: { edge, translationX in
                let clampedPx = clampedDragPx(edge: edge, event: event, rawPx: translationX)
                let deltaSec = Double(clampedPx) * spp
                // Reset drag state immediately to avoid animated "rubber-band" artifacts.
                dragTranslation = 0
                draggingEdge = nil
                onCommitResize(edge, deltaSec)
                if let restoreAbs = resizeRestoreAbsoluteTime, let restoreSourceID = resizeRestoreSourceID {
                    playerManager.seekToAbsoluteTimeOnSourceTimeline(restoreAbs, sourceID: restoreSourceID)
                }
                resizeRestoreAbsoluteTime = nil
                resizeRestoreSourceID = nil
            },
            onDeselect: {
                selection = nil
                dragTranslation = 0
                draggingEdge = nil
                resizeRestoreAbsoluteTime = nil
                resizeRestoreSourceID = nil
            },
            onReset: {
                onReset(event)
            },
            hasOverrides: playlist.eventStartOverrides[event.hiddenKey] != nil || playlist.eventDurationOverrides[event.hiddenKey] != nil,
            onToggleHidden: { onToggleHidden(event) },
            onComment: { onComment(event) },
            onDelete: { onDelete(event) },
            onMoveLeft: { onMoveEvent(event, -1) },
            onMoveRight: { onMoveEvent(event, 1) },
            onDropEvent: { dragData in onDrop(dragData, index) }
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

    // MARK: - Fixed-scale width computation

    /// Базовые ширины тегов: duration * pixelsPerSecond.
    private func baseTagWidths() -> [CGFloat] {
        events.map { max(CGFloat(playlist.effectiveDuration(for: $0)) * pixelsPerSecond, minStripW) }
    }

    /// Ширины с учётом drag'а: только выбранный тег меняет ширину.
    private func currentTagWidths() -> [CGFloat] {
        var widths = baseTagWidths()
        guard let sel = selection, sel.playlistID == playlist.id,
              let edge = draggingEdge, sel.eventIndex < widths.count else {
            return widths
        }
        let event = events[sel.eventIndex]
        let clampedPx = clampedDragPx(edge: edge, event: event, rawPx: dragTranslation)
        switch edge {
        case .left:
            widths[sel.eventIndex] = max(widths[sel.eventIndex] - clampedPx, minStripW)
        case .right:
            widths[sel.eventIndex] = max(widths[sel.eventIndex] + clampedPx, minStripW)
        }
        return widths
    }

    // MARK: - Row wrapping

    /// Раскладывает теги по строкам: если не помещается — переносится на следующую.
    private func computeRows(widths: [CGFloat], availableWidth: CGFloat) -> [PlaylistRowLayout] {
        var rows: [PlaylistRowLayout] = []
        var indices: [Int] = []
        var offsets: [CGFloat] = []
        var x: CGFloat = 0

        for (i, w) in widths.enumerated() {
            let needed = indices.isEmpty ? w : gapPx + w
            if x + needed > availableWidth && !indices.isEmpty {
                rows.append(PlaylistRowLayout(id: rows.count, eventIndices: indices, xOffsets: offsets))
                indices = [i]
                offsets = [0]
                x = w
            } else {
                if !indices.isEmpty { x += gapPx }
                offsets.append(x)
                indices.append(i)
                x += w
            }
        }
        if !indices.isEmpty {
            rows.append(PlaylistRowLayout(id: rows.count, eventIndices: indices, xOffsets: offsets))
        }
        return rows
    }

    /// Позиция события (row + x) по индексу и фракции внутри тега.
    private func eventRowPosition(eventIndex: Int, fraction: CGFloat, widths: [CGFloat], rows: [PlaylistRowLayout]) -> PlayheadRowPosition? {
        for row in rows {
            if let localIdx = row.eventIndices.firstIndex(of: eventIndex) {
                let x = row.xOffsets[localIdx] + fraction * widths[eventIndex]
                return PlayheadRowPosition(rowIndex: row.id, x: x)
            }
        }
        return nil
    }

    private let rightPadding: CGFloat = 8

    // MARK: - Seek helper (used by strip taps)

    /// Core seek: moves playback to `localTime` seconds within `targetEvent`.
    /// `onComplete` fires on the main queue when the underlying player seek has settled,
    /// so callers can release any visual lock they held during the async operation.
    private func performSeek(to targetEvent: SportCutEvent, localTime: Double, onComplete: (() -> Void)? = nil) {
        let isHidden = playlist.hiddenEventKeys.contains(targetEvent.hiddenKey)
        let playable: [SportCutEvent] = isHidden
            ? [targetEvent]
            : events.filter { !playlist.hiddenEventKeys.contains($0.hiddenKey) }
        guard !playable.isEmpty else { onComplete?(); return }

        let isPlaylistActive = playerManager.currentPlaylistID == playlist.id

        if isPlaylistActive && playerManager.playlistPlaybackKind == .singleFilm {
            var filmTime = 0.0
            for ve in events.filter({ !playlist.hiddenEventKeys.contains($0.hiddenKey) }) {
                if ve.hiddenKey == targetEvent.hiddenKey {
                    let cm = CMTime(seconds: filmTime + localTime, preferredTimescale: 600)
                    playerManager.player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        DispatchQueue.main.async { onComplete?() }
                    }
                    return
                }
                filmTime += playlist.effectiveDuration(for: ve)
            }
            onComplete?()
        } else if isPlaylistActive && playerManager.currentEvent?.hiddenKey == targetEvent.hiddenKey {
            let cm = CMTime(seconds: max(0, localTime), preferredTimescale: 600)
            playerManager.player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                DispatchQueue.main.async { onComplete?() }
            }
        } else {
            guard let idx = playable.firstIndex(where: { $0.hiddenKey == targetEvent.hiddenKey }) else { onComplete?(); return }
            let wasPlaying = playerManager.isPlaying
            let shouldPlay = wasPlaying || !isPlaylistActive
            playerManager.sessionID = sessionID
            playerManager.playPlaylist(playable, startIndex: idx, playlistID: playlist.id, autoPlayAfterLoad: false) {
                let cm = CMTime(seconds: max(0, localTime), preferredTimescale: 600)
                playerManager.player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    DispatchQueue.main.async {
                        if shouldPlay { playerManager.play() }
                        onComplete?()
                    }
                }
            }
        }
    }

    var body: some View {
        let availableWidth = gridWidth - rightPadding
        let widths = currentTagWidths()
        let baseWidths = baseTagWidths()
        let rows = computeRows(widths: widths, availableWidth: availableWidth)
        let baseRows = computeRows(widths: baseWidths, availableWidth: availableWidth)
        let totalH = max(CGFloat(rows.count), 1) * rowPitch

        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: rowPitch - stripHeight) {
                ForEach(rows) { row in
                    HStack(spacing: gapPx) {
                        ForEach(row.eventIndices, id: \.self) { eventIdx in
                            stripForEvent(at: eventIdx, widths: widths)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: stripHeight)
                }
            }

            // Smooth 60fps playhead — reads player.currentTime() directly via TimelineView
            WrappedPlayheadLineView(
                playlist: playlist,
                events: events,
                baseWidths: baseWidths,
                rows: baseRows,
                gapPx: gapPx,
                stripHeight: stripHeight,
                rowPitch: rowPitch,
                availableWidth: availableWidth,
                sessionID: sessionID,
                isEdgeDragging: draggingEdge != nil,
                selectedEventIndex: hasSelectionInRow ? selection?.eventIndex : nil,
                externalSeekLockPos: $seekLockPos,
                playerManager: playerManager,
                onSeek: { targetEvent, localTime, completion in
                    performSeek(to: targetEvent, localTime: localTime, onComplete: completion)
                }
            )
        }
        .frame(height: totalH)
        // Auto-select the currently playing strip as the playhead advances.
        .onChange(of: playerManager.currentEvent) { currentEvent in
            guard let currentEvent,
                  playerManager.currentPlaylistID == playlist.id,
                  let idx = events.firstIndex(where: { $0.hiddenKey == currentEvent.hiddenKey })
            else { return }
            let newKey = PlaylistEventSelectionKey(playlistID: playlist.id, eventIndex: idx)
            if selection != newKey { selection = newKey }
        }
    }
}

// MARK: - Smooth 60fps Wrapped Playhead

/// A self-contained playhead that reads `player.currentTime()` directly inside a `TimelineView`
/// firing at the display refresh rate (~60fps). Supports multi-row layout — the playhead
/// moves along rows and wraps to the next row at row boundaries.
///
/// **Seek-lock mechanism**: `externalSeekLockPos` is set by the parent immediately before any
/// async seek starts (tap on a strip). The playhead shows that position as-is until the
/// parent clears it in the seek completion handler, preventing the "flash-back" caused by
/// `player.currentTime()` returning the old value while the seek is still in flight.
private struct WrappedPlayheadLineView: View {
    let playlist: SportCutPlaylist
    let events: [SportCutEvent]
    let baseWidths: [CGFloat]
    let rows: [PlaylistRowLayout]
    let gapPx: CGFloat
    let stripHeight: CGFloat
    let rowPitch: CGFloat
    let availableWidth: CGFloat
    let sessionID: UUID
    let isEdgeDragging: Bool
    let selectedEventIndex: Int?
    @Binding var externalSeekLockPos: PlayheadRowPosition?
    @ObservedObject var playerManager: SportCutPlayerManager
    var onSeek: (_ event: SportCutEvent, _ localTime: Double, _ completion: (() -> Void)?) -> Void

    @State private var scrubbing: Bool = false
    @State private var scrubStartLinearX: CGFloat = 0
    @State private var scrubVisualPos: PlayheadRowPosition?
    @State private var wasPlayingBeforeScrub: Bool = false
    @State private var internalSeekLockPos: PlayheadRowPosition? = nil

    private var isActivePlaylist: Bool {
        playerManager.currentPlaylistID == playlist.id && playerManager.currentPlaylistIndex >= 0
    }

    private var resolvedLockPos: PlayheadRowPosition? {
        externalSeekLockPos ?? internalSeekLockPos
    }

    /// Resolved position to render on each TimelineView tick.
    private func displayPosition() -> PlayheadRowPosition? {
        if isEdgeDragging { return nil }
        if scrubbing { return scrubVisualPos }
        if let lock = resolvedLockPos { return lock }
        return computePlayheadPosition()
    }

    /// Prevent playhead from stealing mouse down when it crosses selected strip resize handles.
    private func playheadOverlapsSelectedHandles(_ pos: PlayheadRowPosition) -> Bool {
        guard let selectedEventIndex,
              selectedEventIndex >= 0,
              selectedEventIndex < baseWidths.count else { return false }
        for row in rows {
            guard row.id == pos.rowIndex else { continue }
            guard let localIdx = row.eventIndices.firstIndex(of: selectedEventIndex),
                  localIdx < row.xOffsets.count else { return false }
            let stripStartX = row.xOffsets[localIdx]
            let stripWidth = baseWidths[selectedEventIndex]
            let handleW: CGFloat = 8
            let playheadHalfHitW: CGFloat = 10 // matches 20pt gesture hit-width
            let overlapPadding: CGFloat = 2
            let leftHandleMin = stripStartX - playheadHalfHitW - overlapPadding
            let leftHandleMax = stripStartX + handleW + playheadHalfHitW + overlapPadding
            let rightEdgeX = stripStartX + stripWidth
            let rightHandleMin = rightEdgeX - handleW - playheadHalfHitW - overlapPadding
            let rightHandleMax = rightEdgeX + playheadHalfHitW + overlapPadding
            return (pos.x >= leftHandleMin && pos.x <= leftHandleMax)
                || (pos.x >= rightHandleMin && pos.x <= rightHandleMax)
        }
        return false
    }

    var body: some View {
        let hasLock = resolvedLockPos != nil
        let paused = isEdgeDragging
            || (!hasLock && !scrubbing && (!playerManager.isPlaying || !isActivePlaylist))
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { _ in
            if let pos = displayPosition() {
                let playheadShouldHitTest = isActivePlaylist && !playheadOverlapsSelectedHandles(pos)
                let yOffset = CGFloat(pos.rowIndex) * rowPitch
                ZStack {
                    PlayheadStemWithGrabHead(stemWidth: 2, headBaseWidth: 12, compact: false)
                        .frame(width: 20, height: stripHeight + 4)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 20, height: stripHeight + 4)
                        .contentShape(Rectangle())
                }
                .offset(x: pos.x - 10, y: yOffset - 2)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !scrubbing {
                                let startPos = computePlayheadPosition()
                                let startLinear = startPos.flatMap { posToLinearX($0) } ?? 0
                                scrubStartLinearX = startLinear
                                wasPlayingBeforeScrub = playerManager.isPlaying
                                if playerManager.isPlaying { playerManager.pause() }
                                scrubbing = true
                            }
                            let totalLinear = totalLinearWidth()
                            let newLinear = max(0, min(scrubStartLinearX + value.translation.width, totalLinear))
                            scrubVisualPos = linearXToPosition(newLinear)
                        }
                        .onEnded { value in
                            let totalLinear = totalLinearWidth()
                            let finalLinear = max(0, min(scrubStartLinearX + value.translation.width, totalLinear))
                            let finalPos = linearXToPosition(finalLinear)
                            internalSeekLockPos = finalPos
                            scrubbing = false
                            seekToLinearX(finalLinear)
                            if wasPlayingBeforeScrub { playerManager.play() }
                        }
                )
                .transaction { $0.animation = nil }
                .allowsHitTesting(playheadShouldHitTest)
            }
        }
        .allowsHitTesting(isActivePlaylist)
    }

    // MARK: - Linear ↔ Row position conversion

    /// Total linear width of all events + gaps (as if in single row).
    private func totalLinearWidth() -> CGFloat {
        guard !baseWidths.isEmpty else { return 0 }
        return baseWidths.reduce(0, +) + gapPx * CGFloat(max(baseWidths.count - 1, 0))
    }

    /// Convert a PlayheadRowPosition to a linearX (for scrub start).
    private func posToLinearX(_ pos: PlayheadRowPosition) -> CGFloat? {
        guard pos.rowIndex < rows.count else { return nil }
        let row = rows[pos.rowIndex]
        // Find which event in this row the X falls into
        for (localIdx, eventIdx) in row.eventIndices.enumerated() {
            guard eventIdx < baseWidths.count else { continue }
            let stripStart = row.xOffsets[localIdx]
            let stripEnd = stripStart + baseWidths[eventIdx]
            if pos.x >= stripStart && pos.x <= stripEnd {
                let fraction = (pos.x - stripStart) / max(baseWidths[eventIdx], 1)
                // Accumulate linear position
                var linear: CGFloat = 0
                for j in 0..<eventIdx {
                    linear += baseWidths[j] + gapPx
                }
                linear += fraction * baseWidths[eventIdx]
                return linear
            }
        }
        return nil
    }

    /// Convert a linearX to a row position for display.
    private func linearXToPosition(_ linearX: CGFloat) -> PlayheadRowPosition? {
        var accum: CGFloat = 0
        for (i, w) in baseWidths.enumerated() {
            if linearX <= accum + w {
                let fraction = max(0, min((linearX - accum) / max(w, 1), 1))
                return eventToRowPosition(eventIndex: i, fraction: fraction)
            }
            accum += w + gapPx
        }
        // Past the end — return end of last event
        if let last = baseWidths.indices.last {
            return eventToRowPosition(eventIndex: last, fraction: 1.0)
        }
        return nil
    }

    /// Find the (row, x) position for a given event index and fraction within it.
    private func eventToRowPosition(eventIndex: Int, fraction: CGFloat) -> PlayheadRowPosition? {
        for row in rows {
            if let localIdx = row.eventIndices.firstIndex(of: eventIndex) {
                let x = row.xOffsets[localIdx] + fraction * baseWidths[eventIndex]
                return PlayheadRowPosition(rowIndex: row.id, x: x)
            }
        }
        return nil
    }

    // MARK: - Position computation

    private func computePlayheadPosition() -> PlayheadRowPosition? {
        guard isActivePlaylist else { return nil }
        let t = playerManager.player.currentTime().seconds
        guard t.isFinite, t >= 0 else { return nil }
        return playerManager.playlistPlaybackKind == .singleFilm
            ? computeFilmPosition(globalTime: t)
            : computeSequentialPosition(localTime: t)
    }

    private func computeFilmPosition(globalTime: Double) -> PlayheadRowPosition? {
        var filmAccum = 0.0
        for event in events where !playlist.hiddenEventKeys.contains(event.hiddenKey) {
            let dur = playlist.effectiveDuration(for: event)
            if globalTime <= filmAccum + dur {
                guard let eventIdx = events.firstIndex(where: { $0.hiddenKey == event.hiddenKey }),
                      eventIdx < baseWidths.count else { return nil }
                let fraction = CGFloat(max(0, (globalTime - filmAccum) / max(dur, 0.001)))
                return eventToRowPosition(eventIndex: eventIdx, fraction: fraction)
            }
            filmAccum += dur
        }
        return nil
    }

    private func computeSequentialPosition(localTime: Double) -> PlayheadRowPosition? {
        guard let currentEvent = playerManager.currentEvent else { return nil }
        for (i, event) in events.enumerated() {
            guard i < baseWidths.count else { break }
            if event.hiddenKey == currentEvent.hiddenKey {
                let clipDur = playlist.effectiveDuration(for: event)
                let fraction = clipDur > 0 ? CGFloat(min(max(localTime / clipDur, 0), 1.0)) : 0
                return eventToRowPosition(eventIndex: i, fraction: fraction)
            }
        }
        return nil
    }

    // MARK: - Scrub seek

    private func seekToLinearX(_ linearX: CGFloat) {
        var accum: CGFloat = 0
        for (i, w) in baseWidths.enumerated() {
            guard i < events.count else { break }
            if linearX <= accum + w {
                let fraction = Double(max(0, min((linearX - accum) / max(w, 1), 1)))
                let event = events[i]
                onSeek(event, fraction * playlist.effectiveDuration(for: event)) {
                    DispatchQueue.main.async { self.internalSeekLockPos = nil }
                }
                return
            }
            accum += w + gapPx
        }
        internalSeekLockPos = nil
    }
}

/// Визуальный элемент тега на таймлайне плейлиста.
/// Ресайз — через drag handles на краях. Reorder — через system drag (center).
private struct SportCutPlaylistStripView: View {
    let event: SportCutEvent
    let effectiveStart: Double
    let effectiveEnd: Double
    let stripWidth: CGFloat
    let isSelected: Bool
    let isDragging: Bool
    let isHidden: Bool
    let hasComment: Bool
    let canMoveLeft: Bool
    let canMoveRight: Bool
    let drawings: [SportCutEventDrawing]
    let sourcePlaylistID: UUID
    let eventIndex: Int
    let onTap: (_ fraction: CGFloat) -> Void
    let onEdgeDragChanged: (_ edge: PlaylistResizeEdge, _ translationX: CGFloat) -> Void
    let onEdgeDragEnded: (_ edge: PlaylistResizeEdge, _ translationX: CGFloat) -> Void
    let onDeselect: () -> Void
    let onReset: () -> Void
    let hasOverrides: Bool
    let onToggleHidden: () -> Void
    let onComment: () -> Void
    let onDelete: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    let onDropEvent: (_ dragData: PlaylistEventDragData) -> Void

    @State private var isDropTarget: Bool = false

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
                .fill(Color(hex: event.color).opacity(isHidden ? 0.3 : (isSelected ? 0.95 : 0.7)))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isDropTarget ? Color.blue : (isSelected ? Color.white : Color(hex: event.color).opacity(0.3)),
                                lineWidth: isDropTarget ? 2 : (isSelected ? 2.5 : 1))
                )

            // Drawing markers — белые вертикальные линии внутри стрипа
            let duration = effectiveEnd - effectiveStart
            if duration > 0 {
                ForEach(drawings.indices, id: \.self) { i in
                    let drawing = drawings[i]
                    let absTime = event.startTime + drawing.videoTime
                    if absTime >= effectiveStart && absTime <= effectiveEnd {
                        let xRatio = CGFloat((absTime - effectiveStart) / duration)
                        Rectangle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 1.5, height: 24)
                            .offset(x: xRatio * stripWidth - stripWidth / 2)
                            .allowsHitTesting(false)
                    }
                }
            }

            // Comment indicator dot
            if hasComment {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, isSelected ? 10 : 3)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }

            Text(event.tagName)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(isHidden ? 0.5 : 1.0))
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
                                .onChanged { value in onEdgeDragChanged(.left, value.translation.width) }
                                .onEnded { value in onEdgeDragEnded(.left, value.translation.width) }
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
                                .onChanged { value in onEdgeDragChanged(.right, value.translation.width) }
                                .onEnded { value in onEdgeDragEnded(.right, value.translation.width) }
                        )
                }
                .frame(width: stripWidth)
            }
        }
        .frame(width: stripWidth, height: 24)
        .contentShape(Rectangle())
        .help("\(event.tagName) — \(formatTime(effectiveStart))–\(formatTime(effectiveEnd))")
        // Location-aware tap: passes the fractional position (0…1) within the strip to onTap.
        // Only fires on genuine taps (small movement) so reorder-drags are not mistaken for seeks.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    let movement = hypot(value.translation.width, value.translation.height)
                    guard movement < 8 else { return }
                    let fraction = max(0.0, min(Double(value.startLocation.x / max(stripWidth, 1)), 1.0))
                    onTap(fraction)
                }
        )
        .onDrag {
            let dragData = PlaylistEventDragData(event: event, sourcePlaylistID: sourcePlaylistID)
            let data = (try? JSONEncoder().encode(dragData)) ?? Data()
            return NSItemProvider(item: data as NSData, typeIdentifier: UTType.data.identifier)
        }
        .onDrop(of: [.data], isTargeted: $isDropTarget) { providers in
            for provider in providers {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
                    guard let data = data,
                          let dragData = try? JSONDecoder().decode(PlaylistEventDragData.self, from: data) else { return }
                    DispatchQueue.main.async { onDropEvent(dragData) }
                }
            }
            return true
        }
        .contextMenu {
            Button(hasComment ? ^String.Titles.sportCutEditComment : ^String.Titles.sportCutAddComment) { onComment() }
            Button(isHidden ? ^String.Titles.sportCutShowEvent : ^String.Titles.sportCutHideEvent) { onToggleHidden() }
            Divider()
            Button(^String.Titles.sportCutMoveLeft) { onMoveLeft() }
                .disabled(!canMoveLeft)
            Button(^String.Titles.sportCutMoveRight) { onMoveRight() }
                .disabled(!canMoveRight)
            Divider()
            Button(^String.Titles.sportCutDeleteFromPlaylist, role: .destructive) { onDelete() }
        }
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
