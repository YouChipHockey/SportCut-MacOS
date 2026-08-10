//
//  ClipAutoSaveManager.swift
//  Youchip-Stat
//
//  Быстрое сохранение клипа выбранного тега (Cmd+S) в заранее заданную папку.
//  Пользователь один раз выбирает папку, дальше каждый Cmd+S на выбранном
//  стампе экспортирует его отрезок туда без диалогов.
//

import AVFoundation
import AppKit
import Combine
import Foundation

final class ClipAutoSaveManager: ObservableObject {

    static let shared = ClipAutoSaveManager()

    private let bookmarkKey = "clipAutoSaveFolderBookmark"
    private let autoExportKey = "clipAutoSaveAutoExportEnabled"

    /// Настроена ли папка автосохранения (и доступна ли она сейчас).
    @Published private(set) var isFolderConfigured = false
    /// Флаг авто-экспорта: сохранять клип в папку на КАЖДЫЙ добавленный тег (файловая разметка).
    @Published private(set) var isAutoExportEnabled = false
    /// Имя выбранной папки для подсказки в UI.
    @Published private(set) var folderName: String?
    /// Идёт ли сейчас экспорт клипа — чтобы не запускать второй параллельно.
    @Published private(set) var isSaving = false

    private var exportSession: AVAssetExportSession?
    /// Таймер опроса прогресса активного экспорта для баннера снизу.
    private var progressTimer: Timer?
    /// Один элемент очереди экспорта. `silentErrors == true` — авто-путь (лайв):
    /// некритичные ошибки (нулевой диапазон инстант-тега и т.п.) тостом не показываем.
    private struct PendingExport { let stampID: UUID; let silentErrors: Bool }
    /// Очередь стампов, ожидающих сохранения — экспорт идёт строго последовательно,
    /// чтобы быстрые подряд-теги в лайве не терялись и не пересекались параллельно.
    private var pendingExports: [PendingExport] = []
    /// В этой сессии уже предлагали выбрать папку (чтобы не спрашивать повторно, если отменили).
    private var didPromptFolderThisSession = false

    private init() {
        isAutoExportEnabled = UserDefaults.standard.bool(forKey: autoExportKey)
        refreshFolderState()
    }

    // MARK: - Папка

    /// Пересчитывает состояние папки. Если бук­марк не резолвится (папку удалили
    /// или отвязали) — сбрасываем настройку, чтобы UI попросил выбрать заново.
    func refreshFolderState() {
        guard let url = resolveFolderURL() else {
            if UserDefaults.standard.data(forKey: bookmarkKey) != nil {
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
            }
            isFolderConfigured = false
            folderName = nil
            return
        }
        url.stopAccessingSecurityScopedResource()
        isFolderConfigured = true
        folderName = url.lastPathComponent
    }

