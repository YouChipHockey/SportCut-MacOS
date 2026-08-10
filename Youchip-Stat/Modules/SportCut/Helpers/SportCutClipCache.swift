//
//  SportCutClipCache.swift
//  Youchip-Stat
//
//  Локальный кэш вырезанных клипов плейлистов, чтобы они продолжали проигрываться
//  даже после удаления исходного видео. Клипы экспортируются в контейнер приложения
//  как отдельные (уже обрезанные) файлы и подхватываются при воспроизведении/экспорте.
//

import Foundation
import AVFoundation

enum SportCutClipCache {

    /// Корневая ВНУТРЕННЯЯ папка приложения (Application Support), не видимая пользователю в Documents.
    private static func rootDir() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("YouChip-Stat-PlaylistClips", isDirectory: true)
    }

    /// Путь к папке клипов сессии БЕЗ создания (для чтения/удаления).
    private static func clipsDirPath(sessionID: UUID) -> URL {
        rootDir().appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    /// Папка клипов сессии, создаётся при необходимости (для записи).
    private static func clipsDir(sessionID: UUID) -> URL {
        let dir = clipsDirPath(sessionID: sessionID)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileName(forHiddenKey hiddenKey: String) -> String {
        // hiddenKey = "sourceID|stampID" — заменяем разделитель для имени файла.
        hiddenKey.replacingOccurrences(of: "|", with: "_") + ".mov"
    }

    private static func fileName(for event: SportCutEvent) -> String {
        fileName(forHiddenKey: event.hiddenKey)
    }

    /// URL закэшированного (обрезанного) клипа события, если он уже экспортирован.
    static func cachedClipURL(sessionID: UUID, event: SportCutEvent) -> URL? {
        let url = clipsDirPath(sessionID: sessionID).appendingPathComponent(fileName(for: event))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// true, если хотя бы один клип плейлиста закэширован (для UI-индикации).
    static func hasAnyCachedClip(sessionID: UUID, events: [SportCutEvent]) -> Bool {
        events.contains { cachedClipURL(sessionID: sessionID, event: $0) != nil }
    }

    /// Экспортирует переданные события в кэш (обрезанные клипы). Уже закэшированные пропускаются.
    /// `progress` вызывается на главном потоке (done, total); `completion` — по завершении.
    static func exportClips(
        events: [SportCutEvent],
        sessionID: UUID,
        sources: [SportCutSource],
        startOverrides: [String: Double],
        durationOverrides: [String: Double],
        progress: ((Int, Int) -> Void)? = nil,
        completion: ((_ exported: Int, _ failed: Int) -> Void)? = nil
    ) {
        let dir = clipsDir(sessionID: sessionID)
        let total = events.count
        var done = 0
        var exported = 0
        var failed = 0

        func finishOne() {
            done += 1
            DispatchQueue.main.async { progress?(done, total) }
            if done >= total {
                DispatchQueue.main.async { completion?(exported, failed) }
            }
        }

        guard total > 0 else { completion?(0, 0); return }

        // Экспортируем последовательно (по одному), цепочка продолжается в completion экспортёра.
        func processNext(_ index: Int) {
            guard index < events.count else { return }
            let event = events[index]
            let outURL = dir.appendingPathComponent(fileName(for: event))

            if FileManager.default.fileExists(atPath: outURL.path) {
                exported += 1; finishOne(); processNext(index + 1); return
            }
            guard let source = sources.first(where: { $0.id == event.sourceID }),
                  let srcURL = source.resolveVideoURL() else {
                failed += 1; finishOne(); processNext(index + 1); return
            }

            let asset = AVAsset(url: srcURL)
            let assetDuration = CMTimeGetSeconds(asset.duration)
            let start = max(0, min(startOverrides[event.hiddenKey] ?? event.startTime, assetDuration))
            let maxAvail = max(0, assetDuration - start)
            let duration = min(max(0, durationOverrides[event.hiddenKey] ?? event.duration), maxAvail)
            guard duration > 0 else { failed += 1; finishOne(); processNext(index + 1); return }

            let range = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(seconds: duration, preferredTimescale: 600)
            )

            let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
            let preset = presets.contains(AVAssetExportPresetHighestQuality) ? AVAssetExportPresetHighestQuality : AVAssetExportPreset1280x720
            guard let export = AVAssetExportSession(asset: asset, presetName: preset) else {
                failed += 1; finishOne(); processNext(index + 1); return
            }
            try? FileManager.default.removeItem(at: outURL)
            export.outputURL = outURL
            export.outputFileType = .mov
            export.timeRange = range

            export.exportAsynchronously {
                if export.status == .completed { exported += 1 } else { failed += 1 }
                finishOne()
                processNext(index + 1)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            processNext(0)
        }
    }

    // MARK: - Auto-caching (клипы плейлистов сохраняются автоматически)

    /// Сессии, для которых прямо сейчас идёт фоновый экспорт — чтобы не запускать вторую цепочку.
    private static var inProgressSessions: Set<UUID> = []

    /// Автоматически до-экспортирует все ещё не закэшированные видимые клипы плейлистов сессии.
    /// Вызывается на каждом изменении сессии; уже закэшированные и слайды пропускаются, тяжёлый
    /// экспорт идёт в фоне. Клипы источников, которых уже нет в сессии, не трогаем (их не переэкспортировать,
    /// но ранее сохранённые копии остаются и продолжают играть).
    static func autoCacheIfNeeded(session: SportCutSession) {
        let sessionID = session.id
        guard !inProgressSessions.contains(sessionID) else { return }

        var seen = Set<String>()
        var events: [SportCutEvent] = []
        var startOverrides: [String: Double] = [:]
        var durationOverrides: [String: Double] = [:]

        for group in session.playlistGroups {
            for playlist in group.playlists {
                for event in playlist.events where !playlist.hiddenEventKeys.contains(event.hiddenKey) {
                    let key = event.hiddenKey
                    if event.isSlide || seen.contains(key) { continue }
                    if cachedClipURL(sessionID: sessionID, event: event) != nil { continue }
                    // Экспортировать можно только пока исходное видео ещё в сессии.
                    guard session.sources.contains(where: { $0.id == event.sourceID }) else { continue }
                    seen.insert(key)
                    events.append(event)
                    if let s = playlist.eventStartOverrides[key] { startOverrides[key] = s }
                    if let d = playlist.eventDurationOverrides[key] { durationOverrides[key] = d }
                }
            }
        }

        guard !events.isEmpty else { return }

        inProgressSessions.insert(sessionID)
        exportClips(
            events: events,
            sessionID: sessionID,
            sources: session.sources,
            startOverrides: startOverrides,
            durationOverrides: durationOverrides,
            completion: { _, _ in
                inProgressSessions.remove(sessionID)
            }
        )
    }

    // MARK: - Cleanup

    /// Удаляет ВСЕ клипы сессии (при удалении сессии просмотра).
    static func removeAllClips(sessionID: UUID) {
        inProgressSessions.remove(sessionID)
        try? FileManager.default.removeItem(at: clipsDirPath(sessionID: sessionID))
    }

    /// Удаляет «осиротевшие» клипы — те, что больше не встречаются ни в одном плейлисте сессии
    /// (при удалении плейлиста/группы/эпизода). Клипы всё ещё присутствующих эпизодов сохраняются.
    static func pruneOrphanedClips(for session: SportCutSession) {
        let dir = clipsDirPath(sessionID: session.id)
        guard FileManager.default.fileExists(atPath: dir.path),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        var keepFileNames = Set<String>()
        for group in session.playlistGroups {
            for playlist in group.playlists {
                for event in playlist.events {
                    keepFileNames.insert(fileName(forHiddenKey: event.hiddenKey))
                }
            }
        }

        for file in files where file.pathExtension.lowercased() == "mov" {
            if !keepFileNames.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
