//
//  PlaylistOverlayVM.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 17.01.2026.
//

import AVFoundation
import Combine

struct CompositionSegment {
    let compositionRange: CMTimeRange
    let tag: OrganizerTag
}

@MainActor
final class PlaylistOverlayViewModel: ObservableObject {
    
    @Published var currentTag: OrganizerTag?
    private var segments: [CompositionSegment] = []
    private var timeObserverToken: Any?

    func attach(to player: AVPlayer?) {
        detach(from: player)
        guard let player else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.handleTick(time)
            }
        }
    }
    
    func detach(from player: AVPlayer?) {
        guard let player, let token = timeObserverToken else { return }
        player.removeTimeObserver(token)
        timeObserverToken = nil
    }
    
    func updateSegments(_ new: [CompositionSegment]) {
        segments = new
        currentTag = nil
    }

    private func handleTick(_ time: CMTime) {
        guard let seg = segments.first(where: { $0.compositionRange.containsTime(time) }) else {
            currentTag = nil
            return
        }
        if currentTag?.id != seg.tag.id {
            currentTag = seg.tag
        }
    }
}
