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
    
    private var reviewTimeObserver: Any?
    private var reviewFileVersionCancellable: AnyCancellable?
    private var reviewItemStatusObserver: AnyCancellable?
    /// Strong reference that keeps the pending review player alive until it reaches readyToPlay and is swapped in.
    private var pendingReviewPlayer: AVPlayer?
    
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
    private var cancellables = Set<AnyCancellable>()
    private var liveDurationCancellable: AnyCancellable?
    
    func loadVideo(from url: URL) {
        isLiveMode = false
        isBroadcastActive = false
        player = AVPlayer(url: url)
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
        LiveStreamManager.shared.startReviewRefresher()
        
        reviewFileVersionCancellable = LiveStreamManager.shared.$reviewFileVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshReviewPlayerItem()
            }
    }
    
    func exitReviewMode() {
        isReviewMode = false
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
            let segments = LiveStreamManager.shared.allSegmentURLs
            guard !segments.isEmpty else { completion(nil); return }
            Task {
                let composition = await LiveStreamManager.shared.buildCompositionFromSegments(segments)
                await MainActor.run { completion(composition) }
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
                        
                        let seekTarget = CMTime(seconds: self.reviewCurrentTime, preferredTimescale: 600)
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
                                pending.isMuted = false
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
    func seek(to time: Double) {
        guard let player = player else { return }
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self else { return }
            self.currentTime = self.player?.currentTime().seconds ?? time
            self.startTimeObserver()
        }
    }
    func deleteVideo() {
        exitReviewMode()
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
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = CMTimeGetSeconds(time)
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
            }
            .store(in: &cancellables)
    }
}
