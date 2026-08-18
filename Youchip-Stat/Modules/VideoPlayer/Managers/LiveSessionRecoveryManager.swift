//
//  LiveSessionRecoveryManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 18/08/26.
//

import Foundation
import AVFoundation
import AppKit

/// Резервное копирование live-сессии.
///
/// Раз в 30 секунд сбрасывает на диск всё, что нужно для восстановления: закрытые сегменты
/// записи копируются в `Documents/Recordings/LiveRecovery/<videoId>/` (туда же, куда кладётся
/// итоговое видео после нормальной остановки), а текущая разметка пишется в `markup.json`
/// и во внутреннее хранилище таймлайнов.
///
/// Если приложение убили или мак выключили, при следующем запуске приложение находит
/// незавершённую сессию, склеивает сегменты в один файл и импортирует обычный проект —
/// пользователь видит его в списке с видео и разметкой. Теряется максимум последний тик
/// (≤ 30 секунд), а чаще и он подхватывается: рекордер пишет фрагментированный MOV
/// (`movieFragmentInterval`), поэтому даже незакрытый «хвост» во временной папке читается.
final class LiveSessionRecoveryManager {

    static let shared = LiveSessionRecoveryManager()

    /// Как часто сбрасываем состояние сессии на диск.
    private let backupInterval: TimeInterval = 30.0

    // MARK: - Manifest

    struct Manifest: Codable {
        var videoId: String
        var fileName: String
        var isAppending: Bool
        var appendTargetId: String?
        /// Исходное видео, к которому идёт дозапись (или предзагруженное видео сессии).
        var baseVideoBookmark: Data?
        var baseVideoPath: String?
        /// Папка пользователя для копии записи (выбирается перед стартом).
        var saveFolderBookmark: Data?
        /// Имена скопированных сегментов внутри папки восстановления, в порядке записи.
        var segments: [String]
        /// Ещё не закрытый сегмент во временной папке — фрагментированный MOV, читается
        /// и без финализации, поэтому при восстановлении добавляем его последним.
        var tailSegmentPath: String?
        var startedAt: Date
        var updatedAt: Date
        var durationSeconds: Double
    }

    struct PendingSession {
        let manifest: Manifest
        let folder: URL

        var name: String { manifest.fileName }
        var duration: Double { manifest.durationSeconds }
    }

    // MARK: - State

    private var activeFolder: URL?
    private var manifest: Manifest?
    private var timer: DispatchSourceTimer?
    /// Пути уже скопированных сегментов-источников — чтобы не копировать их повторно.
    private var copiedSourcePaths: Set<String> = []
    private var isTickInProgress = false

    private let ioQueue = DispatchQueue(label: "com.youchip.liveRecovery", qos: .utility)
    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Paths

