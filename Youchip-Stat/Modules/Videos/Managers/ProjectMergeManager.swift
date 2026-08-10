//
//  ProjectMergeManager.swift
//  Youchip-Stat
//
//  Склейка нескольких проектов в один: видео идут друг за другом,
//  разметка каждого следующего проекта сдвигается на суммарную длительность
//  предыдущих, поэтому метки остаются на своих моментах.
//

import AVFoundation
import AppKit
import Combine
import Foundation

/// Проект-источник в том порядке, в котором его выбрал пользователь.
struct ProjectMergeSource: Identifiable, Equatable {
    let file: FilesFile
    var id: String { file.videoData.id }
    var name: String { file.name }

    static func == (lhs: ProjectMergeSource, rhs: ProjectMergeSource) -> Bool {
        lhs.id == rhs.id
    }
}

struct ProjectMergeOptions {
    /// Имя нового проекта.
    var projectName: String
    /// Имена одноимённых дорожек, которые пользователь выбрал объединить в одну.
    /// Одноимённые дорожки, чьё имя сюда НЕ входит, остаются раздельными (с префиксом проекта);
    /// уникальные дорожки всегда сохраняют своё имя.
    var mergedLineNames: Set<String>
}

final class ProjectMergeManager: ObservableObject {

    static let shared = ProjectMergeManager()

