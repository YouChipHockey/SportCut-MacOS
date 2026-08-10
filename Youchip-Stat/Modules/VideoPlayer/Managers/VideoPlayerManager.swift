//
//  VideoPlayerManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers
import Combine

class VideoPlayerManager: ObservableObject {
    
    static let shared = VideoPlayerManager()
    @Published var player: AVPlayer?
    @Published var playbackSpeed: Double = 1.0
    @Published var currentTime: Double = 0.0
    @Published var isPlaying: Bool = false
    @Published var isResizingTag: Bool = false // Track if user is resizing a tag
    /// Режим редактирования скриншота во вьюхе видео-окна (для обработки кнопки закрытия окна).
    var isVideoPlayerInEditorMode: Bool = false
    
    // MARK: - Live Mode
    @Published var isLiveMode: Bool = false
    @Published var isBroadcastActive: Bool = false
    
    // MARK: - Review Mode
    @Published var isReviewMode: Bool = false
    @Published var reviewPlayer: AVPlayer?
    @Published var reviewCurrentTime: Double = 0
    @Published var reviewPlaybackSpeed: Double = 1.0

    // MARK: - Review Screenshot Overlay
    @Published var reviewScreenshotImage: NSImage?
    @Published var isShowingReviewScreenshot: Bool = false

    private var reviewTimeObserver: Any?
    private var reviewFileVersionCancellable: AnyCancellable?
    private var reviewItemStatusObserver: AnyCancellable?
    /// Strong reference that keeps the pending review player alive until it reaches readyToPlay and is swapped in.
    private var pendingReviewPlayer: AVPlayer?
    private var shouldSeekReviewToEndOnNextReady = false
    
    var videoDuration: Double {
        if isLiveMode {
            return LiveStreamManager.shared.liveDuration
        }
        return player?.currentItem?.duration.seconds ?? 0
    }

    /// Duration used for timelines and real-time markup.
    /// In live mode it always includes a 5 second buffer after the current stream time.
    var timelineDuration: Double {
        if isLiveMode {
            return LiveStreamManager.shared.liveDuration + 5.0
        }
        return videoDuration
    }
    private var timeObserverToken: Any?
    private var isSeeking = false
    /// Пока активен, периодический observer не перезаписывает `currentTime` (скраб плейхэда по таймлайну).
    private var scrubTimelinePreviewSuppressUntil: Date?
    private var cancellables = Set<AnyCancellable>()
    private var liveDurationCancellable: AnyCancellable?
    
    func loadVideo(from url: URL) {
        isLiveMode = false
        isBroadcastActive = false
        isSeeking = false
        player = AVPlayer(url: url).applyDebugMuteIfNeeded()
        player?.play()
        startTimeObserver()
        observePlayerState()
    }
    
    // MARK: - Live Mode
    
