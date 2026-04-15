//
//  SportCutExportSheet.swift
//  Youchip-Stat
//

import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

struct SportCutExportSheet: View {
    let sessionID: UUID
    @ObservedObject var playerManager: SportCutPlayerManager
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var exportType: SportCutExportType = .clips
    @State private var selectedPlaylistIDs: Set<UUID> = []
    @State private var addWatermark = false
    @StateObject private var exportUI = SportCutExportUIState()

    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }

    private var allPlaylists: [SportCutPlaylist] {
        session?.playlistGroups.flatMap(\.playlists) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(^String.Titles.sportCutExportTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.sportCutExportType)
                            .font(.system(size: 14, weight: .semibold))

                        ForEach(SportCutExportType.allCases, id: \.rawValue) { type in
                            Button(action: { exportType = type }) {
                                HStack {
                                    Image(systemName: exportType == type ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(exportType == type ? .blue : .gray)
                                    Text(type.displayName)
                                        .font(.system(size: 13))
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(^String.Titles.sportCutSelectPlaylists)
                                .font(.system(size: 14, weight: .semibold))

                            Spacer()

                            Button(^String.Titles.sportCutSelectAll) {
                                selectedPlaylistIDs = Set(allPlaylists.map(\.id))
                            }
                            .font(.system(size: 11))
                            .buttonStyle(PlainButtonStyle())
                            .foregroundColor(.blue)
                        }

                        ForEach(allPlaylists) { playlist in
                            Button(action: {
                                if selectedPlaylistIDs.contains(playlist.id) {
                                    selectedPlaylistIDs.remove(playlist.id)
                                } else {
                                    selectedPlaylistIDs.insert(playlist.id)
                                }
                            }) {
                                HStack {
                                    Image(systemName: selectedPlaylistIDs.contains(playlist.id) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(selectedPlaylistIDs.contains(playlist.id) ? .blue : .gray)
                                    Text(playlist.name)
                                        .font(.system(size: 12))
                                    Spacer()
                                    Text(String.Titles.sportCutEventsCount.format(playlist.eventCount))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    Toggle(isOn: $addWatermark) {
                        Text(^String.Titles.sportCutAddWatermark)
                    }
                    .font(.system(size: 13))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            if exportUI.isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: exportUI.progress)
                    Text(String.Titles.sportCutExportProgress.format(Int(exportUI.progress * 100)))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
            }

            Divider()

            HStack {
                Button(^String.Titles.cancelButtonTitle) { dismiss() }
                    .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: startExport) {
                    Text(^String.Titles.sportCutExportAction)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedPlaylistIDs.isEmpty || exportUI.isExporting)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 550)
    }

    private func startExport() {
        guard let session = session else { return }

        let selectedPlaylists = allPlaylists.filter { selectedPlaylistIDs.contains($0.id) }
        guard !selectedPlaylists.isEmpty else { return }

        exportUI.isExporting = true
        exportUI.progress = 0

        let panel = NSSavePanel()

        switch exportType {
        case .clips:
            panel.allowedContentTypes = [UTType.zip]
            panel.nameFieldStringValue = "\(session.name)_clips.zip"
        case .film:
            panel.allowedContentTypes = [UTType.mpeg4Movie]
            panel.nameFieldStringValue = "\(session.name)_film.mp4"
        case .filmPerPlaylist:
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [UTType.mpeg4Movie]
            panel.nameFieldStringValue = "\(session.name)_playlists"
        }

        guard panel.runModal() == .OK, let outputURL = panel.url else {
            exportUI.isExporting = false
            return
        }

        let type = exportType
        let ui = exportUI
        let wm = addWatermark
        DispatchQueue.global(qos: .userInitiated).async {
            let backend = SportCutExportBackend(ui: ui)
            backend.run(playlists: selectedPlaylists, outputURL: outputURL, session: session, type: type, addWatermark: wm)
        }
    }
}

// MARK: - Export UI state (main-thread updates from background)

private final class SportCutExportUIState: ObservableObject {
    @Published var progress: Double = 0
    @Published var isExporting: Bool = false
}

// MARK: - Background export

private final class SportCutExportBackend {
    private let ui: SportCutExportUIState
    private var addWatermark: Bool = false

    init(ui: SportCutExportUIState) {
        self.ui = ui
    }

    func run(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession, type: SportCutExportType, addWatermark: Bool) {
        self.addWatermark = addWatermark
        switch type {
        case .clips:
            exportAsClips(playlists: playlists, outputURL: outputURL, session: session)
        case .film:
            exportAsFilm(playlists: playlists, outputURL: outputURL, session: session)
        case .filmPerPlaylist:
            exportAsFilmPerPlaylist(playlists: playlists, outputURL: outputURL, session: session)
        }
    }

    private func resolvedEvent(_ event: SportCutEvent, session: SportCutSession) -> SportCutEvent {
        session.timelineResolvedEvent(for: event)
    }

    private static func bestPreset(for asset: AVAsset) -> String {
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        // Do NOT use Passthrough — it fails with AVMutableComposition from security-scoped bookmarks
        for candidate in [AVAssetExportPresetHighestQuality, AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720, AVAssetExportPreset960x540] {
            if presets.contains(candidate) { return candidate }
        }
        return AVAssetExportPresetHighestQuality
    }

    // MARK: - Watermark overlay

    /// Creates an AVVideoComposition that overlays event tag/comment text on the video.
    /// Each segment gets its own text shown for its duration.
    private func watermarkVideoComposition(
        segments: [(text: String, start: CMTime, duration: CMTime)],
        videoTrack: AVAssetTrack,
        compositionVideoTrack: AVMutableCompositionTrack,
        compositionDuration: CMTime
    ) -> AVVideoComposition? {
        guard !segments.isEmpty else { return nil }

        let transform = videoTrack.preferredTransform
        let natural = videoTrack.naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(natural.width), height: abs(natural.height))
        guard renderSize.width > 0, renderSize.height > 0 else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: compositionDuration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        let total = CMTimeGetSeconds(compositionDuration)
        guard total > 0 else { return nil }

        let fontSize: CGFloat = max(renderSize.height / 30, 14)
        let padding: CGFloat = 12

        for seg in segments {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let attrStr = NSAttributedString(string: seg.text, attributes: attrs)
            let textMaxWidth = renderSize.width - padding * 2
            let textRect = attrStr.boundingRect(
                with: CGSize(width: textMaxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            let textHeight = ceil(textRect.height)
            let overlayHeight = min(textHeight + padding * 2, renderSize.height / 4)

            let bgLayer = CALayer()
            bgLayer.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
            bgLayer.frame = CGRect(x: 0, y: 0, width: renderSize.width, height: overlayHeight)
            parentLayer.addSublayer(bgLayer)

            let textLayer = CATextLayer()
            textLayer.string = attrStr
            textLayer.contentsScale = 2
            textLayer.alignmentMode = .left
            textLayer.isWrapped = true
            textLayer.truncationMode = .end
            textLayer.frame = CGRect(x: padding, y: padding, width: textMaxWidth, height: overlayHeight - padding * 2)
            parentLayer.addSublayer(textLayer)

            let start = CMTimeGetSeconds(seg.start)
            let dur = CMTimeGetSeconds(seg.duration)

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 1, 0, 0]
            opacity.keyTimes = [
                0,
                NSNumber(value: start / total),
                NSNumber(value: (start + dur) / total),
                1
            ]
            opacity.duration = total
            opacity.beginTime = AVCoreAnimationBeginTimeAtZero
            opacity.isRemovedOnCompletion = false
            opacity.fillMode = .forwards
            opacity.calculationMode = .discrete

            bgLayer.add(opacity, forKey: "opacity")
            let opacity2 = opacity.copy() as! CAKeyframeAnimation
            textLayer.add(opacity2, forKey: "opacity")
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        return videoComposition
    }

    /// Builds watermark text for a SportCut event.
    private func watermarkText(for event: SportCutEvent, playlist: SportCutPlaylist, session: SportCutSession) -> String {
        var parts: [String] = []
        parts.append(event.tagName)

        // Labels
        if let source = session.sources.first(where: { $0.id == event.sourceID }) {
            let labels = event.labelIDs.compactMap { source.findLabel(byID: $0)?.name }
            if !labels.isEmpty {
                parts.append(labels.joined(separator: ", "))
            }
        }

        // Comment
        let comment = (playlist.eventComments[event.hiddenKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !comment.isEmpty {
            parts.append(comment)
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Drawing insertion helpers

    /// Builds a composition that interleaves the original video segment with still-image clips for each drawing.
    /// Returns the updated composition time after all insertions.
    @discardableResult
    private func insertDrawingsIntoComposition(
        composition: AVMutableComposition,
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack?,
        eventTimeRange: CMTimeRange,
        drawings: [SportCutEventDrawing],
        drawingsFolder: URL,
        startTime: CMTime
    ) -> CMTime {
        guard let compVideoTrack = composition.tracks(withMediaType: .video).first else { return startTime }

        let transform = videoTrack.preferredTransform
        let naturalSize = videoTrack.naturalSize.applying(transform)
        let videoSize = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))

        let segmentStart = CMTimeGetSeconds(eventTimeRange.start)
        var currentTime = startTime
        var lastVideoTime = segmentStart

        let sorted = drawings.sorted { $0.videoTime < $1.videoTime }

        for drawing in sorted {
            // drawing.videoTime is local within the clip, convert to absolute source time
            let absDrawingTime = segmentStart + drawing.videoTime

            if absDrawingTime > lastVideoTime {
                let videoDuration = absDrawingTime - lastVideoTime
                let videoRange = CMTimeRange(
                    start: CMTime(seconds: lastVideoTime, preferredTimescale: 600),
                    duration: CMTime(seconds: videoDuration, preferredTimescale: 600)
                )
                do {
                    try compVideoTrack.insertTimeRange(videoRange, of: videoTrack, at: currentTime)
                    if let compAudio = composition.tracks(withMediaType: .audio).first, let aTrack = audioTrack {
                        try compAudio.insertTimeRange(videoRange, of: aTrack, at: currentTime)
                    }
                    currentTime = CMTimeAdd(currentTime, videoRange.duration)
                } catch {
                    print("SportCut export: error inserting video before drawing: \(error)")
                }
            }

            let imgURL = drawingsFolder.appendingPathComponent(drawing.imageName)
            if let image = NSImage(contentsOf: imgURL) {
                let semaphore = DispatchSemaphore(value: 0)
                var drawingVideoURL: URL?

                createVideoFromImage(image, duration: drawing.displayDuration, targetSize: videoSize) { result in
                    if case .success(let url) = result { drawingVideoURL = url }
                    semaphore.signal()
                }

                let waitResult = semaphore.wait(timeout: .now() + 30)
                if waitResult == .timedOut {
                    print("SportCut export: drawing video creation timed out for '\(drawing.imageName)'")
                } else if let videoURL = drawingVideoURL,
                          let drawingAsset = try? AVURLAsset(url: videoURL),
                          let drawingVideoTrack = drawingAsset.tracks(withMediaType: .video).first {
                    do {
                        try compVideoTrack.insertTimeRange(
                            CMTimeRange(start: .zero, duration: drawingAsset.duration),
                            of: drawingVideoTrack,
                            at: currentTime
                        )
                        currentTime = CMTimeAdd(currentTime, drawingAsset.duration)
                        try? FileManager.default.removeItem(at: videoURL)
                    } catch {
                        print("SportCut export: error inserting drawing video: \(error)")
                    }
                }
            }

            lastVideoTime = absDrawingTime
        }

        // Insert remaining video after last drawing
        let segmentEnd = segmentStart + CMTimeGetSeconds(eventTimeRange.duration)
        if lastVideoTime < segmentEnd {
            let remainingDuration = segmentEnd - lastVideoTime
            let videoRange = CMTimeRange(
                start: CMTime(seconds: lastVideoTime, preferredTimescale: 600),
                duration: CMTime(seconds: remainingDuration, preferredTimescale: 600)
            )
            do {
                try compVideoTrack.insertTimeRange(videoRange, of: videoTrack, at: currentTime)
                if let compAudio = composition.tracks(withMediaType: .audio).first, let aTrack = audioTrack {
                    try compAudio.insertTimeRange(videoRange, of: aTrack, at: currentTime)
                }
                currentTime = CMTimeAdd(currentTime, videoRange.duration)
            } catch {
                print("SportCut export: error inserting remaining video: \(error)")
            }
        }

        return currentTime
    }

    /// Creates a short .mp4 video from a still image with the specified duration.
    private func createVideoFromImage(_ image: NSImage, duration: Double, targetSize: CGSize, completion: @escaping (Result<URL, Error>) -> Void) {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("sc_drawing_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let fps: Double = 30.0
        let totalFrames = Int(ceil(duration * fps))

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(NSError(domain: "ImageConversion", code: 0)))
            return
        }

        let videoWriter: AVAssetWriter
        do { videoWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4) }
        catch { completion(.failure(error)); return }

        let videoWidth = Int(targetSize.width)
        let videoHeight = Int(targetSize.height)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: videoWidth,
                kCVPixelBufferHeightKey as String: videoHeight
            ]
        )

        videoWriter.add(writerInput)
        videoWriter.startWriting()
        videoWriter.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "com.youchip.sportcut.videoCreation", qos: .userInitiated)

        writerInput.requestMediaDataWhenReady(on: queue) {
            var frameCount = 0
            var success = true

            while frameCount < totalFrames {
                while !writerInput.isReadyForMoreMediaData {
                    if videoWriter.status == .failed { success = false; break }
                    Thread.sleep(forTimeInterval: 0.01)
                }
                if !success { break }

                let presentationTime = CMTime(seconds: Double(frameCount) / fps, preferredTimescale: 600)
                var pixelBuffer: CVPixelBuffer?

                if let pool = adaptor.pixelBufferPool {
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                } else {
                    let opts: [String: Any] = [
                        kCVPixelBufferCGImageCompatibilityKey as String: true,
                        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                        kCVPixelBufferWidthKey as String: videoWidth,
                        kCVPixelBufferHeightKey as String: videoHeight,
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
                    ]
                    CVPixelBufferCreate(kCFAllocatorDefault, videoWidth, videoHeight, kCVPixelFormatType_32ARGB, opts as CFDictionary, &pixelBuffer)
                }

                if let pixelBuffer = pixelBuffer {
                    CVPixelBufferLockBaseAddress(pixelBuffer, [])
                    let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
                    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

                    if let context = CGContext(
                        data: pixelData,
                        width: videoWidth,
                        height: videoHeight,
                        bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                        space: rgbColorSpace,
                        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                    ) {
                        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                        context.fill(CGRect(x: 0, y: 0, width: videoWidth, height: videoHeight))

                        let imageWidth = CGFloat(cgImage.width)
                        let imageHeight = CGFloat(cgImage.height)
                        let videoAspect = CGFloat(videoWidth) / CGFloat(videoHeight)
                        let imageAspect = imageWidth / imageHeight

                        var drawRect: CGRect
                        if imageAspect > videoAspect {
                            let scaledHeight = CGFloat(videoWidth) / imageAspect
                            let yOffset = (CGFloat(videoHeight) - scaledHeight) / 2
                            drawRect = CGRect(x: 0, y: yOffset, width: CGFloat(videoWidth), height: scaledHeight)
                        } else {
                            let scaledWidth = CGFloat(videoHeight) * imageAspect
                            let xOffset = (CGFloat(videoWidth) - scaledWidth) / 2
                            drawRect = CGRect(x: xOffset, y: 0, width: scaledWidth, height: CGFloat(videoHeight))
                        }

                        context.draw(cgImage, in: drawRect)
                    }

                    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

                    if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                        success = false; break
                    }
                }
                frameCount += 1
            }

            writerInput.markAsFinished()
            videoWriter.finishWriting {
                if videoWriter.status == .completed {
                    completion(.success(outputURL))
                } else {
                    completion(.failure(videoWriter.error ?? NSError(domain: "VideoCreation", code: 1)))
                }
            }
        }
    }

    private func exportAsClips(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession) {
        let sink = ui
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let drawingsFolder = SportCutPlayerManager.drawingsFolder(sessionID: session.id)

        struct EventEntry {
            let event: SportCutEvent
            let playlist: SportCutPlaylist
        }
        let allEntries: [EventEntry] = playlists.flatMap { pl in pl.events.map { EventEntry(event: $0, playlist: pl) } }
        let total = max(allEntries.count, 1)
        let group = DispatchGroup()
        var processed = 0
        let progressLock = NSLock()

        for (index, entry) in allEntries.enumerated() {
            group.enter()
            let event = resolvedEvent(entry.event, session: session)
            let drawings = entry.playlist.eventDrawings[entry.event.hiddenKey] ?? []

            guard let source = session.sources.first(where: { $0.id == event.sourceID }),
                  let url = source.mediaAccessURL() else {
                group.leave()
                progressLock.lock(); processed += 1; let p = processed; progressLock.unlock()
                DispatchQueue.main.async { sink.progress = Double(p) / Double(total) }
                continue
            }
            // Do NOT use defer — stopAccessing must happen after async export completes
            let securityURL = url

            let asset = AVAsset(url: url)
            let composition = AVMutableComposition()

            guard let videoTrack = asset.tracks(withMediaType: .video).first,
                  composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) != nil else {
                securityURL.stopAccessingSecurityScopedResource()
                group.leave()
                progressLock.lock(); processed += 1; let p = processed; progressLock.unlock()
                DispatchQueue.main.async { sink.progress = Double(p) / Double(total) }
                continue
            }

            let audioTrack = asset.tracks(withMediaType: .audio).first
            if audioTrack != nil {
                _ = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            }

            let startTime = CMTime(seconds: event.startTime, preferredTimescale: 600)
            let duration = CMTime(seconds: event.duration, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, duration: duration)

            if !drawings.isEmpty {
                insertDrawingsIntoComposition(
                    composition: composition,
                    videoTrack: videoTrack,
                    audioTrack: audioTrack,
                    eventTimeRange: timeRange,
                    drawings: drawings,
                    drawingsFolder: drawingsFolder,
                    startTime: .zero
                )
            } else {
                do {
                    try composition.tracks(withMediaType: .video).first?.insertTimeRange(timeRange, of: videoTrack, at: .zero)
                    if let compAudio = composition.tracks(withMediaType: .audio).first, let audio = audioTrack {
                        try compAudio.insertTimeRange(timeRange, of: audio, at: .zero)
                    }
                } catch {
                    securityURL.stopAccessingSecurityScopedResource()
                    group.leave()
                    progressLock.lock(); processed += 1; let p = processed; progressLock.unlock()
                    DispatchQueue.main.async { sink.progress = Double(p) / Double(total) }
                    continue
                }
            }

            let safeTag = event.tagName
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let prefix = String(safeTag.prefix(80))
            let clipName = "\(prefix)_\(index + 1).mp4"
            let clipURL = tempDir.appendingPathComponent(clipName)

            let preset = Self.bestPreset(for: composition)
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
                securityURL.stopAccessingSecurityScopedResource()
                group.leave()
                progressLock.lock(); processed += 1; let p = processed; progressLock.unlock()
                DispatchQueue.main.async { sink.progress = Double(p) / Double(total) }
                continue
            }

            exportSession.outputURL = clipURL
            exportSession.outputFileType = .mp4

            if addWatermark, let compVideoTrack = composition.tracks(withMediaType: .video).first {
                let wmText = watermarkText(for: entry.event, playlist: entry.playlist, session: session)
                let seg = (text: wmText, start: CMTime.zero, duration: composition.duration)
                if let vc = watermarkVideoComposition(
                    segments: [seg],
                    videoTrack: videoTrack,
                    compositionVideoTrack: compVideoTrack,
                    compositionDuration: composition.duration
                ) {
                    exportSession.videoComposition = vc
                }
            }

            exportSession.exportAsynchronously {
                securityURL.stopAccessingSecurityScopedResource()
                progressLock.lock(); processed += 1; let p = processed; progressLock.unlock()
                DispatchQueue.main.async { sink.progress = Double(p) / Double(total) }
                group.leave()
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            let zipURL = outputURL
            let files = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "mp4" } ?? []
            guard !files.isEmpty else {
                try? FileManager.default.removeItem(at: tempDir)
                DispatchQueue.main.async { sink.isExporting = false }
                return
            }

            // Create ZIP using Foundation (sandbox-safe, no subprocess needed)
            try? FileManager.default.removeItem(at: zipURL)
            var archiveData = Data()
            for file in files {
                guard let fileData = try? Data(contentsOf: file) else { continue }
                let fileName = file.lastPathComponent
                // Minimal ZIP format: local file header + data
                var localHeader = Data()
                localHeader.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // signature
                localHeader.append(contentsOf: [0x14, 0x00]) // version needed
                localHeader.append(contentsOf: [0x00, 0x00]) // flags
                localHeader.append(contentsOf: [0x00, 0x00]) // compression (store)
                localHeader.append(contentsOf: [0x00, 0x00]) // mod time
                localHeader.append(contentsOf: [0x00, 0x00]) // mod date
                let crc = Self.crc32(fileData)
                localHeader.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
                let size = UInt32(fileData.count)
                localHeader.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) }) // compressed
                localHeader.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) }) // uncompressed
                let nameData = Data(fileName.utf8)
                let nameLen = UInt16(nameData.count)
                localHeader.append(contentsOf: withUnsafeBytes(of: nameLen.littleEndian) { Array($0) })
                localHeader.append(contentsOf: [0x00, 0x00]) // extra field length
                localHeader.append(nameData)
                archiveData.append(localHeader)
                archiveData.append(fileData)
            }
            // Build central directory
            var centralDir = Data()
            var offset: UInt32 = 0
            var entryCount: UInt16 = 0
            // Re-iterate to build central directory entries
            for file in files {
                guard let fileData = try? Data(contentsOf: file) else { continue }
                let fileName = file.lastPathComponent
                let nameData = Data(fileName.utf8)
                let nameLen = UInt16(nameData.count)
                let size = UInt32(fileData.count)
                let crc = Self.crc32(fileData)

                var entry = Data()
                entry.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // signature
                entry.append(contentsOf: [0x14, 0x00]) // version made by
                entry.append(contentsOf: [0x14, 0x00]) // version needed
                entry.append(contentsOf: [0x00, 0x00]) // flags
                entry.append(contentsOf: [0x00, 0x00]) // compression
                entry.append(contentsOf: [0x00, 0x00]) // mod time
                entry.append(contentsOf: [0x00, 0x00]) // mod date
                entry.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
                entry.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) }) // compressed
                entry.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) }) // uncompressed
                entry.append(contentsOf: withUnsafeBytes(of: nameLen.littleEndian) { Array($0) })
                entry.append(contentsOf: [0x00, 0x00]) // extra field length
                entry.append(contentsOf: [0x00, 0x00]) // comment length
                entry.append(contentsOf: [0x00, 0x00]) // disk number
                entry.append(contentsOf: [0x00, 0x00]) // internal attrs
                entry.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // external attrs
                entry.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Array($0) })
                entry.append(nameData)
                centralDir.append(entry)

                // local header size: 30 + nameLen + fileData.count
                offset += 30 + UInt32(nameData.count) + size
                entryCount += 1
            }
            let centralDirOffset = UInt32(archiveData.count)
            archiveData.append(centralDir)
            let centralDirSize = UInt32(centralDir.count)
            // End of central directory
            var eocd = Data()
            eocd.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
            eocd.append(contentsOf: [0x00, 0x00]) // disk number
            eocd.append(contentsOf: [0x00, 0x00]) // disk with central dir
            eocd.append(contentsOf: withUnsafeBytes(of: entryCount.littleEndian) { Array($0) })
            eocd.append(contentsOf: withUnsafeBytes(of: entryCount.littleEndian) { Array($0) })
            eocd.append(contentsOf: withUnsafeBytes(of: centralDirSize.littleEndian) { Array($0) })
            eocd.append(contentsOf: withUnsafeBytes(of: centralDirOffset.littleEndian) { Array($0) })
            eocd.append(contentsOf: [0x00, 0x00]) // comment length
            archiveData.append(eocd)

            try? archiveData.write(to: zipURL)

            try? FileManager.default.removeItem(at: tempDir)
            DispatchQueue.main.async { sink.isExporting = false }
        }
    }

    /// CRC32 checksum for ZIP file format.
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 != 0 ? 0xEDB88320 : 0)
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    private func exportAsFilm(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession) {
        let sink = ui
        let drawingsFolder = SportCutPlayerManager.drawingsFolder(sessionID: session.id)
        let composition = AVMutableComposition()

        guard composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) != nil else {
            DispatchQueue.main.async { sink.isExporting = false }
            return
        }

        _ = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var currentTime = CMTime.zero
        var securityURLs: [URL] = []
        var wmSegments: [(text: String, start: CMTime, duration: CMTime)] = []
        var firstVideoTrack: AVAssetTrack?

        for playlist in playlists {
            for rawEvent in playlist.events {
                let event = resolvedEvent(rawEvent, session: session)
                let drawings = playlist.eventDrawings[rawEvent.hiddenKey] ?? []

                guard let source = session.sources.first(where: { $0.id == event.sourceID }),
                      let url = source.mediaAccessURL() else { continue }
                securityURLs.append(url)

                let asset = AVAsset(url: url)
                guard let vTrack = asset.tracks(withMediaType: .video).first else { continue }
                if firstVideoTrack == nil { firstVideoTrack = vTrack }
                let aTrack = asset.tracks(withMediaType: .audio).first

                let startTime = CMTime(seconds: event.startTime, preferredTimescale: 600)
                let duration = CMTime(seconds: event.duration, preferredTimescale: 600)
                let timeRange = CMTimeRange(start: startTime, duration: duration)

                let segStart = currentTime

                if !drawings.isEmpty {
                    currentTime = insertDrawingsIntoComposition(
                        composition: composition,
                        videoTrack: vTrack,
                        audioTrack: aTrack,
                        eventTimeRange: timeRange,
                        drawings: drawings,
                        drawingsFolder: drawingsFolder,
                        startTime: currentTime
                    )
                } else {
                    do {
                        try composition.tracks(withMediaType: .video).first?.insertTimeRange(timeRange, of: vTrack, at: currentTime)
                        if let compAudio = composition.tracks(withMediaType: .audio).first, let aTrack = aTrack {
                            try compAudio.insertTimeRange(timeRange, of: aTrack, at: currentTime)
                        }
                        currentTime = currentTime + duration
                    } catch { continue }
                }

                if addWatermark {
                    let segDuration = CMTimeSubtract(currentTime, segStart)
                    let wmText = watermarkText(for: rawEvent, playlist: playlist, session: session)
                    wmSegments.append((text: wmText, start: segStart, duration: segDuration))
                }
            }
        }

        let preset = Self.bestPreset(for: composition)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
            securityURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async { sink.isExporting = false }
            return
        }

        try? FileManager.default.removeItem(at: outputURL)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        if addWatermark, !wmSegments.isEmpty,
           let vTrack = firstVideoTrack,
           let compVideoTrack = composition.tracks(withMediaType: .video).first {
            if let vc = watermarkVideoComposition(
                segments: wmSegments,
                videoTrack: vTrack,
                compositionVideoTrack: compVideoTrack,
                compositionDuration: composition.duration
            ) {
                exportSession.videoComposition = vc
            }
        }

        exportSession.exportAsynchronously {
            securityURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                sink.isExporting = false
            }
        }
    }

    private func exportAsFilmPerPlaylist(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession) {
        let sink = ui
        let parentDir = outputURL.deletingLastPathComponent()
        let baseName = outputURL.deletingPathExtension().lastPathComponent
        let drawingsFolder = SportCutPlayerManager.drawingsFolder(sessionID: session.id)

        let group = DispatchGroup()

        for playlist in playlists {
            group.enter()

            let composition = AVMutableComposition()
            guard composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) != nil else {
                group.leave()
                continue
            }
            _ = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

            var currentTime = CMTime.zero
            var securityURLs: [URL] = []
            var wmSegments: [(text: String, start: CMTime, duration: CMTime)] = []
            var firstVideoTrack: AVAssetTrack?

            for rawEvent in playlist.events {
                let event = resolvedEvent(rawEvent, session: session)
                let drawings = playlist.eventDrawings[rawEvent.hiddenKey] ?? []

                guard let source = session.sources.first(where: { $0.id == event.sourceID }),
                      let url = source.mediaAccessURL() else { continue }
                securityURLs.append(url)

                let asset = AVAsset(url: url)
                guard let vTrack = asset.tracks(withMediaType: .video).first else { continue }
                if firstVideoTrack == nil { firstVideoTrack = vTrack }
                let aTrack = asset.tracks(withMediaType: .audio).first

                let startTime = CMTime(seconds: event.startTime, preferredTimescale: 600)
                let duration = CMTime(seconds: event.duration, preferredTimescale: 600)
                let timeRange = CMTimeRange(start: startTime, duration: duration)

                let segStart = currentTime

                if !drawings.isEmpty {
                    currentTime = insertDrawingsIntoComposition(
                        composition: composition,
                        videoTrack: vTrack,
                        audioTrack: aTrack,
                        eventTimeRange: timeRange,
                        drawings: drawings,
                        drawingsFolder: drawingsFolder,
                        startTime: currentTime
                    )
                } else {
                    do {
                        try composition.tracks(withMediaType: .video).first?.insertTimeRange(timeRange, of: vTrack, at: currentTime)
                        if let compAudio = composition.tracks(withMediaType: .audio).first, let aTrack = aTrack {
                            try compAudio.insertTimeRange(timeRange, of: aTrack, at: currentTime)
                        }
                        currentTime = currentTime + duration
                    } catch { continue }
                }

                if addWatermark {
                    let segDuration = CMTimeSubtract(currentTime, segStart)
                    let wmText = watermarkText(for: rawEvent, playlist: playlist, session: session)
                    wmSegments.append((text: wmText, start: segStart, duration: segDuration))
                }
            }

            let safePlaylist = playlist.name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let filmURL = parentDir.appendingPathComponent("\(baseName)_\(String(safePlaylist.prefix(120))).mp4")
            try? FileManager.default.removeItem(at: filmURL)

            let preset = Self.bestPreset(for: composition)
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
                securityURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                group.leave()
                continue
            }

            exportSession.outputURL = filmURL
            exportSession.outputFileType = .mp4

            if addWatermark, !wmSegments.isEmpty,
               let vTrack = firstVideoTrack,
               let compVideoTrack = composition.tracks(withMediaType: .video).first {
                if let vc = watermarkVideoComposition(
                    segments: wmSegments,
                    videoTrack: vTrack,
                    compositionVideoTrack: compVideoTrack,
                    compositionDuration: composition.duration
                ) {
                    exportSession.videoComposition = vc
                }
            }

            exportSession.exportAsynchronously {
                securityURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            sink.isExporting = false
        }
    }
}
