//
//  ViewerTableView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI

struct ViewerTableView: View {
    @ObservedObject var timelineData = TimelineDataManager.shared
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var organizer: PlaylistManager
    @ObservedObject var playlistManager: VideoPlaylistManager
    @ObservedObject var filter: TimelineFilter
    
    @State private var selectedStamps: Set<UUID> = []
    @State private var isShiftPressed: Bool = false
    
    private var filteredStamps: [TimelineStampWithLine] {
        let filteredLines: [TimelineLine] = timelineData.lines.compactMap { line in
            let hasMatchingStamps = line.stamps.contains { stamp in
                filter.matches(stamp: stamp)
            }
            
            if !hasMatchingStamps {
                return nil
            }
            
            return line
        }
        
        return filteredLines.flatMap { line in
            line.stamps.filter { filter.matches(stamp: $0) }.map { stamp in
                TimelineStampWithLine(stamp: stamp, line: line)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(^String.Titles.timestampsTable)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(String(format: ^String.Titles.timestampsCount, filteredStamps.count))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            if filteredStamps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    
                    Text(^String.Titles.noTimestamps)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if filter.hasActiveFilters() {
                        Text(^String.Titles.tryChangeFilters)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.1))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text(^String.Titles.timeline)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 120, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                            
                            Divider()
                                .frame(height: 20)
                            
                            Text(^String.Titles.tag)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 150, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                            
                            Divider()
                                .frame(height: 20)
                            
                            Text(^String.Titles.time)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                            
                            Divider()
                                .frame(height: 20)
                            
                            Text(^String.Titles.duration)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                            
                            Divider()
                                .frame(height: 20)
                            
                            Text(^String.Titles.labels)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                        }
                        .overlay(
                            Rectangle()
                                .stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
                        )
                        
                        ForEach(filteredStamps, id: \.stamp.id) { stampWithLine in
                            TableRowView(
                                stampWithLine: stampWithLine,
                                organizer: organizer,
                                playlistManager: playlistManager,
                                selectedStamps: $selectedStamps,
                                isShiftPressed: isShiftPressed,
                                onMultiDragComplete: {
                                    selectedStamps.removeAll()
                                }
                            )
                        }
                    }
                }
            }
        }
        .onAppear {
            setupShiftKeyMonitoring()
        }
    }
    
    private func setupShiftKeyMonitoring() {
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            let shiftPressed = event.modifierFlags.contains(.shift)
            
            if self.isShiftPressed != shiftPressed {
                self.isShiftPressed = shiftPressed
                
                if !shiftPressed {
                    self.selectedStamps.removeAll()
                }
            }
            
            return event
        }
    }
}

struct TimelineStampWithLine: Identifiable {
    let id = UUID()
    let stamp: TimelineStamp
    let line: TimelineLine
}

struct TableRowView: View {
    let stampWithLine: TimelineStampWithLine
    @ObservedObject var organizer: PlaylistManager
    @ObservedObject var playlistManager: VideoPlaylistManager
    @Binding var selectedStamps: Set<UUID>
    let isShiftPressed: Bool
    let onMultiDragComplete: () -> Void
    @State private var isDragging = false
    
    private var isSelected: Bool {
        selectedStamps.contains(stampWithLine.stamp.id)
    }
    
    private var tag: Tag? {
        TagLibraryManager.shared.findTagById(stampWithLine.stamp.idTag)
    }
    
