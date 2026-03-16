//
//  ExportHelper.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 20.12.2025.
//

import Foundation
import AVKit
import Cocoa

class ExportHelper: ObservableObject {
    
    static let exportCancelledCode = 999
    static var exportCancelledError: NSError {
        NSError(domain: "Export", code: exportCancelledCode, userInfo: [NSLocalizedDescriptionKey: "Cancelled"])
    }
    static func isExportCancelled(_ error: Error) -> Bool {
        (error as NSError).code == exportCancelledCode
    }
    
    private let videoManager = VideoPlayerManager.shared
    private let timelineData = TimelineDataManager.shared
    private let tagLibrary = TagLibraryManager.shared
    
    private var exportProgressTimer: DispatchSourceTimer?
    private var processedSegments: Int = 0
    private var activeExportSessions: [AVAssetExportSession] = []
    private let sessionsLock = NSLock()
    private var isExportCancelled = false
    
    var exportWasCancelled: Bool { isExportCancelled }
    
    @Published var progress: Float = 0
    
    func addExportSession(_ session: AVAssetExportSession?) {
        guard let session else { return }
        sessionsLock.lock()
        activeExportSessions.append(session)
        sessionsLock.unlock()
    }
    
    func removeExportSession(_ session: AVAssetExportSession?) {
        guard let session else { return }
        sessionsLock.lock()
        activeExportSessions.removeAll { $0 === session }
        sessionsLock.unlock()
    }
    
    func cancelExport() {
        isExportCancelled = true
        sessionsLock.lock()
        let sessions = activeExportSessions
        activeExportSessions.removeAll()
        sessionsLock.unlock()
        for s in sessions { s.cancelExport() }
        stopProgressTimer()
    }
    
    // MARK: Public Export Method
    
    func performExport(selectedExportType: CutsExportType?, mode: ExportMode, withScreenshots: Bool = false, completion: @escaping (Error?) -> Void) {
        resetValues()
        
        // Handle screenshots export
        if case .screenshots = selectedExportType {
            exportScreenshots(completion: completion)
            return
        }
        
        guard let selectedType = selectedExportType else {
            completion(NSError.getErrorWithDescription("No export type selected"))
            return
        }
        
        let segments = getSegmentsForExport(type: selectedType)
        if segments.isEmpty {
            completion(NSError.getErrorWithDescription(^String.Titles.fullControlExportNoSegments))
            return
        }
        
        let effectiveWithScreenshots: Bool
        if case .drawingsTimeline = selectedType {
            effectiveWithScreenshots = true
        } else {
            effectiveWithScreenshots = withScreenshots
        }
        
        // В режиме трансляции: берём снимок уже готовых сегментов (без остановки записи) как основу для нарезки.
        if videoManager.isLiveMode {
            LiveStreamManager.shared.snapshotCompositionForExport { asset in
                guard let asset = asset else {
                    DispatchQueue.main.async { completion(NSError.getErrorWithDescription(^String.Titles.fullControlExportErrorAsset)) }
                    return
                }
                self.performExportWithAsset(asset, segments: segments, selectedType: selectedType, mode: mode, effectiveWithScreenshots: effectiveWithScreenshots, completion: completion)
            }
            return
        }
        
        guard let asset = VideoPlayerManager.shared.player?.currentItem?.asset else {
            completion(NSError.getErrorWithDescription(^String.Titles.fullControlExportErrorAsset))
            return
        }
        
        performExportWithAsset(asset, segments: segments, selectedType: selectedType, mode: mode, effectiveWithScreenshots: effectiveWithScreenshots, completion: completion)
    }
    
