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
    @Published var currentScreenshot: ScreenshotMetadata?
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
    
    private var lastShownScreenshotName: String?

    func updateSegments(_ new: [CompositionSegment]) {
        segments = new
        currentTag = nil
        currentScreenshot = nil
        lastShownScreenshotName = nil
    }

    private func handleTick(_ time: CMTime) {
        guard let seg = segments.first(where: { $0.compositionRange.containsTime(time) }) else {
            currentTag = nil
            currentScreenshot = nil
            lastShownScreenshotName = nil
            return
        }
        if currentTag?.id != seg.tag.id {
            currentTag = seg.tag
            lastShownScreenshotName = nil
        }
        updateCurrentScreenshot(compositionTime: time, segment: seg)
    }

    private func updateCurrentScreenshot(compositionTime: CMTime, segment: CompositionSegment) {
        let compositionSecs = CMTimeGetSeconds(compositionTime)
        let compositionStart = CMTimeGetSeconds(segment.compositionRange.start)
        let originalVideoTime = segment.tag.startTime + (compositionSecs - compositionStart)
        let stampID = segment.tag.stampID
        let screenshots = ScreenshotsMetadataManager.shared.screenshots

        let matchingScreenshot = screenshots.first { screenshot in
            screenshot.relatedStampIds.contains(stampID) &&
            abs(screenshot.videoTime - originalVideoTime) < 0.15
        }

        if let matching = matchingScreenshot {
            if lastShownScreenshotName != matching.screenshotName {
                lastShownScreenshotName = matching.screenshotName
                currentScreenshot = matching
            }
        } else {
            if let lastShown = lastShownScreenshotName,
               screenshots.contains(where: { $0.screenshotName == lastShown && abs($0.videoTime - originalVideoTime) >= 0.5 }) {
                lastShownScreenshotName = nil
            }
            if currentScreenshot != nil {
                currentScreenshot = nil
            }
        }
    }
}