    func startLiveMode() {
        isLiveMode = true
        isBroadcastActive = true
        player = nil // No AVPlayer in live mode - we use preview layer
        currentTime = 0.0
        
        // Observe live duration to update currentTime (skipped in review mode — review player drives currentTime then)
        liveDurationCancellable = LiveStreamManager.shared.$liveDuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                guard let self = self, self.isLiveMode, self.isBroadcastActive else { return }
                guard !self.isReviewMode else { return }
                self.currentTime = duration
            }
    }
    
    // MARK: - Review Mode
    
    private var isRefreshingReview: Bool = false
    
    func enterReviewMode() {
        guard isLiveMode else { return }
        isReviewMode = true
        shouldSeekReviewToEndOnNextReady = true
        LiveStreamManager.shared.startReviewRefresher()
        
        reviewFileVersionCancellable = LiveStreamManager.shared.$reviewFileVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshReviewPlayerItem()
            }
        refreshReviewPlayerItem()
    }
    
    func exitReviewMode() {
        isReviewMode = false
        shouldSeekReviewToEndOnNextReady = false
        reviewFileVersionCancellable?.cancel()
        reviewFileVersionCancellable = nil
        reviewItemStatusObserver?.cancel()
        reviewItemStatusObserver = nil

        if let token = reviewTimeObserver {
            reviewPlayer?.removeTimeObserver(token)
            reviewTimeObserver = nil
        }
        reviewPlayer?.pause()
        reviewPlayer = nil
        pendingReviewPlayer = nil
        reviewCurrentTime = 0
        isRefreshingReview = false
        reviewScreenshotImage = nil
        isShowingReviewScreenshot = false

        LiveStreamManager.shared.stopReviewRefresher()
    }
    
    func seekReview(to time: Double) {
        guard let player = reviewPlayer else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func seekReview(by seconds: Double) {
        let target = reviewCurrentTime + seconds
        let duration = reviewPlayer?.currentItem?.duration.seconds ?? 0
        let clamped = max(0, min(target, duration))
        seekReview(to: clamped)
    }
    
    func toggleReviewPlayPause() {
        guard let player = reviewPlayer else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.rate = Float(reviewPlaybackSpeed)
        }
    }
    
    func changeReviewPlaybackSpeed(to speed: Double) {
        reviewPlaybackSpeed = speed
        guard let player = reviewPlayer, player.timeControlStatus == .playing else { return }
        player.rate = Float(speed)
    }
    
    /// Returns the appropriate AVAsset for use in the Moment Viewer.
    func assetForMomentViewer(completion: @escaping (AVAsset?) -> Void) {
        if isReviewMode {
            completion(reviewPlayer?.currentItem?.asset)
        } else if isLiveMode {
            LiveStreamManager.shared.finalizeCurrentSegment { [weak self] in
                guard self != nil else { completion(nil); return }
                let segments = LiveStreamManager.shared.allSegmentURLs
                guard !segments.isEmpty else { completion(nil); return }
                Task {
                    let composition = await LiveStreamManager.shared.buildCompositionFromSegments(segments)
                    await MainActor.run { completion(composition) }
                }
            }
        } else {
            completion(player?.currentItem?.asset)
        }
    }
    
    private func refreshReviewPlayerItem() {
        let segmentURLs = LiveStreamManager.shared.allSegmentURLs
        guard !segmentURLs.isEmpty, !isRefreshingReview else { return }
        isRefreshingReview = true
        
        Task { [weak self] in
            guard let self = self else { return }
            
            let composition = await LiveStreamManager.shared.buildCompositionFromSegments(segmentURLs)
            
            await MainActor.run { [weak self] in
                guard let self = self, self.isReviewMode else {
                    self?.isRefreshingReview = false
                    return
                }
                
                let newItem = AVPlayerItem(asset: composition)
                let newPlayer = AVPlayer(playerItem: newItem)
                newPlayer.isMuted = true
                
                // Keep a STRONG reference so ARC doesn't destroy the player before readyToPlay fires.
                self.pendingReviewPlayer = newPlayer
                
                self.reviewItemStatusObserver?.cancel()
                self.reviewItemStatusObserver = newItem.publisher(for: \.status)
                    .filter { $0 == .readyToPlay || $0 == .failed }
                    .first()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] status in
                        guard let self = self, self.isReviewMode else {
                            self?.pendingReviewPlayer = nil
                            self?.isRefreshingReview = false
                            return
                        }
                        // Retrieve the pending player (held strongly by self.pendingReviewPlayer).
                        guard let pending = self.pendingReviewPlayer, status == .readyToPlay else {
                            self.pendingReviewPlayer = nil
                            self.isRefreshingReview = false
                            return
                        }
                        
                        let itemDuration = pending.currentItem?.duration.seconds ?? 0
                        let shouldSeekToEnd = self.shouldSeekReviewToEndOnNextReady && itemDuration > 0
                        let targetSeconds: Double
                        if shouldSeekToEnd {
                            targetSeconds = max(0, itemDuration - 0.05)
                            self.reviewCurrentTime = targetSeconds
                            self.currentTime = targetSeconds
                            self.shouldSeekReviewToEndOnNextReady = false
                        } else {
                            targetSeconds = self.reviewCurrentTime
                        }
                        let seekTarget = CMTime(seconds: targetSeconds, preferredTimescale: 600)
                        pending.seek(
                            to: seekTarget,
                            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
                            toleranceAfter:  CMTime(seconds: 0.5, preferredTimescale: 600)
                        ) { [weak self] _ in
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self, self.isReviewMode,
                                      let pending = self.pendingReviewPlayer else {
                                    self?.pendingReviewPlayer = nil
                                    self?.isRefreshingReview = false
                                    return
                                }
                                // Preserve the pause/play state of the previous player.
                                let wasPlaying = self.reviewPlayer?.timeControlStatus == .playing
                                
                                if let token = self.reviewTimeObserver {
                                    self.reviewPlayer?.removeTimeObserver(token)
                                    self.reviewTimeObserver = nil
                                }
                                self.setupReviewTimeObserver(for: pending)
                                
                                self.reviewPlayer?.pause()
                                pending.isMuted = AppConfig.isDebug
                                self.reviewPlayer = pending
                                self.pendingReviewPlayer = nil
                                if wasPlaying {
                                    pending.play()
                                } else {
                                    pending.pause()
                                }
                                self.isRefreshingReview = false
                            }
                        }
                    }
            }
        }
    }
    
    private func setupReviewTimeObserver(for player: AVPlayer) {
        if let token = reviewTimeObserver {
            player.removeTimeObserver(token)
            reviewTimeObserver = nil
        }
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        reviewTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, self.isReviewMode else { return }
            self.reviewCurrentTime = CMTimeGetSeconds(time)
            self.currentTime = self.reviewCurrentTime
        }
    }
    
    func stopBroadcast() {
        isBroadcastActive = false
        LiveStreamManager.shared.pauseBroadcast()
    }
    
    func resumeBroadcast() {
        isBroadcastActive = true
        LiveStreamManager.shared.resumeBroadcast()
    }
    
    /// При входе в редактор в режиме live — ставим трансляцию на паузу. При выходе — возобновляем.
    private var broadcastPausedForEditor: Bool = false
    
    func pauseBroadcastForEditor() {
        guard isLiveMode, isBroadcastActive else { return }
        broadcastPausedForEditor = true
        LiveStreamManager.shared.pauseBroadcast()
        isBroadcastActive = false
    }
    
    func resumeBroadcastFromEditor() {
        guard isLiveMode, broadcastPausedForEditor else { return }
        broadcastPausedForEditor = false
        LiveStreamManager.shared.resumeBroadcast()
        isBroadcastActive = true
    }
    
    /// Called when live stream ends and video file is ready. Transitions to normal playback mode.
    func transitionToStaticVideo(url: URL) {
        liveDurationCancellable?.cancel()
        liveDurationCancellable = nil
        isLiveMode = false
        isBroadcastActive = false
        loadVideo(from: url)
    }
    
    func endLiveMode() {
        exitReviewMode()
        liveDurationCancellable?.cancel()
        liveDurationCancellable = nil
        isLiveMode = false
        isBroadcastActive = false
    }
    /// Лёгкий seek во время перетаскивания плейхэда: обновляет картинку и `currentTime`, не снимая periodic observer.
    func seekForTimelineScrubPreview(to time: Double) {
        guard let player = player, !isLiveMode, !isReviewMode else { return }
        let dur = timelineDuration
        guard dur > 0 else { return }
        let t = max(0, min(time, dur))
        scrubTimelinePreviewSuppressUntil = Date().addingTimeInterval(0.14)
        currentTime = t
        let cm = CMTime(seconds: t, preferredTimescale: 600)
        let tol = CMTime(seconds: 0.06, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: tol, toleranceAfter: tol)
    }

    func seek(to time: Double, resumePlaybackAfterSeek: Bool = false) {
        guard let player = player else { return }
        scrubTimelinePreviewSuppressUntil = nil
        isSeeking = true
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        currentTime = time
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self else { return }
            self.isSeeking = false
            self.currentTime = self.player?.currentTime().seconds ?? time
            self.startTimeObserver()
            if resumePlaybackAfterSeek, finished {
                self.player?.play()
                self.player?.rate = Float(self.playbackSpeed)
            }
        }
    }
    func deleteVideo() {
        exitReviewMode()
        isSeeking = false
        player?.pause()
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player = nil
        currentTime = 0.0
        playbackSpeed = 1.0
        cancellables.removeAll()
        liveDurationCancellable?.cancel()
        liveDurationCancellable = nil
        isLiveMode = false
        isBroadcastActive = false
    }
    private func startTimeObserver() {
        guard let player = player else { return }
        // Higher update rate for smoother playhead and timeline auto-scroll.
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            guard !self.isSeeking else { return }
            if let u = self.scrubTimelinePreviewSuppressUntil, Date() < u { return }
            self.currentTime = CMTimeGetSeconds(time)
        }
    }
    func togglePlayPause() {
        guard let player = player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.rate = Float(playbackSpeed)
        }
    }
    func seek(by seconds: Double) {
        guard let player = player else { return }
        let actualCurrentTime = player.currentTime().seconds
        seek(to: actualCurrentTime + seconds)
    }
    func changePlaybackSpeed(to speed: Double) {
        playbackSpeed = speed
        player?.rate = Float(speed)
    }
    
    func getCurrentFrameRate() -> Float {
        guard let player = player,
              let asset = player.currentItem?.asset,
              let track = asset.tracks(withMediaType: .video).first else {
            return 30
        }
        
        return track.nominalFrameRate
    }
    
    func getCurrentVideoURL() -> URL? {
        return player?.currentItem?.asset as? AVURLAsset != nil ? (player?.currentItem?.asset as? AVURLAsset)?.url : nil
    }
    
    // MARK: - Helpers
    
    private func observePlayerState() {
        guard let player else { return }
        
        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                guard let welf = self else { return }

                if status == .playing {
                    if player.rate != Float(welf.playbackSpeed) {
                        player.rate = Float(welf.playbackSpeed)
                    }
                }
                DispatchQueue.main.async {
                    welf.isPlaying = (status == .playing)
                }
            }
            .store(in: &cancellables)
    }
}
