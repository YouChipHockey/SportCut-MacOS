//
//  SportCutPlayerManager.swift
//  Youchip-Stat
//

import Foundation
import AVFoundation
import Combine
import AppKit

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
    
    // Drawing editor state
    @Published var isEditorMode: Bool = false
    @Published var editorDrawingState = EditorDrawingState()
    @Published var tempScreenshotImage: NSImage?
    @Published var editorScreenshotVideoTime: Double = 0
    @Published var isShowingDrawing: Bool = false
    @Published var displayedDrawingImage: NSImage?
    @Published var showDrawingWatermark: Bool = true
    private var shownDrawingNames: Set<String> = []
    private var drawingCheckTimer: AnyCancellable?
    
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
        if isShowingDrawing {
            isShowingDrawing = false
            displayedDrawingImage = nil
        }
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
        shownDrawingNames.removeAll()
        
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

    // MARK: - Drawing editor

    func captureFrameForEditor() {
        guard currentPlaylistID != nil else { return }
        guard let item = player.currentItem else { return }
        let asset = item.asset
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        let time = player.currentTime()
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return }
        
        pause()
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        tempScreenshotImage = nsImage
        editorScreenshotVideoTime = time.seconds
        editorDrawingState.clearDrawing()
        editorDrawingState.currentTool = .pencil
        isEditorMode = true
    }

    func editExistingDrawing(drawing: SportCutEventDrawing) {
        guard let sessionID = sessionID else { return }
        let folder = SportCutPlayerManager.drawingsFolder(sessionID: sessionID)
        let imgURL = folder.appendingPathComponent(drawing.imageName)
        
        pause()
        editorScreenshotVideoTime = drawing.videoTime
        editorDrawingState.clearDrawing()
        
        if let snapshot = drawing.editorState {
            // Re-capture the base frame at drawing time to restore editor layers on top
            if let item = player.currentItem {
                let gen = AVAssetImageGenerator(asset: item.asset)
                gen.appliesPreferredTrackTransform = true
                gen.requestedTimeToleranceBefore = .zero
                gen.requestedTimeToleranceAfter = .zero
                let cmTime = CMTime(seconds: drawing.videoTime, preferredTimescale: 600)
                if let cg = try? gen.copyCGImage(at: cmTime, actualTime: nil) {
                    tempScreenshotImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                }
            }
            snapshot.apply(to: editorDrawingState)
        } else {
            tempScreenshotImage = NSImage(contentsOf: imgURL)
        }
        isEditorMode = true
    }

    func saveDrawing(displayDuration: Double = 3.0) {
        guard let baseImage = tempScreenshotImage,
              let sessionID = sessionID,
              let event = currentEvent,
              let playlistID = currentPlaylistID else { return }
        
        let finalImage = DrawingImageMerger.merge(baseImage: baseImage, drawingState: editorDrawingState)
        let editorSnapshot = EditorStateSnapshot.from(drawingState: editorDrawingState)
        
        let folder = SportCutPlayerManager.drawingsFolder(sessionID: sessionID)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let imageName = "drawing_\(playlistID.uuidString.prefix(8))_\(ts).png"
        let fileURL = folder.appendingPathComponent(imageName)
        
        if let tiffData = finalImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
        }
        
        let drawing = SportCutEventDrawing(
            imageName: imageName,
            videoTime: editorScreenshotVideoTime,
            displayDuration: displayDuration,
            editorState: editorSnapshot
        )
        
        if var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) {
            for gi in session.playlistGroups.indices {
                if let pi = session.playlistGroups[gi].playlists.firstIndex(where: { $0.id == playlistID }) {
                    var arr = session.playlistGroups[gi].playlists[pi].eventDrawings[event.hiddenKey] ?? []
                    arr.append(drawing)
                    session.playlistGroups[gi].playlists[pi].eventDrawings[event.hiddenKey] = arr
                    SportCutSessionManager.shared.updateSession(session)
                    break
                }
            }
        }
        
        cancelEditor()
    }

    func cancelEditor() {
        isEditorMode = false
        tempScreenshotImage = nil
        editorDrawingState.clearDrawing()
    }

    func hideDrawingOverlay(resume: Bool = true) {
        isShowingDrawing = false
        displayedDrawingImage = nil
        if resume { play() }
    }

    func currentEventDrawings() -> [SportCutEventDrawing] {
        guard let sessionID = sessionID,
              let playlistID = currentPlaylistID,
              let event = currentEvent,
              let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
              let playlist = session.playlistGroups.flatMap(\.playlists).first(where: { $0.id == playlistID }) else { return [] }
        return playlist.eventDrawings[event.hiddenKey] ?? []
    }

    func startDrawingCheckTimer() {
        drawingCheckTimer?.cancel()
        drawingCheckTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkForDrawingAtCurrentTime()
            }
    }

    func stopDrawingCheckTimer() {
        drawingCheckTimer?.cancel()
        drawingCheckTimer = nil
    }

    private func checkForDrawingAtCurrentTime() {
        guard !isEditorMode, !isShowingDrawing, currentPlaylistID != nil else { return }
        guard let sessionID = sessionID else { return }
        
        let ct = player.currentTime().seconds
        let drawings = currentEventDrawings()
        guard !drawings.isEmpty else { return }
        
        guard let matched = drawings.first(where: {
            abs($0.videoTime - ct) < 0.15 && !shownDrawingNames.contains($0.imageName)
        }) else { return }
        
        let folder = SportCutPlayerManager.drawingsFolder(sessionID: sessionID)
        let imgURL = folder.appendingPathComponent(matched.imageName)
        guard let nsImage = NSImage(contentsOf: imgURL) else { return }
        
        pause()
        displayedDrawingImage = nsImage
        isShowingDrawing = true
        shownDrawingNames.insert(matched.imageName)
    }

    func deleteDrawing(_ drawing: SportCutEventDrawing) {
        guard let sessionID = sessionID,
              let playlistID = currentPlaylistID,
              let event = currentEvent else { return }

        if var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) {
            for gi in session.playlistGroups.indices {
                if let pi = session.playlistGroups[gi].playlists.firstIndex(where: { $0.id == playlistID }) {
                    var arr = session.playlistGroups[gi].playlists[pi].eventDrawings[event.hiddenKey] ?? []
                    arr.removeAll { $0.imageName == drawing.imageName }
                    if arr.isEmpty {
                        session.playlistGroups[gi].playlists[pi].eventDrawings.removeValue(forKey: event.hiddenKey)
                    } else {
                        session.playlistGroups[gi].playlists[pi].eventDrawings[event.hiddenKey] = arr
                    }
                    let folder = SportCutPlayerManager.drawingsFolder(sessionID: sessionID)
                    try? FileManager.default.removeItem(at: folder.appendingPathComponent(drawing.imageName))
                    SportCutSessionManager.shared.updateSession(session)
                    break
                }
            }
        }
    }

    static func drawingsFolder(sessionID: UUID) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("SportCutDrawings").appendingPathComponent(sessionID.uuidString)
    }

    private func observePlayerState() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                let playing = (status == .playing)
                self.isPlaying = playing
                if playing && self.isShowingDrawing {
                    self.isShowingDrawing = false
                    self.displayedDrawingImage = nil
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        removeTimeObserver()
        removeEndObserver()
        stopDrawingCheckTimer()
    }
}
