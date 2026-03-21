//
//  SportCutPlayerManager.swift
//  Youchip-Stat
//

import Foundation
import AVFoundation
import Combine

class SportCutPlayerManager: ObservableObject {
    @Published var player: AVPlayer = AVPlayer()
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var videoDuration: Double = 0
    @Published var playbackSpeed: Double = 1.0
    @Published var currentSourceID: UUID?
    @Published var currentEvent: SportCutEvent?
    @Published var currentPlaylistIndex: Int = -1
    @Published var playlistPlaybackActive: Bool = false
    @Published var currentPlaylistID: UUID?
    @Published var showCommentsWatermark: Bool = true
    @Published var showEventDataWatermark: Bool = true
    
    var sessionID: UUID?
    
    private var sources: [SportCutSource] = []
    private var loadedAssets: [UUID: AVAsset] = [:]
    private var timeObserver: Any?
    private var endObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    private var playlistEvents: [SportCutEvent] = []

    init() {
        observePlayerState()
    }

    var currentEventLabelNames: [String] {
        guard let event = currentEvent,
              let source = sources.first(where: { $0.id == event.sourceID }) else { return [] }
        return event.labelIDs.compactMap { labelID in
            source.findLabel(byID: labelID)?.name ?? labelID
        }
    }

    var currentEventComment: String? {
        guard let sessionID = sessionID,
              let playlistID = currentPlaylistID,
              let event = currentEvent,
              let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
              let playlist = session.playlistGroups.flatMap(\.playlists).first(where: { $0.id == playlistID }) else { return nil }

        let raw = playlist.eventComments[event.hiddenKey] ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    func configure(sources: [SportCutSource]) {
        self.sources = sources
        loadedAssets.removeAll()
    }
    
    // MARK: - Single event playback
    
    func playEvent(_ event: SportCutEvent) {
        currentEvent = event
        playlistPlaybackActive = false
        currentPlaylistID = nil
        loadSourceAndPlay(event: event)
    }
    
    // MARK: - Playlist playback
    
    func playPlaylist(_ events: [SportCutEvent], startIndex: Int = 0, playlistID: UUID? = nil) {
        guard !events.isEmpty, startIndex < events.count else { return }
        playlistEvents = events
        currentPlaylistIndex = startIndex
        playlistPlaybackActive = true
        if let playlistID = playlistID {
            currentPlaylistID = playlistID
        }
        loadSourceAndPlay(event: events[startIndex])
    }
    
    func advanceToNextEvent() {
        guard playlistPlaybackActive else { return }
        let nextIndex = currentPlaylistIndex + 1
        if nextIndex < playlistEvents.count {
            currentPlaylistIndex = nextIndex
            loadSourceAndPlay(event: playlistEvents[nextIndex])
        } else {
            advanceToNextPlaylist()
        }
    }

    func handlePlaylistVisibilityChange(session: SportCutSession, playlistID: UUID) {
        guard playlistPlaybackActive, currentPlaylistID == playlistID else { return }
        guard let playlist = session.playlistGroups
            .flatMap(\.playlists)
            .first(where: { $0.id == playlistID }) else {
            stopPlayback()
            return
        }

        if playlist.isHidden {
            advanceToNextPlaylist(session: session)
        }
    }

    func handleEventVisibilityChange(session: SportCutSession, playlistID: UUID, changedEvent: SportCutEvent) {
        guard playlistPlaybackActive, currentPlaylistID == playlistID else { return }
        guard let playlist = session.playlistGroups
            .flatMap(\.playlists)
            .first(where: { $0.id == playlistID }) else {
            stopPlayback()
            return
        }

        let visible = playlist.events.filter { !playlist.hiddenEventKeys.contains($0.hiddenKey) }
        playlistEvents = visible

        // If no visible events remain in current playlist, jump to next available playlist.
        guard !visible.isEmpty else {
            advanceToNextPlaylist(session: session)
            return
        }

        guard currentEvent == changedEvent else {
            if let current = currentEvent, let idx = visible.firstIndex(of: current) {
                currentPlaylistIndex = idx
            }
            return
        }

        // Current event was hidden. Move to the next visible event in this playlist.
        let allEvents = playlist.events
        let changedIndex = allEvents.firstIndex(of: changedEvent) ?? -1
        let nextVisible = allEvents.dropFirst(max(0, changedIndex + 1)).first {
            !playlist.hiddenEventKeys.contains($0.hiddenKey)
        }
        let target = nextVisible ?? visible.first
        guard let targetEvent = target, let targetIndex = visible.firstIndex(of: targetEvent) else {
            advanceToNextPlaylist(session: session)
            return
        }

        currentPlaylistIndex = targetIndex
        loadSourceAndPlay(event: targetEvent)
    }
    
    private func advanceToNextPlaylist(session: SportCutSession? = nil) {
        let resolvedSession: SportCutSession?
        if let session {
            resolvedSession = session
        } else if let sessionID = sessionID {
            resolvedSession = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID })
        } else {
            resolvedSession = nil
        }

