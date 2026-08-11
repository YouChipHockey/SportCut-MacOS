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
    @State private var addWatermark = true
    @State private var watermarkOptions: ExportWatermarkOptions = .default
    @State private var didStartExport = false
    @StateObject private var exportUI = SportCutExportUIState()
    /// Держим бэкенд живым на всё время экспорта (иначе таймер прогресса/колбэки могут отвалиться).
    @State private var exportBackend: SportCutExportBackend?

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

                    if addWatermark {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(^String.Titles.exportAddEpisodeNumbering, isOn: $watermarkOptions.showEpisodeNumbering)
                            Toggle(^String.Titles.exportAddTagAndLabels, isOn: $watermarkOptions.showTagAndLabels)
                            Toggle(^String.Titles.exportAddComment, isOn: $watermarkOptions.showComment)
                        }
                        .font(.system(size: 12))
                        .padding(.leading, 16)
                    }

                    // Логотип клуба — независимо от текстового вотермарка.
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(^String.Titles.exportShowClubLogo, isOn: $watermarkOptions.showClubLogo)
                            .font(.system(size: 13))
                            .disabled(!ClubLogoWatermarkManager.shared.hasLogo)
                        if !ClubLogoWatermarkManager.shared.hasLogo {
                            Text(^String.Titles.exportClubLogoNotConfigured)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
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
        .frame(width: 500, height: 620)
        .overlay {
            if exportUI.isExporting {
                VStack(spacing: 16) {
                    CircularPercentProgressView(progress: exportUI.progress)
                        .frame(width: 80, height: 80)
                }
                .padding(30)
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
                .shadow(radius: 20)
                .transition(.opacity)
            }
        }
        .onChange(of: exportUI.isExporting) { exporting in
            // Закрываем окно только при успешном завершении. При ошибке — оставляем открытым и показываем алерт.
            if !exporting, didStartExport {
                didStartExport = false
                exportBackend = nil
                if exportUI.errorMessage == nil {
                    dismiss()
                }
            }
        }
        .alert(
            ^String.Titles.alertsErrorTitle,
            isPresented: Binding(
                get: { exportUI.errorMessage != nil },
                set: { if !$0 { exportUI.errorMessage = nil } }
            )
        ) {
            Button(^String.Titles.alertsOkTitle, role: .cancel) {}
        } message: {
            Text(exportUI.errorMessage ?? "")
        }
    }

    private func startExport() {
        guard let session = session else { return }

        let selectedPlaylists = allPlaylists.filter { selectedPlaylistIDs.contains($0.id) }
        guard !selectedPlaylists.isEmpty else { return }

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
            return
        }

        exportUI.errorMessage = nil
        exportUI.isExporting = true
        exportUI.progress = 0
        didStartExport = true

        let type = exportType
        let wm = addWatermark
        let wmOptions = watermarkOptions
        let backend = SportCutExportBackend(ui: exportUI)
        exportBackend = backend
        DispatchQueue.global(qos: .userInitiated).async {
            backend.run(playlists: selectedPlaylists, outputURL: outputURL, session: session, type: type, addWatermark: wm, watermarkOptions: wmOptions)
        }
    }
}

// MARK: - Export UI state (main-thread updates from background)

private final class SportCutExportUIState: ObservableObject {
    @Published var progress: Double = 0
    @Published var isExporting: Bool = false
    /// Непустой — экспорт завершился ошибкой, показываем алерт и НЕ закрываем окно.
    @Published var errorMessage: String? = nil
}

// MARK: - Background export

private final class SportCutExportBackend {
    private let ui: SportCutExportUIState
    private var addWatermark: Bool = false
    private var watermarkOptions: ExportWatermarkOptions = .default
    private var progressTimer: DispatchSourceTimer?

    /// Нужно ли наносить логотип клуба (флаг экспорта + логотип задан в настройках).
    private var showLogo: Bool { watermarkOptions.showClubLogo && ClubLogoWatermarkManager.shared.hasLogo }

    init(ui: SportCutExportUIState) {
        self.ui = ui
    }

    // MARK: - Progress / completion

