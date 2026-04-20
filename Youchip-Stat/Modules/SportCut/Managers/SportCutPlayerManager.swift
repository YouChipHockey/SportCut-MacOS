//
//  SportCutPlayerManager.swift
//  Youchip-Stat
//

import Foundation
import AVFoundation
import Combine
import AppKit

enum SportCutPlaylistPlaybackKind {
    /// Как сейчас: отдельная композиция на клип, по окончании — следующий.
    case sequentialClips
    /// Все клипы плейлиста подряд в одном AVPlayerItem (кнопка play в ячейке).
    case singleFilm
}

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
    @Published var isEditorMode: Bool = false {
        didSet {
            NotificationCenter.default.post(name: .editorModeChanged, object: isEditorMode)
        }
    }
    @Published var editorDrawingState = EditorDrawingState()
    @Published var tempScreenshotImage: NSImage?
    @Published var editorScreenshotVideoTime: Double = 0
    @Published var isShowingDrawing: Bool = false
    @Published var displayedDrawingImage: NSImage?
    @Published var showDrawingWatermark: Bool = true
    @Published var editorDisplayDuration: Double = 3.0
    /// Tracks the drawing being edited so saveDrawing can replace it instead of appending.
    private(set) var editingDrawing: SportCutEventDrawing?
    private(set) var editingDrawingEventKey: String?
    /// User-positionable combined watermark (shared with mirror window via UserDefaults).
    @Published var watermarkDragOffset: CGSize = .zero
    private var shownDrawingNames: Set<String> = []
    private var drawingCheckTimer: AnyCancellable?
    
    private static let wmOffsetXKey = "SportCutWatermarkOffsetX"
    private static let wmOffsetYKey = "SportCutWatermarkOffsetY"
    /// Default anchor: left margin and bottom margin inside the video tile (points).
    static let watermarkLeadingInset: CGFloat = 20
    static let watermarkBottomInset: CGFloat = 40
    
    var sessionID: UUID?
    
    private var sources: [SportCutSource] = []
    private var loadedAssets: [UUID: AVAsset] = [:]
    private var timeObserver: Any?
    private var endObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    /// Tracks which sourceID is currently loaded as a direct file asset for resize preview.
    /// nil means the current item is a composition (normal playback), not a raw file preview.
    private var previewSourceID: UUID?
    
    private var playlistEvents: [SportCutEvent] = []
    @Published private(set) var playlistPlaybackKind: SportCutPlaylistPlaybackKind = .sequentialClips
    /// Per-event start time overrides from the playlist (keyed by `event.hiddenKey`).
    private var playlistStartOverrides: [String: Double] = [:]
    /// Per-event duration overrides from the playlist (keyed by `event.hiddenKey`).
    private var playlistDurationOverrides: [String: Double] = [:]
    /// Границы сегментов в «фильме» (секунды на оси склеенного таймлайна), по одному на элемент `playlistEvents`.
    private var filmSegmentStartSeconds: [Double] = []
    private var filmSegmentDurationSeconds: [Double] = []

    init() {
        let x = UserDefaults.standard.double(forKey: Self.wmOffsetXKey)
        let y = UserDefaults.standard.double(forKey: Self.wmOffsetYKey)
        watermarkDragOffset = CGSize(width: x, height: y)
        observePlayerState()
    }
    
    func commitWatermarkDrag(delta: CGSize, container: CGSize, watermark: CGSize) {
        watermarkDragOffset = CGSize(
            width: watermarkDragOffset.width + delta.width,
            height: watermarkDragOffset.height + delta.height
        )
        syncWatermarkOffsetWithinVideoBounds(container: container, watermark: watermark)
    }

    /// Keeps the stored drag offset consistent with the video rect after resize or layout.
    func syncWatermarkOffsetWithinVideoBounds(container: CGSize, watermark: CGSize) {
        guard watermark.width > 0.5, watermark.height > 0.5 else { return }
        let lead = Self.watermarkLeadingInset
        let bottom = Self.watermarkBottomInset
        let W = container.width
        let H = container.height
        let w = watermark.width
        let h = watermark.height
        guard W > 0, H > 0 else { return }
        let maxX = max(0, W - w)
        let maxYTop = max(0, H - h)
        let rawX = lead + watermarkDragOffset.width
        let rawYTop = H - bottom - h + watermarkDragOffset.height
        let x = min(max(rawX, 0), maxX)
        let yTop = min(max(rawYTop, 0), maxYTop)
        let next = CGSize(width: x - lead, height: yTop - (H - bottom - h))
        guard next != watermarkDragOffset else { return }
        watermarkDragOffset = next
        UserDefaults.standard.set(next.width, forKey: Self.wmOffsetXKey)
        UserDefaults.standard.set(next.height, forKey: Self.wmOffsetYKey)
    }

    var currentEventLabelNames: [String] {
        guard let event = currentEvent,
              let source = sources.first(where: { $0.id == event.sourceID }) else { return [] }
        return event.labelIDs.compactMap { labelID in
            source.findLabel(byID: labelID)?.name ?? labelID
        }
    }

    /// Local playback time within the current clip (0…clipDuration).
    /// In `.sequentialClips` mode this equals `currentTime` directly.
    /// In `.singleFilm` mode this converts the global film time to a per-segment local time.
    var currentClipLocalTime: Double {
        guard playlistPlaybackKind == .singleFilm,
              let (_, localTime) = filmEventIndexAndLocalTime(globalTime: currentTime) else {
            return currentTime
        }
        return localTime
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
        playlistPlaybackActive = false
        currentPlaylistID = nil
        loadSourceAndPlay(event: event)
    }
    
    // MARK: - Playlist playback
    
    func playPlaylist(
        _ events: [SportCutEvent],
        startIndex: Int = 0,
        playlistID: UUID? = nil,
        playbackKind: SportCutPlaylistPlaybackKind = .sequentialClips,
        autoPlayAfterLoad: Bool = true,
        onSeekComplete: (() -> Void)? = nil
    ) {
        guard !events.isEmpty else { return }
        let mapped: [SportCutEvent]
        if let sessionID,
           let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) {
            mapped = events.map { session.timelineResolvedEvent(for: $0) }
        } else {
            mapped = events
        }
        playlistEvents = mapped
        playlistPlaybackActive = true
        if let playlistID = playlistID {
            currentPlaylistID = playlistID
        }
        // Load duration overrides from the playlist, if available
        if let playlistID = playlistID,
           let sessionID,
           let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
           let playlist = session.playlistGroups.flatMap(\.playlists).first(where: { $0.id == playlistID }) {
            playlistStartOverrides = playlist.eventStartOverrides
            playlistDurationOverrides = playlist.eventDurationOverrides
        } else {
            playlistStartOverrides = [:]
            playlistDurationOverrides = [:]
        }

        if playbackKind == .singleFilm {
            currentPlaylistIndex = 0
            loadPlaylistAsSingleFilm(
                events: mapped,
                autoPlayAfterSeek: autoPlayAfterLoad,
                resumeGlobalAfterLoad: nil,
                onSeekFinished: onSeekComplete
            )
            return
        }

        guard startIndex < mapped.count else { return }
        currentPlaylistIndex = startIndex
        loadSourceAndPlay(
            event: mapped[startIndex],
            autoPlayAfterSeek: autoPlayAfterLoad,
            onSeekFinished: onSeekComplete
        )
    }

    /// Новый рисунок для эпизода плейлиста: если клип уже на экране — сразу захват кадра, иначе переключение без автоплея и затем редактор.
    func captureNewDrawingForPlaylistClip(event: SportCutEvent, visiblePlaylistEvents: [SportCutEvent], playlistID: UUID) {
        guard let idx = visiblePlaylistEvents.firstIndex(where: { $0.hiddenKey == event.hiddenKey }) else { return }

        let sameClipActive = playlistPlaybackActive
            && self.currentPlaylistID == playlistID
            && currentEvent?.hiddenKey == event.hiddenKey

        if sameClipActive {
            captureFrameForEditor()
            return
        }

        playPlaylist(
            visiblePlaylistEvents,
            startIndex: idx,
            playlistID: playlistID,
            autoPlayAfterLoad: false,
            onSeekComplete: { [weak self] in
                self?.captureFrameForEditor()
            }
        )
    }
    
    func advanceToNextEvent() {
        guard playlistPlaybackActive else { return }
        if playlistPlaybackKind == .singleFilm {
            advanceToNextPlaylist()
            return
        }
        let nextIndex = currentPlaylistIndex + 1
        if nextIndex < playlistEvents.count {
            currentPlaylistIndex = nextIndex
            loadSourceAndPlay(event: playlistEvents[nextIndex])
        } else {
            advanceToNextPlaylist()
        }
    }

    func handlePlaylistVisibilityChange(session: SportCutSession, playlistID: UUID) {
        guard let playlist = session.playlistGroups
            .flatMap(\.playlists)
            .first(where: { $0.id == playlistID }) else {
            if playlistPlaybackActive, currentPlaylistID == playlistID {
                stopPlayback()
            }
            return
        }

        if playlist.isHidden {
            guard playlistPlaybackActive, currentPlaylistID == playlistID else { return }
            advanceToNextPlaylist(session: session)
        } else if !playlistPlaybackActive, currentPlaylistID == playlistID, currentEvent == nil {
            let visible = playlist.events.filter { !playlist.hiddenEventKeys.contains($0.hiddenKey) }
            guard !visible.isEmpty else { return }
            playPlaylist(visible, startIndex: 0, playlistID: playlistID, playbackKind: .singleFilm)
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

        if playlistPlaybackKind == .singleFilm {
            let resolved = visible.map { session.timelineResolvedEvent(for: $0) }
            let resume = player.currentTime().seconds
            let go = isPlaying
            loadPlaylistAsSingleFilm(
                events: resolved,
                autoPlayAfterSeek: go,
                resumeGlobalAfterLoad: resume,
                onSeekFinished: nil
            )
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
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        playlistPlaybackActive = false
        playlistPlaybackKind = .sequentialClips
        filmSegmentStartSeconds = []
        filmSegmentDurationSeconds = []
        playlistStartOverrides = [:]
        previewSourceID = nil
        playlistDurationOverrides = [:]
        currentPlaylistIndex = -1
        playlistEvents = []
        currentEvent = nil
        currentPlaylistID = nil
        removeEndObserver()
    }
    
    func seek(by seconds: Double) {
        let current = player.currentTime().seconds
        let target = max(0, min(current + seconds, videoDuration > 0 ? videoDuration : .infinity))
        let cmTime = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Покадровая перемотка: +1 кадр (forward = true) или −1 кадр (forward = false).
    func stepFrame(forward: Bool) {
        guard let item = player.currentItem else { return }
        if isPlaying { pause() }
        item.step(byCount: forward ? 1 : -1)
    }

    /// Предпросмотр при ресайзе тега на таймлайне SportCut: время в **исходном видео**, плеер крутит локальное время внутри текущего клипа.
    func seekPreviewDuringResize(absoluteVideoTime: Double, stampID: UUID, sourceID: UUID) {
        guard playlistPlaybackKind != .singleFilm else { return }
        guard currentSourceID == sourceID,
              currentEvent?.stampID == stampID else { return }
        guard let ev = currentEvent else { return }
        let clipLocal = absoluteVideoTime - ev.startTime
        let maxLocal = max(ev.duration, 0.01)
        let t = max(0, min(clipLocal, maxLocal))
        let cm = CMTime(seconds: t, preferredTimescale: 600)
        let tol = CMTime(seconds: 0.08, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: tol, toleranceAfter: tol)
    }
    
    /// Seek to an absolute video time for preview during playlist edge resize.
    /// On first call for a sourceID (or after normal playback reset), loads the raw video file.
    /// On subsequent calls for the same sourceID, only seeks — no item replacement, no black flash.
    func seekPreviewForPlaylistResize(absoluteVideoTime: Double, sourceID: UUID) {
        player.pause()
        isPlaying = false

        let cm = CMTime(seconds: max(0, absoluteVideoTime), preferredTimescale: 600)
        let tol = CMTime(seconds: 0.05, preferredTimescale: 600)

        // If the raw file for this source is already loaded as the current item — just seek.
        // previewSourceID is nil when a composition is loaded (normal playback), so we
        // correctly reload on the first drag gesture after playback.
        if previewSourceID == sourceID {
            player.seek(to: cm, toleranceBefore: tol, toleranceAfter: tol)
            return
        }

        guard let source = sources.first(where: { $0.id == sourceID }) ?? {
            guard let sessionID,
                  let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
                  let s = session.sources.first(where: { $0.id == sourceID }) else { return nil }
            return s
        }() else { return }

        guard let url = source.resolveVideoURL() else { return }
        let asset: AVAsset
        if let cached = loadedAssets[sourceID] {
            asset = cached
        } else {
            asset = AVAsset(url: url)
            loadedAssets[sourceID] = asset
        }

        currentSourceID = sourceID
        previewSourceID = sourceID
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        player.seek(to: cm, toleranceBefore: tol, toleranceAfter: tol)
    }

    func changePlaybackSpeed(to speed: Double) {
        playbackSpeed = speed
        if isPlaying {
            player.rate = Float(speed)
        }
    }
    
    // MARK: - Source loading
    
    private func resolvedAgainstSession(_ event: SportCutEvent) -> SportCutEvent {
        guard let sessionID,
              let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else {
            return event
        }
        return session.timelineResolvedEvent(for: event)
    }

    private func loadPlaylistAsSingleFilm(
        events: [SportCutEvent],
        autoPlayAfterSeek: Bool = true,
        resumeGlobalAfterLoad: Double? = nil,
        onSeekFinished: (() -> Void)? = nil
    ) {
        playlistPlaybackKind = .singleFilm
        filmSegmentStartSeconds = []
        filmSegmentDurationSeconds = []
        shownDrawingNames.removeAll()

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            stopPlayback()
            return
        }
        var compAudioTrack: AVMutableCompositionTrack?

        var cursor = CMTime.zero
        var totalDuration: Double = 0
        var builtEvents: [SportCutEvent] = []

        for event in events {
            let ev = resolvedAgainstSession(event)
            guard let source = sources.first(where: { $0.id == ev.sourceID }),
                  let url = source.resolveVideoURL() else { continue }

            let asset: AVAsset
            if let cached = loadedAssets[ev.sourceID] {
                asset = cached
            } else {
                asset = AVAsset(url: url)
                loadedAssets[ev.sourceID] = asset
            }

            let assetDuration = CMTimeGetSeconds(asset.duration)
            let overrideStart = playlistStartOverrides[ev.hiddenKey] ?? ev.startTime
            let safeStart = max(0.0, min(overrideStart, assetDuration))
            let maxAvailable = max(0.0, assetDuration - safeStart)
            let overrideDuration = playlistDurationOverrides[ev.hiddenKey] ?? ev.duration
            let safeDuration = min(max(0.0, overrideDuration), maxAvailable)

            guard safeDuration > 0,
                  let sourceVideoTrack = asset.tracks(withMediaType: .video).first else { continue }

            let startCM = CMTime(seconds: safeStart, preferredTimescale: 600)
            let durationCM = CMTime(seconds: safeDuration, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startCM, duration: durationCM)

            do {
                try compVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: cursor)
                if let sourceAudioTrack = asset.tracks(withMediaType: .audio).first {
                    if compAudioTrack == nil {
                        compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    }
                    if let at = compAudioTrack {
                        try at.insertTimeRange(timeRange, of: sourceAudioTrack, at: cursor)
                    }
                }
            } catch {
                continue
            }

            filmSegmentStartSeconds.append(totalDuration)
            filmSegmentDurationSeconds.append(safeDuration)
            totalDuration += safeDuration
            builtEvents.append(ev)
            cursor = CMTimeAdd(cursor, durationCM)
        }

        guard totalDuration > 0, !builtEvents.isEmpty else {
            stopPlayback()
            return
        }

        playlistEvents = builtEvents
        currentPlaylistIndex = 0
        currentEvent = builtEvents[0]
        currentSourceID = builtEvents[0].sourceID

        previewSourceID = nil
        let playerItem = AVPlayerItem(asset: composition)
        player.replaceCurrentItem(with: playerItem)
        videoDuration = totalDuration

        setupEndObserver(item: playerItem)
        player.pause()
        isPlaying = false
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self, finished else { return }
            let finishLoad: () -> Void = {
                onSeekFinished?()
                if autoPlayAfterSeek {
                    self.play()
                }
            }
            if let rawResume = resumeGlobalAfterLoad {
                let t = min(max(0, rawResume), max(0, self.videoDuration - 0.05))
                self.player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    finishLoad()
                }
            } else {
                finishLoad()
            }
        }
    }

    private func filmEventIndexAndLocalTime(globalTime: Double) -> (index: Int, localTime: Double)? {
        guard playlistPlaybackKind == .singleFilm,
              !filmSegmentStartSeconds.isEmpty,
              filmSegmentStartSeconds.count == filmSegmentDurationSeconds.count,
              filmSegmentStartSeconds.count == playlistEvents.count else { return nil }
        let t = max(0, globalTime)
        let n = filmSegmentStartSeconds.count
        for i in 0..<n {
            let start = filmSegmentStartSeconds[i]
            let dur = filmSegmentDurationSeconds[i]
            let end = start + dur
            if i < n - 1 {
                if t >= start && t < end {
                    return (i, t - start)
                }
            } else {
                if t >= start {
                    return (i, min(max(0, t - start), dur))
                }
            }
        }
        return (0, 0)
    }

    private func updateFilmModeCurrentEventIfNeeded(globalTime: Double) {
        guard let (idx, _) = filmEventIndexAndLocalTime(globalTime: globalTime) else { return }
        if idx != currentPlaylistIndex {
            currentPlaylistIndex = idx
            currentEvent = resolvedAgainstSession(playlistEvents[idx])
            currentSourceID = playlistEvents[idx].sourceID
            shownDrawingNames.removeAll()
        }
    }

    private func loadSourceAndPlay(
        event: SportCutEvent,
        autoPlayAfterSeek: Bool = true,
        onSeekFinished: (() -> Void)? = nil
    ) {
        playlistPlaybackKind = .sequentialClips
        filmSegmentStartSeconds = []
        filmSegmentDurationSeconds = []
        let event = resolvedAgainstSession(event)
        currentEvent = event
        shownDrawingNames.removeAll()

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

        let composition = AVMutableComposition()
        let assetDuration = CMTimeGetSeconds(asset.duration)
        let overrideStart = playlistStartOverrides[event.hiddenKey] ?? event.startTime
        let safeStart = max(0.0, min(overrideStart, assetDuration))
        let maxAvailable = max(0.0, assetDuration - safeStart)
        let overrideDuration = playlistDurationOverrides[event.hiddenKey] ?? event.duration
        let safeDuration = min(max(0.0, overrideDuration), maxAvailable)

        guard safeDuration > 0,
              let sourceVideoTrack = asset.tracks(withMediaType: .video).first,
              let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            advanceToNextEvent()
            return
        }

        let startCM = CMTime(seconds: safeStart, preferredTimescale: 600)
        let durationCM = CMTime(seconds: safeDuration, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startCM, duration: durationCM)

        do {
            try compVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
            if let sourceAudioTrack = asset.tracks(withMediaType: .audio).first,
               let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
            }
        } catch {
            advanceToNextEvent()
            return
        }

        previewSourceID = nil
        let playerItem = AVPlayerItem(asset: composition)
        player.replaceCurrentItem(with: playerItem)
        videoDuration = safeDuration

        setupEndObserver(item: playerItem)
        player.pause()
        isPlaying = false
        let start = CMTime.zero
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self, finished else { return }
            onSeekFinished?()
            if autoPlayAfterSeek {
                self.play()
            }
        }
    }

    private func setupEndObserver(item: AVPlayerItem) {
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.playlistPlaybackActive {
                self.advanceToNextEvent()
            } else {
                self.pause()
            }
        }
    }

    private func removeEndObserver() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
    }
    
    func setupTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let sec = time.seconds
            self.currentTime = sec
            self.updateFilmModeCurrentEventIfNeeded(globalTime: sec)
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
        let globalT = time.seconds
        if playlistPlaybackKind == .singleFilm, let (idx, local) = filmEventIndexAndLocalTime(globalTime: globalT) {
            currentPlaylistIndex = idx
            currentEvent = resolvedAgainstSession(playlistEvents[idx])
            currentSourceID = playlistEvents[idx].sourceID
            editorScreenshotVideoTime = local
        } else {
            editorScreenshotVideoTime = globalT
        }
        editorDrawingState.clearDrawing()
        editorDrawingState.currentTool = .pencil
        editorDisplayDuration = 3.0
        editingDrawing = nil
        editingDrawingEventKey = nil
        isEditorMode = true
    }

    /// Opens the editor for an existing drawing.
    /// Loads the correct event's video, seeks to the drawing time, then opens the editor.
    func editExistingDrawing(drawing: SportCutEventDrawing, event: SportCutEvent, visiblePlaylistEvents: [SportCutEvent], playlistID: UUID) {
        guard let sessionID = sessionID else { return }

        editingDrawing = drawing
        editingDrawingEventKey = event.hiddenKey
        editorDisplayDuration = drawing.displayDuration

        // Load the correct event's video, seek to drawing time, then open editor
        let events = visiblePlaylistEvents
        guard let idx = events.firstIndex(where: { $0.hiddenKey == event.hiddenKey }) else { return }

        playPlaylist(events, startIndex: idx, playlistID: playlistID, autoPlayAfterLoad: false) { [weak self] in
            guard let self = self else { return }
            // Пересчёт: drawing.videoTime (оригинальный клип) → effective клип
            let absDrawingTime = event.startTime + drawing.videoTime
            let effectiveStart = self.playlistStartOverrides[event.hiddenKey] ?? event.startTime
            let effectiveLocalTime = max(0, absDrawingTime - effectiveStart)
            let seekTime = CMTime(seconds: effectiveLocalTime, preferredTimescale: 600)
            self.player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                DispatchQueue.main.async {
                    self.openEditorAfterSeek(drawing: drawing, sessionID: sessionID)
                }
            }
        }
    }

    private func openEditorAfterSeek(drawing: SportCutEventDrawing, sessionID: UUID) {
        let folder = SportCutPlayerManager.drawingsFolder(sessionID: sessionID)
        let imgURL = folder.appendingPathComponent(drawing.imageName)

        editorScreenshotVideoTime = drawing.videoTime
        editorDrawingState.clearDrawing()

        if let snapshot = drawing.editorState {
            // Capture the base frame from the video at drawing time to restore editor layers on top
            if let item = player.currentItem {
                let gen = AVAssetImageGenerator(asset: item.asset)
                gen.appliesPreferredTrackTransform = true
                gen.requestedTimeToleranceBefore = .zero
                gen.requestedTimeToleranceAfter = .zero
                let cmTime = player.currentTime()
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

    func saveDrawing() {
        let displayDuration = editorDisplayDuration
        guard let baseImage = tempScreenshotImage,
              let sessionID = sessionID,
              let playlistID = currentPlaylistID else { return }

        // Use the stored event key when editing an existing drawing,
        // otherwise fall back to the current event.
        let eventKey: String
        if let storedKey = editingDrawingEventKey {
            eventKey = storedKey
        } else if let event = currentEvent {
            eventKey = event.hiddenKey
        } else {
            return
        }

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

        // If editing an existing drawing, replace it; otherwise append.
        if var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) {
            for gi in session.playlistGroups.indices {
                if let pi = session.playlistGroups[gi].playlists.firstIndex(where: { $0.id == playlistID }) {
                    var arr = session.playlistGroups[gi].playlists[pi].eventDrawings[eventKey] ?? []

                    if let oldDrawing = editingDrawing,
                       let oldIdx = arr.firstIndex(where: { $0.imageName == oldDrawing.imageName }) {
                        // Replace old drawing with new one
                        arr[oldIdx] = drawing
                        // Delete old image file
                        let oldFile = folder.appendingPathComponent(oldDrawing.imageName)
                        try? FileManager.default.removeItem(at: oldFile)
                    } else {
                        arr.append(drawing)
                    }

                    session.playlistGroups[gi].playlists[pi].eventDrawings[eventKey] = arr
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
        editingDrawing = nil
        editingDrawingEventKey = nil
        // Kick the player: play then immediately pause to re-sync AVPlayer's internal state.
        // This ensures native playback controls and spacebar work after editor dismissal.
        player.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.player.pause()
        }
        // Restore key window and clear firstResponder so spacebar hotkey works.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let window = WindowsManager.shared.sportCutWindow?.window {
                window.makeKeyAndOrderFront(nil)
                if window.firstResponder is NSTextView || window.firstResponder is NSTextField {
                    window.makeFirstResponder(window.contentView)
                }
            }
        }
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
        guard let event = currentEvent else { return }

        let globalT = player.currentTime().seconds
        if playlistPlaybackKind == .singleFilm {
            updateFilmModeCurrentEventIfNeeded(globalTime: globalT)
        }
        // compareTime = локальное время внутри текущего клипа (с учётом overrides)
        let compareTime: Double
        if playlistPlaybackKind == .singleFilm, let (_, local) = filmEventIndexAndLocalTime(globalTime: globalT) {
            compareTime = local
        } else {
            compareTime = globalT
        }

        let drawings = currentEventDrawings()
        guard !drawings.isEmpty else { return }

        // Пересчёт: drawing.videoTime — локальное время в ОРИГИНАЛЬНОМ клипе.
        // Нужно перевести в локальное время EFFECTIVE клипа.
        let originalStart = event.startTime
        let effectiveStart = playlistStartOverrides[event.hiddenKey] ?? event.startTime
        let effectiveDuration = playlistDurationOverrides[event.hiddenKey] ?? event.duration

        guard let matched = drawings.first(where: { drawing in
            // Абсолютное время рисунка на исходном видео
            let absDrawingTime = originalStart + drawing.videoTime
            // Проверяем что рисунок попадает в effective границы клипа
            let effectiveEnd = effectiveStart + effectiveDuration
            guard absDrawingTime >= effectiveStart && absDrawingTime <= effectiveEnd else { return false }
            // Локальное время рисунка в effective клипе
            let effectiveLocalTime = absDrawingTime - effectiveStart
            return abs(effectiveLocalTime - compareTime) < 0.15 && !shownDrawingNames.contains(drawing.imageName)
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
