//
//  VideoPlayerManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers
import Combine

class VideoPlayerManager: ObservableObject {
    
    static let shared = VideoPlayerManager()
    @Published var player: AVPlayer?
    @Published var playbackSpeed: Double = 1.0
    /// НЕ `@Published` осознанно. Тик плеера идёт 30 Гц, а на этот синглтон подписаны почти все
    /// экраны разметки — `@Published` здесь означал полную перестройку их `body` 30 раз в секунду
    /// (см. [[PlaybackClock]] и `vault/tasks/…/TASK-007`). Читать значение можно как раньше;
    /// подписываться на изменения — только через `PlaybackClock.shared`.
    var currentTime: Double = 0.0 {
        didSet { PlaybackClock.shared.update(currentTime) }
    }
    @Published var isPlaying: Bool = false
    @Published var isResizingTag: Bool = false // Track if user is resizing a tag
    /// Режим редактирования скриншота во вьюхе видео-окна (для обработки кнопки закрытия окна).
    var isVideoPlayerInEditorMode: Bool = false
    
    // MARK: - Live Mode
    @Published var isLiveMode: Bool = false
    @Published var isBroadcastActive: Bool = false
    
    // MARK: - Review Mode
    @Published var isReviewMode: Bool = false
    @Published var reviewPlayer: AVPlayer?
    /// Тоже не `@Published` — по той же причине, что и `currentTime` (10 Гц × все окна).
    /// Реактивных потребителей нет: значение читают только императивно (`VideoPlayerViewModel`),
    /// а на экране время review-плеера показывается через `PlaybackClock`.
    var reviewCurrentTime: Double = 0 {
        didSet { ReviewPlaybackClock.shared.update(reviewCurrentTime) }
    }
    @Published var reviewPlaybackSpeed: Double = 1.0
    /// В лайве с активным пересмотром: куда добавлять теги/разметку — по плейхеду ЛАЙВА (false) или
    /// по плейхеду ПЕРЕСМОТРА (true). Переключатель «Разметка лайва / Разметка пересмотра» (Opt+W).
    /// Вне пересмотра всегда лайв. Сбрасывается на выходе из пересмотра.
    @Published var markupUsesReviewTime: Bool = false

    /// Время, к которому привязывается новая разметка (тег/интервал/лейбл). В режиме «Разметка
    /// пересмотра» — позиция пересмотра, иначе — текущее время (лайв/обычное видео).
    var markupTime: Double {
        (isReviewMode && markupUsesReviewTime) ? reviewCurrentTime : currentTime
    }

    /// Время разметки для КОНКРЕТНОГО якоря, а не для текущего режима. Интервальная запись
    /// запоминает, с какого плейхеда стартовала, и им же заканчивается — даже если посреди записи
    /// переключили «Разметку лайва / пересмотра» (Opt+W). Иначе интервал склеивал бы два разных
    /// времени и получался кусок «из ниоткуда».
    func markupTime(usesReview: Bool) -> Double {
        (isReviewMode && usesReview) ? reviewCurrentTime : currentTime
    }

    /// Каким плейхедом сейчас ведут разметку — снимок для новой записи (см. `markupTime(usesReview:)`).
    var markupAnchorUsesReview: Bool { isReviewMode && markupUsesReviewTime }

    // MARK: - Review Screenshot Overlay
    @Published var reviewScreenshotImage: NSImage?
    @Published var isShowingReviewScreenshot: Bool = false

    private var reviewTimeObserver: Any?
    /// Пока активен — 10-герцовый observer пересмотра не перезаписывает `reviewCurrentTime`.
    /// Нужен на время seek'а: иначе бирюзовый плейхед во время перетаскивания дёргается назад,
    /// пока плеер не доехал до новой позиции (аналог `scrubTimelinePreviewSuppressUntil`).
    private var reviewSeekSuppressUntil: Date?
    private var reviewFileVersionCancellable: AnyCancellable?
    private var reviewItemStatusObserver: AnyCancellable?
    /// Strong reference that keeps the pending review player alive until it reaches readyToPlay and is swapped in.
    private var pendingReviewPlayer: AVPlayer?
    private var shouldSeekReviewToEndOnNextReady = false
    