    private func performExportWithAsset(_ asset: AVAsset, segments: [ExportSegment], selectedType: CutsExportType, mode: ExportMode, effectiveWithScreenshots: Bool, completion: @escaping (Error?) -> Void) {
        if mode == .film {
            exportFilm(segments: segments, asset: asset, type: selectedType, withScreenshots: effectiveWithScreenshots) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let outputURL):
                        let panel = NSSavePanel()
                        panel.allowedFileTypes = ["mp4"]
                        panel.nameFieldStringValue = outputURL.lastPathComponent
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                if FileManager.default.fileExists(atPath: url.path) == true {
                                    try FileManager.default.removeItem(at: url)
                                }
                                try FileManager.default.copyItem(at: outputURL, to: url)
                                print("\(^String.Titles.fullControlExportFilmSuccess) \(url)")
                                completion(nil)
                            } catch {
                                completion(NSError.getErrorWithDescription("\(^String.Titles.fullControlExportFilmError): \(error.localizedDescription)"))
                            }
                        } else {
                            completion(nil)
                        }
                    case .failure(let error):
                        if ExportHelper.isExportCancelled(error) {
                            completion(nil)
                        } else {
                            completion(NSError.getErrorWithDescription("\(^String.Titles.fullControlExportFilmError): \(error.localizedDescription)"))
                        }
                    }
                }
            }
        } else {
            exportPlaylist(segments: segments, asset: asset, type: selectedType, withScreenshots: effectiveWithScreenshots) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let zipURL):
                        let panel = NSSavePanel()
                        panel.allowedFileTypes = ["zip"]
                        panel.nameFieldStringValue = "export_playlist.zip"
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                if FileManager.default.fileExists(atPath: url.path) == true {
                                    try FileManager.default.removeItem(at: url)
                                }
                                try FileManager.default.copyItem(at: zipURL, to: url)
                                completion(nil)
                            } catch {
                                completion(NSError.getErrorWithDescription("Ошибка сохранения плейлиста: \(error.localizedDescription)"))
                            }
                        } else {
                            completion(nil)
                        }
                    case .failure(let error):
                        if ExportHelper.isExportCancelled(error) {
                            completion(nil)
                        } else {
                            completion(NSError.getErrorWithDescription("Ошибка сохранения плейлиста: \(error.localizedDescription)"))
                        }
                    }
                }
            }
        }
    }
    
    
    // MARK: - startProgressTimer
    
    func startProgressTimer(exportSession: AVAssetExportSession?) {
        guard let exportSession else { return }
        
        exportProgressTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self, weak exportSession] in
            guard let self, let exportSession else { return }
            
            self.progress = switch exportSession.status {
            case .completed:
                1
            default:
                exportSession.progress
            }
        }
        exportProgressTimer = timer
        timer.resume()
    }
    
    // MARK: - stopProgressTimer
    func stopProgressTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.exportProgressTimer?.cancel()
            self?.exportProgressTimer = nil
        }
    }
    
    func processSegment(segmentsCount: Int) {
        processedSegments += 1
        DispatchQueue.main.async { [weak self] in
            guard let welf = self else { return }
            welf.progress = Float(welf.processedSegments) / Float(segmentsCount)
        }
    }
    
    func resetValues() {
        progress = 0
        processedSegments = 0
        isExportCancelled = false
    }
    
    // MARK: - Export Film
    
    private func exportFilm(segments: [ExportSegment], asset: AVAsset, type: CutsExportType, withScreenshots: Bool = false, completion: @escaping (Result<URL, Error>) -> Void) {
        // Проверка на пустоту сегментов перед созданием композиции
        if segments.isEmpty {
            completion(.failure(NSError(domain: "Export", code: -1, userInfo: [NSLocalizedDescriptionKey: "No segments to export"])))
            return
        }
        
        let composition = AVMutableComposition()
        
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(NSError(domain: "Export", code: 0, userInfo: [NSLocalizedDescriptionKey: "Video track not found"])))
            return
        }
        let audioTrack = asset.tracks(withMediaType: .audio).first
        
        // Получаем длительность видео для валидации сегментов
        let videoDuration = CMTimeGetSeconds(asset.duration)
        
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(.failure(NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create video track"])))
            return
        }
        var compAudioTrack: AVMutableCompositionTrack? = nil
        if audioTrack != nil {
            compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        
        var overlayItems: [OverlayItem] = []
        var currentTime = CMTime.zero
        for segment in segments {
            // Проверяем, что сегмент не равен всему видео (с допуском 0.1 секунды)
            let segmentStart = CMTimeGetSeconds(segment.timeRange.start)
            let segmentDuration = CMTimeGetSeconds(segment.timeRange.duration)
            let segmentEnd = segmentStart + segmentDuration
            
            // Пропускаем сегменты, которые покрывают почти всё видео (более 99% длительности)
            if segmentStart < 0.1 && segmentEnd > videoDuration * 0.99 {
                print("Пропущен сегмент, который равен всему видео: start=\(segmentStart), duration=\(segmentDuration), videoDuration=\(videoDuration)")
                continue
            }
            
            let transform = videoTrack.preferredTransform
            let naturalSize = videoTrack.naturalSize.applying(transform)
            let videoSize = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))

            // Handle screenshots insertion if enabled
            if withScreenshots {
                let screenshots = getScreenshotsInSegment(segment)
                if !screenshots.isEmpty {
                    let timeBefore = currentTime
                    currentTime = insertScreenshotsIntoComposition(
                        composition: composition,
                        videoTrack: videoTrack,
                        audioTrack: audioTrack,
                        segmentTimeRange: segment.timeRange,
                        screenshots: screenshots,
                        startTime: currentTime
                    )
                    let tag = tagLibrary.allTags.first(where: { $0.id == segment.stamp.idTag })
                        ?? Tag.syntheticDrawingTag(for: segment.stamp)
                    if let tag {
                        let overlayItem = OverlayItem(
                            tag: tag,
                            stamp: segment.stamp,
                            selectedLabelGroups: OverlayLabelGroupItem.labelGroupItems(forLabels: segment.stamp.labelIDs),
                            start: timeBefore,
                            duration: currentTime - timeBefore,
                            videoSize: videoSize
                        )
                        overlayItems.append(overlayItem)
                    }
                    continue
                }
            }
            
            do {
                try compVideoTrack.insertTimeRange(segment.timeRange, of: videoTrack, at: currentTime)
                if let compAudio = compAudioTrack, let aTrack = audioTrack {
                    try compAudio.insertTimeRange(segment.timeRange, of: aTrack, at: currentTime)
                }
                currentTime = currentTime + segment.timeRange.duration
            } catch {
                completion(.failure(error))
                return
            }
            
            let tag = tagLibrary.allTags.first(where: { $0.id == segment.stamp.idTag })
                ?? Tag.syntheticDrawingTag(for: segment.stamp)
            if let tag {
                let overlayItem = OverlayItem(
                    tag: tag,
                    stamp: segment.stamp,
                    selectedLabelGroups: OverlayLabelGroupItem.labelGroupItems(forLabels: segment.stamp.labelIDs),
                    start: currentTime - segment.timeRange.duration,
                    duration: segment.timeRange.duration,
                    videoSize: videoSize
                )
                overlayItems.append(overlayItem)
            }
            
        }
        
        // Проверяем, что в композицию были добавлены сегменты
        if currentTime == CMTime.zero {
            completion(.failure(NSError(domain: "Export", code: -2, userInfo: [NSLocalizedDescriptionKey: "No valid segments to export"])))
            return
        }
        
        let fileName: String
        switch type {
        case .currentTimeline:
            if let lineName = segments.first?.lineName {
                fileName = "\(lineName)\(^String.Titles.fullControlFileTimelineFile)"
            } else {
                fileName = "timeline\(^String.Titles.fullControlFileTimelineFile)"
            }
        case .tag(let selectedTag):
            let groupName = segments.first?.groupName ?? "group"
            fileName = "\(groupName)_\(selectedTag.name)\(^String.Titles.fullControlFileTimelineFile)"
        case .timeEvent(let selectedEvent):
            let tagName = segments.first?.tagName ?? "tag"
            fileName = "\(selectedEvent.name)_\(tagName)\(^String.Titles.fullControlFileTimelineFile)"
        case .allTimelines:
            if let firstSegment = segments.first {
                let groupName = firstSegment.groupName ?? "group"
                let tagName = firstSegment.tagName
                fileName = "\(groupName)_\(tagName)\(^String.Titles.fullControlFileTimelineFile)"
            } else {
                fileName = ^String.Titles.fullControlFileAllTimelinesFile
            }
        case .label(let selectedLabel):
            fileName = "\(selectedLabel.name)\(^String.Titles.fullControlFileTimelineFile)"
            
        case .tagWithLabels(let selectedTag, let selectedLabels):
            let labelsString = selectedLabels.map { $0.name }.joined(separator: "_")
            fileName = "\(selectedTag.name)_\(labelsString)\(^String.Titles.fullControlFileTimelineFile)"
            
        case .labelWithTags(let selectedLabel, let selectedTags):
            let tagsString = selectedTags.map { $0.name }.joined(separator: "_")
            fileName = "\(selectedLabel.name)_\(tagsString)\(^String.Titles.fullControlFileTimelineFile)"
        
        case .screenshots:
            fileName = "screenshots.mp4"
        case .drawingsTimeline:
            fileName = "\(ScreenshotConstants.screenshotsGroupName)_Фильм\(^String.Titles.fullControlFileTimelineFile)"
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
        } catch {
            completion(.failure(error.localizedDescription))
        }
        
        let overlayVideoComposition = videoCompositionWithTextOverlay(overlayItems: overlayItems, videoTrack: videoTrack, compositionVideoTrack: compVideoTrack, compositionDuration: composition.duration)
        
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        exportSession?.outputURL = outputURL
        exportSession?.outputFileType = .mp4
        exportSession?.videoComposition = overlayVideoComposition
        
        addExportSession(exportSession)
        startProgressTimer(exportSession: exportSession)
        
        exportSession?.exportAsynchronously { [weak self] in
            self?.removeExportSession(exportSession)
            self?.stopProgressTimer()
            if exportSession?.status == .completed {
                completion(.success(outputURL))
            } else if exportSession?.status == .cancelled {
                completion(.failure(ExportHelper.exportCancelledError))
            } else {
                completion(.failure(exportSession?.error ?? NSError(domain: "Export", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown export error"])))
            }
        }
    }
    
    // MARK: - Export Playlist
    
    private func exportPlaylist(
        segments: [ExportSegment],
        asset: AVAsset,
        type: CutsExportType,
        withScreenshots: Bool = false,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if segments.isEmpty {
            completion(.failure(NSError(domain: "Export", code: -1, userInfo: [NSLocalizedDescriptionKey: "No segments to export"])))
            return
        }
        
        isExportCancelled = false
        var exportedURLs: [URL] = []
        let group = DispatchGroup()
        var exportError: Error? = nil
        
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(NSError(domain: "Export", code: 0, userInfo: [NSLocalizedDescriptionKey: "Video track not found"])))
            return
        }
        let audioTrack = asset.tracks(withMediaType: .audio).first
        
        // Получаем длительность видео для валидации сегментов
        let videoDuration = CMTimeGetSeconds(asset.duration)
        
        for (index, segment) in segments.enumerated() {
            // Проверяем, что сегмент не равен всему видео (с допуском 0.1 секунды)
            let segmentStart = CMTimeGetSeconds(segment.timeRange.start)
            let segmentDuration = CMTimeGetSeconds(segment.timeRange.duration)
            let segmentEnd = segmentStart + segmentDuration
            
            // Пропускаем сегменты, которые покрывают почти всё видео (более 99% длительности)
            if segmentStart < 0.1 && segmentEnd > videoDuration * 0.99 {
                print("Пропущен сегмент в плейлисте, который равен всему видео: start=\(segmentStart), duration=\(segmentDuration), videoDuration=\(videoDuration)")
                continue
            }
            
            group.enter()
            
            let composition = AVMutableComposition()
            guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video,
                                                                   preferredTrackID: kCMPersistentTrackID_Invalid)
            else {
                exportError = NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create video track"])
                group.leave()
                continue
            }
            var compAudioTrack: AVMutableCompositionTrack? = nil
            if let aTrack = audioTrack {
                compAudioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid)
            }
            
            var currentSegmentTime = CMTime.zero
            
            // Handle screenshots insertion if enabled
            if withScreenshots {
                let screenshots = getScreenshotsInSegment(segment)
                if !screenshots.isEmpty {
                    currentSegmentTime = insertScreenshotsIntoComposition(
                        composition: composition,
                        videoTrack: videoTrack,
                        audioTrack: audioTrack,
                        segmentTimeRange: segment.timeRange,
                        screenshots: screenshots,
                        startTime: .zero
                    )
                } else {
                    // No screenshots, insert video normally
                    do {
                        try compVideoTrack.insertTimeRange(segment.timeRange, of: videoTrack, at: .zero)
                        if let compAudio = compAudioTrack, let aTrack = audioTrack {
                            try compAudio.insertTimeRange(segment.timeRange, of: aTrack, at: .zero)
                        }
                    } catch {
                        exportError = error
                        group.leave()
                        continue
                    }
                }
            } else {
                // No screenshots mode - insert normally
                do {
                    try compVideoTrack.insertTimeRange(segment.timeRange, of: videoTrack, at: .zero)
                    if let compAudio = compAudioTrack, let aTrack = audioTrack {
                        try compAudio.insertTimeRange(segment.timeRange, of: aTrack, at: .zero)
                    }
                } catch {
                    exportError = error
                    group.leave()
                    continue
                }
            }
            let fileName: String
            
            switch type {
            case .currentTimeline:
                let lineName = segment.lineName ?? ^String.Titles.fullControlFileTimeline
                fileName = "\(lineName)_\(segment.tagName)_\(index + 1).mp4"
                
            case .allTimelines:
                let lineName = segment.lineName ?? ^String.Titles.fullControlFileTimeline
                let groupName = segment.groupName ?? "group"
                let tagName = segment.tagName
                fileName = "\(lineName)_\(groupName)_\(tagName)_\(index + 1).mp4"
                
            case .tag(let selectedTag):
                let groupName = segment.groupName ?? "group"
                fileName = "\(groupName)_\(selectedTag.name)_\(index + 1).mp4"
                
            case .timeEvent(let selectedEvent):
                fileName = "\(selectedEvent.name)_\(segment.tagName)_\(index + 1).mp4"
            case .label(let selectedLabel):
                let labelGroupName = segment.labelGroupName ?? "Labels"
                fileName = "\(labelGroupName)_\(selectedLabel.name)_\(segment.tagName)_\(index + 1).mp4"
                
            case .tagWithLabels(let selectedTag, let selectedLabels):
                let groupName = segment.groupName ?? "group"
                let stampLabels = segment.stamp.labelIDs.compactMap { labelID in
                    tagLibrary.allLabels.first(where: { $0.id == labelID })
                }
                if !stampLabels.isEmpty {
                    let labelsString = stampLabels.map { $0.name }.joined(separator: "_")
                    fileName = "\(groupName)_\(selectedTag.name)_\(labelsString)_\(index + 1).mp4"
                } else {
                    fileName = "\(groupName)_\(selectedTag.name)_\(index + 1).mp4"
                }
                
            case .labelWithTags(let selectedLabel, let selectedTags):
                let labelGroupName = segment.labelGroupName ?? "Labels"
                fileName = "\(labelGroupName)_\(selectedLabel.name)_\(segment.tagName)_\(index + 1).mp4"
            
            case .screenshots:
                fileName = "screenshot_\(index + 1).png"
            case .drawingsTimeline:
                fileName = "\(ScreenshotConstants.screenshotsGroupName)_\(segment.tagName)_\(index + 1).mp4"
            }
            
            let clipOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: clipOutputURL)
            
            let transform = videoTrack.preferredTransform
            let naturalSize = videoTrack.naturalSize.applying(transform)
            let videoSize = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))
            let overlayVideoComposition: AVVideoComposition?
            let tag = tagLibrary.allTags.first(where: { $0.id == segment.stamp.idTag })
                ?? Tag.syntheticDrawingTag(for: segment.stamp)
            if let tag {
                let overlayItem = OverlayItem(
                    tag: tag,
                    stamp: segment.stamp,
                    selectedLabelGroups: OverlayLabelGroupItem.labelGroupItems(forLabels: segment.stamp.labelIDs),
                    start: .zero,
                    duration: segment.timeRange.duration,
                    videoSize: videoSize
                )
                overlayVideoComposition = videoCompositionWithTextOverlay(overlayItem: overlayItem, videoTrack: videoTrack, compositionVideoTrack: compVideoTrack, compositionDuration: composition.duration)
            } else {
                overlayVideoComposition = nil
            }
            
            
            let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
            exportSession?.outputURL = clipOutputURL
            exportSession?.outputFileType = .mp4
            exportSession?.videoComposition = overlayVideoComposition
            
            addExportSession(exportSession)
            
            exportSession?.exportAsynchronously { [weak self] in
                self?.removeExportSession(exportSession)
                if exportSession?.status == .completed {
                    exportedURLs.append(clipOutputURL)
                } else if self?.isExportCancelled != true {
                    exportError = exportSession?.error ?? NSError(domain: "Export", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown export error"])
                }
                self?.processSegment(segmentsCount: segments.count)
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.progress = 1
            if self?.exportWasCancelled == true {
                completion(.failure(ExportHelper.exportCancelledError))
                return
            }
            if let error = exportError {
                completion(.failure(error))
            } else if exportedURLs.isEmpty {
                completion(.failure(NSError(domain: "Export", code: -3, userInfo: [NSLocalizedDescriptionKey: "No valid segments were exported"])))
            } else {
                self?.compressFiles(urls: exportedURLs, completion: completion)
            }
        }
    }
    
    
    // MARK: - Helpers
    
    private func correctTimeRange(startSeconds: Double, durationSeconds: Double, maxVideoDuration: Double) -> (start: Double, duration: Double)? {
        var correctedStart = startSeconds
        var correctedDuration = durationSeconds
        if correctedStart < 0 {
            correctedStart = 0
        }
        let endSeconds = correctedStart + correctedDuration
        if endSeconds > maxVideoDuration {
            let newDuration = maxVideoDuration - correctedStart
            if newDuration > 0 {
                correctedDuration = newDuration
            } else {
                return nil
            }
        }
        
        guard correctedDuration > 0 else {
            return nil
        }
        
        return (correctedStart, correctedDuration)
    }
    
    
    private func getSegmentsForExport(type: CutsExportType) -> [ExportSegment] {
        var result: [ExportSegment] = []
        
        let maxVideoDuration = max(1.0, videoManager.videoDuration)
        
        switch type {
        case .currentTimeline:
            if let lineID = timelineData.selectedLineID,
               let line = timelineData.lines.first(where: { $0.id == lineID }) {
                for stamp in line.stamps {
                    guard let correctedTime = correctTimeRange(
                        startSeconds: stamp.timeStartSeconds,
                        durationSeconds: stamp.duration,
                        maxVideoDuration: maxVideoDuration
                    ) else {
                        continue
                    }
                    
                    let start = CMTime(seconds: correctedTime.start, preferredTimescale: 600)
                    let duration = CMTime(seconds: correctedTime.duration, preferredTimescale: 600)
                    let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                    
                    result.append(
                        ExportSegment(
                            stamp: stamp,
                            tagName: stamp.label,
                            timeRange: CMTimeRange(start: start, duration: duration),
                            lineName: line.name,
                            groupName: possibleGroup?.name,
                            labelGroupName: nil,
                            selectedLabel: nil,
                            stampId: stamp.id
                        )
                    )
                }
            }
        case .allTimelines:
            for line in timelineData.lines {
                for stamp in line.stamps {
                    guard let correctedTime = correctTimeRange(
                        startSeconds: stamp.timeStartSeconds,
                        durationSeconds: stamp.duration,
                        maxVideoDuration: maxVideoDuration
                    ) else {
                        continue
                    }
                    
                    let start = CMTime(seconds: correctedTime.start, preferredTimescale: 600)
                    let duration = CMTime(seconds: correctedTime.duration, preferredTimescale: 600)
                    let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                    let labels = stamp.labelIDs.compactMap { labelID in
                        tagLibrary.findLabelById(labelID)?.name
                    }
                    let tagNameWithLabels = labels.isEmpty ? stamp.label : "\(stamp.label)(\(labels.joined(separator: "_")))"
                    
                    result.append(
                        ExportSegment(
                            stamp: stamp,
                            tagName: tagNameWithLabels,
                            timeRange: CMTimeRange(start: start, duration: duration),
                            lineName: line.name,
                            groupName: possibleGroup?.name,
                            labelGroupName: nil,
                            selectedLabel: nil,
                            stampId: stamp.id
                        )
                    )
                }
            }
        case .tag(let selectedTag):
            let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(selectedTag.id) })
            
            for line in timelineData.lines {
                for stamp in line.stamps {
                    guard stamp.idTags.contains(selectedTag.id) else {
                        continue
                    }
                    
                    guard let correctedTime = correctTimeRange(
                        startSeconds: stamp.timeStartSeconds,
                        durationSeconds: stamp.duration,
                        maxVideoDuration: maxVideoDuration
                    ) else {
                        continue
                    }
                    
                    let segmentRatio = correctedTime.duration / maxVideoDuration
                    if correctedTime.start < 0.1 && segmentRatio > 0.99 {
                        print("Пропущен сегмент тега '\(stamp.label)' в getSegmentsForExport: покрывает \(segmentRatio * 100)% видео")
                        continue
                    }
                    
                    if correctedTime.duration < 0.1 {
                        print("Пропущен слишком короткий сегмент тега '\(stamp.label)': duration=\(correctedTime.duration)")
                        continue
                    }
                    
                    let start = CMTime(seconds: correctedTime.start, preferredTimescale: 600)
                    let duration = CMTime(seconds: correctedTime.duration, preferredTimescale: 600)

                    result.append(
                        ExportSegment(
                            stamp: stamp,
                            tagName: stamp.label,
                            timeRange: CMTimeRange(start: start, duration: duration),
                            lineName: line.name,
                            groupName: possibleGroup?.name,
                            labelGroupName: nil,
                            selectedLabel: nil,
                            stampId: stamp.id
                        )
                    )
                }
            }
        case .timeEvent(let selectedEvent):
            for line in timelineData.lines {
                for stamp in line.stamps {
                    if stamp.timeEvents.contains(selectedEvent.id) {
                        guard let correctedTime = correctTimeRange(
                            startSeconds: stamp.timeStartSeconds,
                            durationSeconds: stamp.duration,
                            maxVideoDuration: maxVideoDuration
                        ) else {
                            continue
                        }
                        
                        let start = CMTime(seconds: correctedTime.start, preferredTimescale: 600)
                        let duration = CMTime(seconds: correctedTime.duration, preferredTimescale: 600)
                        let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })

                        result.append(
                            ExportSegment(
                                stamp: stamp,
                                tagName: stamp.label,
                                timeRange: CMTimeRange(start: start, duration: duration),
                                lineName: line.name,
                                groupName: possibleGroup?.name,
                                labelGroupName: nil,
                                selectedLabel: nil,
                                stampId: stamp.id
                            )
                        )
                    }
                }
            }
        case .label(let selectedLabel):
            var labelGroupName: String? = nil
            for group in tagLibrary.allLabelGroups {
                if group.lables.contains(selectedLabel.id) {
                    labelGroupName = group.name
                    break
                }
            }
            
            for line in timelineData.lines {
                for stamp in line.stamps {
                    if stamp.labelIDs.contains(selectedLabel.id) {
                        guard let correctedTime = correctTimeRange(
                            startSeconds: stamp.timeStartSeconds,
                            durationSeconds: stamp.duration,
                            maxVideoDuration: maxVideoDuration
                        ) else {
                            continue
                        }

                        let start = CMTime(seconds: correctedTime.start, preferredTimescale: 600)
                        let duration = CMTime(seconds: correctedTime.duration, preferredTimescale: 600)
                        let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                        
                        result.append(
                            ExportSegment(
                                stamp: stamp,
                                tagName: stamp.label,
                                timeRange: CMTimeRange(start: start, duration: duration),
                                lineName: line.name,
                                groupName: possibleGroup?.name,
                                labelGroupName: labelGroupName,
                                selectedLabel: selectedLabel,
                                stampId: stamp.id
                            )
                        )
                    }
                }
            }
            
        case .tagWithLabels(let selectedTag, let selectedLabels):
            let labelIDs = Set(selectedLabels.map { $0.id })
            for line in timelineData.lines {
                for stamp in line.stamps {
                    if stamp.idTags.contains(selectedTag.id) && !Set(stamp.labelIDs).isDisjoint(with: labelIDs) {
                        guard let correctedTime = correctTimeRange(
                            startSeconds: stamp.timeStartSeconds,
                            durationSeconds: stamp.duration,
                            maxVideoDuration: maxVideoDuration
                        ) else {
                            continue
                        }
                        
                        let start = CMTime(seconds: correctedTime.start, preferredTimescale: 600)
                        let duration = CMTime(seconds: correctedTime.duration, preferredTimescale: 600)
                        let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                        
                        result.append(
                            ExportSegment(
                                stamp: stamp,
                                tagName: stamp.label,
                                timeRange: CMTimeRange(start: start, duration: duration),
                                lineName: line.name,
                                groupName: possibleGroup?.name,
                                labelGroupName: nil,
                                selectedLabel: nil,
                                stampId: stamp.id
                            )
                        )
                    }
                }
            }
            
        case .labelWithTags(let selectedLabel, let selectedTags):
            var labelGroupName: String? = nil
            for group in tagLibrary.allLabelGroups {
                if group.lables.contains(selectedLabel.id) {
                    labelGroupName = group.name
                    break
                }
            }
            
            let tagIDs = Set(selectedTags.map { $0.id })
            for line in timelineData.lines {
                for stamp in line.stamps {
                    if stamp.labelIDs.contains(selectedLabel.id) && !tagIDs.isDisjoint(with: stamp.idTags) {
                        guard let correctedTime = correctTimeRange(
                            startSeconds: stamp.timeStartSeconds,
                            durationSeconds: stamp.duration,
                            maxVideoDuration: maxVideoDuration
                        ) else {
                            continue
                        }
                        
                        let start = CMTime(seconds: correctedTime.start, preferredTimescale: 600)
                        let duration = CMTime(seconds: correctedTime.duration, preferredTimescale: 600)
                        let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                        
                        result.append(
                            ExportSegment(
                                stamp: stamp,
                                tagName: stamp.label,
                                timeRange: CMTimeRange(start: start, duration: duration),
                                lineName: line.name,
                                groupName: possibleGroup?.name,
                                labelGroupName: labelGroupName,
                                selectedLabel: selectedLabel,
                                stampId: stamp.id
                            )
                        )
                    }
                }
            }
        case .screenshots:
            break
        case .drawingsTimeline:
            if let line = timelineData.lines.first(where: { $0.id == ScreenshotConstants.screenshotsTimelineID }) {
                for stamp in line.stamps {
                    guard let correctedTime = correctTimeRange(
                        startSeconds: stamp.timeStartSeconds,
                        durationSeconds: stamp.duration,
                        maxVideoDuration: maxVideoDuration
                    ) else {
                        continue
                    }
                    let start = CMTime(seconds: correctedTime.start, preferredTimescale: 600)
                    let duration = CMTime(seconds: correctedTime.duration, preferredTimescale: 600)
                    let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                    result.append(
                        ExportSegment(
                            stamp: stamp,
                            tagName: stamp.label,
                            timeRange: CMTimeRange(start: start, duration: duration),
                            lineName: line.name,
                            groupName: possibleGroup?.name,
                            labelGroupName: nil,
                            selectedLabel: nil,
                            stampId: stamp.id
                        )
                    )
                }
            }
        }
        
        result.sort { $0.timeRange.start.seconds < $1.timeRange.start.seconds }
        return result
    }

    
    // MARK: - Create Overlay
    func videoCompositionWithTextOverlay(
        overlayItems: [OverlayItem],
        videoTrack: AVAssetTrack,
        compositionVideoTrack: AVMutableCompositionTrack,
        compositionDuration: CMTime
    ) -> AVVideoComposition {
        let videoComposition = AVMutableVideoComposition()

        let transform = videoTrack.preferredTransform
        let natural = videoTrack.naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(natural.width), height: abs(natural.height))

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
        overlayItems.forEach { item in
            guard let attributedText = NSAttributedString.attributedStringForTagInfo(overlayItem: item) else { return }
            
            let padding: CGFloat = 12
            let textMaxWidth = renderSize.width - padding * 2
            
            let textRect = attributedText.boundingRect(
                with: CGSize(width: textMaxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            
            let textHeight = ceil(textRect.height)
            let overlayHeight = min(textHeight + padding * 2, renderSize.height / 4)
            
            let bgLayer = CALayer()
            bgLayer.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
            bgLayer.frame = CGRect(
                x: 0,
                y: 0,
                width: renderSize.width,
                height: overlayHeight
            )
            parentLayer.addSublayer(bgLayer)
            
            let textLayer = CATextLayer()
            textLayer.string = attributedText
            textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            textLayer.alignmentMode = .left
            textLayer.isWrapped = true
            textLayer.truncationMode = .end
            textLayer.frame = CGRect(
                x: padding,
                y: padding,
                width: textMaxWidth,
                height: overlayHeight - padding * 2
            )
            textLayer.displayIfNeeded()
            parentLayer.addSublayer(textLayer)
            
            // Animations
            let start = CMTimeGetSeconds(item.start)
            let duration = CMTimeGetSeconds(item.duration)

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 1, 0, 0]
            opacity.keyTimes = [
                0,
                NSNumber(value: start / total),
                NSNumber(value: (start + duration) / total),
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
    
    func videoCompositionWithTextOverlay(
        overlayItem: OverlayItem,
        videoTrack: AVAssetTrack,
        compositionVideoTrack: AVMutableCompositionTrack,
        compositionDuration: CMTime
    ) -> AVVideoComposition {
        let videoComposition = AVMutableVideoComposition()

        let transform = videoTrack.preferredTransform
        let natural = videoTrack.naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(natural.width), height: abs(natural.height))

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
        

        let attributedText = NSAttributedString.attributedStringForTagInfo(overlayItem: overlayItem) ?? NSAttributedString(string: "")
        
        let padding: CGFloat = 12
        let textMaxWidth = renderSize.width - padding * 2
        
        let textRect = attributedText.boundingRect(
            with: CGSize(width: textMaxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        
        let textHeight = ceil(textRect.height)
        let overlayHeight = min(textHeight + padding * 2, renderSize.height / 4)
        
        let bgLayer = CALayer()
        bgLayer.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        bgLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: renderSize.width,
            height: overlayHeight
        )
        parentLayer.addSublayer(bgLayer)
        
        let textLayer = CATextLayer()
        textLayer.string = attributedText
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.alignmentMode = .left
        textLayer.isWrapped = true
        textLayer.truncationMode = .end
        textLayer.frame = CGRect(
            x: padding,
            y: padding,
            width: textMaxWidth,
            height: overlayHeight - padding * 2
        )
        textLayer.displayIfNeeded()
        parentLayer.addSublayer(textLayer)
        
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        
        return videoComposition
    }
    
    // MARK: - Screenshot Export Helper Functions
    
    private func getCurrentFile() -> FilesFile? {
        guard let currentBookmark = timelineData.currentBookmark else {
            return nil
        }
        return VideoFilesManager.shared.files.first(where: { $0.videoData.bookmark == currentBookmark })
    }
    
    /// Returns screenshots linked to the given stamp that fall within the time range.
    func screenshots(in timeRange: CMTimeRange, stampId: UUID) -> [ScreenshotMetadata] {
        let all = ScreenshotsMetadataManager.shared.screenshots
        let segmentStart = CMTimeGetSeconds(timeRange.start)
        let segmentEnd = segmentStart + CMTimeGetSeconds(timeRange.duration)
        return all.filter {
            $0.videoTime >= segmentStart &&
            $0.videoTime <= segmentEnd &&
            $0.relatedStampIds.contains(stampId)
        }
    }

    private func getScreenshotsInSegment(_ segment: ExportSegment) -> [ScreenshotMetadata] {
        guard let stampId = segment.stampId else {
            let all = ScreenshotsMetadataManager.shared.screenshots
            let segmentStart = CMTimeGetSeconds(segment.timeRange.start)
            let segmentEnd = segmentStart + CMTimeGetSeconds(segment.timeRange.duration)
            return all.filter { $0.videoTime >= segmentStart && $0.videoTime <= segmentEnd }
        }
        return screenshots(in: segment.timeRange, stampId: stampId)
    }

    /// Inserts video frames and screenshot still-image clips into the composition.
    /// Returns the updated composition time after all insertions.
    @discardableResult
    func insertScreenshotsIntoComposition(
        composition: AVMutableComposition,
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack?,
        segmentTimeRange: CMTimeRange,
        screenshots: [ScreenshotMetadata],
        startTime: CMTime
    ) -> CMTime {
        guard let compVideoTrack = composition.tracks(withMediaType: .video).first,
              let filesFile = getCurrentFile() else {
            return startTime
        }
        
        // Получаем размеры видео с учетом трансформации
        let transform = videoTrack.preferredTransform
        let naturalSize = videoTrack.naturalSize.applying(transform)
        let videoSize = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))
        
        let screenshotsFolder = filesFile.screenshotsFolder
        let segmentStart = CMTimeGetSeconds(segmentTimeRange.start)
        var currentTime = startTime
        var lastVideoTime = segmentStart
        
        let sortedScreenshots = screenshots.sorted(by: { $0.videoTime < $1.videoTime })
        
        for screenshot in sortedScreenshots {
            let screenshotTimeInSegment = screenshot.videoTime
            
            if screenshotTimeInSegment > lastVideoTime {
                let videoDuration = screenshotTimeInSegment - lastVideoTime
                let videoRange = CMTimeRange(
                    start: CMTime(seconds: lastVideoTime, preferredTimescale: 600),
                    duration: CMTime(seconds: videoDuration, preferredTimescale: 600)
                )
                
                do {
                    try compVideoTrack.insertTimeRange(videoRange, of: videoTrack, at: currentTime)
                    if let compAudioTrack = composition.tracks(withMediaType: .audio).first,
                       let aTrack = audioTrack {
                        try compAudioTrack.insertTimeRange(videoRange, of: aTrack, at: currentTime)
                    }
                    currentTime = CMTimeAdd(currentTime, videoRange.duration)
                } catch {
                    print("Error inserting video before screenshot: \(error)")
                }
            }
            
            let imageFileName = screenshot.screenshotName.hasSuffix(".png") ? screenshot.screenshotName : "\(screenshot.screenshotName).png"
            let imageURL = screenshotsFolder.appendingPathComponent(imageFileName)
            
            if let image = NSImage(contentsOf: imageURL) {
                // Use semaphore instead of DispatchGroup.wait() to prevent potential crashes
                let semaphore = DispatchSemaphore(value: 0)
                var screenshotVideoURL: URL?
                
                let displayDuration = screenshot.displayDuration
                print("📸 Экспорт скриншота '\(screenshot.screenshotName)' с длительностью \(displayDuration) секунд")
                
                createVideoFromImage(image, duration: displayDuration, targetSize: videoSize) { result in
                    if case .success(let url) = result {
                        screenshotVideoURL = url
                    }
                    semaphore.signal()
                }
                
                // Wait with timeout to prevent infinite blocking
                let waitResult = semaphore.wait(timeout: .now() + 30)
                
                if waitResult == .timedOut {
                    print("❌ Screenshot video creation timed out for '\(screenshot.screenshotName)'")
                } else if let videoURL = screenshotVideoURL,
                          let screenshotAsset = try? AVURLAsset(url: videoURL),
                          let screenshotVideoTrack = screenshotAsset.tracks(withMediaType: .video).first {
                    do {
                        try compVideoTrack.insertTimeRange(
                            CMTimeRange(start: .zero, duration: screenshotAsset.duration),
                            of: screenshotVideoTrack,
                            at: currentTime
                        )
                        currentTime = CMTimeAdd(currentTime, screenshotAsset.duration)
                        try? FileManager.default.removeItem(at: videoURL)
                    } catch {
                        print("Error inserting screenshot video: \(error)")
                    }
                }
            }
            
            lastVideoTime = screenshotTimeInSegment
        }
        
        let segmentEnd = segmentStart + CMTimeGetSeconds(segmentTimeRange.duration)
        if lastVideoTime < segmentEnd {
            let remainingDuration = segmentEnd - lastVideoTime
            let videoRange = CMTimeRange(
                start: CMTime(seconds: lastVideoTime, preferredTimescale: 600),
                duration: CMTime(seconds: remainingDuration, preferredTimescale: 600)
            )
            
            do {
                try compVideoTrack.insertTimeRange(videoRange, of: videoTrack, at: currentTime)
                if let compAudioTrack = composition.tracks(withMediaType: .audio).first,
                   let aTrack = audioTrack {
                    try compAudioTrack.insertTimeRange(videoRange, of: aTrack, at: currentTime)
                }
                currentTime = CMTimeAdd(currentTime, videoRange.duration)
            } catch {
                print("Error inserting remaining video: \(error)")
            }
        }
        
        return currentTime
    }
    
    private func createVideoFromImage(_ image: NSImage, duration: Double = 3.0, targetSize: CGSize, completion: @escaping (Result<URL, Error>) -> Void) {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        let fps: Double = 30.0
        let totalFrames = Int(ceil(duration * fps))
        print("🎬 createVideoFromImage: создание видео длительностью \(duration) секунд, \(totalFrames) кадров, размер \(Int(targetSize.width))x\(Int(targetSize.height))")
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(NSError(domain: "ImageConversion", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not convert image to CGImage"])))
            return
        }
        
        let videoWriter: AVAssetWriter
        do {
            videoWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Используем размеры целевого видео
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
        
        let queue = DispatchQueue(label: "com.youchip.videoCreation", qos: .userInitiated)
        
        writerInput.requestMediaDataWhenReady(on: queue) {
            var frameCount = 0
            var success = true
            
            while frameCount < totalFrames {
                while !writerInput.isReadyForMoreMediaData {
                    if videoWriter.status == .failed {
                        success = false
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.01)
                }
                
                if !success {
                    break
                }
                
                let presentationTime = CMTime(seconds: Double(frameCount) / fps, preferredTimescale: 600)
                
                var pixelBuffer: CVPixelBuffer?
                
                if let pixelBufferPool = adaptor.pixelBufferPool {
                    CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
                } else {
                    let options: [String: Any] = [
                        kCVPixelBufferCGImageCompatibilityKey as String: true,
                        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                        kCVPixelBufferWidthKey as String: videoWidth,
                        kCVPixelBufferHeightKey as String: videoHeight,
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
                    ]
                    CVPixelBufferCreate(kCFAllocatorDefault, videoWidth, videoHeight, kCVPixelFormatType_32ARGB, options as CFDictionary, &pixelBuffer)
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
                        // Заполняем фон черным цветом
                        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                        context.fill(CGRect(x: 0, y: 0, width: videoWidth, height: videoHeight))
                        
                        // Вычисляем размеры изображения с сохранением пропорций
                        let imageWidth = CGFloat(cgImage.width)
                        let imageHeight = CGFloat(cgImage.height)
                        let videoAspect = CGFloat(videoWidth) / CGFloat(videoHeight)
                        let imageAspect = imageWidth / imageHeight
                        
                        var drawRect: CGRect
                        if imageAspect > videoAspect {
                            // Изображение шире - масштабируем по ширине
                            let scaledHeight = CGFloat(videoWidth) / imageAspect
                            let yOffset = (CGFloat(videoHeight) - scaledHeight) / 2
                            drawRect = CGRect(x: 0, y: yOffset, width: CGFloat(videoWidth), height: scaledHeight)
                        } else {
                            // Изображение выше - масштабируем по высоте
                            let scaledWidth = CGFloat(videoHeight) * imageAspect
                            let xOffset = (CGFloat(videoWidth) - scaledWidth) / 2
                            drawRect = CGRect(x: xOffset, y: 0, width: scaledWidth, height: CGFloat(videoHeight))
                        }
                        
                        // Рисуем изображение с сохранением пропорций
                        context.draw(cgImage, in: drawRect)
                    }
                    
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                    
                    if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                        print("⚠️ Не удалось добавить кадр \(frameCount) в видео")
                        success = false
                        break
                    }
                }
                
                frameCount += 1
            }
            
            print("✅ Записано \(frameCount) кадров из \(totalFrames)")
            
            writerInput.markAsFinished()
            videoWriter.finishWriting {
                if videoWriter.status == .completed {
                    print("✅ Видео успешно создано: \(outputURL.lastPathComponent), длительность: \(duration)с")
                    completion(.success(outputURL))
                } else if let error = videoWriter.error {
                    print("❌ Ошибка создания видео: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("❌ Неизвестная ошибка создания видео, статус: \(videoWriter.status.rawValue)")
                    completion(.failure(NSError(domain: "VideoCreation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error creating video from image, status: \(videoWriter.status.rawValue)"])))
                }
            }
        }
    }
    
    private func compressFiles(urls: [URL], completion: @escaping (Result<URL, Error>) -> Void) {
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("export_playlist.zip")
        try? FileManager.default.removeItem(at: zipURL)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        
        var arguments = ["-j", zipURL.path]
        for fileURL in urls {
            arguments.append(fileURL.path)
        }
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                completion(.success(zipURL))
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: data, encoding: .utf8) ?? ^String.Titles.unknownError
                let error = NSError(domain: "ZIPError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMessage])
                completion(.failure(error))
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    private func exportScreenshots(completion: @escaping (Error?) -> Void) {
        let screenshots = ScreenshotsMetadataManager.shared.screenshots
        
        if screenshots.isEmpty {
            completion(NSError.getErrorWithDescription("Нет скриншотов для экспорта"))
            return
        }
        
        guard let filesFile = getCurrentFile() else {
            completion(NSError.getErrorWithDescription("Не найдены файлы проекта"))
            return
        }
        
        let screenshotsFolder = filesFile.screenshotsFolder
        var screenshotURLs: [URL] = []
        
        for screenshot in screenshots {
            let imageFileName = screenshot.screenshotName.hasSuffix(".png") ? screenshot.screenshotName : "\(screenshot.screenshotName).png"
            let imageURL = screenshotsFolder.appendingPathComponent(imageFileName)
            
            if FileManager.default.fileExists(atPath: imageURL.path) {
                screenshotURLs.append(imageURL)
            } else {
                print("Screenshot not found: \(imageFileName)")
            }
        }
        
        if screenshotURLs.isEmpty {
            completion(NSError.getErrorWithDescription("Не найдены файлы скриншотов"))
            return
        }
        
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("screenshots.zip")
        try? FileManager.default.removeItem(at: zipURL)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        
        var arguments = ["-j", zipURL.path]
        for fileURL in screenshotURLs {
            arguments.append(fileURL.path)
        }
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                DispatchQueue.main.async {
                    let panel = NSSavePanel()
                    panel.allowedFileTypes = ["zip"]
                    panel.nameFieldStringValue = "screenshots.zip"
                    if panel.runModal() == .OK, let url = panel.url {
                        do {
                            try FileManager.default.copyItem(at: zipURL, to: url)
                            print("Скриншоты успешно экспортированы: \(url)")
                            completion(nil)
                        } catch {
                            completion(NSError.getErrorWithDescription("Ошибка сохранения скриншотов: \(error.localizedDescription)"))
                        }
                    } else {
                        completion(nil)
                    }
                }
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: data, encoding: .utf8) ?? ^String.Titles.unknownError
                completion(NSError.getErrorWithDescription(errorMessage))
            }
        } catch {
            completion(error)
        }
    }

}