    enum MergeError: LocalizedError {
        case notEnoughProjects
        case videoUnavailable(String)
        case noVideoTrack(String)
        case compositionFailed
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .notEnoughProjects:
                return ^String.Titles.mergeErrorNotEnoughProjects
            case .videoUnavailable(let name):
                return String(format: ^String.Titles.mergeErrorVideoUnavailable, name)
            case .noVideoTrack(let name):
                return String(format: ^String.Titles.mergeErrorNoVideoTrack, name)
            case .compositionFailed:
                return ^String.Titles.mergeErrorComposition
            case .exportFailed(let message):
                return message
            }
        }
    }

    @Published private(set) var isMerging = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText: String = ""

    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?

    private init() {}

    // MARK: - Публичный запуск

    func merge(
        sources: [ProjectMergeSource],
        options: ProjectMergeOptions,
        outputURL: URL,
        completion: @escaping (Result<FilesFile, Error>) -> Void
    ) {
        guard sources.count >= 2 else {
            completion(.failure(MergeError.notEnoughProjects))
            return
        }

        isMerging = true
        progress = 0
        statusText = ^String.Titles.mergeStatusPreparing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let prepared = try self.buildComposition(for: sources)
                self.export(prepared, sources: sources, options: options, outputURL: outputURL, completion: completion)
            } catch {
                DispatchQueue.main.async {
                    self.finish(with: .failure(error), completion: completion)
                }
            }
        }
    }

    func cancel() {
        exportSession?.cancelExport()
    }

    // MARK: - Композиция

    private struct PreparedComposition {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        /// Смещение начала каждого источника в общей шкале, в секундах.
        let offsets: [Double]
    }

    private func buildComposition(for sources: [ProjectMergeSource]) throws -> PreparedComposition {
        var assets: [AVURLAsset] = []
        for source in sources {
            guard let url = source.file.url else {
                throw MergeError.videoUnavailable(source.name)
            }
            assets.append(AVURLAsset(url: url))
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MergeError.compositionFailed
        }
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        // Общий кадр — самый крупный из исходников, остальные вписываются с полями.
        var renderSize = CGSize.zero
        var maxFrameRate: Float = 0
        for (index, asset) in assets.enumerated() {
            guard let track = asset.tracks(withMediaType: .video).first else {
                throw MergeError.noVideoTrack(sources[index].name)
            }
            let size = orientedSize(of: track)
            renderSize.width = max(renderSize.width, size.width)
            renderSize.height = max(renderSize.height, size.height)
            maxFrameRate = max(maxFrameRate, track.nominalFrameRate)
        }
        guard renderSize.width > 0, renderSize.height > 0 else {
            throw MergeError.compositionFailed
        }
        // Размер кадра должен быть чётным, иначе часть кодеков ругается.
        renderSize.width.round(.down)
        renderSize.height.round(.down)
        if Int(renderSize.width) % 2 != 0 { renderSize.width -= 1 }
        if Int(renderSize.height) % 2 != 0 { renderSize.height -= 1 }

        var instructions: [AVMutableVideoCompositionInstruction] = []
        var offsets: [Double] = []
        var cursor = CMTime.zero

        for (index, asset) in assets.enumerated() {
            guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                throw MergeError.noVideoTrack(sources[index].name)
            }
            let duration = asset.duration
            guard duration.isValid, duration.seconds > 0 else { continue }
            let range = CMTimeRange(start: .zero, duration: duration)

            offsets.append(cursor.seconds)

            do {
                try compositionVideoTrack.insertTimeRange(range, of: videoTrack, at: cursor)
            } catch {
                throw MergeError.compositionFailed
            }

            if let audioTrack = asset.tracks(withMediaType: .audio).first {
                // Пропуск звука не критичен — в этом куске просто будет тишина.
                try? compositionAudioTrack?.insertTimeRange(range, of: audioTrack, at: cursor)
            }

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            layerInstruction.setTransform(transform(for: videoTrack, renderSize: renderSize), at: cursor)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: duration)
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)

            cursor = cursor + duration
        }

        guard !instructions.isEmpty else {
            throw MergeError.compositionFailed
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.instructions = instructions
        let frameRate = min(60, max(24, maxFrameRate > 0 ? maxFrameRate : 30))
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rounded()))

        return PreparedComposition(composition: composition, videoComposition: videoComposition, offsets: offsets)
    }

    /// Размер кадра с учётом поворота, записанного в дорожке.
    private func orientedSize(of track: AVAssetTrack) -> CGSize {
        let transformed = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    /// Поворот исходника + вписывание в общий кадр по центру.
    private func transform(for track: AVAssetTrack, renderSize: CGSize) -> CGAffineTransform {
        let size = orientedSize(of: track)
        guard size.width > 0, size.height > 0 else { return track.preferredTransform }

        let scale = min(renderSize.width / size.width, renderSize.height / size.height)
        let translationX = (renderSize.width - size.width * scale) / 2
        let translationY = (renderSize.height - size.height * scale) / 2

        return track.preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: translationX, y: translationY))
    }

    // MARK: - Экспорт

    private func export(
        _ prepared: PreparedComposition,
        sources: [ProjectMergeSource],
        options: ProjectMergeOptions,
        outputURL: URL,
        completion: @escaping (Result<FilesFile, Error>) -> Void
    ) {
        guard let session = AVAssetExportSession(
            asset: prepared.composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            DispatchQueue.main.async { [weak self] in
                self?.finish(with: .failure(MergeError.compositionFailed), completion: completion)
            }
            return
        }

        try? FileManager.default.removeItem(at: outputURL)

        session.outputURL = outputURL
        session.outputFileType = outputURL.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        session.shouldOptimizeForNetworkUse = false
        session.videoComposition = prepared.videoComposition
        exportSession = session

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusText = ^String.Titles.mergeStatusExporting
            self.startProgressTimer(for: session)
        }

        session.exportAsynchronously { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.stopProgressTimer()

                switch session.status {
                case .completed:
                    self.statusText = ^String.Titles.mergeStatusFinishing
                    self.progress = 0.97
                    let result = self.assembleProject(
                        sources: sources,
                        options: options,
                        offsets: prepared.offsets,
                        videoURL: outputURL
                    )
                    self.finish(with: result, completion: completion)
                case .cancelled:
                    try? FileManager.default.removeItem(at: outputURL)
                    self.finish(with: .failure(MergeError.exportFailed(^String.Titles.mergeErrorCancelled)), completion: completion)
                default:
                    try? FileManager.default.removeItem(at: outputURL)
                    let message = Self.detailedExportError(status: session.status, error: session.error)
                    self.finish(with: .failure(MergeError.exportFailed(message)), completion: completion)
                }
            }
        }
    }

    /// Подробный текст ошибки экспорта — с domain/code и всей цепочкой underlying-ошибок,
    /// чтобы пользователь мог прислать скриншот, а мы точно опознали причину
    /// (например AVFoundation -11847 = операция прервана системой).
    private static func detailedExportError(status: AVAssetExportSession.Status, error: Error?) -> String {
        guard let error else {
            return "\(^String.Titles.mergeErrorExport) [status=\(status.rawValue), no error]"
        }

        var lines: [String] = []

        func describe(_ error: Error, prefix: String) {
            let ns = error as NSError
            lines.append("\(prefix)\(ns.localizedDescription) [\(ns.domain) \(ns.code)]")
            if let reason = ns.localizedFailureReason {
                lines.append("\(prefix)  reason: \(reason)")
            }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
                describe(underlying, prefix: prefix + "  → ")
            }
        }

        describe(error, prefix: "")
        return lines.joined(separator: "\n")
    }

    private func startProgressTimer(for session: AVAssetExportSession) {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Экспорт занимает почти всё время операции, оставляем хвост на сборку проекта.
            self.progress = 0.02 + Double(session.progress) * 0.93
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func finish(with result: Result<FilesFile, Error>, completion: @escaping (Result<FilesFile, Error>) -> Void) {
        stopProgressTimer()
        exportSession = nil
        isMerging = false
        progress = 0
        statusText = ""
        completion(result)
    }

    // MARK: - Сборка нового проекта

    private func assembleProject(
        sources: [ProjectMergeSource],
        options: ProjectMergeOptions,
        offsets: [Double],
        videoURL: URL
    ) -> Result<FilesFile, Error> {
        let filesManager = VideoFilesManager.shared
        guard let newFile = filesManager.importFile(url: videoURL, newName: options.projectName) else {
            return .failure(MergeError.exportFailed(^String.Titles.mergeErrorProjectCreation))
        }

        let timelineSources: [TimelineMergeSource] = sources.enumerated().map { index, source in
            TimelineMergeSource(
                projectName: source.name,
                timelines: source.file.timelines,
                offset: index < offsets.count ? offsets[index] : 0
            )
        }

        let (merged, remaps) = Self.mergedTimelines(sources: timelineSources, mergedLineNames: options.mergedLineNames)
        filesManager.saveTimelines(merged, for: newFile.videoData.id)

        copyScreenshots(
            from: sources.enumerated().map { index, source in
                (source.file,
                 index < offsets.count ? offsets[index] : 0,
                 index < remaps.count ? remaps[index] : [:])
            },
            to: newFile
        )

        return .success(newFile)
    }

    // MARK: - Слияние разметки

    struct TimelineMergeSource {
        let projectName: String
        let timelines: [TimelineLine]
        /// Сдвиг в секундах, с которого начинается видео этого проекта.
        let offset: Double
    }

    /// Собирает разметку всех проектов в одну шкалу времени.
    /// Дорожка рисунков всегда одна — она опознаётся по фиксированному id.
    /// `mergedLineNames` — имена одноимённых дорожек, которые пользователь выбрал слить в одну.
    /// Одноимённые дорожки не из этого набора остаются раздельными (различаются префиксом проекта);
    /// уникальные дорожки всегда сохраняют своё имя без изменений.
    /// Возвращает также per-source ремапы `oldStampID → newStampID` (в порядке `sources`) —
    /// нужны, чтобы перенести привязки скриншотов к штампам после перегенерации id.
    static func mergedTimelines(
        sources: [TimelineMergeSource],
        mergedLineNames: Set<String>
    ) -> (lines: [TimelineLine], stampIDRemaps: [[UUID: UUID]]) {
        // Имена, встречающиеся более одного раза среди всех проектов (кроме дорожки рисунков).
        let duplicateNames = duplicateLineNames(in: sources)

        var result: [TimelineLine] = []
        var indexByKey: [String: Int] = [:]
        var remaps: [[UUID: UUID]] = Array(repeating: [:], count: sources.count)

        for (sourceIndex, source) in sources.enumerated() {
            for line in source.timelines {
                // Каждый штамп пересобираем с НОВЫМ уникальным id (+ сдвиг времени на смещение видео).
                // Если проекты имеют совпадающие id штампов (напр. один проект дублировали из другого),
                // то при слиянии в одну дорожку дубликаты id ломают SwiftUI ForEach(id:) — теги
                // «схлопываются» (виден только один набор) и «уезжают» с мест. Новый id это исключает.
                let mergedStamps: [TimelineStamp] = line.stamps.map { stamp in
                    let newID = UUID()
                    remaps[sourceIndex][stamp.id] = newID
                    return mergedStamp(stamp, offset: source.offset, newID: newID)
                }

                let key: String?
                if line.isDrawingsTimeline {
                    key = "drawings:\(line.id.uuidString)"       // рисунки всегда в одну дорожку по id
                } else if mergedLineNames.contains(line.name) {
                    key = "name:\(line.name)"                    // пользователь выбрал объединить
                } else {
                    key = nil                                    // оставляем раздельной
                }

                if let key, let existingIndex = indexByKey[key] {
                    result[existingIndex].stamps.append(contentsOf: mergedStamps)
                    continue
                }

                var newLine = line
                newLine.stamps = mergedStamps
                if key == nil {
                    newLine.id = UUID()
                    // Одноимённые, которые НЕ сливаем, различаем префиксом проекта; уникальные — не трогаем.
                    if duplicateNames.contains(line.name) {
                        newLine.name = "\(source.projectName) — \(line.name)"
                    }
                }
                result.append(newLine)
                if let key {
                    indexByKey[key] = result.count - 1
                }
            }
        }

        for index in result.indices {
            result[index].stamps.sort { $0.timeStartSeconds < $1.timeStartSeconds }
        }

        return (result, remaps)
    }

    /// Имена дорожек (кроме дорожки рисунков), встречающиеся более одного раза среди всех источников.
    static func duplicateLineNames(in sources: [TimelineMergeSource]) -> Set<String> {
        var counts: [String: Int] = [:]
        for source in sources {
            for line in source.timelines where !line.isDrawingsTimeline {
                counts[line.name, default: 0] += 1
            }
        }
        return Set(counts.filter { $0.value >= 2 }.keys)
    }

    /// Копия штампа с новым id и временем, сдвинутым на `offset` (id у `TimelineStamp` — `let`,
    /// поэтому пересобираем через init, сохраняя все поля).
    private static func mergedStamp(_ stamp: TimelineStamp, offset: Double, newID: UUID) -> TimelineStamp {
        TimelineStamp(
            id: newID,
            tagRefs: stamp.tagRefs,
            primaryID: stamp.primaryID,
            timeStartSeconds: stamp.timeStartSeconds + offset,
            timeFinishSeconds: stamp.timeFinishSeconds + offset,
            colorHex: stamp.colorHex,
            label: stamp.label,
            labels: stamp.labels,
            timeEvents: stamp.timeEvents,
            isActiveForMapView: stamp.isActiveForMapView,
            comment: stamp.comment,
            mapPositions: stamp.mapPositions
        )
    }

    // MARK: - Скриншоты и рисунки

    /// Переносит скриншоты каждого проекта в новый, сдвигая привязку ко времени и перенося
    /// ссылки на штампы (`relatedStampIds`) на их новые id после слияния.
    private func copyScreenshots(from sources: [(file: FilesFile, offset: Double, stampIDRemap: [UUID: UUID])], to newFile: FilesFile) {
        let fileManager = FileManager.default
        let destinationFolder = newFile.screenshotsFolder

        for source in sources {
            let sourceFolder = source.file.screenshotsFolder
            guard let contents = try? fileManager.contentsOfDirectory(at: sourceFolder, includingPropertiesForKeys: nil) else {
                continue
            }

            for url in contents {
                let destination = destinationFolder.appendingPathComponent(url.lastPathComponent)
                // Имена вида Screenshot_<timestamp> практически не пересекаются;
                // если всё же совпали — оставляем уже перенесённый файл.
                guard !fileManager.fileExists(atPath: destination.path) else { continue }

                if url.pathExtension.lowercased() == "json" {
                    copyScreenshotMetadata(from: url, to: destination, offset: source.offset, stampIDRemap: source.stampIDRemap)
                } else {
                    try? fileManager.copyItem(at: url, to: destination)
                }
            }
        }
    }

    private func copyScreenshotMetadata(from url: URL, to destination: URL, offset: Double, stampIDRemap: [UUID: UUID]) {
        guard let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(ScreenshotMetadata.self, from: data) else {
            try? FileManager.default.copyItem(at: url, to: destination)
            return
        }

        // Штампы получили новые id при слиянии — переносим привязки скриншота на них.
        let remappedRelated = metadata.relatedStampIds.map { stampIDRemap[$0] ?? $0 }

        let shifted = ScreenshotMetadata(
            screenshotName: metadata.screenshotName,
            videoTime: metadata.videoTime + offset,
            createdAt: metadata.createdAt,
            saveAsTag: metadata.saveAsTag,
            displayDuration: metadata.displayDuration,
            relatedStampIds: remappedRelated,
            editorState: metadata.editorState
        )

        guard let encoded = try? JSONEncoder().encode(shifted) else {
            try? FileManager.default.copyItem(at: url, to: destination)
            return
        }
        try? encoded.write(to: destination)
    }
}
