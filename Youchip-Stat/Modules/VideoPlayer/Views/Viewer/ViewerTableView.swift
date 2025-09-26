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
    
    private var filteredStamps: [TimelineStampWithLine] {
        let allStamps = timelineData.lines.flatMap { line in
            line.stamps.map { stamp in
                TimelineStampWithLine(stamp: stamp, line: line)
            }
        }
        
        if !filter.hasActiveFilters() {
            return allStamps
        }
        
        return allStamps.filter { stampWithLine in
            filter.matches(stamp: stampWithLine.stamp)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Таблица таймстемпов")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(filteredStamps.count) таймстемпов")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Table content
            if filteredStamps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    
                    Text("Нет таймстемпов")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if filter.hasActiveFilters() {
                        Text("Попробуйте изменить фильтры")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.1))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Table header
                        HStack(spacing: 0) {
                            Text("Таймлайн")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 120, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                            
                            Divider()
                                .frame(height: 20)
                            
                            Text("Тег")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 150, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                            
                            Divider()
                                .frame(height: 20)
                            
                            Text("Время")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                            
                            Divider()
                                .frame(height: 20)
                            
                            Text("Длительность")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                            
                            Divider()
                                .frame(height: 20)
                            
                            Text("Лейблы")
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
                        
                        // Table rows
                        ForEach(filteredStamps, id: \.stamp.id) { stampWithLine in
                            TableRowView(
                                stampWithLine: stampWithLine,
                                organizer: organizer,
                                playlistManager: playlistManager
                            )
                        }
                    }
                }
            }
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
    @State private var isDragging = false
    
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
            // Timeline name
            Text(stampWithLine.line.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 120, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .lineLimit(1)
            
            Divider()
                .frame(height: 20)
            
            // Tag name with color
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
            
            // Start time
            Text(formatTime(stampWithLine.stamp.startSeconds))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            
            Divider()
                .frame(height: 20)
            
            // Duration
            Text(formatTime(stampWithLine.stamp.duration))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            
            Divider()
                .frame(height: 20)
            
            // Labels
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
        .overlay(
            Rectangle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .opacity(isDragging ? 0.8 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .onDrag {
            let tag = createOrganizerTag()
            print("🚀 Starting drag for tag from table: \(tag.tagName)")
            let data = try? JSONEncoder().encode(tag)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: "com.youchip.organizerTag", visibility: .all) { completion in
                print("📦 Providing data for tag from table: \(tag.tagName)")
                completion(data, nil)
                return nil
            }
            return provider
        }
        .contextMenu {
            Button("Добавить в органайзер") {
                addToOrganizer()
            }
            
            Button("Воспроизвести") {
                playStamp()
            }
        }
        .onTapGesture {
            playStamp()
        }
    }
    
    private func createOrganizerTag() -> OrganizerTag {
        let tag = TagLibraryManager.shared.findTagById(stampWithLine.stamp.idTag)
        return OrganizerTag(
            stampID: stampWithLine.stamp.id,
            lineID: stampWithLine.line.id,
            tagName: stampWithLine.stamp.label,
            lineName: stampWithLine.line.name,
            startTime: stampWithLine.stamp.startSeconds,
            duration: stampWithLine.stamp.duration,
            color: tag?.color ?? "FFFFFF"
        )
    }
    
    private func addToOrganizer() {
        organizer.addTag(createOrganizerTag())
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