    /// Диалог выбора папки автосохранения.
    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = ^String.Titles.clipAutoSavePickPrompt
        panel.title = ^String.Titles.clipAutoSavePickTitle

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            refreshFolderState()
        } catch {
            showAlert(title: ^String.Titles.clipAutoSaveErrorTitle, message: error.localizedDescription)
        }
    }

    func resetFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        refreshFolderState()
    }

    /// Включить/выключить авто-экспорт клипа на каждый добавленный тег.
    func setAutoExportEnabled(_ enabled: Bool) {
        isAutoExportEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: autoExportKey)
    }

    /// При старте новой сессии разметки: если папка автосохранения ещё не задана —
    /// предложить выбрать её. Не блокируем открытие окон (показываем асинхронно).
    func promptFolderForNewSessionIfNeeded() {
        guard !isFolderConfigured, !didPromptFolderThisSession else { return }
        didPromptFolderThisSession = true
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isFolderConfigured else { return }
            self.pickFolder()
        }
    }

    /// Резолвит URL папки из бук­марка и открывает доступ. Вызывающий обязан
    /// вызвать `stopAccessingSecurityScopedResource()` после использования.
    private func resolveFolderURL() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            guard url.startAccessingSecurityScopedResource() else { return nil }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                url.stopAccessingSecurityScopedResource()
                return nil
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Сохранение клипа

    /// Экспортирует отрезок целевого стампа в папку автосохранения.
    /// Вызывается по Cmd+S в окне разметки. Цель: явно выбранный стамп, иначе последний добавленный.
    func saveSelectedStampClip() {
        guard isFolderConfigured else {
            refreshFolderState()
            // Лайв-поток: без модалок — просто предложить настроить папку неблокирующим тостом.
            ClipSaveToastPresenter.shared.show(^String.Titles.clipAutoSaveNotConfiguredMessage, style: .error)
            return
        }

        // Если сейчас выбрано несколько клипов (Cmd+клик по штампам) — сохраняем КАЖДЫЙ
        // отдельным видео в папку (через ту же последовательную очередь). Иначе — один клип.
        let selectedIDs = TimelineDataManager.shared.stampsSelectedForSportCut
        if selectedIDs.count > 1 {
            let ordered = orderedSelectedStampIDs(selectedIDs)
            guard !ordered.isEmpty else {
                ClipSaveToastPresenter.shared.show(^String.Titles.clipAutoSaveNoStampMessage, style: .error)
                return
            }
            for id in ordered {
                pendingExports.append(PendingExport(stampID: id, silentErrors: false))
            }
            drainPendingQueue()
            return
        }

        guard let (stamp, _) = selectedStampAndName() else {
            // Не показываем модальный alert в лайве — только неблокирующий тост.
            ClipSaveToastPresenter.shared.show(^String.Titles.clipAutoSaveNoStampMessage, style: .error)
            return
        }

        // Явный Cmd+S идёт через ту же последовательную очередь (без гонок с авто-сейвом),
        // но с показом ошибок пользователю.
        pendingExports.append(PendingExport(stampID: stamp.id, silentErrors: false))
        drainPendingQueue()
    }

    /// Выбранные стампы в порядке времени начала (для сохранения набора отдельными файлами).
    private func orderedSelectedStampIDs(_ selectedIDs: Set<UUID>) -> [UUID] {
        var stamps: [TimelineStamp] = []
        for line in TimelineDataManager.shared.lines {
            for stamp in line.stamps where selectedIDs.contains(stamp.id) {
                stamps.append(stamp)
            }
        }
        return stamps.sorted { $0.timeStartSeconds < $1.timeStartSeconds }.map { $0.id }
    }

    /// Авто-экспорт только что добавленного стампа — ТОЛЬКО при включённом флаге и настроенной
    /// папке. В лайве пропускаем (получение отрезка рестартит рекордер — недопустимо на каждый
    /// тег; в лайве сохранять по явному Cmd+S / Opt+Cmd+S).
    func autoSaveStampIfConfigured(stampID: UUID) {
        guard isAutoExportEnabled, isFolderConfigured else { return }
        guard !LiveStreamManager.shared.isLive else { return }
        pendingExports.append(PendingExport(stampID: stampID, silentErrors: true))
        drainPendingQueue()
    }

    /// Последовательно экспортирует накопленные в очереди стампы (по одному за раз).
    private func drainPendingQueue() {
        guard !isSaving else { return }
        guard !pendingExports.isEmpty else { return }
        guard let folderURL = resolveFolderURL() else {
            pendingExports.removeAll()
            refreshFolderState()
            return
        }
        let job = pendingExports.removeFirst()
        guard let (stamp, tagName) = stampAndName(forID: job.stampID) else {
            folderURL.stopAccessingSecurityScopedResource()
            drainPendingQueue()
            return
        }
        // Резервируем isSaving на время асинхронного получения источника (в лайве это
        // финализация записи), иначе параллельный drain стартует второй экспорт.
        isSaving = true
        resolveExportAsset { [weak self] asset in
            guard let self else { folderURL.stopAccessingSecurityScopedResource(); return }
            guard let asset else {
                self.isSaving = false
                folderURL.stopAccessingSecurityScopedResource()
                if !job.silentErrors {
                    ClipSaveToastPresenter.shared.show(^String.Titles.clipAutoSaveNoVideoMessage, style: .error)
                }
                self.drainPendingQueue()
                return
            }
            self.exportClip(stamp: stamp, tagName: tagName, folderURL: folderURL, asset: asset, silentErrors: job.silentErrors) { [weak self] in
                self?.drainPendingQueue()
            }
        }
    }

    /// Источник для экспорта: в лайве — полная композиция записи (база + сегменты + текущий
    /// фрагмент; тайминги штампов ложатся на неё напрямую), иначе — текущий файл плеера.
    /// Асинхронно: в лайве финализирует запись и перезапускает рекордер.
    private func resolveExportAsset(completion: @escaping (AVAsset?) -> Void) {
        let live = LiveStreamManager.shared
        if live.isLive {
            live.prepareFullCompositionForExport { asset in
                if Thread.isMainThread {
                    completion(asset)
                } else {
                    DispatchQueue.main.async { completion(asset) }
                }
            }
        } else if let url = VideoPlayerManager.shared.getCurrentVideoURL() {
            completion(AVURLAsset(url: url))
        } else {
            completion(nil)
        }
    }

    /// Общий экспорт одного отрезка стампа в папку. `folderURL` уже с открытым security-scoped
    /// доступом — закрывается здесь по завершении. `onFinish` — для последовательной очереди.
    private func exportClip(stamp: TimelineStamp, tagName: String, folderURL: URL, asset: AVAsset, silentErrors: Bool, onFinish: (() -> Void)? = nil) {
        var didStopFolderAccess = false
        func stopFolderAccess() {
            guard !didStopFolderAccess else { return }
            didStopFolderAccess = true
            folderURL.stopAccessingSecurityScopedResource()
        }
        func fail(_ message: String) {
            isSaving = false
            stopFolderAccess()
            // На авто-пути (лайв) некритичные ошибки не показываем — только по явному Cmd+S.
            if !silentErrors {
                ClipSaveToastPresenter.shared.show(message, style: .error)
            }
            onFinish?()
        }

        let assetDuration = CMTimeGetSeconds(asset.duration)
        let start = max(0, stamp.timeStartSeconds)
        let end = min(assetDuration > 0 ? assetDuration : stamp.timeFinishSeconds, stamp.timeFinishSeconds)
        guard end > start else {
            fail(^String.Titles.clipAutoSaveBadRangeMessage)
            return
        }

        // Вотермарка клипов (название тега, лейблы, номер эпизода, комментарий) — тот же
        // текстовый оверлей, что и флаг в окне экспорта. Для быстрого сохранения окна нет,
        // поэтому управляется настройкой. Если включена — экспортируем композицию из отрезка
        // с наложенным оверлеем; иначе — быстрый путь (исходный asset + timeRange).
        let session: AVAssetExportSession
        if AppSettingsStore.shared.exportClipsWithWatermark,
           let (composition, overlayComposition) = makeWatermarkedClipComposition(asset: asset, stamp: stamp, start: start, end: end),
           let s = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) {
            s.videoComposition = overlayComposition
            session = s
        } else {
            guard let s = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                fail(^String.Titles.clipAutoSaveExportFailedMessage)
                return
            }
            s.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )
            session = s
        }

        // Уникальное имя: при мульти-карте несколько стампов с одним тегом и временем
        // не должны перезатирать друг друга.
        let outputURL = uniqueOutputURL(in: folderURL, fileName: makeFileName(tagName: tagName, start: start))
        session.outputURL = outputURL
        session.outputFileType = .mov
        exportSession = session
        // isSaving уже выставлен в drainPendingQueue на время получения источника.

        // По явному Cmd+S показываем баннер с прогресс-баром на время подготовки клипа;
        // по завершении он заменится тостом успеха/ошибки. В лайв-авто-сейве (silentErrors) — без баннера.
        if !silentErrors {
            startProgressBanner(text: ^String.Titles.clipAutoSaveInProgress, session: session)
        }

        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard let self else { stopFolderAccess(); onFinish?(); return }
                self.isSaving = false
                self.exportSession = nil
                self.stopProgressBanner()

                let fileExists = FileManager.default.fileExists(atPath: outputURL.path)
                switch session.status {
                case .completed where fileExists:
                    ClipSaveToastPresenter.shared.show(
                        String(format: ^String.Titles.clipAutoSaveSuccess, outputURL.lastPathComponent),
                        style: .success
                    )
                case .cancelled:
                    try? FileManager.default.removeItem(at: outputURL)
                    ClipSaveToastPresenter.shared.dismissProgress()
                default:
                    // Честная диагностика: сессия «завершилась», но файла нет, или явная ошибка.
                    try? FileManager.default.removeItem(at: outputURL)
                    print("ClipAutoSave export failed: status=\(session.status.rawValue) error=\(String(describing: session.error))")
                    if !silentErrors {
                        ClipSaveToastPresenter.shared.show(
                            session.error?.localizedDescription ?? ^String.Titles.clipAutoSaveExportFailedMessage,
                            style: .error
                        )
                    } else {
                        ClipSaveToastPresenter.shared.dismissProgress()
                    }
                }
                stopFolderAccess()
                onFinish?()
            }
        }
    }

    // MARK: - Склеенный фильм (Opt+Cmd+S)

    /// Склеивает выделенные для просмотра клипы (`stampsSelectedForSportCut`) в один фильм
    /// и сохраняет его в папку автосохранения. Если папка не задана — предлагает выбрать.
    func saveMergedSelectedClips() {
        guard !isSaving else { return }

        let timelineData = TimelineDataManager.shared
        let selectedIDs = timelineData.stampsSelectedForSportCut
        guard !selectedIDs.isEmpty else {
            ClipSaveToastPresenter.shared.show(^String.Titles.clipAutoSaveNoSelectedClips, style: .error)
            return
        }

        if !isFolderConfigured {
            pickFolder()
        }
        guard isFolderConfigured, let folderURL = resolveFolderURL() else {
            refreshFolderState()
            ClipSaveToastPresenter.shared.show(^String.Titles.clipAutoSaveNotConfiguredMessage, style: .error)
            return
        }

        // Собираем стампы по порядку времени.
        var stamps: [TimelineStamp] = []
        for line in timelineData.lines {
            for stamp in line.stamps where selectedIDs.contains(stamp.id) {
                stamps.append(stamp)
            }
        }
        stamps.sort { $0.timeStartSeconds < $1.timeStartSeconds }
        guard !stamps.isEmpty else {
            folderURL.stopAccessingSecurityScopedResource()
            ClipSaveToastPresenter.shared.show(^String.Titles.clipAutoSaveNoSelectedClips, style: .error)
            return
        }

        // Источник (в лайве — полная композиция записи) получаем асинхронно.
        isSaving = true
        ClipSaveToastPresenter.shared.show(^String.Titles.clipAutoSaveMergedInProgress, style: .info)
        resolveExportAsset { [weak self] asset in
            guard let self else { folderURL.stopAccessingSecurityScopedResource(); return }
            guard let asset else {
                self.isSaving = false
                folderURL.stopAccessingSecurityScopedResource()
                ClipSaveToastPresenter.shared.show(^String.Titles.clipAutoSaveNoVideoMessage, style: .error)
                return
            }
            self.performMergedExport(stamps: stamps, asset: asset, folderURL: folderURL)
        }
    }

    /// Склейка выбранных отрезков из уже полученного `asset` в один файл в папке автосейва.
    private func performMergedExport(stamps: [TimelineStamp], asset: AVAsset, folderURL: URL) {
        var didStopFolderAccess = false
        func stopFolderAccess() {
            guard !didStopFolderAccess else { return }
            didStopFolderAccess = true
            folderURL.stopAccessingSecurityScopedResource()
        }
        func fail(_ message: String) {
            isSaving = false
            stopFolderAccess()
            ClipSaveToastPresenter.shared.show(message, style: .error)
        }

        let assetDuration = CMTimeGetSeconds(asset.duration)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            fail(^String.Titles.clipAutoSaveExportFailedMessage)
            return
        }
        let audioTrack = asset.tracks(withMediaType: .audio).first

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            fail(^String.Titles.clipAutoSaveExportFailedMessage)
            return
        }
        var compAudioTrack: AVMutableCompositionTrack?
        if audioTrack != nil {
            compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        compVideoTrack.preferredTransform = videoTrack.preferredTransform

        let timescale: CMTimeScale = 600
        var cursor = CMTime.zero
        var overlayItems: [OverlayItem] = []
        for stamp in stamps {
            let start = max(0, stamp.timeStartSeconds)
            let end = min(assetDuration > 0 ? assetDuration : stamp.timeFinishSeconds, stamp.timeFinishSeconds)
            guard end > start else { continue }
            let range = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: timescale),
                end: CMTime(seconds: end, preferredTimescale: timescale)
            )
            do {
                try compVideoTrack.insertTimeRange(range, of: videoTrack, at: cursor)
                if let compAudio = compAudioTrack, let aTrack = audioTrack {
                    try compAudio.insertTimeRange(range, of: aTrack, at: cursor)
                }
                // Каждый склеенный отрезок получает свой текстовый оверлей на своём интервале.
                if let item = overlayItem(for: stamp, videoTrack: videoTrack, start: cursor, duration: range.duration) {
                    overlayItems.append(item)
                }
                cursor = cursor + range.duration
            } catch {
                fail(error.localizedDescription)
                return
            }
        }
        guard cursor > .zero else {
            fail(^String.Titles.clipAutoSaveBadRangeMessage)
            return
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            fail(^String.Titles.clipAutoSaveExportFailedMessage)
            return
        }

        let outputURL = uniqueOutputURL(in: folderURL, fileName: makeMergedFileName(count: stamps.count))
        session.outputURL = outputURL
        session.outputFileType = .mov
        if AppSettingsStore.shared.exportClipsWithWatermark, !overlayItems.isEmpty {
            session.videoComposition = ExportHelper().videoCompositionWithTextOverlay(
                overlayItems: overlayItems,
                videoTrack: videoTrack,
                compositionVideoTrack: compVideoTrack,
                compositionDuration: composition.duration
            )
        }
        exportSession = session
        // isSaving и стартовый тост уже выставлены в saveMergedSelectedClips —
        // заменяем его на баннер с прогресс-баром на время склейки.
        startProgressBanner(text: ^String.Titles.clipAutoSaveMergedInProgress, session: session)

        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard let self else { stopFolderAccess(); return }
                self.isSaving = false
                self.exportSession = nil
                self.stopProgressBanner()

                let fileExists = FileManager.default.fileExists(atPath: outputURL.path)
                switch session.status {
                case .completed where fileExists:
                    ClipSaveToastPresenter.shared.show(
                        String(format: ^String.Titles.clipAutoSaveMergedSuccess, outputURL.lastPathComponent),
                        style: .success
                    )
                case .cancelled:
                    try? FileManager.default.removeItem(at: outputURL)
                    ClipSaveToastPresenter.shared.dismissProgress()
                default:
                    try? FileManager.default.removeItem(at: outputURL)
                    print("ClipAutoSave merged export failed: status=\(session.status.rawValue) error=\(String(describing: session.error))")
                    ClipSaveToastPresenter.shared.show(
                        session.error?.localizedDescription ?? ^String.Titles.clipAutoSaveExportFailedMessage,
                        style: .error
                    )
                }
                stopFolderAccess()
                // Если за время склейки в очереди накопились авто-сейвы — продолжим их.
                self.drainPendingQueue()
            }
        }
    }

    // MARK: - Баннер прогресса экспорта

    /// Показывает баннер снизу с прогресс-баром и опрашивает `session.progress` до завершения.
    /// По завершении экспорта баннер заменяется тостом успеха/ошибки (см. completion экспорта).
    private func startProgressBanner(text: String, session: AVAssetExportSession) {
        progressTimer?.invalidate()
        ClipSaveToastPresenter.shared.showProgress(text, progress: Double(session.progress))
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak session] t in
            guard let session else { t.invalidate(); return }
            ClipSaveToastPresenter.shared.showProgress(text, progress: Double(session.progress))
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressBanner() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Вотермарка (текстовый оверлей)

    /// Строит `OverlayItem` для стампа — то же, что окно экспорта: название тега, лейблы,
    /// номер эпизода, комментарий (`ExportWatermarkOptions.default`). Логотип клуба здесь не
    /// включаем — это отдельная опция окна экспорта. `start`/`duration` — в координатах итоговой
    /// композиции (для одиночного клипа — .zero и его длительность).
    private func overlayItem(for stamp: TimelineStamp, videoTrack: AVAssetTrack, start: CMTime, duration: CMTime) -> OverlayItem? {
        let tag = TagLibraryManager.shared.allTags.first(where: { $0.id == stamp.idTag })
            ?? Tag.syntheticDrawingTag(for: stamp)
        guard let tag else { return nil }
        let transform = videoTrack.preferredTransform
        let natural = videoTrack.naturalSize.applying(transform)
        let videoSize = CGSize(width: abs(natural.width), height: abs(natural.height))
        return OverlayItem(
            tag: tag,
            stamp: stamp,
            selectedLabelGroups: OverlayLabelGroupItem.labelGroupItems(forStamp: stamp),
            start: start,
            duration: duration,
            videoSize: videoSize,
            watermarkOptions: .default
        )
    }

    /// Композиция из одного отрезка [start;end] `asset` c наложенным текстовым оверлеем.
    /// nil — если нет видеодорожки или не удалось собрать оверлей.
    private func makeWatermarkedClipComposition(asset: AVAsset, stamp: TimelineStamp, start: Double, end: Double) -> (AVMutableComposition, AVVideoComposition)? {
        guard let videoTrack = asset.tracks(withMediaType: .video).first else { return nil }
        let audioTrack = asset.tracks(withMediaType: .audio).first

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        compVideo.preferredTransform = videoTrack.preferredTransform
        var compAudio: AVMutableCompositionTrack?
        if audioTrack != nil {
            compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }

        let timescale: CMTimeScale = 600
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: timescale),
            end: CMTime(seconds: end, preferredTimescale: timescale)
        )
        do {
            try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)
            if let compAudio, let audioTrack {
                try compAudio.insertTimeRange(range, of: audioTrack, at: .zero)
            }
        } catch {
            return nil
        }

        guard let item = overlayItem(for: stamp, videoTrack: videoTrack, start: .zero, duration: composition.duration) else { return nil }
        let overlayComposition = ExportHelper().videoCompositionWithTextOverlay(
            overlayItems: [item],
            videoTrack: videoTrack,
            compositionVideoTrack: compVideo,
            compositionDuration: composition.duration
        )
        return (composition, overlayComposition)
    }

    // MARK: - Хелперы

    /// Возвращает URL со свободным именем: если файл уже есть, добавляет « (2)», « (3)»…
    private func uniqueOutputURL(in folder: URL, fileName: String) -> URL {
        let ns = fileName as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var candidate = folder.appendingPathComponent(fileName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = folder.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }

    /// Целевой стамп для Cmd+S: явно выбранный на таймлайне, иначе — последний добавленный.
    private func selectedStampAndName() -> (stamp: TimelineStamp, tagName: String)? {
        let timelineData = TimelineDataManager.shared
        if let selectedID = timelineData.selectedStampID, let result = stampAndName(forID: selectedID) {
            return result
        }
        if let lastID = timelineData.lastAddedStampID {
            return stampAndName(forID: lastID)
        }
        return nil
    }

    /// Находит стамп по id и имя его тега для названия файла.
    private func stampAndName(forID stampID: UUID) -> (stamp: TimelineStamp, tagName: String)? {
        let timelineData = TimelineDataManager.shared
        for line in timelineData.lines {
            if let stamp = line.stamps.first(where: { $0.id == stampID }) {
                let tagName = TagLibraryManager.shared.findTagById(stamp.idTag)?.name
                    ?? (stamp.label.isEmpty ? line.name : stamp.label)
                return (stamp, tagName)
            }
        }
        return nil
    }

    private func makeMergedFileName(count: Int) -> String {
        let prefix = ^String.Titles.clipAutoSaveMergedPrefix
        let now = Int(Date().timeIntervalSinceReferenceDate)
        return "\(prefix)_\(count)_\(now).mov"
    }

    private func makeFileName(tagName: String, start: Double) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let safeName = tagName.components(separatedBy: invalid).joined(separator: "-")
        let cleanName = safeName.isEmpty ? "clip" : safeName

        let totalSeconds = Int(start.rounded())
        let timeStamp = String(format: "%02d-%02d-%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
        return "\(cleanName)_\(timeStamp).mov"
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: ^String.Titles.alertsOkTitle)
        alert.runModal()
    }
}