    /// Периодически опрашивает реальный прогресс сессий экспорта и пишет в UI (0…1 через `map`).
    private func startProgressPolling(_ map: @escaping () -> Double) {
        stopProgressPolling()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 0.15, repeating: 0.15)
        timer.setEventHandler { [weak self] in
            let value = min(max(map(), 0), 1)
            DispatchQueue.main.async { self?.ui.progress = value }
        }
        timer.resume()
        progressTimer = timer
    }

    private func stopProgressPolling() {
        progressTimer?.cancel()
        progressTimer = nil
    }

    private func finishSuccess() {
        stopProgressPolling()
        DispatchQueue.main.async {
            self.ui.progress = 1.0
            self.ui.isExporting = false
        }
    }

    private func finishError(_ message: String) {
        stopProgressPolling()
        DispatchQueue.main.async {
            self.ui.errorMessage = message
            self.ui.isExporting = false
        }
    }

    func run(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession, type: SportCutExportType, addWatermark: Bool, watermarkOptions: ExportWatermarkOptions = .default) {
        self.addWatermark = addWatermark
        self.watermarkOptions = watermarkOptions
        switch type {
        case .clips:
            exportAsClips(playlists: playlists, outputURL: outputURL, session: session)
        case .film:
            exportAsFilm(playlists: playlists, outputURL: outputURL, session: session)
        case .filmPerPlaylist:
            exportAsFilmPerPlaylist(playlists: playlists, outputURL: outputURL, session: session)
        }
    }

    /// Событие в том виде, в каком его надо экспортировать.
    ///
    /// `timelineResolvedEvent` пересобирает событие из ТЕКУЩЕЙ разметки — то есть возвращает тег
    /// ровно с теми границами, что лежат в проекте разметки. Границы, изменённые ресайзом клипа
    /// уже в режиме просмотра, живут отдельно — в оверрайдах плейлиста, и без их наложения
    /// экспорт писал исходный вариант тега, хотя плеер и плейлист показывали изменённый
    /// (плеер их учитывает, см. SportCutPlayerManager).
    ///
    /// Порядок тот же, что в плеере: оверрайд плейлиста важнее, иначе — свежее значение из разметки.
    private func resolvedEvent(
        _ event: SportCutEvent,
        playlist: SportCutPlaylist,
        session: SportCutSession
    ) -> SportCutEvent {
        let resolved = session.timelineResolvedEvent(for: event)
        guard !resolved.isSlide else { return resolved }

        // Ключ оверрайдов — sourceID|stampID, он переживает пересборку события.
        let start = playlist.eventStartOverrides[event.hiddenKey] ?? resolved.startTime
        let duration = playlist.eventDurationOverrides[event.hiddenKey] ?? resolved.duration
        guard start != resolved.startTime || duration != resolved.duration else { return resolved }
        return resolved.withClipRange(start: start, duration: duration)
    }

    /// Вставляет слайд-события между клипами по `position` (индекс в `playlist.events`).
    private func interleavedExportEvents(_ playlist: SportCutPlaylist) -> [SportCutEvent] {
        guard !playlist.slides.isEmpty else { return playlist.events }
        let sorted = playlist.slides.sorted { $0.position < $1.position }
        var result: [SportCutEvent] = []
        var si = 0
        for (idx, ev) in playlist.events.enumerated() {
            while si < sorted.count && sorted[si].position <= idx {
                result.append(SportCutEvent.slideEvent(from: sorted[si])); si += 1
            }
            result.append(ev)
        }
        while si < sorted.count { result.append(SportCutEvent.slideEvent(from: sorted[si])); si += 1 }
        return result
    }

    /// Вставляет видео-сегмент слайда в композицию (без звука), дозаполняя аудио тишиной. Возвращает новый `currentTime`.
    private func insertSlideSegment(
        event: SportCutEvent,
        slideURLs: [UUID: URL],
        composition: AVMutableComposition,
        startTime: CMTime,
        firstVideoTrack: inout AVAssetTrack?,
        allSegmentTracks: inout [(start: CMTime, duration: CMTime, sourceTrack: AVAssetTrack)]
    ) -> CMTime {
        guard let sid = event.slideID, let url = slideURLs[sid] else { return startTime }
        let asset = AVAsset(url: url)
        guard let vTrack = asset.tracks(withMediaType: .video).first else { return startTime }
        if firstVideoTrack == nil { firstVideoTrack = vTrack }
        let dur = CMTime(seconds: event.duration, preferredTimescale: 600)
        let range = CMTimeRange(start: .zero, duration: dur)
        do {
            try composition.tracks(withMediaType: .video).first?.insertTimeRange(range, of: vTrack, at: startTime)
        } catch {
            return startTime
        }
        let newTime = startTime + dur
        // Держим аудиодорожку той же длины (тишина под слайдом), чтобы звук клипов не сдвигался.
        if let compAudio = composition.tracks(withMediaType: .audio).first, compAudio.timeRange.duration < newTime {
            compAudio.insertEmptyTimeRange(CMTimeRange(start: compAudio.timeRange.duration, end: newTime))
        }
        allSegmentTracks.append((start: startTime, duration: dur, sourceTrack: vTrack))
        return newTime
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

    private func fittedWatermarkText(_ source: NSAttributedString, maxWidth: CGFloat, maxHeight: CGFloat) -> NSAttributedString {
        let measure: (NSAttributedString) -> CGFloat = { text in
            text.boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height
        }

        guard measure(source) > maxHeight, source.length > 1 else { return source }

        var low = 0
        var high = source.length
        var best = 0

        while low <= high {
            let mid = (low + high) / 2
            let prefix = source.attributedSubstring(from: NSRange(location: 0, length: mid))
            let candidate = NSMutableAttributedString(attributedString: prefix)
            let attrs: [NSAttributedString.Key: Any]
            if source.length > 0 {
                let attrIdx = min(max(mid - 1, 0), source.length - 1)
                attrs = source.attributes(at: attrIdx, effectiveRange: nil)
            } else {
                attrs = [:]
            }
            candidate.append(NSAttributedString(string: "…", attributes: attrs))
            if measure(candidate) <= maxHeight {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let prefix = source.attributedSubstring(from: NSRange(location: 0, length: best))
        let result = NSMutableAttributedString(attributedString: prefix)
        let attrs: [NSAttributedString.Key: Any]
        if source.length > 0 {
            let attrIdx = min(max(best - 1, 0), source.length - 1)
            attrs = source.attributes(at: attrIdx, effectiveRange: nil)
        } else {
            attrs = [:]
        }
        result.append(NSAttributedString(string: "…", attributes: attrs))
        return result
    }

    private func watermarkVideoComposition(
        segments: [(text: NSAttributedString, start: CMTime, duration: CMTime)],
        videoTrack: AVAssetTrack,
        compositionVideoTrack: AVMutableCompositionTrack,
        compositionDuration: CMTime,
        allSegmentTracks: [(start: CMTime, duration: CMTime, sourceTrack: AVAssetTrack)]? = nil
    ) -> AVVideoComposition? {
        // Композицию строим, если есть текстовые сегменты ИЛИ включён логотип клуба.
        guard !segments.isEmpty || showLogo else { return nil }

        // Compute render size: max across all segment tracks, or from single videoTrack
        let renderSize: CGSize
        if let allTracks = allSegmentTracks, !allTracks.isEmpty {
            var maxW: CGFloat = 0
            var maxH: CGFloat = 0
            for info in allTracks {
                let o = info.sourceTrack.naturalSize.applying(info.sourceTrack.preferredTransform)
                maxW = max(maxW, abs(o.width))
                maxH = max(maxH, abs(o.height))
            }
            renderSize = CGSize(width: maxW, height: maxH)
        } else {
            let transform = videoTrack.preferredTransform
            let natural = videoTrack.naturalSize.applying(transform)
            renderSize = CGSize(width: abs(natural.width), height: abs(natural.height))
        }
        guard renderSize.width > 0, renderSize.height > 0 else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        // Per-segment instructions with scaling transforms for different resolutions
        if let allTracks = allSegmentTracks, !allTracks.isEmpty {
            var instructions: [AVMutableVideoCompositionInstruction] = []
            for info in allTracks {
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: info.start, duration: info.duration)
                let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
                let oriented = info.sourceTrack.naturalSize.applying(info.sourceTrack.preferredTransform)
                let srcW = abs(oriented.width)
                let srcH = abs(oriented.height)
                if srcW > 0, srcH > 0, (abs(srcW - renderSize.width) > 1 || abs(srcH - renderSize.height) > 1) {
                    let scaleX = renderSize.width / srcW
                    let scaleY = renderSize.height / srcH
                    let scale = min(scaleX, scaleY)
                    let scaledW = srcW * scale
                    let scaledH = srcH * scale
                    let tx = (renderSize.width - scaledW) / 2
                    let ty = (renderSize.height - scaledH) / 2
                    layerInstr.setTransform(
                        CGAffineTransform(scaleX: scale, y: scale)
                            .concatenating(CGAffineTransform(translationX: tx, y: ty)),
                        at: info.start
                    )
                } else {
                    layerInstr.setTransform(.identity, at: info.start)
                }
                instruction.layerInstructions = [layerInstr]
                instructions.append(instruction)
            }
            videoComposition.instructions = instructions
        } else {
            let transform = videoTrack.preferredTransform
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: compositionDuration)
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            layerInstruction.setTransform(transform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]
        }

        let total = CMTimeGetSeconds(compositionDuration)
        guard total > 0 else { return nil }

        let padding: CGFloat = 12

        // CALayer/CATextLayer setup and NSAttributedString measurement must happen on main thread
        var parentLayer: CALayer!
        var videoLayer: CALayer!

        let buildLayers = { [weak self] in
            guard let welf = self else { return }
            parentLayer = CALayer()
            parentLayer.frame = CGRect(origin: .zero, size: renderSize)
            videoLayer = CALayer()
            videoLayer.frame = parentLayer.frame
            parentLayer.addSublayer(videoLayer)

            for seg in segments {
                let attrStr = seg.text
                let textMaxWidth = renderSize.width - padding * 2
                let maxOverlayHeight = renderSize.height * 0.55
                let maxTextHeight = max(20, maxOverlayHeight - padding * 2)
                let fittedText = welf.fittedWatermarkText(attrStr, maxWidth: textMaxWidth, maxHeight: maxTextHeight)

                // boundingRect must run on main thread for accurate font metrics
                let textRect = fittedText.boundingRect(
                    with: CGSize(width: textMaxWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                // Ensure a minimum height so text is never clipped to zero
                let minHeight = max(ceil(textRect.height), 20)
                let overlayHeight = min(minHeight + padding * 2, maxOverlayHeight)

                let bgLayer = CALayer()
                bgLayer.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
                bgLayer.frame = CGRect(x: 0, y: 0, width: renderSize.width, height: overlayHeight)
                parentLayer.addSublayer(bgLayer)

                let textLayer = CATextLayer()
                textLayer.string = fittedText
                textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
                textLayer.alignmentMode = .left
                textLayer.isWrapped = true
                textLayer.truncationMode = .end
                textLayer.frame = CGRect(x: padding, y: padding, width: textMaxWidth, height: overlayHeight - padding * 2)
                textLayer.displayIfNeeded()
                parentLayer.addSublayer(textLayer)

                let start = CMTimeGetSeconds(seg.start)
                let dur = CMTimeGetSeconds(seg.duration)
                let endFrac = min(1.0 - 1e-7, (start + dur) / total)

                let opacity = CAKeyframeAnimation(keyPath: "opacity")
                if start < 1e-6 {
                    // Starts at composition time 0: visible immediately, no fade-in delay
                    opacity.values = [1, 0, 0]
                    opacity.keyTimes = [0, NSNumber(value: endFrac), 1]
                } else {
                    let startFrac = start / total
                    opacity.values = [0, 1, 0, 0]
                    opacity.keyTimes = [0, NSNumber(value: startFrac), NSNumber(value: endFrac), 1]
                }
                opacity.duration = total
                opacity.beginTime = AVCoreAnimationBeginTimeAtZero
                opacity.isRemovedOnCompletion = false
                // .both ensures the first keyframe value is used BEFORE the animation starts,
                // eliminating any invisible period at the beginning of the video.
                opacity.fillMode = .both
                opacity.calculationMode = .discrete

                bgLayer.add(opacity, forKey: "opacity")
                textLayer.add(opacity.copy() as! CAKeyframeAnimation, forKey: "opacity")
            }

            // Логотип клуба — статично на весь ролик, поверх текстового оверлея.
            if welf.showLogo,
               let logoLayer = ClubLogoWatermarkManager.shared.makeLogoLayer(renderSize: renderSize) {
                parentLayer.addSublayer(logoLayer)
            }
        }

        if Thread.isMainThread {
            buildLayers()
        } else {
            DispatchQueue.main.sync { buildLayers() }
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        return videoComposition
    }

    /// Builds a colored NSAttributedString overlay for a SportCut event, respecting watermark options.
    private func watermarkAttributedString(
        event: SportCutEvent,
        source: SportCutSource,
        playlist: SportCutPlaylist,
        ordinal: Int,
        videoTrack: AVAssetTrack?
    ) -> NSAttributedString {
        let options = watermarkOptions
        let videoSize: CGSize? = videoTrack.map {
            let n = $0.naturalSize.applying($0.preferredTransform)
            return CGSize(width: abs(n.width), height: abs(n.height))
        }
        let fontSize: CGFloat = videoSize.map { max(($0.height / 360) * 13, 10) } ?? 13

        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.systemGreen
        ]
        let eventAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.systemOrange
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.white
        ]
        let groupAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white
        ]

        let result = NSMutableAttributedString()

        // Line 1: [ordinal prefix if enabled] + tag name + [time events if tagAndLabels enabled]
        if options.showEpisodeNumbering || options.showTagAndLabels {
            let timeEvents = event.eventIDs.compactMap { id in source.timeEvents.first { $0.id == id } }

            var lineStart = ""
            if options.showEpisodeNumbering {
                lineStart += "\(ordinal). "
            }
            lineStart += event.tagName
            result.append(NSAttributedString(string: lineStart, attributes: tagAttrs))

            if options.showTagAndLabels && !timeEvents.isEmpty {
                result.append(NSAttributedString(string: " • ", attributes: tagAttrs))
                let eventsStr = timeEvents.enumerated().map { i, e in
                    e.name + (i < timeEvents.count - 1 ? ", " : "")
                }.joined()
                result.append(NSAttributedString(string: eventsStr, attributes: eventAttrs))
            }
            let hasLabels = options.showTagAndLabels && !event.labelIDs.isEmpty
            let comment = (playlist.eventComments[event.hiddenKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hasComment = options.showComment && !comment.isEmpty
            if hasLabels || hasComment {
                result.append(NSAttributedString(string: "\n", attributes: tagAttrs))
            }
        }

        // Line 2: all label groups in one row: "Group A: L1, L2 • Group B: L3"
        if options.showTagAndLabels {
            let stampLabels = event.labelIDs.compactMap { source.findLabel(byID: $0) }
            var grouped: [(group: LabelGroupData, labels: [Label])] = []
            for label in stampLabels {
                if let g = source.labelGroups.first(where: { $0.lables.contains(label.id) }) {
                    if let idx = grouped.firstIndex(where: { $0.group.id == g.id }) {
                        grouped[idx].labels.append(label)
                    } else {
                        grouped.append((group: g, labels: [label]))
                    }
                }
            }
            let sortedGroups = grouped.sorted { $0.group.labelGroupDisplayName < $1.group.labelGroupDisplayName }
            for (groupIndex, item) in sortedGroups.enumerated() {
                let labelsJoined = item.labels.map(\.name).joined(separator: ", ")
                result.append(
                    NSAttributedString(
                        string: "\(item.group.labelGroupDisplayName):",
                        attributes: groupAttrs
                    )
                )
                result.append(
                    NSAttributedString(
                        string: " \(labelsJoined)",
                        attributes: labelAttrs
                    )
                )
                if groupIndex < sortedGroups.count - 1 {
                    result.append(NSAttributedString(string: " • ", attributes: labelAttrs))
                }
            }
            let comment = (playlist.eventComments[event.hiddenKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if options.showComment && !comment.isEmpty {
                result.append(NSAttributedString(string: "\n", attributes: labelAttrs))
            }
        }

        // Last line: comment (only when comment is enabled)
        if options.showComment {
            let comment = (playlist.eventComments[event.hiddenKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !comment.isEmpty {
                result.append(NSAttributedString(string: comment, attributes: labelAttrs))
            }
        }

        return result
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

    /// Creates a video composition that scales all segments to a uniform render size (no watermark).
    private func scalingVideoComposition(
        compositionVideoTrack: AVMutableCompositionTrack,
        allSegmentTracks: [(start: CMTime, duration: CMTime, sourceTrack: AVAssetTrack)]
    ) -> AVMutableVideoComposition? {
        guard allSegmentTracks.count > 1 else { return nil }
        var maxW: CGFloat = 0
        var maxH: CGFloat = 0
        for info in allSegmentTracks {
            let o = info.sourceTrack.naturalSize.applying(info.sourceTrack.preferredTransform)
            maxW = max(maxW, abs(o.width))
            maxH = max(maxH, abs(o.height))
        }
        guard maxW > 0, maxH > 0 else { return nil }
        let renderSize = CGSize(width: maxW, height: maxH)
        let hasDifferentSizes = allSegmentTracks.contains { info in
            let o = info.sourceTrack.naturalSize.applying(info.sourceTrack.preferredTransform)
            return abs(abs(o.width) - renderSize.width) > 1 || abs(abs(o.height) - renderSize.height) > 1
        }
        guard hasDifferentSizes else { return nil }

        let vc = AVMutableVideoComposition()
        vc.renderSize = renderSize
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        var instructions: [AVMutableVideoCompositionInstruction] = []
        for info in allSegmentTracks {
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: info.start, duration: info.duration)
            let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            let oriented = info.sourceTrack.naturalSize.applying(info.sourceTrack.preferredTransform)
            let srcW = abs(oriented.width)
            let srcH = abs(oriented.height)
            if srcW > 0, srcH > 0, (abs(srcW - renderSize.width) > 1 || abs(srcH - renderSize.height) > 1) {
                let scaleX = renderSize.width / srcW
                let scaleY = renderSize.height / srcH
                let scale = min(scaleX, scaleY)
                let scaledW = srcW * scale
                let scaledH = srcH * scale
                let tx = (renderSize.width - scaledW) / 2
                let ty = (renderSize.height - scaledH) / 2
                layerInstr.setTransform(
                    CGAffineTransform(scaleX: scale, y: scale)
                        .concatenating(CGAffineTransform(translationX: tx, y: ty)),
                    at: info.start
                )
            } else {
                layerInstr.setTransform(.identity, at: info.start)
            }
            instruction.layerInstructions = [layerInstr]
            instructions.append(instruction)
        }
        vc.instructions = instructions
        return vc
    }

    /// Общий прогресс экспорта клипов, потокобезопасно (таймер прогресса читает из фонового потока).
    private final class ClipsProgress {
        private let lock = NSLock()
        private var completed = 0
        private var session: AVAssetExportSession?
        func setSession(_ s: AVAssetExportSession?) { lock.lock(); session = s; lock.unlock() }
        func markCompleted() { lock.lock(); completed += 1; session = nil; lock.unlock() }
        func snapshot() -> (done: Int, frac: Double) {
            lock.lock(); let c = completed; let p = Double(session?.progress ?? 0); lock.unlock()
            return (c, p)
        }
    }

    /// Клипы экспортируются ПОСЛЕДОВАТЕЛЬНО (не все разом) — иначе десятки параллельных
    /// AVAssetExportSession (особенно с вотермаркой) перегружают систему и «вешают» экспорт.
    private func exportAsClips(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let drawingsFolder = SportCutPlayerManager.drawingsFolder(sessionID: session.id)

        struct EventEntry {
            let event: SportCutEvent
            let playlist: SportCutPlaylist
        }
        let allEntries: [EventEntry] = playlists.flatMap { pl in pl.events.map { EventEntry(event: $0, playlist: pl) } }
        let total = max(allEntries.count, 1)

        var producedFiles: [URL] = []
        var failures = 0
        let prog = ClipsProgress()

        // Экспорт клипов — 0…0.9, упаковка zip — 0.9…1.0.
        startProgressPolling {
            let s = prog.snapshot()
            return min((Double(s.done) + s.frac) / Double(total) * 0.9, 0.9)
        }

        func finishZip() {
            guard !producedFiles.isEmpty else {
                try? FileManager.default.removeItem(at: tempDir)
                self.finishError(^String.Titles.exportErrorNothingProduced)
                return
            }
            do {
                try Self.writeZip(files: producedFiles, to: outputURL) { frac in
                    DispatchQueue.main.async { self.ui.progress = 0.9 + frac * 0.1 }
                }
                try? FileManager.default.removeItem(at: tempDir)
                self.finishSuccess()
            } catch {
                try? FileManager.default.removeItem(at: tempDir)
                self.finishError(error.localizedDescription)
            }
        }

        func exportNext(_ index: Int) {
            guard index < allEntries.count else { finishZip(); return }
            let entry = allEntries[index]
            let event = resolvedEvent(entry.event, playlist: entry.playlist, session: session)
            let drawings = entry.playlist.eventDrawings[entry.event.hiddenKey] ?? []

            func skip() { failures += 1; exportNext(index + 1) }

            guard let source = session.sources.first(where: { $0.id == event.sourceID }),
                  let url = source.mediaAccessURL() else { skip(); return }
            let securityURL = url

            let asset = AVAsset(url: url)
            let composition = AVMutableComposition()
            guard let videoTrack = asset.tracks(withMediaType: .video).first,
                  composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) != nil else {
                securityURL.stopAccessingSecurityScopedResource(); skip(); return
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
                    securityURL.stopAccessingSecurityScopedResource(); skip(); return
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
                securityURL.stopAccessingSecurityScopedResource(); skip(); return
            }

            exportSession.outputURL = clipURL
            exportSession.outputFileType = .mp4

            if (addWatermark || showLogo), let compVideoTrack = composition.tracks(withMediaType: .video).first {
                // При выключенном текстовом вотермарке сегменты пустые — рисуется только логотип.
                var segs: [(text: NSAttributedString, start: CMTime, duration: CMTime)] = []
                if addWatermark {
                    let wmText = watermarkAttributedString(
                        event: entry.event,
                        source: source,
                        playlist: entry.playlist,
                        ordinal: index + 1,
                        videoTrack: videoTrack
                    )
                    segs = [(text: wmText, start: CMTime.zero, duration: composition.duration)]
                }
                if let vc = watermarkVideoComposition(
                    segments: segs,
                    videoTrack: videoTrack,
                    compositionVideoTrack: compVideoTrack,
                    compositionDuration: composition.duration
                ) {
                    exportSession.videoComposition = vc
                }
            }

            prog.setSession(exportSession)
            exportSession.exportAsynchronously {
                securityURL.stopAccessingSecurityScopedResource()
                if exportSession.status == .completed {
                    producedFiles.append(clipURL)
                } else {
                    failures += 1
                }
                prog.markCompleted()
                exportNext(index + 1)
            }
        }

        exportNext(0)
    }

    // MARK: - Streaming ZIP (store, no compression) — не держит все файлы в памяти сразу.

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for byte in raw {
                crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func le32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
    private static func le16(_ v: UInt16) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }

    /// Дата/время в формате MS-DOS для zip-заголовков (иначе распакованные файлы получают дату 1980).
    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let comps = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        let year: Int = max(1980, comps.year ?? 1980)
        let month: Int = comps.month ?? 1
        let day: Int = comps.day ?? 1
        let hour: Int = comps.hour ?? 0
        let minute: Int = comps.minute ?? 0
        let second: Int = comps.second ?? 0

        let dateBits: Int = ((year - 1980) << 9) | (month << 5) | day
        let timeBits: Int = (hour << 11) | (minute << 5) | (second / 2)
        return (UInt16(truncatingIfNeeded: timeBits), UInt16(truncatingIfNeeded: dateBits))
    }

    /// Пишет zip потоково прямо в файл (по одному входному файлу в памяти за раз), считая CRC один раз.
    private static func writeZip(files: [URL], to outputURL: URL, progress: (Double) -> Void) throws {
        try? FileManager.default.removeItem(at: outputURL)
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: outputURL) else {
            throw NSError(domain: "SportCutZip", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create archive"])
        }
        defer { try? handle.close() }

        struct CentralEntry { let name: Data; let crc: UInt32; let size: UInt32; let offset: UInt32 }
        var central: [CentralEntry] = []
        var offset: UInt32 = 0
        let count = max(files.count, 1)
        let (dosTime, dosDate) = dosDateTime(Date())

        for (i, file) in files.enumerated() {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            let name = Data(file.lastPathComponent.utf8)
            let crc = crc32(data)
            let size = UInt32(truncatingIfNeeded: data.count)

            var local = Data()
            local.append(contentsOf: [0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00])
            local.append(contentsOf: le16(dosTime))
            local.append(contentsOf: le16(dosDate))
            local.append(contentsOf: le32(crc))
            local.append(contentsOf: le32(size)) // compressed
            local.append(contentsOf: le32(size)) // uncompressed
            local.append(contentsOf: le16(UInt16(name.count)))
            local.append(contentsOf: [0x00, 0x00]) // extra len
            local.append(name)

            try handle.write(contentsOf: local)
            try handle.write(contentsOf: data)

            central.append(CentralEntry(name: name, crc: crc, size: size, offset: offset))
            offset += UInt32(local.count) + size
            progress(Double(i + 1) / Double(count))
        }

        var centralData = Data()
        for e in central {
            var entry = Data()
            entry.append(contentsOf: [0x50, 0x4B, 0x01, 0x02, 0x14, 0x00, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00])
            entry.append(contentsOf: le16(dosTime))
            entry.append(contentsOf: le16(dosDate))
            entry.append(contentsOf: le32(e.crc))
            entry.append(contentsOf: le32(e.size))
            entry.append(contentsOf: le32(e.size))
            entry.append(contentsOf: le16(UInt16(e.name.count)))
            entry.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) // extra/comment/disk/attrs
            entry.append(contentsOf: le32(e.offset))
            entry.append(e.name)
            centralData.append(entry)
        }
        let centralOffset = offset
        try handle.write(contentsOf: centralData)

        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4B, 0x05, 0x06, 0x00, 0x00, 0x00, 0x00])
        eocd.append(contentsOf: le16(UInt16(central.count)))
        eocd.append(contentsOf: le16(UInt16(central.count)))
        eocd.append(contentsOf: le32(UInt32(centralData.count)))
        eocd.append(contentsOf: le32(centralOffset))
        eocd.append(contentsOf: [0x00, 0x00])
        try handle.write(contentsOf: eocd)
    }

    private func exportAsFilm(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession) {
        // Сначала рендерим титульные слайды в видео, потом собираем фильм.
        let allSlides = playlists.flatMap { $0.slides }
        SportCutSlideVideoRenderer.renderVideos(for: allSlides) { [self] slideURLs in
            DispatchQueue.global(qos: .userInitiated).async {
                self.exportAsFilmBuild(playlists: playlists, outputURL: outputURL, session: session, slideURLs: slideURLs)
            }
        }
    }

    private func exportAsFilmBuild(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession, slideURLs: [UUID: URL]) {
        let drawingsFolder = SportCutPlayerManager.drawingsFolder(sessionID: session.id)
        let composition = AVMutableComposition()

        guard composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) != nil else {
            finishError(^String.Titles.exportErrorFailedGeneric)
            return
        }

        _ = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var currentTime = CMTime.zero
        var securityURLs: [URL] = []
        var wmSegments: [(text: NSAttributedString, start: CMTime, duration: CMTime)] = []
        var firstVideoTrack: AVAssetTrack?
        var eventOrdinal = 0
        var allSegmentTracks: [(start: CMTime, duration: CMTime, sourceTrack: AVAssetTrack)] = []

        for playlist in playlists {
            for rawEvent in interleavedExportEvents(playlist) {
                // Титульный слайд: вставляем отрендеренный видео-сегмент без звука/рисунков/вотермарки.
                if rawEvent.isSlide {
                    currentTime = insertSlideSegment(
                        event: rawEvent, slideURLs: slideURLs, composition: composition,
                        startTime: currentTime, firstVideoTrack: &firstVideoTrack, allSegmentTracks: &allSegmentTracks
                    )
                    continue
                }
                let event = resolvedEvent(rawEvent, playlist: playlist, session: session)
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
                eventOrdinal += 1

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

                allSegmentTracks.append((start: segStart, duration: CMTimeSubtract(currentTime, segStart), sourceTrack: vTrack))

                if addWatermark {
                    let segDuration = CMTimeSubtract(currentTime, segStart)
                    let wmText = watermarkAttributedString(
                        event: rawEvent,
                        source: source,
                        playlist: playlist,
                        ordinal: eventOrdinal,
                        videoTrack: vTrack
                    )
                    wmSegments.append((text: wmText, start: segStart, duration: segDuration))
                }
            }
        }

        guard composition.duration.seconds > 0 else {
            securityURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            finishError(^String.Titles.exportErrorNothingProduced)
            return
        }

        let preset = Self.bestPreset(for: composition)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
            securityURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            finishError(^String.Titles.exportErrorFailedGeneric)
            return
        }

        try? FileManager.default.removeItem(at: outputURL)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        if ((addWatermark && !wmSegments.isEmpty) || showLogo),
           let vTrack = firstVideoTrack,
           let compVideoTrack = composition.tracks(withMediaType: .video).first {
            if let vc = watermarkVideoComposition(
                segments: wmSegments,
                videoTrack: vTrack,
                compositionVideoTrack: compVideoTrack,
                compositionDuration: composition.duration,
                allSegmentTracks: allSegmentTracks
            ) {
                exportSession.videoComposition = vc
            }
        } else if let compVideoTrack = composition.tracks(withMediaType: .video).first {
            if let vc = scalingVideoComposition(
                compositionVideoTrack: compVideoTrack,
                allSegmentTracks: allSegmentTracks
            ) {
                exportSession.videoComposition = vc
            }
        }

        startProgressPolling { Double(exportSession.progress) }
        exportSession.exportAsynchronously {
            securityURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            switch exportSession.status {
            case .completed:
                self.finishSuccess()
            case .failed, .cancelled:
                self.finishError(exportSession.error?.localizedDescription ?? (^String.Titles.exportErrorFailedGeneric))
            default:
                self.finishError(^String.Titles.exportErrorFailedGeneric)
            }
        }
    }

    private func exportAsFilmPerPlaylist(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession) {
        let allSlides = playlists.flatMap { $0.slides }
        SportCutSlideVideoRenderer.renderVideos(for: allSlides) { [self] slideURLs in
            DispatchQueue.global(qos: .userInitiated).async {
                self.exportAsFilmPerPlaylistBuild(playlists: playlists, outputURL: outputURL, session: session, slideURLs: slideURLs)
            }
        }
    }

    private func exportAsFilmPerPlaylistBuild(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession, slideURLs: [UUID: URL]) {
        _ = ui
        let parentDir = outputURL.deletingLastPathComponent()
        let baseName = outputURL.deletingPathExtension().lastPathComponent
        let drawingsFolder = SportCutPlayerManager.drawingsFolder(sessionID: session.id)

        let group = DispatchGroup()
        var sessions: [AVAssetExportSession] = []
        let resultLock = NSLock()
        var succeeded = 0
        var lastError: String?

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
            var wmSegments: [(text: NSAttributedString, start: CMTime, duration: CMTime)] = []
            var firstVideoTrack: AVAssetTrack?
            var eventOrdinal = 0
            var allSegmentTracks: [(start: CMTime, duration: CMTime, sourceTrack: AVAssetTrack)] = []

            for rawEvent in interleavedExportEvents(playlist) {
                if rawEvent.isSlide {
                    currentTime = insertSlideSegment(
                        event: rawEvent, slideURLs: slideURLs, composition: composition,
                        startTime: currentTime, firstVideoTrack: &firstVideoTrack, allSegmentTracks: &allSegmentTracks
                    )
                    continue
                }
                let event = resolvedEvent(rawEvent, playlist: playlist, session: session)
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
                eventOrdinal += 1

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

                allSegmentTracks.append((start: segStart, duration: CMTimeSubtract(currentTime, segStart), sourceTrack: vTrack))

                if addWatermark {
                    let segDuration = CMTimeSubtract(currentTime, segStart)
                    let wmText = watermarkAttributedString(
                        event: rawEvent,
                        source: source,
                        playlist: playlist,
                        ordinal: eventOrdinal,
                        videoTrack: vTrack
                    )
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

            if ((addWatermark && !wmSegments.isEmpty) || showLogo),
               let vTrack = firstVideoTrack,
               let compVideoTrack = composition.tracks(withMediaType: .video).first {
                if let vc = watermarkVideoComposition(
                    segments: wmSegments,
                    videoTrack: vTrack,
                    compositionVideoTrack: compVideoTrack,
                    compositionDuration: composition.duration,
                    allSegmentTracks: allSegmentTracks
                ) {
                    exportSession.videoComposition = vc
                }
            } else if let compVideoTrack = composition.tracks(withMediaType: .video).first {
                if let vc = scalingVideoComposition(
                    compositionVideoTrack: compVideoTrack,
                    allSegmentTracks: allSegmentTracks
                ) {
                    exportSession.videoComposition = vc
                }
            }

            sessions.append(exportSession)
            exportSession.exportAsynchronously {
                securityURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                resultLock.lock()
                if exportSession.status == .completed {
                    succeeded += 1
                } else {
                    lastError = exportSession.error?.localizedDescription ?? lastError
                }
                resultLock.unlock()
                group.leave()
            }
        }

        // Средний прогресс по всем сессиям плейлистов.
        startProgressPolling {
            guard !sessions.isEmpty else { return 0 }
            let sum = sessions.reduce(0.0) { $0 + Double($1.progress) }
            return sum / Double(sessions.count)
        }

        group.notify(queue: .main) {
            resultLock.lock(); let ok = succeeded; let err = lastError; resultLock.unlock()
            if ok > 0 {
                self.finishSuccess()
            } else {
                self.finishError(err ?? (^String.Titles.exportErrorNothingProduced))
            }
        }
    }
}
