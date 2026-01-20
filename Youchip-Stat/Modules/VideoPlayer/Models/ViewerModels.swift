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
import Combine

extension Notification.Name {
    static let playSingleTag = Notification.Name("playSingleTag")
    static let toggleViewerPlayer = Notification.Name("toggleViewerPlayer")
    static let stopViewerPlayer = Notification.Name("stopViewerPlayer")
    static let closeViewerWindow = Notification.Name("closeViewerWindow")
    static let createPlaylistComposition = Notification.Name("createPlaylistComposition")
    static let seekViewerPlayerForward = Notification.Name("seekViewerPlayerForward")
    static let seekViewerPlayerBackward = Notification.Name("seekViewerPlayerBackward")
}

class PlaylistManager: ObservableObject {
    @Published var playlists: [SavedPlaylist] = [] {
        didSet {
            savePlaylists()
        }
    }
    @Published var currentPlaylistId: UUID?
    @Published var currentTags: [OrganizerTag] = []
    
    var currentPlaylist: SavedPlaylist? {
        guard let currentPlaylistId else { return nil }
        return playlists.first(where: { $0.id == currentPlaylistId })
    }
    
    private let videoID: String
    private var playlistsKey: String {
        return "SavedPlaylists_\(videoID)"
    }
    
    init(videoID: String) {
        self.videoID = videoID
        loadPlaylists()
    }
    
    var isPlaylistModified: Bool {
        guard let current = currentPlaylist else { return false }
        return current.tags.count != currentTags.count ||
               !current.tags.elementsEqual(currentTags, by: { $0.stampID == $1.stampID })
    }
    
    func createNewPlaylist() {
        currentPlaylistId = nil
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
        currentPlaylistId = newPlaylist.id
    }
    
    func updateCurrentPlaylist() {
        guard let current = currentPlaylist, !currentTags.isEmpty else { return }
        
        let updatedPlaylist = SavedPlaylist(
            id: current.id,
            name: current.name,
            tags: currentTags,
            createdAt: current.createdAt
        )
        
        if let index = playlists.firstIndex(where: { $0.id == current.id }) {
            playlists[index] = updatedPlaylist
            currentPlaylistId = updatedPlaylist.id
        }
    }
    
    func loadPlaylist(_ playlist: SavedPlaylist) {
        currentPlaylistId = playlist.id
        currentTags = playlist.tags
    }
    
    func deletePlaylist(_ playlist: SavedPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        if currentPlaylist?.id == playlist.id {
            createNewPlaylist()
            NotificationCenter.default.post(name: .stopViewerPlayer, object: nil)
        }
    }
    
    func addTag(_ tag: OrganizerTag) {
        if !currentTags.contains(where: { $0.stampID == tag.stampID }) {
            currentTags.append(tag)
        }
    }
    
    func removeTag(at index: Int) {
        guard index < currentTags.count else { return }
        currentTags.remove(at: index)
    }
    
    func moveTag(from source: IndexSet, to destination: Int) {
        currentTags.move(fromOffsets: source, toOffset: destination)
    }
    
    func clear() {
        currentTags.removeAll()
        currentPlaylistId = nil
        NotificationCenter.default.post(name: .stopViewerPlayer, object: nil)
    }
    
    private func savePlaylists() {
        do {
            let data = try JSONEncoder().encode(playlists)
            UserDefaults.standard.set(data, forKey: playlistsKey)
        } catch {
            print(error)
        }
    }
    
    func loadPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: playlistsKey) else { return }
        
        do {
            playlists = try JSONDecoder().decode([SavedPlaylist].self, from: data)
        } catch {
            playlists = []
        }
    }

    func renamePlaylist(withId id: UUID, newName: String) {
        guard var playlistIndex = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[playlistIndex].updateName(newName)
    }
}

struct SavedPlaylist: Identifiable, Codable {
    let id: UUID
    var name: String
    let tags: [OrganizerTag]
    let createdAt: Date
    
    var tagCount: Int {
        return tags.count
    }
    
    var duration: Double {
        return tags.reduce(0) { $0 + $1.duration }
    }
    