    private var labels: [Label] {
        stampWithLine.stamp.labels.compactMap { labelID in
            TagLibraryManager.shared.findLabelById(labelID)
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Text(stampWithLine.line.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 120, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .lineLimit(1)
            
            Divider()
                .frame(height: 20)
            
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: tag?.color ?? "FFFFFF") ?? .gray)
                    .frame(width: 8, height: 8)
                
                Text(stampWithLine.stamp.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            
            Divider()
                .frame(height: 20)
            
            Text(formatTime(stampWithLine.stamp.timeStartSeconds))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            
            Divider()
                .frame(height: 20)
            
            Text(formatTime(stampWithLine.stamp.duration))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            
            Divider()
                .frame(height: 20)
            
            HStack(spacing: 4) {
                ForEach(labels, id: \.id) { label in
                    Text(label.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.7))
                        .cornerRadius(4)
                }
                
                if labels.isEmpty {
                    Text("—")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
        .overlay(
            Rectangle()
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 1.5 : 0.5)
        )
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .opacity(isDragging ? 0.8 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onDrag {
            isDragging = true
            
            if !selectedStamps.isEmpty && isSelected {
                let tags = createMultipleOrganizerTags()
                let data = try? JSONEncoder().encode(tags)
                let provider = NSItemProvider()
                
                provider.registerDataRepresentation(forTypeIdentifier: "public.data", visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
                
                provider.registerDataRepresentation(forTypeIdentifier: "com.youchip.organizerTags", visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isDragging = false
                    onMultiDragComplete()
                }
                
                return provider
            } else {
                let tag = createOrganizerTag()
                let data = try? JSONEncoder().encode(tag)
                let provider = NSItemProvider()
                
                provider.registerDataRepresentation(forTypeIdentifier: "public.data", visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
                
                provider.registerDataRepresentation(forTypeIdentifier: "com.youchip.organizerTag", visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isDragging = false
                }
                
                return provider
            }
        }
        .contextMenu {
            if !selectedStamps.isEmpty {
                Button(String(format: ^String.Titles.moveAll, selectedStamps.count)) {
                    addMultipleToOrganizer()
                    onMultiDragComplete()
                }
            } else {
                Button(^String.Titles.addToOrganizer) {
                    addToOrganizer()
                }
                
                Button(^String.Titles.play) {
                    playStamp()
                }
            }
        }
        .onTapGesture {
            if isShiftPressed {
                toggleSelection()
            } else {
                playStamp()
            }
        }
    }
    
    private func createOrganizerTag() -> OrganizerTag {
        let tag = TagLibraryManager.shared.findTagById(stampWithLine.stamp.idTag)
        let tagGroup = TagLibraryManager.shared.findTagGroupForTag(stampWithLine.stamp.idTag)
        return OrganizerTag(
            stampID: stampWithLine.stamp.id,
            mainTagID: stampWithLine.stamp.idTag,
            lineID: stampWithLine.line.id,
            tagName: stampWithLine.stamp.label,
            lineName: stampWithLine.line.name,
            startTime: stampWithLine.stamp.timeStartSeconds,
            duration: stampWithLine.stamp.duration,
            color: tag?.color ?? "FFFFFF",
            tagGroupName: tagGroup?.name,
            labelIDs: stampWithLine.stamp.labels,
            eventIDs: stampWithLine.stamp.timeEvents
        )
    }
    
    private func toggleSelection() {
        if selectedStamps.contains(stampWithLine.stamp.id) {
            selectedStamps.remove(stampWithLine.stamp.id)
        } else {
            selectedStamps.insert(stampWithLine.stamp.id)
        }
    }
    
    private func createMultipleOrganizerTags() -> [OrganizerTag] {
        let allStampsWithLines = TimelineDataManager.shared.lines.flatMap { line in
            line.stamps.map { stamp in
                TimelineStampWithLine(stamp: stamp, line: line)
            }
        }
        
        return allStampsWithLines
            .filter { selectedStamps.contains($0.stamp.id) }
            .map { stampWithLine in
                let tag = TagLibraryManager.shared.findTagById(stampWithLine.stamp.idTag)
                let tagGroup = TagLibraryManager.shared.findTagGroupForTag(stampWithLine.stamp.idTag)
                return OrganizerTag(
                    stampID: stampWithLine.stamp.id,
                    mainTagID: stampWithLine.stamp.idTag,
                    lineID: stampWithLine.line.id,
                    tagName: stampWithLine.stamp.label,
                    lineName: stampWithLine.line.name,
                    startTime: stampWithLine.stamp.timeStartSeconds,
                    duration: stampWithLine.stamp.duration,
                    color: tag?.color ?? "FFFFFF",
                    tagGroupName: tagGroup?.name,
                    labelIDs: stampWithLine.stamp.labels,
                    eventIDs: stampWithLine.stamp.timeEvents
                )
            }
    }
    
    private func addToOrganizer() {
        organizer.addTag(createOrganizerTag())
    }
    
    private func addMultipleToOrganizer() {
        let tags = createMultipleOrganizerTags()
        for tag in tags {
            organizer.addTag(tag)
        }
    }
    
    private func playStamp() {
        playlistManager.playSingleTag(createOrganizerTag())
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
