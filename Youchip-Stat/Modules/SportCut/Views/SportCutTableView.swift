//
//  SportCutTableView.swift
//  Youchip-Stat
//

import SwiftUI
import AppKit

struct SportCutTableView: View {
    let sessionID: UUID
    @ObservedObject var playerManager: SportCutPlayerManager
    @ObservedObject var filter: TimelineFilter
    let selectedSourceIndex: Int
    @Binding var bulkSelectedStampIDs: Set<UUID>

    @ObservedObject var sessionManager = SportCutSessionManager.shared
    @State private var sortMode: SportCutTableSortMode = .startTimeAsc
    /// Stamp IDs (across all project sources) that have a drawing attached in the original markup.
    @State private var stampsWithDrawings: Set<UUID> = []
    @State private var showCSVExport = false

    private enum SportCutTableSortMode: String, CaseIterable {
        case startTimeAsc
        case startTimeDesc
        case durationAsc
        case durationDesc
        case tagNameAsc
        case projectAsc

        var label: String {
            switch self {
            case .startTimeAsc: return ^String.Titles.sportCutSortTimeAsc
            case .startTimeDesc: return ^String.Titles.sportCutSortTimeDesc
            case .durationAsc: return ^String.Titles.sportCutSortDurationAsc
            case .durationDesc: return ^String.Titles.sportCutSortDurationDesc
            case .tagNameAsc: return ^String.Titles.sportCutSortTagNameAsc
            case .projectAsc: return ^String.Titles.sportCutSortProjectAsc
            }
        }
    }
    
    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }
    
    private var filteredStamps: [SportCutEventRow] {
        guard let session = session else { return [] }
        
        let sourcesToUse: [SportCutSource]
        if selectedSourceIndex < 0 {
            sourcesToUse = session.sources
        } else if selectedSourceIndex < session.sources.count {
            sourcesToUse = [session.sources[selectedSourceIndex]]
        } else {
            return []
        }
        
        let rows = sourcesToUse.flatMap { source in
            source.timelines.flatMap { line in
                line.stamps
                    .filter { filter.matches(stamp: $0) }
                    .map { stamp in
                        SportCutEventRow(
                            stamp: stamp,
                            line: line,
                            source: source
                        )
                    }
            }
        }
        return sortedRows(rows)
    }

    private func sortedRows(_ rows: [SportCutEventRow]) -> [SportCutEventRow] {
        switch sortMode {
        case .startTimeAsc:
            return rows.sorted { $0.stamp.timeStartSeconds < $1.stamp.timeStartSeconds }
        case .startTimeDesc:
            return rows.sorted { $0.stamp.timeStartSeconds > $1.stamp.timeStartSeconds }
        case .durationAsc:
            return rows.sorted { $0.stamp.duration < $1.stamp.duration }
        case .durationDesc:
            return rows.sorted { $0.stamp.duration > $1.stamp.duration }
        case .tagNameAsc:
            return rows.sorted { $0.stamp.label.localizedCaseInsensitiveCompare($1.stamp.label) == .orderedAscending }
        case .projectAsc:
            return rows.sorted { $0.source.name.localizedCaseInsensitiveCompare($1.source.name) == .orderedAscending }
        }
    }
    
    // MARK: - CSV export data

    /// Источники в текущей области видимости (все проекты или выбранный).
    private var csvSources: [SportCutSource] {
        guard let session = session else { return [] }
        if selectedSourceIndex < 0 { return session.sources }
        if selectedSourceIndex < session.sources.count { return [session.sources[selectedSourceIndex]] }
        return []
    }

    private var csvLines: [TimelineLine] {
        csvSources.flatMap { $0.timelines }
    }

    /// Резолвер имён для CSV — ищет теги/лейблы/группы/события по всем источникам в области.
    private var csvResolver: CSVNameResolver {
        let sources = csvSources
        return CSVNameResolver(
            tagName: { id in sources.compactMap { $0.findTag(byID: id) }.first?.name ?? id },
            labelName: { id in sources.compactMap { $0.findLabel(byID: id) }.first?.name ?? id },
            labelGroupName: { id in
                sources.compactMap { src in src.labelGroups.first { $0.lables.contains(id) } }.first?.name ?? "Лейблы"
            },
            eventName: { id in sources.compactMap { $0.timeEvents.first { $0.id == id } }.first?.name ?? id }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(^String.Titles.sportCutEventsTable)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()

                Menu {
                    ForEach(SportCutTableSortMode.allCases, id: \.self) { mode in
                        Button(mode.label) { sortMode = mode }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .font(.system(size: 11))
                        Text(sortMode.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)

                Button(action: { showCSVExport = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "tablecells").font(.system(size: 11))
                        Text(^String.Titles.csvExportButton).font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .help(^String.Titles.csvExportTitle)

                Text(String.Titles.sportCutEventsCount.format(filteredStamps.count))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .sheet(isPresented: $showCSVExport) {
                CSVExportSheet(
                    lines: csvLines,
                    resolver: csvResolver,
                    defaultFileName: session?.name ?? "sportcut"
                ) { showCSVExport = false }
            }

            Divider()

            if !bulkSelectedStampIDs.isEmpty {
                tableBulkSelectionBar
            }

            if filteredStamps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    Text(^String.Titles.sportCutNoEvents)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        tableHeader
                        
                        ForEach(filteredStamps, id: \.stamp.id) { row in
                            SportCutTableRowView(
                                row: row,
                                playerManager: playerManager,
                                sessionID: sessionID,
                                hasDrawing: stampsWithDrawings.contains(row.stamp.id),
                                bulkSelectedStampIDs: $bulkSelectedStampIDs
                            )
                        }
                    }
                }
            }
        }
        .onAppear { loadDrawingMarkers() }
        .onChange(of: sessionID) { _ in loadDrawingMarkers() }
        .onChange(of: session?.sources.count ?? 0) { _ in loadDrawingMarkers() }
    }

    /// Loads, per project source, the set of stamp IDs that have a drawing attached in the
    /// original markup. Markup drawings are stored as per-project screenshot metadata JSONs
    /// (each with `relatedStampIds`); the SportCut table can span several projects, so we
    /// index all of them here rather than relying on the single-project shared manager.
    private func loadDrawingMarkers() {
        guard let session = session else { return }
        let folders: [URL] = session.sources.compactMap { source in
            guard let projectID = source.projectID,
                  let file = VideoFilesManager.shared.files.first(where: { $0.videoData.id == projectID }) else { return nil }
            return file.screenshotsFolder
        }
        guard !folders.isEmpty else {
            stampsWithDrawings = []
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var result: Set<UUID> = []
            let fm = FileManager.default
            for folder in folders {
                guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
                for url in urls where url.pathExtension.lowercased() == "json" {
                    guard let data = try? Data(contentsOf: url),
                          let meta = try? JSONDecoder().decode(ScreenshotMetadata.self, from: data) else { continue }
                    result.formUnion(meta.relatedStampIds)
                }
            }
            DispatchQueue.main.async { self.stampsWithDrawings = result }
        }
    }
    
    private var tableHeader: some View {
        HStack(spacing: 0) {
            headerCell(^String.Titles.sportCutProjectColumn, width: 100)
            Divider().frame(height: 20)
            
            headerCell(^String.Titles.sportCutTimelineColumn, width: 100)
            Divider().frame(height: 20)
            
            headerCell(^String.Titles.sportCutTagColumn, width: 120)
            Divider().frame(height: 20)
            
            headerCell(^String.Titles.sportCutStartColumn, width: 80)
            Divider().frame(height: 20)
            
            headerCell(^String.Titles.sportCutEndColumn, width: 80)
            Divider().frame(height: 20)
            
            headerCell(^String.Titles.sportCutDurationColumn, width: 60)
            Divider().frame(height: 20)

            headerCell(^String.Titles.sportCutDrawingColumn, width: 60)
            Divider().frame(height: 20)

            headerCell(^String.Titles.sportCutLabelsColumn)
            Divider().frame(height: 20)
            
            headerCell(^String.Titles.sportCutEventsColumn, width: 120)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
        )
    }

    private var tableBulkSelectionBar: some View {
        let selected = filteredStamps.filter { bulkSelectedStampIDs.contains($0.stamp.id) }
        let totalSeconds = selected.reduce(0.0) { $0 + max(0.0, $1.stamp.duration) }
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
            let events: [SportCutEvent] = selected.compactMap { row in
                SportCutEvent.from(stamp: row.stamp, line: row.line, source: row.source)
            }
            let data = try? JSONEncoder().encode(events)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: "public.data", visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
            return provider
        }
    }

    private func headerCell(_ title: String, width: CGFloat? = nil) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }
}