        guard let currentPlaylistID = currentPlaylistID,
              let session = resolvedSession else {
            stopPlayback()
            return
        }
        
        let allPlaylists = session.playlistGroups.flatMap(\.playlists)
        guard let currentIdx = allPlaylists.firstIndex(where: { $0.id == currentPlaylistID }) else {
            stopPlayback()
            return
        }
        
        var nextIdx = currentIdx + 1
        while nextIdx < allPlaylists.count {
            let candidate = allPlaylists[nextIdx]
            let candidateVisibleEvents = candidate.events.filter { !candidate.hiddenEventKeys.contains($0.hiddenKey) }
            if !candidate.isHidden && !candidateVisibleEvents.isEmpty {
                self.currentPlaylistID = candidate.id
                playlistEvents = candidateVisibleEvents
                currentPlaylistIndex = 0
                loadSourceAndPlay(event: candidateVisibleEvents[0])
                return
            }
            nextIdx += 1
        }
        
        stopPlayback()
    }
    
    func jumpToPlaylistEvent(at index: Int) {
        guard playlistPlaybackActive, index < playlistEvents.count else { return }
        currentPlaylistIndex = index
        loadSourceAndPlay(event: playlistEvents[index])
    }
    
    // MARK: - Playback controls
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func play() {
        player.rate = Float(playbackSpeed)
        isPlaying = true
    }
    
    func pause() {
        player.pause()
        isPlaying = false
    }
    
    func stopPlayback() {
        player.pause()
        isPlaying = false
        playlistPlaybackActive = false
        currentPlaylistIndex = -1
        playlistEvents = []
        currentEvent = nil
        currentPlaylistID = nil
        removeEndObserver()
    }
    
    func seek(by seconds: Double) {
        let current = player.currentTime().seconds
        let target = max(0, current + seconds)
        let cmTime = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func changePlaybackSpeed(to speed: Double) {
        playbackSpeed = speed
        if isPlaying {
            player.rate = Float(speed)
        }
    }
    
    // MARK: - Source loading
    
    private func loadSourceAndPlay(event: SportCutEvent) {
        currentEvent = event
        
        if currentSourceID == event.sourceID, player.currentItem != nil {
            let seekTime = CMTime(seconds: event.startTime, preferredTimescale: 600)
            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
            setupEndObserver(for: event)
            play()
            return
        }
        
        guard let source = sources.first(where: { $0.id == event.sourceID }),
              let url = source.resolveVideoURL() else {
            advanceToNextEvent()
            return
        }
        
        let asset: AVAsset
        if let cached = loadedAssets[event.sourceID] {
            asset = cached
        } else {
            asset = AVAsset(url: url)
            loadedAssets[event.sourceID] = asset
        }
        
        currentSourceID = event.sourceID
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
        
        let seekTime = CMTime(seconds: event.startTime, preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        videoDuration = CMTimeGetSeconds(asset.duration)
        
        setupEndObserver(for: event)
        play()
    }
    
    private func setupEndObserver(for event: SportCutEvent) {
        removeEndObserver()
        
        let endTime = CMTime(seconds: event.startTime + event.duration, preferredTimescale: 600)
        let times = [NSValue(time: endTime)]
        
        endObserver = player.addBoundaryTimeObserver(forTimes: times, queue: .main) { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if self.playlistPlaybackActive {
                    self.advanceToNextEvent()
                } else {
                    self.pause()
                }
            }
        }
    }
    
    private func removeEndObserver() {
        if let observer = endObserver {
            player.removeTimeObserver(observer)
            endObserver = nil
        }
    }
    
    func setupTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }
    
    func removeTimeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func observePlayerState() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.isPlaying = (status == .playing)
            }
            .store(in: &cancellables)
    }
    
    deinit {
        removeTimeObserver()
        removeEndObserver()
    }
}