    mutating func updateName(_ name: String) {
        self.name = name
    }
}

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
    let id : UUID
    let mainTagID: String
    let stampID: UUID
    let lineID: UUID
    let tagName: String
    let lineName: String
    let startTime: Double
    let duration: Double
    let color: String
    let tagGroupName: String?
    let labelIDs: [String]
    let eventIDs: [String]
    
    init(stampID: UUID, mainTagID: String, lineID: UUID, tagName: String, lineName: String, startTime: Double, duration: Double, color: String, tagGroupName: String? = nil, labelIDs: [String] = [], eventIDs: [String] = []) {
        self.id = UUID()
        self.mainTagID = mainTagID
        self.stampID = stampID
        self.lineID = lineID
        self.tagName = tagName
        self.lineName = lineName
        self.startTime = startTime
        self.duration = duration
        self.color = color
        self.tagGroupName = tagGroupName
        self.labelIDs = labelIDs
        self.eventIDs = eventIDs
    }
    
    static func == (lhs: OrganizerTag, rhs: OrganizerTag) -> Bool {
        return lhs.stampID == rhs.stampID
    }
}

enum ViewerExportMode {
    case archive
    case film
}

enum DrawingTool {
    case pencil
    case eraser
}

enum DrawingLineStyle: Codable {
    case solid
    case dashed
    
    var dashPattern: [CGFloat]? {
        switch self {
        case .solid:
            return nil
        case .dashed:
            return [10, 5]
        }
    }
}

class DrawingSettings: ObservableObject {
    @Published var lineWidth: CGFloat = 3.0
    @Published var lineStyle: DrawingLineStyle = .solid
    @Published var color: Color = .red
    @Published var eraserWidth: CGFloat = 20.0
}

class DrawingState: ObservableObject {
    @Published var isDrawingMode: Bool = false
    @Published var showDrawingMenu: Bool = false
    @Published var currentTool: DrawingTool = .pencil
    @Published var currentPath: DrawingPath = DrawingPath()
    @Published var completedPaths: [DrawingPath] = []
    @Published var currentTime: Double = 0.0
    @Published var settings = DrawingSettings()
    @Published var viewSize: CGSize = .zero
    
    func startNewPath(at point: CGPoint) {
        if currentTool == .pencil {
            currentPath = DrawingPath(
                color: settings.color,
                lineWidth: settings.lineWidth,
                lineStyle: settings.lineStyle
            )
            currentPath.addPoint(point)
        } else {
            eraseAt(point)
        }
    }
    
    func addPoint(_ point: CGPoint) {
        if currentTool == .pencil {
            currentPath.addPoint(point)
        } else {
            eraseAt(point)
        }
    }
    
    func finishPath() {
        if currentTool == .pencil && !currentPath.points.isEmpty {
            completedPaths.append(currentPath)
            currentPath = DrawingPath()
        }
    }
    
    func eraseAt(_ point: CGPoint) {
        let eraserRadius = settings.eraserWidth / 2
        completedPaths.removeAll { path in
            path.points.contains { pathPoint in
                let distance = hypot(pathPoint.x - point.x, pathPoint.y - point.y)
                return distance < eraserRadius
            }
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
    var id = UUID()
    var points: [CGPoint] = []
    var colorHex: String
    var lineWidth: CGFloat
    var lineStyle: DrawingLineStyle
    
    var color: Color {
        Color(hex: colorHex)
    }
    
    init(color: Color = .red, lineWidth: CGFloat = 3.0, lineStyle: DrawingLineStyle = .solid) {
        self.colorHex = color.toHex() ?? "FF0000"
        self.lineWidth = lineWidth
        self.lineStyle = lineStyle
    }
    
    mutating func addPoint(_ point: CGPoint) {
        points.append(point)
    }
}

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

enum TimelineDisplayMode: String, CaseIterable {
    case timeline
    case table
    
    var localizedName: String {
        switch self {
        case .timeline:
            return ^String.Titles.timelineView
        case .table:
            return ^String.Titles.table
        }
    }
    
    var icon: String {
        switch self {
        case .timeline:
            return "timeline.selection"
        case .table:
            return "tablecells"
        }
    }
}

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
        
        if !selectedTags.isEmpty && !selectedTags.contains(stamp.idTag) {
            return false
        }
        
        if !selectedLabels.isEmpty && selectedLabels.isDisjoint(with: stamp.labels) {
            return false
        }
        
        if !selectedEvents.isEmpty && selectedEvents.isDisjoint(with: stamp.timeEvents) {
            return false
        }
        
        return true
    }
}