struct SportCutEventRow {
    let stamp: TimelineStamp
    let line: TimelineLine
    let source: SportCutSource
}

struct SportCutTableRowView: View {
    let row: SportCutEventRow
    @ObservedObject var playerManager: SportCutPlayerManager
    let sessionID: UUID
    let hasDrawing: Bool
    @Binding var bulkSelectedStampIDs: Set<UUID>

    @ObservedObject var sessionManager = SportCutSessionManager.shared
    @State private var isDragging = false

    private var isBulkSelected: Bool {
        bulkSelectedStampIDs.contains(row.stamp.id)
    }
    
    private var labels: [Label] {
        row.stamp.labelIDs.compactMap { row.source.findLabel(byID: $0) }
    }
    
    private var events: [TimeEvent] {
        row.stamp.timeEvents.compactMap { eventID in
            row.source.timeEvents.first { $0.id == eventID }
        }
    }
    
    private func createEvent() -> SportCutEvent {
        SportCutEvent.from(stamp: row.stamp, line: row.line, source: row.source)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Text(row.source.name)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 6)
            Divider().frame(height: 20)
            
            Text(row.line.name)
                .font(.system(size: 10))
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 6)
            Divider().frame(height: 20)
            
            HStack(spacing: 4) {
                let tag = row.source.findTag(byID: row.stamp.idTag)
                Circle()
                    .fill(Color(hex: tag?.color ?? row.stamp.colorHex))
                    .frame(width: 6, height: 6)
                Text(row.stamp.label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)
            .padding(.horizontal, 6)
            Divider().frame(height: 20)
            
            Text(formatTime(row.stamp.timeStartSeconds))
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
                .padding(.horizontal, 6)
            Divider().frame(height: 20)
            
            Text(formatTime(row.stamp.timeFinishSeconds))
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
                .padding(.horizontal, 6)
            Divider().frame(height: 20)
            
            Text(formatTime(row.stamp.duration))
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
                .padding(.horizontal, 6)
            Divider().frame(height: 20)

            Group {
                if hasDrawing {
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.blue)
                        .help(^String.Titles.sportCutDrawingColumn)
                } else {
                    Text("—")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 60, alignment: .center)
            .padding(.horizontal, 6)
            Divider().frame(height: 20)

            HStack(spacing: 4) {
                if labels.isEmpty {
                    Text("—")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                } else {
                    ForEach(labels, id: \.id) { label in
                        Text(label.name)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.7))
                            .cornerRadius(3)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            Divider().frame(height: 20)
            
            HStack(spacing: 4) {
                if events.isEmpty {
                    Text("—")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                } else {
                    ForEach(events, id: \.id) { event in
                        Text(event.name)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.7))
                            .cornerRadius(3)
                    }
                }
            }
            .frame(width: 120, alignment: .leading)
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 4)
        .overlay(
            Rectangle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
        .onDrag {
            isDragging = true
            let data: Data?
            if isBulkSelected, bulkSelectedStampIDs.count > 1 {
                let allStamps = row.source.timelines.flatMap { ln in
                    ln.stamps.filter { bulkSelectedStampIDs.contains($0.id) }.map { (stamp: $0, line: ln) }
                }.sorted { $0.stamp.timeStartSeconds < $1.stamp.timeStartSeconds }
                let events = allStamps.map { SportCutEvent.from(stamp: $0.stamp, line: $0.line, source: row.source) }
                data = try? JSONEncoder().encode(events)
            } else {
                let event = createEvent()
                data = try? JSONEncoder().encode(event)
            }
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
        .background(isBulkSelected ? Color.blue.opacity(0.15) : Color.clear)
        .onTapGesture {
            let commandDown = NSEvent.modifierFlags.contains(.command)
            if commandDown {
                if bulkSelectedStampIDs.contains(row.stamp.id) {
                    bulkSelectedStampIDs.remove(row.stamp.id)
                } else {
                    bulkSelectedStampIDs.insert(row.stamp.id)
                }
            } else {
                playerManager.playEvent(createEvent())
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
            if let raw = row.stamp.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                session.playlistGroups[0].playlists[lastIdx].eventComments[event.hiddenKey] = raw
            }
            sessionManager.updateSession(session)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
