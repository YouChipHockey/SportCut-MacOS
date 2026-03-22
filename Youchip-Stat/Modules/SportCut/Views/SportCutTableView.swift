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
    @State private var selectedEventIDs: Set<UUID> = []
    @State private var isShiftPressed = false
    
    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }
    
    private var filteredStamps: [SportCutEventRow] {
        guard let session = session else { return [] }
        
        let sourcesToUse: [SportCutSource]
        if selectedSourceIndex == -1 {
            sourcesToUse = session.sources
        } else if selectedSourceIndex < session.sources.count {
            sourcesToUse = [session.sources[selectedSourceIndex]]
        } else {
            return []
        }
        
        return sourcesToUse.flatMap { source in
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
        .sorted { $0.stamp.timeStartSeconds < $1.stamp.timeStartSeconds }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(^String.Titles.sportCutEventsTable)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
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
                                sessionID: sessionID,
                                isSelected: selectedEventIDs.contains(row.stamp.id),
                                isShiftPressed: isShiftPressed,
                                onToggleSelection: {
                                    if selectedEventIDs.contains(row.stamp.id) {
                                        selectedEventIDs.remove(row.stamp.id)
                                    } else {
                                        selectedEventIDs.insert(row.stamp.id)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .onAppear { setupShiftKeyMonitoring() }
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
    
    private func setupShiftKeyMonitoring() {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let shift = event.modifierFlags.contains(.shift)
            if isShiftPressed != shift {
                isShiftPressed = shift
                if !shift { selectedEventIDs.removeAll() }
            }
            return event
        }
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
    let isSelected: Bool
    let isShiftPressed: Bool
    let onToggleSelection: () -> Void
    
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        .overlay(
            Rectangle()
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: isSelected ? 1 : 0.5)
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
            if isShiftPressed {
                onToggleSelection()
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
            sessionManager.updateSession(session)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