    var videoDuration: Double {
        if isLiveMode {
            return LiveStreamManager.shared.liveDuration
        }
        return player?.currentItem?.duration.seconds ?? 0
    }

    /// Duration used for timelines and real-time markup.
    /// In live mode it always includes a 5 second buffer after the current stream time.
    var timelineDuration: Double {
        if isLiveMode {
            return LiveStreamManager.shared.liveDuration + 5.0
        }
        return videoDuration
    }
    private var timeObserverToken: Any?
    private var isSeeking = false
    /// Пока активен, периодический observer не перезаписывает `currentTime` (скраб плейхэда по таймлайну).
    private var scrubTimelinePreviewSuppressUntil: Date?
    private var cancellables = Set<AnyCancellable>()
    private var liveDurationCancellable: AnyCancellable?
    
    func loadVideo(from url: URL) {
        isLiveMode = false
        isBroadcastActive = false
        isSeeking = false
        player = AVPlayer(url: url).applyDebugMuteIfNeeded()
        player?.play()
        startTimeObserver()
        observePlayerState()
    }
    
    // MARK: - Live Mode
    
    func startLiveMode() {
        isLiveMode = true
        isBroadcastActive = true
        player = nil // No AVPlayer in live mode - we use preview layer
        currentTime = 0.0
        
        // `currentTime` следует за живой записью ДАЖЕ во время пересмотра — основной плейхед и
        // разметка остаются на лайве, пока пересмотр живёт своей позицией (см. review time observer).
        liveDurationCancellable = LiveStreamManager.shared.$liveDuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                guard let self = self, self.isLiveMode, self.isBroadcastActive else { return }
                self.currentTime = duration
            }
    }
    
    // MARK: - Review Mode
    
    private var isRefreshingReview: Bool = false
    
    func enterReviewMode() {
        guard isLiveMode else { return }
        isReviewMode = true
        shouldSeekReviewToEndOnNextReady = true
        LiveStreamManager.shared.startReviewRefresher()
        
        reviewFileVersionCancellable = LiveStreamManager.shared.$reviewFileVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshReviewPlayerItem()
            }
        refreshReviewPlayerItem()
    }
    
    func exitReviewMode() {
        // ДО сброса флага: записи, начатые по плейхеду пересмотра, закрываем по нему же и кладём
        // на таймлайн — иначе они бы «дописывались» лайвом или потерялись. Синхронно, чтобы
        // штампы успели лечь до того, как позиция пересмотра обнулится.
        if isReviewMode {
            NotificationCenter.default.post(name: .reviewModeWillClose, object: nil)
            ClockRuntimeManager.shared.finalizeReviewAnchored()
        }

        isReviewMode = false
        shouldSeekReviewToEndOnNextReady = false
        reviewFileVersionCancellable?.cancel()
        reviewFileVersionCancellable = nil
        reviewItemStatusObserver?.cancel()
        reviewItemStatusObserver = nil

        if let token = reviewTimeObserver {
            reviewPlayer?.removeTimeObserver(token)
            reviewTimeObserver = nil
        }
        reviewPlayer?.pause()
        reviewPlayer = nil
        pendingReviewPlayer = nil
        reviewSeekSuppressUntil = nil
        reviewCurrentTime = 0
        // Пересмотр закрыт — разметка снова только по лайву, бирюзовый плейхед в 0.
        markupUsesReviewTime = false
        isRefreshingReview = false
        reviewScreenshotImage = nil
        isShowingReviewScreenshot = false

        LiveStreamManager.shared.stopReviewRefresher()
    }
    
    func seekReview(to time: Double, resumePlaybackAfterSeek: Bool = false) {
        guard let player = reviewPlayer else { return }
        let clamped = max(0, min(time, reviewDuration > 0 ? reviewDuration : time))
        // Позицию проставляем сразу: observer пересмотра тикает 10 Гц, и без этого бирюзовый
        // плейхед после отпускания «отскакивал» назад на старое значение.
        reviewCurrentTime = clamped
        reviewSeekSuppressUntil = Date().addingTimeInterval(0.3)
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self else { return }
            self.reviewSeekSuppressUntil = nil
            if resumePlaybackAfterSeek, finished, self.isReviewMode {
                self.reviewPlayer?.play()
                self.reviewPlayer?.rate = Float(self.reviewPlaybackSpeed)
            }
        }
    }

    /// Длительность склейки пересмотра (кадры, записанные к этому моменту).
    var reviewDuration: Double {
        let d = reviewPlayer?.currentItem?.duration.seconds ?? 0
        return d.isFinite ? d : 0
    }

    /// Быстрый превью-seek бирюзового плейхеда во время перетаскивания: с допуском (чтобы кадр
    /// поспевал за курсором) и с мгновенным обновлением позиции — аналог
    /// `seekForTimelineScrubPreview` для основного плейхеда.
    func seekReviewForTimelineScrubPreview(to time: Double) {
        guard let player = reviewPlayer else { return }
        let dur = reviewDuration
        guard dur > 0 else { return }
        let t = max(0, min(time, dur))
        reviewCurrentTime = t
        reviewSeekSuppressUntil = Date().addingTimeInterval(0.14)
        let cm = CMTime(seconds: t, preferredTimescale: 600)
        let tol = CMTime(seconds: 0.06, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: tol, toleranceAfter: tol)
    }
    
    func seekReview(by seconds: Double) {
        let target = reviewCurrentTime + seconds
        let duration = reviewDuration
        let clamped = max(0, min(target, duration))
        seekReview(to: clamped)
    }
    
    func toggleReviewPlayPause() {
        guard let player = reviewPlayer else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.rate = Float(reviewPlaybackSpeed)
        }
    }
    
    func changeReviewPlaybackSpeed(to speed: Double) {
        reviewPlaybackSpeed = speed
        guard let player = reviewPlayer, player.timeControlStatus == .playing else { return }
        player.rate = Float(speed)
    }
    
    /// Returns the appropriate AVAsset for use in the Moment Viewer.
    func assetForMomentViewer(completion: @escaping (AVAsset?) -> Void) {
        if isReviewMode {
            completion(reviewPlayer?.currentItem?.asset)
        } else if isLiveMode {
            LiveStreamManager.shared.finalizeCurrentSegment { [weak self] in
                guard self != nil else { completion(nil); return }
                let segments = LiveStreamManager.shared.allSegmentURLs
                guard !segments.isEmpty else { completion(nil); return }
                Task {
                    let composition = await LiveStreamManager.shared.buildCompositionFromSegments(segments)
                    await MainActor.run { completion(composition) }
                }
            }
        } else {
            completion(player?.currentItem?.asset)
        }
    }
    
    private func refreshReviewPlayerItem() {
        let segmentURLs = LiveStreamManager.shared.allSegmentURLs
        guard !segmentURLs.isEmpty, !isRefreshingReview else { return }
        isRefreshingReview = true
        
        Task { [weak self] in
            guard let self = self else { return }
            
            let composition = await LiveStreamManager.shared.buildCompositionFromSegments(segmentURLs)
            
            await MainActor.run { [weak self] in
                guard let self = self, self.isReviewMode else {
                    self?.isRefreshingReview = false
                    return
                }
                
                let newItem = AVPlayerItem(asset: composition)

                // ВАЖНО: переиспользуем ТОТ ЖЕ `AVPlayer` и меняем только item (`replaceCurrentItem`),
                // а НЕ создаём новый плеер. Раньше на каждое обновление (докидка live-сегментов)
                // создавался новый `AVPlayer` и присваивался в `reviewPlayer` (@Published) → SwiftUI
                // пересобирал `VideoPlayer`, а нативный бар AVKit терял привязку своего таймера:
                // «текущее время» в баре замирало (само видео и плейхед на таймлайнах при этом шли),
                // и лечилось только скрытием/показом бара (увод/наведение курсора). При смене только
                // item того же плеера бар остаётся привязан и время в нём продолжает идти.
                let isNewPlayer = (self.reviewPlayer == nil)
                let player = self.reviewPlayer ?? AVPlayer()
                let wasPlaying = self.reviewPlayer?.timeControlStatus == .playing

                // Пока меняем item и досеиваемся — глушим persistent time-observer, иначе он на миг
                // напишет reviewCurrentTime ≈ 0 (item пересоздаётся) и бирюзовый плейхед дёрнется в
                // начало. Снимаем глушилку по завершении сика (или при провале готовности).
                self.reviewSeekSuppressUntil = Date().addingTimeInterval(5)

                self.reviewItemStatusObserver?.cancel()
                self.reviewItemStatusObserver = newItem.publisher(for: \.status)
                    .filter { $0 == .readyToPlay || $0 == .failed }
                    .first()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] status in
                        guard let self = self, self.isReviewMode, status == .readyToPlay else {
                            self?.reviewSeekSuppressUntil = nil
                            self?.isRefreshingReview = false
                            return
                        }

                        let itemDuration = newItem.duration.seconds
                        let shouldSeekToEnd = self.shouldSeekReviewToEndOnNextReady && itemDuration > 0
                        let targetSeconds: Double
                        if shouldSeekToEnd {
                            targetSeconds = max(0, itemDuration - 0.05)
                            self.shouldSeekReviewToEndOnNextReady = false
                        } else {
                            targetSeconds = self.reviewCurrentTime
                        }
                        let seekTarget = CMTime(seconds: targetSeconds, preferredTimescale: 600)
                        player.seek(
                            to: seekTarget,
                            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
                            toleranceAfter:  CMTime(seconds: 0.5, preferredTimescale: 600)
                        ) { [weak self] _ in
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self, self.isReviewMode else {
                                    self?.reviewSeekSuppressUntil = nil
                                    self?.isRefreshingReview = false
                                    return
                                }
                                self.reviewCurrentTime = targetSeconds
                                if shouldSeekToEnd { self.currentTime = targetSeconds }
                                if wasPlaying { player.play() } else { player.pause() }
                                self.reviewSeekSuppressUntil = nil
                                self.isRefreshingReview = false
                            }
                        }
                    }

                player.isMuted = AppConfig.isDebug
                // Пауза на время подмены — чтобы новый item не проигрывался с 0 до сика.
                player.pause()
                player.replaceCurrentItem(with: newItem)

                if isNewPlayer {
                    self.setupReviewTimeObserver(for: player)
                    self.reviewPlayer = player
                }
            }
        }
    }
    
    private func setupReviewTimeObserver(for player: AVPlayer) {
        if let token = reviewTimeObserver {
            player.removeTimeObserver(token)
            reviewTimeObserver = nil
        }
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        reviewTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, self.isReviewMode else { return }
            // Идёт наш собственный seek — позицию уже проставили вручную, не откатываем её назад.
            if let until = self.reviewSeekSuppressUntil {
                if Date() < until { return }
                self.reviewSeekSuppressUntil = nil
            }
            let seconds = CMTimeGetSeconds(time)
            // Пересмотр НЕ трогает `currentTime` (он держит позицию ЛАЙВА, чтобы разметка и
            // основной плейхед оставались на живой записи). Позицию пересмотра публикует
            // `didSet` у `reviewCurrentTime` — её читает бирюзовый плейхед и записи, начатые
            // по нему (`markupTime(usesReview:)`).
            self.reviewCurrentTime = seconds
        }
    }
    
    func stopBroadcast() {
        isBroadcastActive = false
        LiveStreamManager.shared.pauseBroadcast()
    }
    
    func resumeBroadcast() {
        isBroadcastActive = true
        LiveStreamManager.shared.resumeBroadcast()
    }
    
    /// При входе в редактор в режиме live — ставим трансляцию на паузу. При выходе — возобновляем.
    private var broadcastPausedForEditor: Bool = false
    
    func pauseBroadcastForEditor() {
        guard isLiveMode, isBroadcastActive else { return }
        broadcastPausedForEditor = true
        LiveStreamManager.shared.pauseBroadcast()
        isBroadcastActive = false
    }
    
    func resumeBroadcastFromEditor() {
        guard isLiveMode, broadcastPausedForEditor else { return }
        broadcastPausedForEditor = false
        LiveStreamManager.shared.resumeBroadcast()
        isBroadcastActive = true
    }
    
    /// Called when live stream ends and video file is ready. Transitions to normal playback mode.
    func transitionToStaticVideo(url: URL) {
        liveDurationCancellable?.cancel()
        liveDurationCancellable = nil
        isLiveMode = false
        isBroadcastActive = false
        loadVideo(from: url)
    }
    
    func endLiveMode() {
        exitReviewMode()
        liveDurationCancellable?.cancel()
        liveDurationCancellable = nil
        isLiveMode = false
        isBroadcastActive = false
    }
    /// Лёгкий seek во время перетаскивания плейхэда: обновляет картинку и `currentTime`, не снимая periodic observer.
    func seekForTimelineScrubPreview(to time: Double) {
        guard let player = player, !isLiveMode, !isReviewMode else { return }
        let dur = timelineDuration
        guard dur > 0 else { return }
        let t = max(0, min(time, dur))
        scrubTimelinePreviewSuppressUntil = Date().addingTimeInterval(0.14)
        currentTime = t
        let cm = CMTime(seconds: t, preferredTimescale: 600)
        let tol = CMTime(seconds: 0.06, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: tol, toleranceAfter: tol)
    }

    func seek(to time: Double, resumePlaybackAfterSeek: Bool = false) {
        guard let player = player else { return }
        scrubTimelinePreviewSuppressUntil = nil
        isSeeking = true
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        currentTime = time
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self else { return }
            self.isSeeking = false
            self.currentTime = self.player?.currentTime().seconds ?? time
            self.startTimeObserver()
            if resumePlaybackAfterSeek, finished {
                self.player?.play()
                self.player?.rate = Float(self.playbackSpeed)
            }
        }
    }
    func deleteVideo() {
        exitReviewMode()
        isSeeking = false
        player?.pause()
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player = nil
        currentTime = 0.0
        playbackSpeed = 1.0
        cancellables.removeAll()
        liveDurationCancellable?.cancel()
        liveDurationCancellable = nil
        isLiveMode = false
        isBroadcastActive = false
    }
    private func startTimeObserver() {
        guard let player = player else { return }
        // Higher update rate for smoother playhead and timeline auto-scroll.
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            guard !self.isSeeking else { return }
            if let u = self.scrubTimelinePreviewSuppressUntil, Date() < u { return }
            self.currentTime = CMTimeGetSeconds(time)
        }
    }
    func togglePlayPause() {
        guard let player = player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.rate = Float(playbackSpeed)
        }
    }
    func seek(by seconds: Double) {
        guard let player = player else { return }
        let actualCurrentTime = player.currentTime().seconds
        seek(to: actualCurrentTime + seconds)
    }
    func changePlaybackSpeed(to speed: Double) {
        playbackSpeed = speed
        player?.rate = Float(speed)
    }
    
    func getCurrentFrameRate() -> Float {
        guard let player = player,
              let asset = player.currentItem?.asset,
              let track = asset.tracks(withMediaType: .video).first else {
            return 30
        }
        
        return track.nominalFrameRate
    }
    
    func getCurrentVideoURL() -> URL? {
        return player?.currentItem?.asset as? AVURLAsset != nil ? (player?.currentItem?.asset as? AVURLAsset)?.url : nil
    }
    
    // MARK: - Helpers
    
    private func observePlayerState() {
        guard let player else { return }
        
        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                guard let welf = self else { return }

                if status == .playing {
                    if player.rate != Float(welf.playbackSpeed) {
                        player.rate = Float(welf.playbackSpeed)
                    }
                }
                DispatchQueue.main.async {
                    welf.isPlaying = (status == .playing)
                }
            }
            .store(in: &cancellables)
    }
}
