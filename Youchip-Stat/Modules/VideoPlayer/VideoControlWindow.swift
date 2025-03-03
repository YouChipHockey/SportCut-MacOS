//
//  VideoControlWindow.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import SwiftUI

struct VideoControlWindow: View {
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @State private var selectedSpeed: Double = 1.0

    let speeds: [Double] = [0.5, 1.0, 2.0, 5.0]

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: { videoManager.seek(by: -10) }) {
                    Label("⏪ 10 сек", systemImage: "gobackward.10")
                }
                Button(action: { videoManager.togglePlayPause() }) {
                    Label(videoManager.player?.timeControlStatus == .playing ? "⏸ Пауза" : "▶️ Пуск", systemImage: "playpause")
                }
                Button(action: { videoManager.seek(by: 10) }) {
                    Label("10 сек ⏩", systemImage: "goforward.10")
                }
            }
            .buttonStyle(.borderedProminent)

            Text("Скорость:")
                .font(.headline)

            HStack {
                ForEach(speeds, id: \.self) { speed in
                    Button(action: {
                        selectedSpeed = speed
                        videoManager.changePlaybackSpeed(to: speed)
                    }) {
                        Text(String(format: "%.1fx", speed))
                            .padding()
                            .frame(width: 75)
                            .background(selectedSpeed == speed ? Color.blue : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
        }
        .frame(width: 400, height: 200)
        .padding()
    }
}

class VideoControlWindowController: NSWindowController {
    
    init() {
        let view = VideoControlWindow()
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(
            contentViewController: hostingController
        )
        window.title = "Управление видео"
        window.setContentSize(NSSize(width: 300, height: 200))
        window.styleMask.insert(.closable)
        window.makeKeyAndOrderFront(nil)
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
