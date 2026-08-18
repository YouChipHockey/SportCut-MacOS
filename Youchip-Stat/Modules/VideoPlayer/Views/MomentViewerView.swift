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
    let player = AVPlayer().applyDebugMuteIfNeeded()
    let tagName: String
    let lineName: String
    let lineID: UUID?
    let stampID: UUID?
    /// Длительность исходного ассета (сек), для ограничения видимого окна мини-таймлайна.
    private(set) var sourceAssetDuration: Double

    @Published private(set) var displayStartTime: Double
    @Published private(set) var displayDuration: Double
    @Published private(set) var compositionPlaybackSeconds: Double = 0
    /// true, если исходный буфер ещё не покрывает всю длительность тега (напр. «время после» ещё не
    /// дозаписалось в лайве). Тогда во вью показываем плашку «не дозаписано» + кнопку «Обновить».
    @Published private(set) var isTruncated: Bool = false
    /// Идёт повторное вытягивание буфера по кнопке «Обновить».
    @Published private(set) var isRefreshing: Bool = false

    /// Запрошенная (полная) длительность тега — до обрезки под доступный буфер. Нужна для детекта обрезки.
    private var requestedDuration: Double
    /// Разрешён ли рефреш буфера (только лайв-разметка). В остальных режимах ассет полный.
    let allowsRefresh: Bool
    /// Поставщик свежего ассета (форс-финализация буфера) для кнопки «Обновить». nil — рефреш недоступен.
    private let assetProvider: ((@escaping (AVAsset?) -> Void) -> Void)?

    private var sourceAsset: AVAsset
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var didInvalidate = false
    /// Во время resize-preview загружен исходный ассет и идут только seek'и (без постоянного replace item).
    private var isResizePreviewMode = false
    /// Увеличивается на каждый `configure`, чтобы игнорировать устаревшие completion после `replaceCurrentItem`.
    private var configureGeneration: Int = 0
    /// Не перезаписывать время с плеера сразу после seek/reconfigure (убирает «дёрганье» плейхеда у конца).
    private var suppressPeriodicTimeUntil: Date?

    /// Единый «зазор» у конца локальной шкалы композиции (сек), чтобы плейхед не дёргался между seek и periodic time.
    private static let compositionEndSlip = 1e-4

    private func maxCompositionLocalSeconds(duration d: Double) -> Double {
        let dd = max(d, 0.000_001)
        return max(0, dd * (1 - Self.compositionEndSlip))
    }

    init(
        asset: AVAsset,
        startTime: Double,
        duration: Double,
        sourceAssetDuration: Double,
        tagName: String,
        lineName: String,
        lineID: UUID? = nil,
        stampID: UUID? = nil,
        allowsRefresh: Bool = false,
        assetProvider: ((@escaping (AVAsset?) -> Void) -> Void)? = nil
    ) {
        self.sourceAsset = asset
        self.tagName = tagName
        self.lineName = lineName
        self.lineID = lineID
        self.stampID = stampID
        self.allowsRefresh = allowsRefresh
        self.assetProvider = assetProvider
        self.displayStartTime = startTime
        self.displayDuration = max(duration, 0.000_001)
        self.requestedDuration = max(duration, 0.000_001)
        let ad = sourceAssetDuration.isFinite && sourceAssetDuration > 0
            ? sourceAssetDuration
            : (startTime + duration + 1)
        self.sourceAssetDuration = max(ad, startTime + duration + 0.01)
        // Без автоплея при открытии: иначе короткий клип уходит в конец, мини-таймлайн на Intel успевает
        // отрисоваться с неверным скроллом до первого центрирования — тег «мигает» и пропадает.
        configure(anchorAbsoluteTime: nil, resumePlaybackAfterSeek: false)
    }

    /// Пересобрать клип после изменения границ тега на таймлайне. `anchorAbsoluteTime` — абсолютное время видео, которое остаётся на экране (nil → начало клипа).
    /// `resumePlaybackAfterSeek`: false при частых обновлениях во время жеста — иначе каждый `replaceCurrentItem` + `play()` даёт «мигание» play/pause.
    func recompose(startTime: Double, duration: Double, anchorAbsoluteTime: Double?, resumePlaybackAfterSeek: Bool = true) {
        displayStartTime = startTime
        displayDuration = max(duration, 0.5)
        requestedDuration = max(duration, 0.5)
        configure(anchorAbsoluteTime: anchorAbsoluteTime, resumePlaybackAfterSeek: resumePlaybackAfterSeek)
    }

    func pausePlayback() {
        player.pause()
    }

    /// По кнопке «Обновить»: повторно вытягивает буфер (форс-финализация) и пересобирает клип,
    /// чтобы дозаписавшееся «время после» тега попало в нарезку — без закрытия/переоткрытия окна.
    func refresh() {
        guard allowsRefresh, !isRefreshing, !didInvalidate, let assetProvider else { return }
        isRefreshing = true
        assetProvider { [weak self] newAsset in
            Task { @MainActor [weak self] in
                guard let self, !self.didInvalidate else { return }
                defer { self.isRefreshing = false }
                guard let newAsset else { return }
                self.sourceAsset = newAsset
                let ad = CMTimeGetSeconds(newAsset.duration)
                if ad.isFinite, ad > 0 {
                    self.sourceAssetDuration = max(ad, self.displayStartTime + self.requestedDuration + 0.01)
                }
                self.configure(anchorAbsoluteTime: nil, resumePlaybackAfterSeek: false)
            }
        }
    }

    /// Локальное время внутри композиции (0…cap), то же ограничение, что в `seekToCompositionTime`.
    func clampedCompositionLocal(_ localSeconds: Double) -> Double {
        let d = max(displayDuration, 0.000_001)
        let cap = maxCompositionLocalSeconds(duration: d)
        return max(0, min(localSeconds, cap))
    }

    func seekToCompositionTime(_ seconds: Double) {
        let d = max(displayDuration, 0.000_001)
        let cap = maxCompositionLocalSeconds(duration: d)
        let clamped = max(0, min(seconds, cap))
        suppressPeriodicTimeUntil = Date().addingTimeInterval(0.22)
        compositionPlaybackSeconds = clamped
        let cm = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: CMTime(seconds: 0.02, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.02, preferredTimescale: 600)) { [weak self] finished in
            guard let self, finished, !self.didInvalidate else { return }
            self.suppressPeriodicTimeUntil = Date().addingTimeInterval(0.16)
            self.compositionPlaybackSeconds = min(max(0, CMTimeGetSeconds(self.player.currentTime())), cap)
        }
    }

    /// Preview при изменении границ тега: один раз переключаемся на исходный ассет, дальше только seek.
    /// Это убирает "черные кадры" от частого `replaceCurrentItem` во время drag.
    func seekPreviewDuringResize(absoluteVideoTime: Double) {
        guard !didInvalidate else { return }
        player.pause()
        let targetAbs = max(0, min(absoluteVideoTime, sourceAssetDuration))
        let cm = CMTime(seconds: targetAbs, preferredTimescale: 600)
        let tol = CMTime(seconds: 0.05, preferredTimescale: 600)

        if isResizePreviewMode {
            player.seek(to: cm, toleranceBefore: tol, toleranceAfter: tol)
            return
        }

        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        if let old = timeObserver {
            player.removeTimeObserver(old)
            timeObserver = nil
        }

        isResizePreviewMode = true
        let item = AVPlayerItem(asset: sourceAsset)
        player.replaceCurrentItem(with: item)
        suppressPeriodicTimeUntil = Date().addingTimeInterval(0.2)
        let local = max(0, min(targetAbs - displayStartTime, maxCompositionLocalSeconds(duration: displayDuration)))
        compositionPlaybackSeconds = local
        player.seek(to: cm, toleranceBefore: tol, toleranceAfter: tol)
    }

    private func configure(anchorAbsoluteTime: Double?, resumePlaybackAfterSeek: Bool) {
        configureGeneration += 1
        let generation = configureGeneration
        isResizePreviewMode = false
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        if let old = timeObserver {
            player.removeTimeObserver(old)
            timeObserver = nil
        }

        let composition = AVMutableComposition()

        let videoTracks = sourceAsset.tracks(withMediaType: .video)
        let audioTracks = sourceAsset.tracks(withMediaType: .audio)
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

        let assetDuration = CMTimeGetSeconds(sourceAsset.duration)
        let safeStart = max(0.0, min(displayStartTime, assetDuration))
        let maxAvailable = max(0.0, assetDuration - safeStart)
        // Считаем от ПОЛНОЙ запрошенной длительности тега (а не от ранее обрезанной displayDuration),
        // чтобы после рефреша (более длинный буфер) клип снова дотягивался до полной длины.
        let safeDuration = min(max(0.0, requestedDuration), maxAvailable)

        // Обрезка: доступного буфера не хватает на всю длительность тега (напр. «время после» в лайве
        // ещё не дозаписалось). Показываем плашку + кнопку «Обновить» (только в лайв-разметке).
        isTruncated = allowsRefresh && (requestedDuration - safeDuration) > 0.1

        guard safeDuration > 0 else { return }

        displayStartTime = safeStart
        displayDuration = safeDuration

        let startCM = CMTime(seconds: safeStart, preferredTimescale: 600)
        let durationCM = CMTime(seconds: safeDuration, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startCM, duration: durationCM)

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

        suppressPeriodicTimeUntil = Date().addingTimeInterval(0.22)

        let anchor = anchorAbsoluteTime ?? safeStart
        let capLocal = maxCompositionLocalSeconds(duration: safeDuration)
        let localSeek = max(0, min(anchor - safeStart, capLocal))
        compositionPlaybackSeconds = localSeek

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.didInvalidate else { return }
            if let u = self.suppressPeriodicTimeUntil, Date() < u { return }
            let raw = CMTimeGetSeconds(time)
            guard raw.isFinite else { return }
            let d = max(self.displayDuration, 0.000_001)
            let cap = self.maxCompositionLocalSeconds(duration: d)
            let capped = min(max(0, raw), cap)
            if abs(capped - self.compositionPlaybackSeconds) < 0.0003 { return }
            self.compositionPlaybackSeconds = capped
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.didInvalidate else { return }
            let d = max(self.displayDuration, 0.000_001)
            let endT = self.maxCompositionLocalSeconds(duration: d)
            self.player.seek(to: CMTime(seconds: endT, preferredTimescale: 600), toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
            self.player.pause()
            self.compositionPlaybackSeconds = endT
            self.suppressPeriodicTimeUntil = Date().addingTimeInterval(0.35)
        }

        let seekCM = CMTime(seconds: localSeek, preferredTimescale: 600)
        player.seek(to: seekCM, toleranceBefore: CMTime(seconds: 0.02, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.02, preferredTimescale: 600)) { [weak self] finished in
            guard let self, finished, !self.didInvalidate, self.configureGeneration == generation else { return }
            let d = max(self.displayDuration, 0.000_001)
            let cap = self.maxCompositionLocalSeconds(duration: d)
            let t = min(max(0, CMTimeGetSeconds(self.player.currentTime())), cap)
            self.compositionPlaybackSeconds = t
            self.suppressPeriodicTimeUntil = Date().addingTimeInterval(0.2)
            if resumePlaybackAfterSeek {
                self.player.play()
            }
        }
    }

    func invalidate() {
        guard !didInvalidate else { return }
        didInvalidate = true

        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        if let t = timeObserver {
            player.removeTimeObserver(t)
            timeObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

/// Совпадает с `momentMiniTimelineMaxScale` в `MomentMiniTimelineView`.
private let momentViewerMiniTimelineMaxScale: CGFloat = 40

struct MomentViewerView: View {

    @ObservedObject var session: MomentViewerSession
    @ObservedObject private var timelineData = TimelineDataManager.shared
    @ObservedObject private var tagLibrary = TagLibraryManager.shared

    /// Масштаб мини-таймлайна (родитель держит слайдер и отдаёт ширину самой полосе).
    @State private var momentMiniTimelineScale: CGFloat = 1.0
    /// Увеличивается при каждом показе окна — мини-таймлайн снова ставит ~25% и центрирует тег.
    @State private var momentMiniLayoutEpoch = 0
    /// Отмеченные счётчики: их показываем поверх кадра момента.
    @State private var enabledClockStampIDs: Set<UUID> = []

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
        return stamp.labels.compactMap { labelItem in
            let name = tagLibrary.findLabelById(labelItem.id)?.name ?? labelItem.name
            return name.isEmpty ? nil : name
        }
    }

    /// Записи счётчиков, пересекающиеся с этим моментом. Считаются от ТЕКУЩИХ границ момента,
    /// поэтому ресайз клипа сам обновляет и список, и отрисовку.
    private var clockEntries: [MomentClockEntry] {
        MomentClocksFinder.entries(
            from: timelineData.lines,
            start: session.displayStartTime,
            duration: session.displayDuration
        )
    }

    /// Время в исходном видео: начало момента + позиция воспроизведения внутри клипа.
    private var sourceVideoTime: Double {
        session.displayStartTime + session.compositionPlaybackSeconds
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZoomableVideoPlayerView(player: session.player) {
                    VideoPlayer(player: session.player)
                }
                .background(Color.black)
                .overlay(alignment: .top) {
                    if session.isTruncated {
                        truncationBanner
                            .padding(.top, 10)
                            .padding(.horizontal, 10)
                    }
                }
                // Включённые счётчики идут прямо на кадре — значения те же, что были в разметке.
                .overlay(
                    MomentClocksOverlay(
                        entries: clockEntries,
                        enabledStampIDs: enabledClockStampIDs,
                        videoTime: sourceVideoTime
                    )
                )

                // Панель появляется только если в момент вообще попали счётчики.
                if !clockEntries.isEmpty {
                    Divider()
                    MomentClocksPanel(entries: clockEntries, enabledStampIDs: $enabledClockStampIDs)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(tagTitleWithOrder)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: 220, alignment: .leading)

                        MomentMiniTimelineView(
                            session: session,
                            stamp: sourceStamp,
                            lineID: session.lineID,
                            stampID: session.stampID,
                            timelineScale: $momentMiniTimelineScale,
                            layoutEpoch: momentMiniLayoutEpoch
                        )
                        .frame(height: 72)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                    }

                    HStack(alignment: .center, spacing: 0) {
                        Text(String(format: ^String.Titles.momentDurationLabel, session.displayDuration))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Spacer(minLength: 28)

                        HStack(alignment: .center, spacing: 8) {
                            Text(^String.Titles.momentScaleLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)

                            Slider(
                                value: Binding(
                                    get: { Double(momentMiniTimelineScale) },
                                    set: { v in
                                        momentMiniTimelineScale = CGFloat(
                                            min(momentViewerMiniTimelineMaxScale, max(1, v))
                                        )
                                    }
                                ),
                                in: 1...Double(momentViewerMiniTimelineMaxScale)
                            )
                            .controlSize(.small)
                            .labelsHidden()
                            .frame(width: 112)
                            .accessibilityLabel(^String.Titles.momentScaleAccessibility)

                            Text(String(format: "%.1fx", momentMiniTimelineScale))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

                if !stampEventNames.isEmpty || !stampLabelNames.isEmpty || !(sourceStamp?.comment ?? "").isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        if !stampEventNames.isEmpty {
                            Text(String.Titles.momentEventsPrefix.format(stampEventNames.joined(separator: ", ")))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if !stampLabelNames.isEmpty {
                            Text(String.Titles.momentLabelsPrefix.format(stampLabelNames.joined(separator: ", ")))
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor))
                }
            }
        }
        .onAppear {
            momentMiniLayoutEpoch += 1
        }
        .onDisappear {
            session.invalidate()
        }
    }

    /// Плашка «клип ещё не дозаписан» + кнопка «Обновить» (только в лайв-разметке).
    private var truncationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(^String.Titles.momentClipNotFullyRecorded)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: { session.refresh() }) {
                HStack(spacing: 5) {
                    if session.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(^String.Titles.momentRefreshClip)
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isRefreshing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.78))
        )
    }

    private func stampOrdinal(for stamp: TimelineStamp) -> Int {
        stamp.chronologicalOrdinalAmongSameTag(in: timelineData.lines)
    }
}
