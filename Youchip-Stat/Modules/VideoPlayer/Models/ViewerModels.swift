//
//  ViewerModels.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import Foundation
import AVFoundation
import UniformTypeIdentifiers
import SwiftUI

// MARK: - Notifications
extension Notification.Name {
    static let playSingleTag = Notification.Name("playSingleTag")
    static let stopViewerPlayer = Notification.Name("stopViewerPlayer")
}

// MARK: - Playlist System
class PlaylistManager: ObservableObject {
    @Published var playlists: [SavedPlaylist] = [] {
        didSet {
            savePlaylists()
        }
    }
    @Published var currentPlaylist: SavedPlaylist?
    @Published var currentTags: [OrganizerTag] = []
    
    private let videoID: String
    private var playlistsKey: String {
        return "SavedPlaylists_\(videoID)"
    }
    
    init(videoID: String) {
        self.videoID = videoID
        loadPlaylists()
    }
    
    func createNewPlaylist() {
        currentPlaylist = nil
        currentTags.removeAll()
    }
    
    func saveCurrentPlaylist(name: String) {
        guard !currentTags.isEmpty else { return }
        
        let newPlaylist = SavedPlaylist(
            id: UUID(),
            name: name,
            tags: currentTags,
            createdAt: Date()
        )
        
        playlists.append(newPlaylist)
        currentPlaylist = newPlaylist
    }
    
    func loadPlaylist(_ playlist: SavedPlaylist) {
        currentPlaylist = playlist
        currentTags = playlist.tags
    }
    
    func deletePlaylist(_ playlist: SavedPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        if currentPlaylist?.id == playlist.id {
            createNewPlaylist()
        }
    }
    
    func addTag(_ tag: OrganizerTag) {
        if !currentTags.contains(where: { $0.stampID == tag.stampID }) {
            currentTags.append(tag)
            // Сбрасываем текущий плейлист при изменении
            currentPlaylist = nil
        }
    }
    
    func removeTag(at index: Int) {
        guard index < currentTags.count else { return }
        currentTags.remove(at: index)
        // Сбрасываем текущий плейлист при изменении
        currentPlaylist = nil
    }
    
    func moveTag(from source: IndexSet, to destination: Int) {
        currentTags.move(fromOffsets: source, toOffset: destination)
        // Сбрасываем текущий плейлист при изменении
        currentPlaylist = nil
    }
    
    func clear() {
        currentTags.removeAll()
        currentPlaylist = nil
    }
    
    // MARK: - Persistence
    private func savePlaylists() {
        do {
            let data = try JSONEncoder().encode(playlists)
            UserDefaults.standard.set(data, forKey: playlistsKey)
        } catch {
            print("Ошибка сохранения плейлистов: \(error)")
        }
    }
    
    func loadPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: playlistsKey) else { return }
        
        do {
            playlists = try JSONDecoder().decode([SavedPlaylist].self, from: data)
        } catch {
            print("Ошибка загрузки плейлистов: \(error)")
            playlists = []
        }
    }

}

struct SavedPlaylist: Identifiable, Codable {
    let id: UUID
    let name: String
    let tags: [OrganizerTag]
    let createdAt: Date
    
    var tagCount: Int {
        return tags.count
    }
    
    var duration: Double {
        return tags.reduce(0) { $0 + $1.duration }
    }
}

// MARK: - Organizer Models (Legacy - keeping for compatibility)
class TagOrganizer: ObservableObject {
    @Published var tags: [OrganizerTag] = []
    
    func addTag(_ tag: OrganizerTag) {
        if !tags.contains(where: { $0.stampID == tag.stampID }) {
            tags.append(tag)
        }
    }
    
    func removeTag(at index: Int) {
        guard index < tags.count else { return }
        tags.remove(at: index)
    }
    
    func moveTag(from source: IndexSet, to destination: Int) {
        tags.move(fromOffsets: source, toOffset: destination)
    }
    
    func clear() {
        tags.removeAll()
    }
}

struct OrganizerTag: Identifiable, Equatable, Codable {
    let id: UUID
    let stampID: UUID
    let lineID: UUID
    let tagName: String
    let lineName: String
    let startTime: Double
    let duration: Double
    let color: String
    
