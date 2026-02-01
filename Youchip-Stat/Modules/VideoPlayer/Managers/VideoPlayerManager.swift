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

class VideoPlayerManager: ObservableObject {
    
    static let shared = VideoPlayerManager()
    @Published var player: AVPlayer?
    @Published var playbackSpeed: Double = 1.0
    @Published var currentTime: Double = 0.0
    @Published var isResizingTag: Bool = false // Track if user is resizing a tag
    /// Режим редактирования скриншота во вьюхе видео-окна (для обработки кнопки закрытия окна).
    var isVideoPlayerInEditorMode: Bool = false
    var videoDuration: Double {
        player?.currentItem?.duration.seconds ?? 0
    }
    private var timeObserverToken: Any?
    
    func loadVideo(from url: URL) {
        player = AVPlayer(url: url)
        player?.play()
        startTimeObserver()
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
            player.play()
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
}
