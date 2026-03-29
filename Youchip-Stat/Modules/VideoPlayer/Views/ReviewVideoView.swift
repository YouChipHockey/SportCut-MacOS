//
//  ReviewVideoView.swift
//  Youchip-Stat
//

import SwiftUI
import AVKit

struct ReviewVideoView: View {
    
    @ObservedObject private var videoManager = VideoPlayerManager.shared
    @ObservedObject private var liveStreamManager = LiveStreamManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            reviewToolbar
            Divider()
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let player = videoManager.reviewPlayer {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Загрузка записи...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                // Version badge
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("Пересмотр · обновлено")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                        .padding(12)
                    }
                    Spacer()
                }
            }
        }
        .frame(minWidth: 480, minHeight: 270)
    }
    
    // MARK: - Toolbar
    
    private var reviewToolbar: some View {
        HStack(spacing: 12) {
            // Editor button — captures frame from review player, opens editor in main video window
            Button {
                NotificationCenter.default.post(name: .takeReviewScreenshotForEditor, object: nil)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 13, weight: .medium))
                    Text("Редактор")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(videoManager.reviewPlayer == nil)
            .opacity(videoManager.reviewPlayer == nil ? 0.4 : 1)
            .help("Открыть редактор рисования на текущем кадре пересмотра")
            
            Spacer()
            
            // Play/Pause button
            Button {
                videoManager.toggleReviewPlayPause()
            } label: {
                Image(systemName: videoManager.reviewPlayer?.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 30, height: 30)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(videoManager.reviewPlayer == nil)
            .opacity(videoManager.reviewPlayer == nil ? 0.4 : 1)
            .help("Воспроизведение / Пауза (Пробел)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