    init(stampID: UUID, lineID: UUID, tagName: String, lineName: String, startTime: Double, duration: Double, color: String) {
        self.id = UUID()
        self.stampID = stampID
        self.lineID = lineID
        self.tagName = tagName
        self.lineName = lineName
        self.startTime = startTime
        self.duration = duration
        self.color = color
    }
    
    static func == (lhs: OrganizerTag, rhs: OrganizerTag) -> Bool {
        return lhs.stampID == rhs.stampID
    }
}

// MARK: - Export Mode
enum ViewerExportMode {
    case archive
    case film
}

// MARK: - Drawing State
class DrawingState: ObservableObject {
    @Published var isDrawingMode: Bool = false
    @Published var currentPath: DrawingPath = DrawingPath()
    @Published var completedPaths: [DrawingPath] = []
    @Published var currentTime: Double = 0.0
    
    func startNewPath(at point: CGPoint) {
        currentPath = DrawingPath()
        currentPath.addPoint(point)
    }
    
    func addPoint(_ point: CGPoint) {
        currentPath.addPoint(point)
    }
    
    func finishPath() {
        if !currentPath.points.isEmpty {
            completedPaths.append(currentPath)
            currentPath = DrawingPath()
        }
    }
    
    func clearDrawing() {
        completedPaths.removeAll()
        currentPath = DrawingPath()
    }
    
    var hasDrawing: Bool {
        return !completedPaths.isEmpty || !currentPath.points.isEmpty
    }
}

struct DrawingPath: Identifiable, Codable {
    let id = UUID()
    var points: [CGPoint] = []
    let color: String = "red"
    let lineWidth: CGFloat = 3.0
    
    mutating func addPoint(_ point: CGPoint) {
        points.append(point)
    }
}

// MARK: - Viewer State
class ViewerState: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var selectedTag: OrganizerTag?
    @Published var playbackMode: PlaybackMode = .singleTag
    
    enum PlaybackMode {
        case singleTag
        case playlist
    }
}

// MARK: - Timeline Display Mode
enum TimelineDisplayMode: String, CaseIterable {
    case timeline = "Таймлайн"
    case table = "Таблица"
    
    var icon: String {
        switch self {
        case .timeline:
            return "timeline.selection"
        case .table:
            return "tablecells"
        }
    }
}

// MARK: - Timeline Filter
class TimelineFilter: ObservableObject {
    @Published var selectedTags: Set<String> = []
    @Published var selectedLabels: Set<String> = []
    @Published var selectedEvents: Set<String> = []
    @Published var isFilterActive: Bool = false
    
    func clearFilters() {
        selectedTags.removeAll()
        selectedLabels.removeAll()
        selectedEvents.removeAll()
        isFilterActive = false
    }
    
    func hasActiveFilters() -> Bool {
        return !selectedTags.isEmpty || !selectedLabels.isEmpty || !selectedEvents.isEmpty
    }
    
    func matches(stamp: TimelineStamp) -> Bool {
        if !isFilterActive || !hasActiveFilters() {
            return true
        }
        
        // Проверяем теги
        if !selectedTags.isEmpty && !selectedTags.contains(stamp.idTag) {
            return false
        }
        
        // Проверяем лейблы
        if !selectedLabels.isEmpty && selectedLabels.isDisjoint(with: stamp.labels) {
            return false
        }
        
        // Проверяем события
        if !selectedEvents.isEmpty && selectedEvents.isDisjoint(with: stamp.timeEvents) {
            return false
        }
        
        return true
    }
}

// MARK: - Video Playlist Manager
class VideoPlaylistManager: ObservableObject {
    @Published var currentPlaylist: [OrganizerTag] = []
    @Published var currentIndex: Int = 0
    @Published var isPlaying: Bool = false
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    
    func setPlaylist(_ tags: [OrganizerTag]) {
        currentPlaylist = tags
        currentIndex = 0
        stopPlayback()
    }
    
    func playPlaylist() {
        guard !currentPlaylist.isEmpty else { return }
        isPlaying = true
        // Логика воспроизведения плейлиста будет реализована в VideoView
    }
    
    func stopPlayback() {
        isPlaying = false
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    func playSingleTag(_ tag: OrganizerTag) {
        currentPlaylist = [tag]
        currentIndex = 0
        isPlaying = true
        
        // Отправляем уведомление для запуска воспроизведения
        NotificationCenter.default.post(name: .playSingleTag, object: tag)
    }
}

