//
//  SportCutMinimalPlayerView.swift
//  Youchip-Stat
//

import SwiftUI
import AVKit
import AppKit

/// AVPlayerView with standard inline controls (scrubber, transport). Composition duration still matches trimmed clip.
struct SportCutMinimalPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .inline
        v.showsFullScreenToggleButton = true
        v.showsSharingServiceButton = false
        v.videoGravity = .resizeAspect
        v.player = player
        return v
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