    private static var recoveryRoot: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Recordings").appendingPathComponent("LiveRecovery", isDirectory: true)
    }

    private static let manifestName = "session.json"
    private static let markupName = "markup.json"

    // MARK: - Session lifecycle

    /// Начинает резервное копирование текущей live-сессии.
    func startSession(videoId: String,
                      fileName: String,
                      isAppending: Bool,
                      appendTargetId: String?,
                      baseVideoURL: URL?) {
        stopTimer()

        let folder = Self.recoveryRoot.appendingPathComponent(videoId, isDirectory: true)
        if fileManager.fileExists(atPath: folder.path) {
            try? fileManager.removeItem(at: folder)
        }
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let newManifest = Manifest(
            videoId: videoId,
            fileName: fileName,
            isAppending: isAppending,
            appendTargetId: appendTargetId,
            baseVideoBookmark: baseVideoURL?.makeBookmark(),
            baseVideoPath: baseVideoURL?.path,
            saveFolderBookmark: LiveStreamManager.shared.saveCopyFolderBookmark,
            segments: [],
            // Уже известен: рекордер создаёт файл сегмента синхронно на старте. Пишем его сразу,
            // чтобы падение до первого тика тоже можно было восстановить (файл фрагментированный).
            tailSegmentPath: LiveStreamManager.shared.currentSegmentURL?.path,
            startedAt: Date(),
            updatedAt: Date(),
            durationSeconds: 0
        )

        activeFolder = folder
        manifest = newManifest
        copiedSourcePaths = []
        isTickInProgress = false
        writeManifest(newManifest, to: folder)

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + backupInterval, repeating: backupInterval)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()

        CameraLogger.shared.log("LiveRecovery: session started, folder=\(folder.lastPathComponent)")
    }

    /// Сессия завершилась штатно и проект уже сохранён — резервные данные больше не нужны.
    func finishSession() {
        stopTimer()
        if let folder = activeFolder {
            let folderToRemove = folder
            ioQueue.async { [weak self] in
                try? self?.fileManager.removeItem(at: folderToRemove)
            }
        }
        activeFolder = nil
        manifest = nil
        copiedSourcePaths = []
        isTickInProgress = false
        CameraLogger.shared.log("LiveRecovery: session finished, backup removed")
    }

    /// Финализация сорвалась — оставляем резервные данные, их предложат восстановить при запуске.
    func keepSessionForRecovery() {
        stopTimer()
        activeFolder = nil
        manifest = nil
        copiedSourcePaths = []
        isTickInProgress = false
        CameraLogger.shared.log("LiveRecovery: session kept for recovery", level: .warn)
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Backup tick

    /// Останавливает периодические бэкапы, не трогая уже сохранённые данные. Вызывается в начале
    /// финализации: тик не должен крутить ротацию сегментов, пока запись останавливается.
    func stopBackups() {
        stopTimer()
    }

    private func tick() {
        guard let folder = activeFolder, let current = manifest else { return }
        guard !isTickInProgress else { return }
        isTickInProgress = true

        let live = LiveStreamManager.shared
        let lines = TimelineDataManager.shared.lines
        let duration = live.liveDuration

        // Страховка на случай правок в обход `TimelineDataManager.updateTimelines()`: там запись
        // отложенная и на своей очереди, поэтому главный поток здесь не блокируем.
        VideoFilesManager.shared.saveTimelines(lines, for: current.videoId)

        let base = live.preloadedBaseURL
        let pendingSources = live.allSegmentURLs.filter { $0 != base && !copiedSourcePaths.contains($0.path) }

        // Если новых закрытых сегментов нет (режим просмотра не крутит ротацию), закрываем
        // текущий сегмент сами — иначе пришлось бы копировать растущий файл целиком.
        if pendingSources.isEmpty, live.isLive, !live.isBroadcastPaused {
            live.finalizeCurrentSegment { [weak self] in
                self?.flushToDisk(folder: folder, lines: lines, duration: duration)
            }
        } else {
            flushToDisk(folder: folder, lines: lines, duration: duration)
        }
    }

    private func flushToDisk(folder: URL, lines: [TimelineLine], duration: Double) {
        guard var current = manifest else {
            isTickInProgress = false
            return
        }
        let live = LiveStreamManager.shared
        let base = live.preloadedBaseURL
        let newSources = live.allSegmentURLs.filter { $0 != base && !copiedSourcePaths.contains($0.path) }
        let tailPath = live.currentSegmentURL?.path

        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let markupData = try? JSONEncoder().encode(lines)
            var names = current.segments
            var copied: [String] = []

            for source in newSources {
                let name = String(format: "seg_%04d.mov", names.count)
                let destination = folder.appendingPathComponent(name)
                if self.fileManager.fileExists(atPath: destination.path) {
                    try? self.fileManager.removeItem(at: destination)
                }
                do {
                    try self.fileManager.copyItem(at: source, to: destination)
                    names.append(name)
                    copied.append(source.path)
                } catch {
                    // Не помечаем скопированным — попробуем этот сегмент на следующем тике.
                    CameraLogger.shared.logError("LiveRecovery: failed to copy segment \(source.lastPathComponent): \(error.localizedDescription)")
                }
            }

            if let markupData = markupData {
                let markupURL = folder.appendingPathComponent(Self.markupName)
                try? markupData.write(to: markupURL, options: .atomic)
            }

            current.segments = names
            current.tailSegmentPath = tailPath
            current.durationSeconds = duration
            current.updatedAt = Date()
            self.writeManifest(current, to: folder)

            DispatchQueue.main.async {
                // Сессию могли остановить, пока шло копирование — тогда состояние уже сброшено.
                guard self.activeFolder == folder else {
                    self.isTickInProgress = false
                    return
                }
                self.manifest = current
                self.copiedSourcePaths.formUnion(copied)
                self.isTickInProgress = false
            }
        }
    }

    private func writeManifest(_ manifest: Manifest, to folder: URL) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: folder.appendingPathComponent(Self.manifestName), options: .atomic)
    }

    // MARK: - Pending sessions

    /// Незавершённые сессии, найденные на диске (самая свежая первой).
    func pendingSessions() -> [PendingSession] {
        let root = Self.recoveryRoot
        guard let folders = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        var result: [PendingSession] = []
        for folder in folders {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            // Папку активной сессии не предлагаем — она ещё пишется.
            if let active = activeFolder, active == folder { continue }
            let manifestURL = folder.appendingPathComponent(Self.manifestName)
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(Manifest.self, from: data) else {
                continue
            }
            let hasTail = manifest.tailSegmentPath.map { fileManager.fileExists(atPath: $0) } ?? false
            guard !manifest.segments.isEmpty || hasTail else {
                // Сессия оборвалась раньше первого бэкапа — восстанавливать нечего.
                try? fileManager.removeItem(at: folder)
                continue
            }
            result.append(PendingSession(manifest: manifest, folder: folder))
        }
        return result.sorted { $0.manifest.updatedAt > $1.manifest.updatedAt }
    }

    /// Удаляет резервные данные сессии без восстановления.
    func discard(_ session: PendingSession) {
        let folder = session.folder
        ioQueue.async { [weak self] in
            try? self?.fileManager.removeItem(at: folder)
        }
    }

    // MARK: - Recovery

    enum RecoveryError: LocalizedError {
        case nothingToRecover
        case exportFailed(String)
        case importFailed

        var errorDescription: String? {
            switch self {
            case .nothingToRecover: return "no readable segments"
            case .exportFailed(let reason): return reason
            case .importFailed: return "import failed"
            }
        }
    }

    /// Склеивает сохранённые сегменты в один файл и создаёт (или обновляет) проект с разметкой.
    func recover(_ session: PendingSession, completion: @escaping (Result<FilesFile, Error>) -> Void) {
        let manifest = session.manifest
        var sources: [URL] = []

        // Дозапись/предзагрузка: исходное видео идёт первым.
        if let targetId = manifest.appendTargetId,
           let existing = VideoFilesManager.shared.files.first(where: { $0.videoData.id == targetId }),
           let url = existing.url {
            sources.append(url)
        } else if let bookmark = manifest.baseVideoBookmark,
                  let url = resolveBookmark(bookmark) {
            sources.append(url)
        } else if let path = manifest.baseVideoPath, fileManager.fileExists(atPath: path) {
            sources.append(URL(fileURLWithPath: path))
        }

        for name in manifest.segments {
            let url = session.folder.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                sources.append(url)
            }
        }
        if let tailPath = manifest.tailSegmentPath,
           fileManager.fileExists(atPath: tailPath) {
            sources.append(URL(fileURLWithPath: tailPath))
        }

        guard !sources.isEmpty else {
            completion(.failure(RecoveryError.nothingToRecover))
            return
        }

        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.assembleRecording(from: sources, videoId: manifest.videoId)
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let finalURL):
                    self.finishRecovery(session: session, finalURL: finalURL, completion: completion)
                }
            }
        }
    }

    /// Собирает финальный файл в `Documents/Recordings` — там же, где оказывается запись после
    /// штатной остановки live-сессии.
    private func assembleRecording(from sources: [URL], videoId: String) async -> Result<URL, Error> {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return .failure(RecoveryError.exportFailed("no video track"))
        }

        var insertTime = CMTime.zero
        for url in sources {
            // Незакрытый фрагментированный MOV отдаёт корректную длительность только с точным разбором.
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            guard let duration = try? await asset.load(.duration),
                  duration.isValid, !duration.isIndefinite, duration.seconds > 0,
                  let track = try? await asset.loadTracks(withMediaType: .video).first else {
                CameraLogger.shared.logError("LiveRecovery: skipping unreadable segment \(url.lastPathComponent)")
                continue
            }
            let range = CMTimeRange(start: .zero, duration: duration)
            do {
                try videoTrack.insertTimeRange(range, of: track, at: insertTime)
                insertTime = CMTimeAdd(insertTime, duration)
            } catch {
                CameraLogger.shared.logError("LiveRecovery: failed to insert segment \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        guard insertTime.seconds > 0 else {
            return .failure(RecoveryError.nothingToRecover)
        }

        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = documents.appendingPathComponent("Recordings")
        if !fileManager.fileExists(atPath: recordingsDir.path) {
            try? fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }
        var finalURL = recordingsDir.appendingPathComponent("\(videoId).mov")
        var counter = 1
        while fileManager.fileExists(atPath: finalURL.path) {
            finalURL = recordingsDir.appendingPathComponent("\(videoId)_\(counter).mov")
            counter += 1
        }

        let presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        var lastError = "unknown"
        for preset in presets {
            guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else { continue }
            exporter.outputURL = finalURL
            exporter.outputFileType = .mov
            await exporter.export()
            if exporter.status == .completed {
                return .success(finalURL)
            }
            lastError = exporter.error?.localizedDescription ?? "unknown"
            try? fileManager.removeItem(at: finalURL)
        }
        return .failure(RecoveryError.exportFailed(lastError))
    }

    private func finishRecovery(session: PendingSession,
                                finalURL: URL,
                                completion: @escaping (Result<FilesFile, Error>) -> Void) {
        let manifest = session.manifest
        let timelines = loadMarkup(from: session)

        var resultFile: FilesFile?

        if let targetId = manifest.appendTargetId,
           let existing = VideoFilesManager.shared.files.first(where: { $0.videoData.id == targetId }) {
            VideoFilesManager.shared.updateVideoURL(for: existing, newURL: finalURL)
            VideoFilesManager.shared.saveTimelines(timelines, for: existing.videoData.id)
            resultFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == targetId }) ?? existing
        } else if let imported = VideoFilesManager.shared.importFile(url: finalURL, newName: manifest.fileName) {
            VideoFilesManager.shared.updateTimelines(forVideoId: imported.videoData.id, with: timelines)
            copyScreenshots(fromLiveVideoId: manifest.videoId, to: imported.screenshotsFolder)
            resultFile = imported
        }

        guard let file = resultFile else {
            completion(.failure(RecoveryError.importFailed))
            return
        }

        InMemoryStorageManager.shared.flushTimelinesNow()

        if let bookmark = manifest.saveFolderBookmark {
            LiveStreamManager.shared.copyRecording(finalURL, suggestedName: manifest.fileName, folderBookmark: bookmark)
        }

        discard(session)
        CameraLogger.shared.log("LiveRecovery: recovered '\(manifest.fileName)' with \(timelines.count) timelines")
        completion(.success(file))
    }

    private func loadMarkup(from session: PendingSession) -> [TimelineLine] {
        let markupURL = session.folder.appendingPathComponent(Self.markupName)
        if let data = try? Data(contentsOf: markupURL),
           let lines = try? JSONDecoder().decode([TimelineLine].self, from: data) {
            return lines
        }
        // Запасной вариант: разметка, сброшенная во внутреннее хранилище на последнем тике.
        return VideoFilesManager.shared.loadTimelines(for: session.manifest.videoId)
    }

    private func copyScreenshots(fromLiveVideoId liveVideoId: String, to destinationFolder: URL) {
        guard !liveVideoId.isEmpty,
              let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let source = documents.appendingPathComponent("Screenshots").appendingPathComponent(liveVideoId)
        guard fileManager.fileExists(atPath: source.path),
              let items = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        for item in items where item.isFileURL {
            let destination = destinationFolder.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            try? fileManager.copyItem(at: item, to: destination)
        }
    }

    private func resolveBookmark(_ bookmark: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale) else { return nil }
        // Доступ не закрываем: файл читается склейкой дальше по флоу (как в `FilesFile.url`).
        guard url.startAccessingSecurityScopedResource() else { return nil }
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
