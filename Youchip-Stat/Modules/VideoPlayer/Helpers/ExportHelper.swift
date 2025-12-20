//
//  ExportHelper.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 20.12.2025.
//

import Foundation
import AVKit

class ExportHelper: ObservableObject {
    
    let videoManager = VideoPlayerManager.shared
    let timelineData = TimelineDataManager.shared
    let tagLibrary = TagLibraryManager.shared
    
    // MARK: Public Export Method
    
    func performExport(selectedExportType: CutsExportType?, mode: ExportMode, completion: @escaping (Error?) -> Void) {
        guard let asset = VideoPlayerManager.shared.player?.currentItem?.asset else {
            completion(NSError.getErrorWithDescription("Asset not found"))
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
        
        if mode == .film {
            exportFilm(segments: segments, asset: asset, type: selectedType) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let outputURL):
                        let panel = NSSavePanel()
                        panel.allowedFileTypes = ["mp4"]
                        panel.nameFieldStringValue = outputURL.lastPathComponent
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
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
                        completion(NSError.getErrorWithDescription("\(^String.Titles.fullControlExportFilmError): \(error.localizedDescription)"))
                    }
                }
            }
        } else {
            exportPlaylist(segments: segments, asset: asset, type: selectedType) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let zipURL):
                        let panel = NSSavePanel()
                        panel.allowedFileTypes = ["zip"]
                        panel.nameFieldStringValue = "export_playlist.zip"
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                try FileManager.default.copyItem(at: zipURL, to: url)
                                completion(nil)
                            } catch {
                                completion(NSError.getErrorWithDescription("Ошибка сохранения плейлиста: \(error.localizedDescription)"))
                            }
                        } else {
                            completion(nil)
                        }
                    case .failure(let error):
                        completion(NSError.getErrorWithDescription("Ошибка сохранения плейлиста: \(error.localizedDescription)"))
                    }
                }
            }
        }
    }
    
    // MARK: - Export Film
    
    private func exportFilm(segments: [ExportSegment], asset: AVAsset, type: CutsExportType, completion: @escaping (Result<URL, Error>) -> Void) {
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
            
            if let tag = tagLibrary.allTags.first(where: { $0.id == segment.stamp.idTag }) {
                let overlayItem = OverlayItem(
                    tag: tag,
                    stamp: segment.stamp,
                    selectedLabelGroups: labelGroupItem(for: segment),
                    start: currentTime - segment.timeRange.duration,
                    duration: segment.timeRange.duration
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
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: outputURL)
        
        let overlayVideoComposition = videoCompositionWithTextOverlay(overlayItems: overlayItems, videoTrack: videoTrack, compositionVideoTrack: compVideoTrack, compositionDuration: composition.duration)
        
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        exportSession?.outputURL = outputURL
        exportSession?.outputFileType = .mp4
        exportSession?.videoComposition = overlayVideoComposition
        exportSession?.exportAsynchronously {
            if exportSession?.status == .completed {
                completion(.success(outputURL))
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
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if segments.isEmpty {
            completion(.failure(NSError(domain: "Export", code: -1, userInfo: [NSLocalizedDescriptionKey: "No segments to export"])))
            return
        }
        
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
                do {
                    try compAudioTrack?.insertTimeRange(segment.timeRange, of: aTrack, at: .zero)
                } catch {
                    exportError = error
                    group.leave()
                    continue
                }
            }
            
            do {
                try compVideoTrack.insertTimeRange(segment.timeRange, of: videoTrack, at: .zero)
            } catch {
                exportError = error
                group.leave()
                continue
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
                let stampLabels = segment.stamp.labels.compactMap { labelID in
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
            }
            
            let clipOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: clipOutputURL)
            
            let overlayVideoComposition: AVVideoComposition?
            if let tag = tagLibrary.allTags.first(where: { $0.id == segment.stamp.idTag }) {
                let overlayItem = OverlayItem(
                    tag: tag,
                    stamp: segment.stamp,
                    selectedLabelGroups: labelGroupItem(for: segment),
                    start: .zero,
                    duration: segment.timeRange.duration
                )
                overlayVideoComposition = videoCompositionWithTextOverlay(overlayItem: overlayItem, videoTrack: videoTrack, compositionVideoTrack: compVideoTrack, compositionDuration: composition.duration)
            } else {
                overlayVideoComposition = nil
            }
            
            
            let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
            exportSession?.outputURL = clipOutputURL
            exportSession?.outputFileType = .mp4
            exportSession?.videoComposition = overlayVideoComposition
            
            exportSession?.exportAsynchronously {
                if exportSession?.status == .completed {
                    exportedURLs.append(clipOutputURL)
                } else {
                    exportError = exportSession?.error ?? NSError(domain: "Export", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown export error"])
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if let error = exportError {
                completion(.failure(error))
            } else if exportedURLs.isEmpty {
                completion(.failure(NSError(domain: "Export", code: -3, userInfo: [NSLocalizedDescriptionKey: "No valid segments were exported"])))
            } else {
                self.compressFiles(urls: exportedURLs, completion: completion)
            }
        }
    }
    
    
    // MARK: - Helpers
    
    private func labelGroupItem(for segment: ExportSegment) -> [OverlayLabelGroupItem] {
        var selectedLabelGroups: [OverlayLabelGroupItem] = []
        let stampLabels = segment.stamp.labels.compactMap { labelID in
            tagLibrary.allLabels.first(where: { $0.id == labelID })
        }
        stampLabels.forEach { label in
            guard let labelGroup = tagLibrary.allLabelGroups.first(where: { $0.lables.contains(label.id) }) else { return }
            if let index = selectedLabelGroups.firstIndex(where: { $0.group.id == labelGroup.id }) {
                selectedLabelGroups[index].selectedLabels.append(label)
            } else {
                let groupItem = OverlayLabelGroupItem(group: labelGroup, selectedLabels: [label])
                selectedLabelGroups.append(groupItem)
            }
        }
        return selectedLabelGroups
    }
    
    private func compressFiles(urls: [URL], completion: @escaping (Result<URL, Error>) -> Void) {
        do {
            let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("export_playlist.zip")
            if FileManager.default.fileExists(atPath: zipURL.path) {
                try FileManager.default.removeItem(at: zipURL)
            }
            
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
                    let labels = stamp.labels.compactMap { labelID in
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
                        )
                    )
                }
            }
        case .tag(let selectedTag):
            let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(selectedTag.id) })
            
            for line in timelineData.lines {
                for stamp in line.stamps {
                    guard stamp.idTag == selectedTag.id else {
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
                    if stamp.labels.contains(selectedLabel.id) {
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
                            )
                        )
                    }
                }
            }
            
        case .tagWithLabels(let selectedTag, let selectedLabels):
            let labelIDs = Set(selectedLabels.map { $0.id })
            for line in timelineData.lines {
                for stamp in line.stamps {
                    if stamp.idTag == selectedTag.id && !Set(stamp.labels).isDisjoint(with: labelIDs) {
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
                    if stamp.labels.contains(selectedLabel.id) && tagIDs.contains(stamp.idTag) {
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
                            )
                        )
                    }
                }
            }
        }
        
        result.sort { $0.timeRange.start.seconds < $1.timeRange.start.seconds }
        return result
    }
    
    private func videoCompositionWithTextOverlay(
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
    
    private func videoCompositionWithTextOverlay(
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
        parentLayer.addSublayer(textLayer)
        
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        
        return videoComposition
    }

}
