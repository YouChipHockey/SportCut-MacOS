//
//  VideoPlayerManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import AVKit
import SwiftUI

class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var playbackSpeed: Double = 1.0
    
    static let shared = VideoPlayerManager()

    func loadVideo(from url: URL) {
        player = AVPlayer(url: url)
        player?.play()
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
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let newTime = currentTime + seconds
        let time = CMTime(seconds: newTime, preferredTimescale: 600)
        player.seek(to: time)
    }
    
    func changePlaybackSpeed(to speed: Double) {
        playbackSpeed = speed
        player?.rate = Float(speed)
    }
}
