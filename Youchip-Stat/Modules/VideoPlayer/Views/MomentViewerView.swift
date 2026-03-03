//
//  MomentViewerView.swift
//  Youchip-Stat
//

import SwiftUI
import AVKit
import AVFoundation

struct MomentViewerView: View {
    
    let asset: AVAsset
    let startTime: Double
    let duration: Double
    let tagName: String
    let lineName: String
    
    @State private var player: AVPlayer = AVPlayer()
    @State private var isPlayerReady: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: player)
                .onAppear { setupPlayer() }
                .background(Color.black)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tagName)
                        .font(.headline)
                    Text(lineName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatTime(startTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "Длительность: %.2f с", duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private func setupPlayer() {
        guard !isPlayerReady else { return }
        isPlayerReady = true
        
        let composition = AVMutableComposition()
        
        let videoTracks = asset.tracks(withMediaType: .video)
        let audioTracks = asset.tracks(withMediaType: .audio)
        guard let sourceVideoTrack = videoTracks.first,
              let compVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else { return }
        
        var compAudioTrack: AVMutableCompositionTrack? = nil
        if let sourceAudioTrack = audioTracks.first {
            compAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            _ = sourceAudioTrack // silence unused warning
        }
        
        let assetDuration = CMTimeGetSeconds(asset.duration)
        let safeStart = max(0.0, min(startTime, assetDuration))
        let maxAvailable = max(0.0, assetDuration - safeStart)
        let safeDuration = min(max(0.0, duration), maxAvailable)
        guard safeDuration > 0 else { return }
        
        let startCM = CMTime(seconds: safeStart, preferredTimescale: 600)
        let durationCM = CMTime(seconds: safeDuration, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startCM, duration: durationCM)
        
        do {
            try compVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
            if let compAudio = compAudioTrack, let sourceAudio = audioTracks.first {
                try compAudio.insertTimeRange(timeRange, of: sourceAudio, at: .zero)
            }
        } catch {
            return
        }
        
        let item = AVPlayerItem(asset: composition)
        player.replaceCurrentItem(with: item)
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        
        player.play()
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
