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
    let lineID: UUID?
    let stampID: UUID?
    let displayStartTime: Double
    let displayDuration: Double

    private var endObserver: NSObjectProtocol?
    private var didInvalidate = false

    init(asset: AVAsset, startTime: Double, duration: Double, tagName: String, lineName: String, lineID: UUID? = nil, stampID: UUID? = nil) {
        self.tagName = tagName
        self.lineName = lineName
        self.lineID = lineID
        self.stampID = stampID
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

        let startCM    = CMTime(seconds: safeStart, preferredTimescale: 600)
        let durationCM = CMTime(seconds: safeDuration, preferredTimescale: 600)
        let timeRange  = CMTimeRange(start: startCM, duration: durationCM)

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
    @ObservedObject private var timelineData = TimelineDataManager.shared
    @ObservedObject private var tagLibrary = TagLibraryManager.shared

    private var sourceStamp: TimelineStamp? {
        guard let lineID = session.lineID,
              let stampID = session.stampID,
              let line = timelineData.lines.first(where: { $0.id == lineID }),
              let stamp = line.stamps.first(where: { $0.id == stampID }) else { return nil }
        return stamp
    }

    private var tagTitleWithOrder: String {
        guard let stamp = sourceStamp else { return session.tagName }
        let baseTagName = tagLibrary.findTagById(stamp.idTag)?.name ?? stamp.label
        let ordinal = stampOrdinal(for: stamp)
        return "\(baseTagName)_\(ordinal)"
    }

    private var stampEventNames: [String] {
        guard let stamp = sourceStamp else { return [] }
        return stamp.timeEvents.compactMap { eventID in
            tagLibrary.allTimeEvents.first(where: { $0.id == eventID })?.name
        }
    }

    private var stampLabelNames: [String] {
        guard let stamp = sourceStamp else { return [] }
        return stamp.labelIDs.compactMap { labelID in
            tagLibrary.findLabelById(labelID)?.name
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: session.player)
                .background(Color.black)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tagTitleWithOrder)
                        .font(.headline)
                        .fontWeight(.bold)
                    if !stampEventNames.isEmpty {
                        Text("События: \(stampEventNames.joined(separator: ", "))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if !stampLabelNames.isEmpty {
                        Text("Лейблы: \(stampLabelNames.joined(separator: ", "))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if let comment = sourceStamp?.comment, !comment.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .overlay(Circle().stroke(Color.black, lineWidth: 0.8))
                                .frame(width: 7, height: 7)
                                .padding(.top, 3)
                            Text(comment)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
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

    private func stampOrdinal(for stamp: TimelineStamp) -> Int {
        stamp.chronologicalOrdinalAmongSameTag(in: timelineData.lines)
    }
}
