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
    
    var videoDuration: Double {
        if isLiveMode {
            return LiveStreamManager.shared.liveDuration
        }
        return player?.currentItem?.duration.seconds ?? 0
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
        
        // Observe live duration to update currentTime
        liveDurationCancellable = LiveStreamManager.shared.$liveDuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                guard let self = self, self.isLiveMode, self.isBroadcastActive else { return }
                self.currentTime = duration
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
    
    /// Called when live stream ends and video file is ready. Transitions to normal playback mode.
    func transitionToStaticVideo(url: URL) {
        liveDurationCancellable?.cancel()
        liveDurationCancellable = nil
        isLiveMode = false
        isBroadcastActive = false
        loadVideo(from: url)
    }
    
    func endLiveMode() {
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
