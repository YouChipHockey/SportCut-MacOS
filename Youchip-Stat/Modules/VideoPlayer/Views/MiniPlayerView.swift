//
//  MiniPlayerView.swift
//  Youchip-Stat
//
//  Created by Copilot on 6/25/25.
//

import SwiftUI
import AVKit
import AVFoundation
import Combine
import AppKit

struct MiniPlayerView: View {
    let stamp: TimelineStamp
    let initialVideoURL: URL?
    
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var isPlaying = false
    @State private var loopingPlayer: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var windowObservation: NSObjectProtocol?
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(^String.Titles.momentVideo)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
            
            ZStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(maxWidth: .infinity)
                } else if player != nil {
                    VideoPlayer(player: loopingPlayer)
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    Text(^String.Titles.videoUnavailable)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding([.horizontal, .bottom], 8)
        .onAppear {
            prepareVideoClip()
            setupWindowCloseObserver()
        }
        .onDisappear {
            stopAndCleanup()
            removeWindowCloseObserver()
        }
    }
    
    private func prepareVideoClip() {
        guard let videoURL = initialVideoURL else {
            isLoading = false
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: videoURL)
            let startTime = CMTime(seconds: stamp.startSeconds, preferredTimescale: 600)
            let endTime = CMTime(seconds: stamp.finishSeconds, preferredTimescale: 600)
            
            let bufferTime = CMTime(seconds: 0.5, preferredTimescale: 600)
            let adjustedStartTime = CMTimeSubtract(startTime, bufferTime)
            let adjustedEndTime = CMTimeAdd(endTime, bufferTime)
            
            let timeRange = CMTimeRange(start: max(CMTime.zero, adjustedStartTime), end: adjustedEndTime)
            
            let tempDirectoryURL = FileManager.default.temporaryDirectory
            let outputURL = tempDirectoryURL.appendingPathComponent("mini_player_clip_\(UUID().uuidString).mp4")
            
            let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality)
            exporter?.outputURL = outputURL
            exporter?.outputFileType = .mp4
            exporter?.timeRange = timeRange
            
            exporter?.exportAsynchronously {
                
                DispatchQueue.main.async {
                    if let error = exporter?.error {
                        print("Error exporting clip: \(error.localizedDescription)")
                        self.isLoading = false
                        return
                    }
                    
                    guard let outputURL = exporter?.outputURL else {
                        self.isLoading = false
                        return
                    }
                    
                    guard self.loopingPlayer == nil else {
                        try? FileManager.default.removeItem(at: outputURL)
                        return
                    }
                    
                    let playerItem = AVPlayerItem(url: outputURL)
                    let queuePlayer = AVQueuePlayer(playerItem: playerItem)
                    self.loopingPlayer = queuePlayer
                    self.looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
                    self.player = queuePlayer
                    
                    self.isLoading = false
                    self.isPlaying = true
                    queuePlayer.play()
                    
                    NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
                        .sink { _ in
                            try? FileManager.default.removeItem(at: outputURL)
                        }
                        .store(in: &self.cancellables)
                    
                    NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem)
                        .sink {_ in
                            self.loopingPlayer?.seek(to: .zero)
                            self.loopingPlayer?.play()
                        }
                        .store(in: &self.cancellables)
                }
            }
        }
    }
    
    private func togglePlayPause() {
        guard let player = self.loopingPlayer else { return }
        
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        
        isPlaying.toggle()
    }
    
    private func stopAndCleanup() {
        player?.pause()
        loopingPlayer?.pause()
        looper = nil
        loopingPlayer = nil
        player = nil
        cancellables.removeAll()
    }
    
    private func setupWindowCloseObserver() {
        if let window = NSApplication.shared.mainWindow {
            windowObservation = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main) { _ in
                    self.stopAndCleanup()
                }
        }
        
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .sink { _ in
                if self.isPlaying == true {
                    self.loopingPlayer?.pause()
                    self.isPlaying = false
                }
            }
            .store(in: &cancellables)
    }
    
    private func removeWindowCloseObserver() {
        if let observer = windowObservation {
            NotificationCenter.default.removeObserver(observer)
            windowObservation = nil
        }
    }
}
