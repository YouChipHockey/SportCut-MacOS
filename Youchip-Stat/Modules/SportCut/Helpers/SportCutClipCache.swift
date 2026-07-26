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

    private static func clipsDir(sessionID: UUID) -> URL {
        let dir = URL.appDocumentsDirectory
            .appendingPathComponent("YouChip-Stat/PlaylistClips/\(sessionID.uuidString)", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileName(for event: SportCutEvent) -> String {
        // hiddenKey = "sourceID|stampID" — заменяем разделитель для имени файла.
        event.hiddenKey.replacingOccurrences(of: "|", with: "_") + ".mov"
    }

    /// URL закэшированного (обрезанного) клипа события, если он уже экспортирован.
    static func cachedClipURL(sessionID: UUID, event: SportCutEvent) -> URL? {
        let url = clipsDir(sessionID: sessionID).appendingPathComponent(fileName(for: event))
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
}
