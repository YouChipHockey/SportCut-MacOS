//
//  SportCutTableView.swift
//  Youchip-Stat
//

import SwiftUI

struct SportCutTableView: View {
    let sessionID: UUID
    @ObservedObject var playerManager: SportCutPlayerManager
    @ObservedObject var filter: TimelineFilter
    let selectedSourceIndex: Int
    
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    @State private var sortMode: SportCutTableSortMode = .startTimeAsc

    private enum SportCutTableSortMode: String, CaseIterable {
        case startTimeAsc
        case startTimeDesc
        case durationAsc
        case durationDesc
        case tagNameAsc
        case projectAsc

        var label: String {
            switch self {
            case .startTimeAsc: return "Время ↑"
            case .startTimeDesc: return "Время ↓"
            case .durationAsc: return "Длительность ↑"
            case .durationDesc: return "Длительность ↓"
            case .tagNameAsc: return "Тег А→Я"
            case .projectAsc: return "Проект А→Я"
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
                
                Text(String.Titles.sportCutEventsCount.format(filteredStamps.count))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            
            Divider()
            
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
                                sessionID: sessionID
                            )
                        }
                    }
                }
            }
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
            
            headerCell(^String.Titles.sportCutLabelsColumn)
            Divider().frame(height: 20)
            
            headerCell(^String.Titles.sportCutEventsColumn, width: 120)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
        )
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
    
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    @State private var isDragging = false
    
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
                    .fill(Color(hex: tag?.color ?? "FFFFFF"))
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
            playerManager.playEvent(createEvent())
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
