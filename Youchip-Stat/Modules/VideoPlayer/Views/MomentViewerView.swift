//
//  MomentViewerView.swift
//  Youchip-Stat
//

import SwiftUI
import AVKit
import AVFoundation
import Combine

@MainActor
final class MomentViewerSession: ObservableObject {
    let player = AVPlayer()
    let tagName: String
    let lineName: String
    let displayStartTime: Double
    let displayDuration: Double
    
    private var endObserver: NSObjectProtocol?
    private var didInvalidate = false
    
    init(asset: AVAsset, startTime: Double, duration: Double, tagName: String, lineName: String) {
        self.tagName = tagName
        self.lineName = lineName
        self.displayStartTime = startTime
        self.displayDuration = duration
        configure(asset: asset, startTime: startTime, duration: duration)
    }
    
    private func configure(asset: AVAsset, startTime: Double, duration: Double) {
        let composition = AVMutableComposition()
        
        let videoTracks = asset.tracks(withMediaType: .video)
        let audioTracks = asset.tracks(withMediaType: .audio)
        guard let sourceVideoTrack = videoTracks.first,
              let compVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else { return }
        
        var compAudioTrack: AVMutableCompositionTrack?
        if audioTracks.first != nil {
            compAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
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
        
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.didInvalidate else { return }
            self.player.seek(to: .zero)
            self.player.play()
        }
        
        player.play()
    }
    
    func invalidate() {
        guard !didInvalidate else { return }
        didInvalidate = true
        
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

struct MomentViewerView: View {
    
    @ObservedObject var session: MomentViewerSession
    
    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: session.player)
                .background(Color.black)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.tagName)
                        .font(.headline)
                    Text(session.lineName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatClipTime(session.displayStartTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "Длительность: %.2f с", session.displayDuration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onDisappear {
            session.invalidate()
        }
    }
    
    private func formatClipTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
