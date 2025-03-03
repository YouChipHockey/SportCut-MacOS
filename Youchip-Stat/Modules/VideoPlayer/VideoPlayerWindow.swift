//
//  VideoPlayerWindow.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import SwiftUI
import AVKit

struct VideoPlayerWindow: View {
    @ObservedObject var videoManager = VideoPlayerManager.shared
    
    var body: some View {
        VStack {
            if let player = videoManager.player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
            } else {
                Text("Видео не загружено")
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 800, height: 450)
    }
}

class VideoPlayerWindowController: NSWindowController {
    
    init() {
        let view = VideoPlayerWindow()
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(
            contentViewController: hostingController
        )
        window.title = "Видео"
        window.setContentSize(NSSize(width: 800, height: 450))
        window.styleMask.insert(.closable)
        window.makeKeyAndOrderFront(nil)
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
