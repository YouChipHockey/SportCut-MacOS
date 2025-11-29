//
//  ViewerTimelineView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVFoundation

struct ViewerTimelineView: View {
    @ObservedObject var timelineData = TimelineDataManager.shared
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var organizer: PlaylistManager
    @ObservedObject var playlistManager: VideoPlaylistManager
    @StateObject private var filter = TimelineFilter()
    @State private var timelineScale: CGFloat = 1.0
    @GestureState private var magnifyScale: CGFloat = 1.0
    @State private var showFilterSheet = false
    @State private var displayMode: TimelineDisplayMode = .timeline
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(^String.Titles.timelines)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    addAllFilteredTagsToOrganizer()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.rectangle.on.folder")
                            .font(.system(size: 12, weight: .medium))
                        Text(^String.Titles.addAll)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Добавить все отображаемые теги в органайзер")
                
                HStack(spacing: 2) {
                    ForEach(TimelineDisplayMode.allCases, id: \.self) { mode in
                        Button(action: {
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
                        .help("Переключить режим отображения")
                    }
                }
                
                Button(action: {
                    showFilterSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: filter.hasActiveFilters() ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 12, weight: .medium))
                        Text(^String.Titles.filter)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(filter.hasActiveFilters() ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .foregroundColor(filter.hasActiveFilters() ? .blue : .primary)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Фильтровать таймстемпы")
                
                if filter.hasActiveFilters() {
                    Button(action: {
                        filter.clearFilters()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Очистить фильтры")
                }
                
                HStack(spacing: 4) {
                    Button {
                        timelineScale = max(1.0, timelineScale - 0.5)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Уменьшить масштаб")
                    
                    Text(String(format: "%.1fx", timelineScale))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                    
                    Button {
                        timelineScale += 0.5
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Увеличить масштаб")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            if displayMode == .timeline {
                ScrollView(.vertical) {
                    ScrollViewReader { scrollProxy in
                        timelineContent(proxy: scrollProxy)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .gesture(
                    MagnificationGesture()
                        .updating($magnifyScale) { currentState, gestureState, _ in
                            gestureState = max(1.0, currentState)
                        }
                        .onEnded { value in
                            let newScale = timelineScale * value
                            let duration = max(1.0, videoManager.videoDuration)
                            let potentialInterval = calculateTimeGridInterval(scale: newScale, totalDuration: duration)
                            if potentialInterval >= 0.5 {
                                timelineScale = max(1.0, newScale)
                            } else {
                                let baseInterval = 5.0
                                let maxScale = baseInterval / 0.5
                                timelineScale = maxScale
                            }
                        }
                )
            } else {
                ViewerTableView(
                    organizer: organizer,
                    playlistManager: playlistManager,
                    filter: filter
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            TimelineFilterSheet(filter: filter)
        }
    }
    
    @ViewBuilder
    private func timelineContent(proxy: ScrollViewProxy) -> some View {
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
                .frame(width: 195, height: 30, alignment: .leading)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
                .id("header-row")
                
                ForEach(filteredLines) { line in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.name)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .minimumScaleFactor(0.6)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                        }
                        
                        Spacer()
                    }
                    .padding(.leading, 5)
                    .frame(width: 195, height: 30, alignment: .leading)
                    .id("name-\(line.id)")
                }
            }
            .frame(width: 195)
            .padding(.trailing, 5)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            GeometryReader { geo in
                let effectiveScale = timelineScale * magnifyScale
                let duration = max(1.0, videoManager.videoDuration)
                let interval = calculateTimeGridInterval(scale: effectiveScale, totalDuration: duration)
                let gridWidth = geo.size.width * max(effectiveScale, 1.0)
                
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            TimeGridView(
                                duration: duration,
                                interval: interval,
                                width: gridWidth,
                                height: 30 * CGFloat(filteredLines.count + 1)
                            )
                            
                            VStack(spacing: 0) {
                                TimelineTimestampsHeaderView(
                                    duration: duration,
                                    interval: interval,
                                    width: gridWidth
                                )
                                .frame(height: 30)
                                
                                ForEach(filteredLines) { line in
                                    ViewerTimelineLineView(
                                        videoManager: videoManager,
                                        timelineData: timelineData,
                                        line: line,
                                        scale: effectiveScale,
                                        widthMax: gridWidth,
                                        organizer: organizer,
                                        playlistManager: playlistManager,
                                        filter: filter
                                    )
                                    .frame(height: 30)
                                    .id("timeline-\(line.id)")
                                }
                            }
                        }
                        .frame(width: gridWidth)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    private func calculateTimeGridInterval(scale: CGFloat, totalDuration: Double) -> Double {
        let baseCount = 20 * scale
        let baseInterval = totalDuration / baseCount
        return max(0.5, baseInterval)
    }
    
    private var filteredLines: [TimelineLine] {
        return timelineData.lines.compactMap { line in
            let hasMatchingStamps = line.stamps.contains { stamp in
                filter.matches(stamp: stamp)
            }
            
            if !hasMatchingStamps {
                return nil
            }
            return line
        }
    }
    
    private func addAllFilteredTagsToOrganizer() {
        var addedCount = 0
        
        for line in filteredLines {
            let matchingStamps = line.stamps.filter { filter.matches(stamp: $0) }
            
            for stamp in matchingStamps {
                let tag = TagLibraryManager.shared.findTagById(stamp.idTag)
                let tagGroup = TagLibraryManager.shared.findTagGroupForTag(stamp.idTag)
                let organizerTag = OrganizerTag(
                    stampID: stamp.id,
                    lineID: line.id,
                    tagName: stamp.label,
                    lineName: line.name,
                    startTime: stamp.startSeconds,
                    duration: stamp.duration,
                    color: tag?.color ?? "FFFFFF",
                    tagGroupName: tagGroup?.name,
                    labelIDs: stamp.labels,
                    eventIDs: stamp.timeEvents
                )
                organizer.addTag(organizerTag)
                addedCount += 1
            }
        }
    }
}

struct ViewerTimelineLineView: View {
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    let line: TimelineLine
    let scale: CGFloat
    let widthMax: CGFloat
    @ObservedObject var organizer: PlaylistManager
    @ObservedObject var playlistManager: VideoPlaylistManager
    @ObservedObject var filter: TimelineFilter
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: widthMax, height: 30)
            ForEach(line.stamps.filter { filter.matches(stamp: $0) }) { stamp in
                let startX = (stamp.startSeconds / videoManager.videoDuration) * widthMax
                let width = (stamp.duration / videoManager.videoDuration) * widthMax
                
                        ViewerStampView(
                            stamp: stamp,
                            line: line,
                            startX: startX,
                            width: width,
                            organizer: organizer,
                            playlistManager: playlistManager,
                            filter: filter
                        )
            }
        }
        .frame(width: widthMax, height: 30)
    }
}

struct ViewerStampView: View {
    let stamp: TimelineStamp
    let line: TimelineLine
    let startX: CGFloat
    let width: CGFloat
    @ObservedObject var organizer: PlaylistManager
    @ObservedObject var playlistManager: VideoPlaylistManager
    @ObservedObject var filter: TimelineFilter
    @State private var isDragging = false
    
    var body: some View {
        let tag = TagLibraryManager.shared.findTagById(stamp.idTag)
        let color = Color(hex: tag?.color ?? "FFFFFF") ?? .gray
        
        Rectangle()
            .fill(color.opacity(isDragging ? 0.5 : 0.7))
            .overlay(
                Rectangle()
                    .stroke(color, lineWidth: 1)
            )
            .frame(width: max(width, 2), height: 24)
            .position(x: startX + width/2, y: 15)
            .overlay(
                Text(stamp.label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: max(width - 4, 0), height: 20)
                    .position(x: startX + width/2, y: 15)
            )
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isDragging)
            .onDrag {
                isDragging = true
                let organizerTag = createOrganizerTag()
                let data = try? JSONEncoder().encode(organizerTag)
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: "public.data", visibility: .all) { completion in
                    DispatchQueue.main.async {
                        isDragging = false
                    }
                    completion(data, nil)
                    return nil
                }
                
                provider.registerDataRepresentation(forTypeIdentifier: "com.youchip.organizerTag", visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
                
                return provider
            }
            .contextMenu {
                Button(^String.Titles.addToOrganizer) {
                    addToOrganizer()
                }
                
                Button(^String.Titles.play) {
                    playStamp()
                }
            }
            .onTapGesture {
                playStamp()
            }
    }
    
    private func createOrganizerTag() -> OrganizerTag {
        let tag = TagLibraryManager.shared.findTagById(stamp.idTag)
        let tagGroup = TagLibraryManager.shared.findTagGroupForTag(stamp.idTag)
        return OrganizerTag(
            stampID: stamp.id,
            lineID: line.id,
            tagName: stamp.label,
            lineName: line.name,
            startTime: stamp.startSeconds,
            duration: stamp.duration,
            color: tag?.color ?? "FFFFFF",
            tagGroupName: tagGroup?.name,
            labelIDs: stamp.labels,
            eventIDs: stamp.timeEvents
        )
    }
    
    private func addToOrganizer() {
        organizer.addTag(createOrganizerTag())
    }
    
    private func playStamp() {
        playlistManager.playSingleTag(createOrganizerTag())
    }
}

struct TimelineFilterSheet: View {
    @ObservedObject var filter: TimelineFilter
    @Environment(\.presentationMode) var presentationMode
    
    private var availableTags: [Tag] {
        let tagIDs = TimelineDataManager.shared.lines.flatMap { line in
            line.stamps.map { $0.idTag }
        }
        let uniqueTagIDs = Array(Set(tagIDs))
        return TagLibraryManager.shared.allTags.filter { uniqueTagIDs.contains($0.id) }
    }
    
    private var availableLabels: [Label] {
        let labelIDs = TimelineDataManager.shared.lines.flatMap { line in
            line.stamps.flatMap { $0.labels }
        }
        let uniqueLabelIDs = Array(Set(labelIDs))
        return TagLibraryManager.shared.allLabels.filter { uniqueLabelIDs.contains($0.id) }
    }
    
    private var availableEvents: [TimeEvent] {
        let eventIDs = TimelineDataManager.shared.lines.flatMap { line in
            line.stamps.flatMap { $0.timeEvents }
        }
        let uniqueEventIDs = Array(Set(eventIDs))
        return TagLibraryManager.shared.allTimeEvents.filter { uniqueEventIDs.contains($0.id) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(^String.Titles.filterTimestampsTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(^String.Titles.clear) {
                    filter.clearFilters()
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.red)
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.tags)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                            ForEach(availableTags, id: \.id) { tag in
                                FilterTagView(
                                    tag: tag,
                                    isSelected: filter.selectedTags.contains(tag.id),
                                    onToggle: {
                                        if filter.selectedTags.contains(tag.id) {
                                            filter.selectedTags.remove(tag.id)
                                        } else {
                                            filter.selectedTags.insert(tag.id)
                                        }
                                        filter.isFilterActive = filter.hasActiveFilters()
                                    }
                                )
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.labels)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                            ForEach(availableLabels, id: \.id) { label in
                                FilterLabelView(
                                    label: label,
                                    isSelected: filter.selectedLabels.contains(label.id),
                                    onToggle: {
                                        if filter.selectedLabels.contains(label.id) {
                                            filter.selectedLabels.remove(label.id)
                                        } else {
                                            filter.selectedLabels.insert(label.id)
                                        }
                                        filter.isFilterActive = filter.hasActiveFilters()
                                    }
                                )
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.events)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                            ForEach(availableEvents, id: \.id) { event in
                                FilterEventView(
                                    event: event,
                                    isSelected: filter.selectedEvents.contains(event.id),
                                    onToggle: {
                                        if filter.selectedEvents.contains(event.id) {
                                            filter.selectedEvents.remove(event.id)
                                        } else {
                                            filter.selectedEvents.insert(event.id)
                                        }
                                        filter.isFilterActive = filter.hasActiveFilters()
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            HStack {
                Button(^String.Titles.cancelButtonTitle) {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(^String.Titles.apply) {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 500, height: 400)
    }
}

struct FilterTagView: View {
    let tag: Tag
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .gray)
                Text(tag.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            .foregroundColor(isSelected ? .blue : .primary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FilterLabelView: View {
    let label: Label
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .gray)
                Text(label.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.2))
            .foregroundColor(isSelected ? .blue : .primary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FilterEventView: View {
    let event: TimeEvent
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .gray)
                Text(event.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.2))
            .foregroundColor(isSelected ? .blue : .primary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