class VideoPlaylistManager: ObservableObject {
    @Published var currentPlaylist: [OrganizerTag] = [] {
        didSet {
            if isPlaying {
                createCompositionFromPlaylist()
            }
        }
    }
    @Published var currentIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var playbackSpeed: Double = 1.0
    @Published private(set) var currentComposition: AVMutableComposition?
    private(set) var compositionSegments: [CompositionSegment] = []
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var startViewerPlayerObserver: Any?
    private var seekForwardPlayerObserver: Any?
    private var seekBackwardPlayerObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        startViewerPlayerObserver = NotificationCenter.default.addObserver(
            forName: .toggleViewerPlayer,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.togglePlayback()
        }
        seekForwardPlayerObserver = NotificationCenter.default.addObserver(
            forName: .seekViewerPlayerForward,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.seek(by: 3)
        }
        seekBackwardPlayerObserver = NotificationCenter.default.addObserver(
            forName: .seekViewerPlayerBackward,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.seek(by: -3)
        }
    }
    
    deinit {
        if let startViewerPlayerObserver {
            NotificationCenter.default.removeObserver(startViewerPlayerObserver)
        }
        if let seekForwardPlayerObserver {
            NotificationCenter.default.removeObserver(seekForwardPlayerObserver)
        }
        if let seekBackwardPlayerObserver {
            NotificationCenter.default.removeObserver(seekBackwardPlayerObserver)
        }
    }
    
    func playVideo(_ play: Bool, changePlayerStatus: Bool = true) {
        guard isPlaying != play else { return }
        isPlaying = play
        if play {
            player?.rate = Float(playbackSpeed)
        }
        guard changePlayerStatus else { return }
        if play {
            player?.play()
        } else {
            player?.pause()
        }
    }
    
    func setPlayer(_ player: AVPlayer?) {
        self.player = player
        if player == nil {
            cancellables.removeAll()
        } else {
            observePlayerState()
        }
    }
    
    func setPlaylist(_ tags: [OrganizerTag]) {
        currentPlaylist = tags
        currentIndex = 0
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        playVideo(false)
    }
    
    func stopPlayback() {
        playVideo(false)
    }
    
    func togglePlayback() {
        playVideo(!isPlaying)
    }
    
    func seek(by seconds: Double) {
        guard let player else { return }
        let actualCurrentTime = player.currentTime().seconds
        let seekToTime = actualCurrentTime + seconds

        let cmTime = CMTime(seconds: seekToTime, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)

    }
    func changePlaybackSpeed(to speed: Double) {
        playbackSpeed = speed
        player?.rate = Float(speed)
    }
    
    func playSingleTag(_ tag: OrganizerTag) {
        currentPlaylist = [tag]
        currentIndex = 0
        
        NotificationCenter.default.post(name: .playSingleTag, object: tag)
    }
    
    private func observePlayerState() {
        guard let player else { return }
        
        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                self?.playVideo(status == .playing, changePlayerStatus: false)
            }
            .store(in: &cancellables)
    }
    
    func createCompositionFromPlaylist() {
        guard let originalAsset = VideoPlayerManager.shared.player?.currentItem?.asset else {
            return
        }
        
        let composition = AVMutableComposition()
        
        guard let videoTrack = originalAsset.tracks(withMediaType: .video).first,
              let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return
        }
        
        let audioTrack = originalAsset.tracks(withMediaType: .audio).first
        var compAudioTrack: AVMutableCompositionTrack? = nil
        if let audioTrack = audioTrack {
            compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        
        var currentTime = CMTime.zero
        var compositionSegments: [CompositionSegment] = []
        
        for tag in currentPlaylist {
            let startTime = CMTime(seconds: tag.startTime, preferredTimescale: 600)
            let duration = CMTime(seconds: tag.duration, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, duration: duration)
            
            do {
                try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: currentTime)
                if let compAudio = compAudioTrack, let aTrack = audioTrack {
                    try compAudio.insertTimeRange(timeRange, of: aTrack, at: currentTime)
                }
                let compositionRange = CMTimeRange(start: currentTime, duration: duration)
                compositionSegments.append(.init(compositionRange: compositionRange, tag: tag))
                currentTime = currentTime + duration
            } catch {
                return
            }
        }
        
        self.compositionSegments = compositionSegments
        currentComposition = composition
        let playerItem = AVPlayerItem(asset: composition)
        player?.replaceCurrentItem(with: playerItem)
        playVideo(true)
        NotificationCenter.default.post(
            name: .createPlaylistComposition,
            object: nil)
    }

}

