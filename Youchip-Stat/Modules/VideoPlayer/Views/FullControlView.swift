//
//  FullControlView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct FullControlView: View {
    
    @State private var scrollOffset: CGFloat = 0
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    @ObservedObject var focusManager = FocusStateManager.shared
    @ObservedObject var hotkeyManager = HotKeyManager.shared
    
    @State private var markupMode: MarkupMode = MarkupMode.current
    @State private var showMarkupModeToggle = false
    
    @State private var sliderValue: Double = 0.0
    @State private var isDraggingSlider = false
    @State private var showAddLineSheet = false
    @State private var isExporting: Bool = false
    @State private var showLabelEditSheet = false
    @State private var showFieldMapVisualizationPicker = false
    @State private var editingStampLineID: UUID?
    @State private var editingStampID: UUID?
    @State private var timelineScale: CGFloat = 1.0
    @GestureState private var magnifyScale: CGFloat = 1.0
    @State private var keyEventMonitor: Any?
    
    private func setupKeyboardShortcuts() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if focusManager.isAnyTextFieldFocused {
                return event
            }
            
            switch event.keyCode {
            case 53:
                timelineData.selectStamp(stampID: nil)
                return nil
            case 51:
                if event.modifierFlags.contains(.option) {
                    if let stampID = timelineData.selectedStampID {
                        for line in timelineData.lines {
                            if line.stamps.contains(where: { $0.id == stampID }) {
                                timelineData.removeStamp(lineID: line.id, stampID: stampID)
                                break
                            }
                        }
                        return nil
                    }
                }
                return event
            default:
                return event
            }
        }
    }
    
    @State private var selectedExportType: CutsExportType?
    @State private var showExportModeSheet: Bool = false
    @State private var showTagSelectionSheet: Bool = false
    @State private var parentWindowHeight: CGFloat = 600
    @State private var showEditNameSheet = false
    @State private var showEventSelectionSheet: Bool = false
    @State private var showAiReportSheet: Bool = false
    
    @State private var showLabelSelectionSheet: Bool = false
    @State private var showMultiLabelSelectionSheet: Bool = false
    @State private var showMultiTagSelectionSheet: Bool = false
    @State private var selectedLabelForMultiSelection: Label?
    @State private var selectedTagForMultiSelection: Tag?

    
    func getSegmentsForExport(type: CutsExportType) -> [ExportSegment] {
        var result: [ExportSegment] = []
        let tagLibrary = TagLibraryManager.shared
        
        switch type {
        case .currentTimeline:
            if let lineID = timelineData.selectedLineID,
               let line = timelineData.lines.first(where: { $0.id == lineID }) {
                for stamp in line.stamps {
                    let start = CMTime(seconds: stamp.startSeconds, preferredTimescale: 600)
                    let duration = CMTime(seconds: stamp.duration, preferredTimescale: 600)
                    let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                    
                    result.append(
                        ExportSegment(
                            timeRange: CMTimeRange(start: start, duration: duration),
                            lineName: line.name,
                            tagName: stamp.label,
                            groupName: possibleGroup?.name
                        )
                    )
                }
            }
        case .allTimelines:
            for line in timelineData.lines {
                for stamp in line.stamps {
                    let start = CMTime(seconds: stamp.startSeconds, preferredTimescale: 600)
                    let duration = CMTime(seconds: stamp.duration, preferredTimescale: 600)
                    let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                    
                    result.append(
                        ExportSegment(
                            timeRange: CMTimeRange(start: start, duration: duration),
                            lineName: line.name,
                            tagName: stamp.label,
                            groupName: possibleGroup?.name
                        )
                    )
                }
            }
        case .tag(let selectedTag):
            let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(selectedTag.id) })
            
            for line in timelineData.lines {
                for stamp in line.stamps {
                    if stamp.idTag == selectedTag.id {
                        let start = CMTime(seconds: stamp.startSeconds, preferredTimescale: 600)
                        let duration = CMTime(seconds: stamp.duration, preferredTimescale: 600)
                        result.append(
                            ExportSegment(
                                timeRange: CMTimeRange(start: start, duration: duration),
                                lineName: line.name,
                                tagName: stamp.label,
                                groupName: possibleGroup?.name
                            )
                        )
                    }
                }
            }
        case .timeEvent(let selectedEvent):
            for line in timelineData.lines {
                for stamp in line.stamps {
                    if stamp.timeEvents.contains(selectedEvent.id) {
                        let start = CMTime(seconds: stamp.startSeconds, preferredTimescale: 600)
                        let duration = CMTime(seconds: stamp.duration, preferredTimescale: 600)
                        let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                        
                        result.append(
                            ExportSegment(
                                timeRange: CMTimeRange(start: start, duration: duration),
                                lineName: line.name,
                                tagName: stamp.label,
                                groupName: possibleGroup?.name
                            )
                        )
                    }
                }
            }
        case .label(let selectedLabel):
            print("Экспорт по лейблу: \(selectedLabel.name), ID: \(selectedLabel.id)")
            for line in timelineData.lines {
                print("Проверяем линию: \(line.name)")
                for stamp in line.stamps {
                    print("  Штамп: \(stamp.label), лейблы штампа: \(stamp.labels)")
                    if stamp.labels.contains(selectedLabel.id) {
                        print("    ✓ Найден подходящий штамп!")
                        let start = CMTime(seconds: stamp.startSeconds, preferredTimescale: 600)
                        let duration = CMTime(seconds: stamp.duration, preferredTimescale: 600)
                        let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                        
                        result.append(
                            ExportSegment(
                                timeRange: CMTimeRange(start: start, duration: duration),
                                lineName: line.name,
                                tagName: stamp.label,
                                groupName: possibleGroup?.name
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
                        let start = CMTime(seconds: stamp.startSeconds, preferredTimescale: 600)
                        let duration = CMTime(seconds: stamp.duration, preferredTimescale: 600)
                        let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                        
                        result.append(
                            ExportSegment(
                                timeRange: CMTimeRange(start: start, duration: duration),
                                lineName: line.name,
                                tagName: stamp.label,
                                groupName: possibleGroup?.name
                            )
                        )
                    }
                }
            }
            
        case .labelWithTags(let selectedLabel, let selectedTags):
            let tagIDs = Set(selectedTags.map { $0.id })
            for line in timelineData.lines {
                for stamp in line.stamps {
                    if stamp.labels.contains(selectedLabel.id) && tagIDs.contains(stamp.idTag) {
                        let start = CMTime(seconds: stamp.startSeconds, preferredTimescale: 600)
                        let duration = CMTime(seconds: stamp.duration, preferredTimescale: 600)
                        let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                        
                        result.append(
                            ExportSegment(
                                timeRange: CMTimeRange(start: start, duration: duration),
                                lineName: line.name,
                                tagName: stamp.label,
                                groupName: possibleGroup?.name
                            )
                        )
                    }
                }
            }
        }
        
        result.sort { $0.timeRange.start.seconds < $1.timeRange.start.seconds }
        return result
    }
    
    func exportFilm(segments: [ExportSegment], asset: AVAsset, type: CutsExportType, completion: @escaping (Result<URL, Error>) -> Void) {
        let composition = AVMutableComposition()
        
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(NSError(domain: "Export", code: 0, userInfo: [NSLocalizedDescriptionKey: "Video track not found"])))
            return
        }
        let audioTrack = asset.tracks(withMediaType: .audio).first
        
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(.failure(NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create video track"])))
            return
        }
        var compAudioTrack: AVMutableCompositionTrack? = nil
        if audioTrack != nil {
            compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        
        var currentTime = CMTime.zero
        for segment in segments {
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
            fileName = "\(^String.Titles.fullControlFileEventFile)_\(selectedEvent.name)\(^String.Titles.fullControlFileTimelineFile)"
        case .allTimelines:
            fileName = ^String.Titles.fullControlFileAllTimelinesFile
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
        
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        exportSession?.outputURL = outputURL
        exportSession?.outputFileType = .mp4
        exportSession?.exportAsynchronously {
            if exportSession?.status == .completed {
                completion(.success(outputURL))
            } else {
                completion(.failure(exportSession?.error ?? NSError(domain: "Export", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown export error"])))
            }
        }
    }
    
    func exportPlaylist(segments: [ExportSegment],
                        asset: AVAsset,
                        type: CutsExportType,
                        completion: @escaping (Result<URL, Error>) -> Void)
    {
        var exportedURLs: [URL] = []
        let group = DispatchGroup()
        var exportError: Error? = nil
        
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(NSError(domain: "Export", code: 0, userInfo: [NSLocalizedDescriptionKey: "Video track not found"])))
            return
        }
        let audioTrack = asset.tracks(withMediaType: .audio).first
        
        for (index, segment) in segments.enumerated() {
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
                fileName = "\(lineName)_\(segment.tagName)_\(index + 1).mp4"
                
            case .tag(let selectedTag):
                let groupName = segment.groupName ?? "group"
                fileName = "\(groupName)_\(selectedTag.name)_\(index + 1).mp4"
                
            case .timeEvent(let selectedEvent):
                fileName = "\(^String.Titles.fullControlFileEventFile)_\(selectedEvent.name)_\(index + 1).mp4"
            case .label(let selectedLabel):
                fileName = "\(selectedLabel.name)_\(index + 1).mp4"
                
            case .tagWithLabels(let selectedTag, let selectedLabels):
                let labelsString = selectedLabels.map { $0.name }.joined(separator: "_")
                fileName = "\(selectedTag.name)_\(labelsString)_\(index + 1).mp4"
                
            case .labelWithTags(let selectedLabel, let selectedTags):
                let tagsString = selectedTags.map { $0.name }.joined(separator: "_")
                fileName = "\(selectedLabel.name)_\(tagsString)_\(index + 1).mp4"
            }
            
            let clipOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: clipOutputURL)
            
            let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
            exportSession?.outputURL = clipOutputURL
            exportSession?.outputFileType = .mp4
            
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
            } else {
                compressFiles(urls: exportedURLs, completion: completion)
            }
        }
    }
    
    @State private var isLoading = false
    @State private var availableTags: [Tag] = []
    @State private var availableLabels: [Label] = []
    
    func compressFiles(urls: [URL], completion: @escaping (Result<URL, Error>) -> Void) {
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
                let errorMessage = String(data: data, encoding: .utf8) ?? "Неизвестная ошибка"
                let error = NSError(domain: "ZIPError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMessage])
                completion(.failure(error))
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    func generateReport() {
        
    }
    
    func performExport(mode: ExportMode) {
        guard let asset = VideoPlayerManager.shared.player?.currentItem?.asset else {
            print("Asset not found")
            return
        }
        guard let selectedType = selectedExportType else { return }
        
        let segments = getSegmentsForExport(type: selectedType)
        if segments.isEmpty {
            print("Нет сегментов для экспорта")
            return
        }
        
        isExporting = true
        
        if mode == .film {
            exportFilm(segments: segments, asset: asset, type: selectedType) { result in
                DispatchQueue.main.async {
                    self.isExporting = false
                    
                    switch result {
                    case .success(let outputURL):
                        let panel = NSSavePanel()
                        panel.allowedFileTypes = ["mp4"]
                        panel.nameFieldStringValue = outputURL.lastPathComponent
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                try FileManager.default.copyItem(at: outputURL, to: url)
                                print("\(^String.Titles.fullControlExportFilmSuccess) \(url)")
                            } catch {
                                print("Ошибка сохранения фильма: \(error)")
                            }
                        }
                    case .failure(let error):
                        print("\(^String.Titles.fullControlExportFilmError) \(error)")
                    }
                }
            }
        } else {
            exportPlaylist(segments: segments, asset: asset, type: selectedType) { result in
                DispatchQueue.main.async {
                    self.isExporting = false
                    
                    switch result {
                    case .success(let zipURL):
                        let panel = NSSavePanel()
                        panel.allowedFileTypes = ["zip"]
                        panel.nameFieldStringValue = "export_playlist.zip"
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                try FileManager.default.copyItem(at: zipURL, to: url)
                                print("Плейлист экспортирован и сохранён по \(url)")
                            } catch {
                                print("Ошибка сохранения плейлиста: \(error)")
                            }
                        }
                    case .failure(let error):
                        print("Ошибка экспорта плейлиста: \(error)")
                    }
                }
            }
        }
    }
    
    @State private var multiTagSelectionItem: MultiSelectionItem?
    @State private var multiLabelSelectionItem: MultiSelectionItem?
    
    struct MultiSelectionItem: Identifiable {
        let id = UUID()
        let tag: Tag?
        let label: Label?
        
        init(tag: Tag? = nil, label: Label? = nil) {
            self.tag = tag
            self.label = label
        }
    }
    
    @ViewBuilder
    private func scrollBlock() -> some View {
        VStack(spacing: 0) {
            // Modern timeline container with rounded corners and shadow
            ScrollView(.vertical) {
                ScrollViewReader { scrollProxy in
                    timelineContent(proxy: scrollProxy)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .shadow(
                        color: Color.black.opacity(0.1),
                        radius: 8,
                        x: 0,
                        y: 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .gesture(
                MagnificationGesture()
                    .updating($magnifyScale) { currentState, gestureState, _ in
                        gestureState = max(1.0, currentState)
                    }
                    .onEnded { value in
                        let newScale = timelineScale * value
                        let duration = max(1.0, videoManager.videoDuration)
                        let potentialInterval = calculateTimeGridInterval(scale: newScale, totalDuration: duration)
                        if potentialInterval >= 0.5 {
                            timelineScale = max(1.0, newScale)
                        } else {
                            let baseInterval = 5.0
                            let maxScale = baseInterval / 0.5
                            timelineScale = maxScale
                        }
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func calculateTimeGridInterval(scale: CGFloat, totalDuration: Double) -> Double {
        let baseCount = 20 * scale
        let baseInterval = totalDuration / baseCount
        
        return max(0.5, baseInterval)
    }
    
    @ViewBuilder
    private func timelineContent(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Modern header with gradient matching button blocks
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.05),
                        Color.gray.opacity(0.02)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 195, height: 30, alignment: .leading)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
                .id("header-row")
                
                ForEach(timelineData.lines) { line in
                    if markupMode == .standard {
                        HStack(spacing: 8) {
                            // Timeline name on the left
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .minimumScaleFactor(0.6)
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill((line.id == timelineData.selectedLineID) ? 
                                                  Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke((line.id == timelineData.selectedLineID) ? 
                                                   Color.blue.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 0.5)
                                    )
                                    .onTapGesture { 
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            timelineData.selectLine(line.id)
                                        }
                                    }
                            }
                            
                            Spacer()
                            
                            // Buttons row on the right
                            HStack(spacing: 4) {
                                Button(action: {
                                    timelineData.selectLine(line.id)
                                    showEditNameSheet = true
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.blue)
                                        .padding(3)
                                        .background(
                                            Circle()
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .help(^String.Titles.editTimelineName)
                                
                                Button(action: {
                                    let isSelectedLine = (TimelineDataManager.shared.selectedLineID == line.id)
                                    TimelineDataManager.shared.lines.removeAll { $0.id == line.id }
                                    if isSelectedLine {
                                        TimelineDataManager.shared.selectedLineID = nil
                                    }
                                    TimelineDataManager.shared.updateTimelines()
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.red)
                                        .padding(3)
                                        .background(
                                            Circle()
                                                .fill(Color.red.opacity(0.1))
                                        )
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .help(^String.Titles.timelineButtonDeleteTimeline)
                            }
                        }
                        .padding(.leading, 5)
                        .frame(width: 195, height: 30, alignment: .leading)
                        .contextMenu {
                            Button(^String.Titles.editName) {
                                timelineData.selectLine(line.id)
                                showEditNameSheet = true
                            }
                            Button(^String.Titles.timelineButtonDeleteTimeline) {
                                let isSelectedLine = (TimelineDataManager.shared.selectedLineID == line.id)
                                TimelineDataManager.shared.lines.removeAll { $0.id == line.id }
                                if isSelectedLine {
                                    TimelineDataManager.shared.selectedLineID = nil
                                }
                                TimelineDataManager.shared.updateTimelines()
                            }
                        }
                        .onDrag {
                            return NSItemProvider(object: line.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TimelineDropDelegate(
                            currentLine: line,
                            timelineData: timelineData
                        ))
                        .id("name-\(line.id)")
                    } else {
                        HStack(spacing: 8) {
                            // Timeline name on the left
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .minimumScaleFactor(0.6)
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill((line.id == timelineData.selectedLineID) ? 
                                                  Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke((line.id == timelineData.selectedLineID) ? 
                                                   Color.blue.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 0.5)
                                    )
                                    .onTapGesture { 
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            timelineData.selectLine(line.id)
                                        }
                                    }
                            }
                            
                            Spacer()
                            
                            // Buttons row on the right
                            HStack(spacing: 4) {
                                Button(action: {
                                    let isSelectedLine = (TimelineDataManager.shared.selectedLineID == line.id)
                                    TimelineDataManager.shared.lines.removeAll { $0.id == line.id }
                                    if isSelectedLine {
                                        TimelineDataManager.shared.selectedLineID = nil
                                    }
                                    TimelineDataManager.shared.updateTimelines()
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.red)
                                        .padding(3)
                                        .background(
                                            Circle()
                                                .fill(Color.red.opacity(0.1))
                                        )
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .help(^String.Titles.timelineButtonDeleteTimeline)
                            }
                        }
                        .padding(.leading, 5)
                        .frame(width: 195, height: 30, alignment: .leading)
                        .contextMenu {
                            Button(^String.Titles.timelineButtonDeleteTimeline) {
                                let isSelectedLine = (TimelineDataManager.shared.selectedLineID == line.id)
                                TimelineDataManager.shared.lines.removeAll { $0.id == line.id }
                                if isSelectedLine {
                                    TimelineDataManager.shared.selectedLineID = nil
                                }
                                TimelineDataManager.shared.updateTimelines()
                            }
                        }
                        .onDrag {
                            return NSItemProvider(object: line.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TimelineDropDelegate(
                            currentLine: line,
                            timelineData: timelineData
                        ))
                        .id("name-\(line.id)")
                    }
                }
            }
            .frame(width: 195)
            .padding(.trailing, 5)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.05))
            )
            
            GeometryReader { geo in
                let effectiveScale = timelineScale * magnifyScale
                let duration = max(1.0, videoManager.videoDuration)
                let interval = calculateTimeGridInterval(scale: effectiveScale, totalDuration: duration)
                let gridWidth = geo.size.width * max(effectiveScale, 1.0)
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            TimeGridView(
                                duration: duration,
                                interval: interval,
                                width: gridWidth,
                                height: 30 * CGFloat(timelineData.lines.count + 1)
                            )
                            
                            VStack(spacing: 0) {
                                TimelineTimestampsHeaderView(
                                    duration: duration,
                                    interval: interval,
                                    width: gridWidth
                                )
                                .frame(height: 30)
                                
                                ForEach(timelineData.lines) { line in
                                    TimelineLineView(
                                        videoManager: VideoPlayerManager.shared,
                                        timelineData: TimelineDataManager.shared,
                                        line: line,
                                        scale: effectiveScale,
                                        widthMax: gridWidth,
                                        isSelected: (line.id == timelineData.selectedLineID),
                                        onSelect: { timelineData.selectLine(line.id) },
                                        onEditLabelsRequest: { stampID in
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                showLabelEditSheet = true
                                            }
                                            UserDefaults.standard.set(line.id.uuidString, forKey: "editingStampLineID")
                                            UserDefaults.standard.set(stampID.uuidString, forKey: "editingStampID")
                                        },
                                        tagLibrary: TagLibraryManager.shared,
                                        scrollOffset: $scrollOffset
                                    )
                                    .frame(height: 30)
                                    .id("timeline-\(line.id)")
                                }
                            }
                        }
                        .frame(width: gridWidth)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .sheet(isPresented: $showAiReportSheet) {
                    AiReportSheet(onSubmit: { teamName, opponentName, venue, matchDate in
                        generateAndDownloadAiReport(teamName: teamName,
                                                    opponentName: opponentName,
                                                    venue: venue,
                                                    matchDate: matchDate)
                    })
                }
                .sheet(isPresented: $showEditNameSheet) {
                    if let lineID = timelineData.selectedLineID,
                       let line = timelineData.lines.first(where: { $0.id == lineID }) {
                        EditTimelineNameSheet(lineName: line.name) { newName in
                            if let index = timelineData.lines.firstIndex(where: { $0.id == lineID }) {
                                timelineData.lines[index].name = newName
                                timelineData.updateTimelines()
                            }
                        }
                    }
                }
            }
        }
    }
    
    func generateAndDownloadAiReport(teamName: String, opponentName: String, venue: String, matchDate: String) {
        let fullLines = transformToFullTimelineLines()
        
        struct AIReportRequest: Encodable {
            let match_data: MatchData
            let team_name: String
            let opponent_name: String
            let venue: String
            let match_date: String
            
            struct MatchData: Encodable {
                let data: [FullTimelineLine]
            }
        }
        
        let request = AIReportRequest(
            match_data: AIReportRequest.MatchData(data: fullLines),
            team_name: teamName,
            opponent_name: opponentName,
            venue: venue,
            match_date: matchDate
        )
        
        guard let url = URL(string: "https://razmetka.youchip.pro/api/generate-match-report") else {
            print("Invalid URL")
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        isExporting = true
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            urlRequest.httpBody = try encoder.encode(request)
            
            URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                DispatchQueue.main.async {
                    self.isExporting = false
                    
                    if let error = error {
                        print("Error: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                        print("No data returned or invalid response")
                        return
                    }
                    
                    if httpResponse.statusCode == 200 {
                        self.saveReportFile(data: data, teamName: teamName, opponentName: opponentName)
                    } else {
                        print("Server error: \(httpResponse.statusCode)")
                        if let responseString = String(data: data, encoding: .utf8) {
                            print("Response: \(responseString)")
                        }
                    }
                }
            }.resume()
        } catch {
            DispatchQueue.main.async {
                self.isExporting = false
                print("Failed to encode request: \(error.localizedDescription)")
            }
        }
    }
    
    func saveReportFile(data: Data, teamName: String, opponentName: String) {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["pdf"]
        panel.nameFieldStringValue = "ИИ_Отчет_\(teamName)_vs_\(opponentName).pdf"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                print("Report saved successfully at \(url)")
            } catch {
                print("Failed to save report: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Compact Control Panel
    @ViewBuilder
    private var compactControlPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            // Block 1: Video Controls
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.video)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Button(action: { videoManager.seek(by: -10) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 12, weight: .medium))
                            Text("10s")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { videoManager.togglePlayPause() }) {
                        Image(systemName: "playpause")
                            .font(.system(size: 14, weight: .medium))
                            .padding(6)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { videoManager.seek(by: 10) }) {
                        HStack(spacing: 4) {
                            Text("10s")
                                .font(.system(size: 10, weight: .medium))
                            Image(systemName: "goforward.10")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Speed Control
                    Menu {
                        ForEach([0.1, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 5.0], id: \.self) { speed in
                            Button(String(format: "%.2fx", speed)) {
                                videoManager.changePlaybackSpeed(to: speed)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "speedometer")
                                .font(.system(size: 12, weight: .medium))
                            Text("x\(String(format: "%.2f", videoManager.playbackSpeed))")
                                .font(.system(size: 10, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .foregroundColor(.orange)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            
            // Block 2: Timeline Management
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.timelines)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                // First row: Add button, Mode selector, and Zoom controls
                HStack(spacing: 8) {
                    if markupMode == .standard {
                        Button {
                            showAddLineSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(^String.Titles.fullControlButtonAddTimeline)
                    }
                    
                    // Mode Selector
                    HStack(spacing: 2) {
                        Button(action: {
                            WindowsManager.shared.setMarkupMode(.standard)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 10))
                                Text("Standard")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(markupMode == .standard ? Color.blue : Color.gray.opacity(0.1))
                            .foregroundColor(markupMode == .standard ? .white : .primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            WindowsManager.shared.setMarkupMode(.tagBased)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "tag")
                                    .font(.system(size: 10))
                                Text("Tags")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(markupMode == .tagBased ? Color.blue : Color.gray.opacity(0.1))
                            .foregroundColor(markupMode == .tagBased ? .white : .primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .help(^String.Titles.fullControlModeHelp)
                    
                    // Timeline Zoom Controls (moved to first row)
                    HStack(spacing: 4) {
                        Text("Zoom")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Button {
                            timelineScale = max(1.0, timelineScale - 0.5)
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(CompactButtonStyle(icon: "minus.magnifyingglass", color: .gray))
                        .help(^String.Titles.fullControlButtonTimelineZoomOut)
                        
                        Text(String(format: "%.1fx", timelineScale))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                        
                        Button {
                            timelineScale += 0.5
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(CompactButtonStyle(icon: "plus.magnifyingglass", color: .gray))
                        .help(^String.Titles.fullControlButtonTimelineZoomIn)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            
            // Block 3: Export & Reports
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.exportReports)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    // JSON Export Menu
                    Menu {
                        Button(^String.Titles.fullControlButtonJSONSimple) {
                            exportSimpleJSON()
                        }
                        Button(^String.Titles.fullControlButtonJSONFull) {
                            exportFullJSON()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 12, weight: .medium))
                            Text("JSON")
                                .font(.system(size: 10, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.1))
                        .foregroundColor(.purple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Video Export Menu
                    Menu {
                        Button(^String.Titles.fullControlButtonExportTimeline) {
                            selectedExportType = .currentTimeline
                            showExportModeSheet = true
                        }
                        Button(^String.Titles.fullControlButtonExportAll) {
                            selectedExportType = .allTimelines
                            showExportModeSheet = true
                        }
                        Button(^String.Titles.fullControlButtonExportTags) {
                            showTagSelectionSheet = true
                        }
                        Button(^String.Titles.fullControlButtonExportLabels) {
                            showLabelSelectionSheet = true
                        }
                        Button(^String.Titles.fullControlButtonExportEvents) {
                            showEventSelectionSheet = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "video")
                                .font(.system(size: 12, weight: .medium))
                            Text("Export")
                                .font(.system(size: 10, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // AI Reports
                    Button(^String.Titles.aIReports) {
                        showAiReportSheet = true
                    }
                    .buttonStyle(CompactButtonStyle(icon: "brain", color: .indigo, showText: true))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            
            Spacer()
            
            // Block 4: Screenshots & Map (Right aligned)
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.tools)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    // Screenshots
                    Button(^String.Titles.fullControlButtonScreenshots) {
                        WindowsManager.shared.showScreenshots()
                    }
                    .buttonStyle(CompactButtonStyle(icon: "camera", color: .teal, showText: true, text: ^String.Titles.screenshots))
                    
                    // Map Menu
                    Menu {
                        Button(^String.Titles.configureVisualization) {
                            WindowsManager.shared.showFieldMapConfigurationWindow()
                        }
                        Button(^String.Titles.fullControlButtonMap) {
                            WindowsManager.shared.showFieldMapVisualizationPicker()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "map")
                                .font(.system(size: 12, weight: .medium))
                            Text(^String.Titles.map)
                                .font(.system(size: 10, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.brown.opacity(0.1))
                        .foregroundColor(.brown)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Helper Methods
    private func exportSimpleJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(timelineData.lines)
            let panel = NSSavePanel()
            panel.allowedFileTypes = ["json"]
            panel.nameFieldStringValue = "timelines_simple.json"
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            print("Ошибка сохранения JSON: \(error)")
        }
    }
    
    private func exportFullJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let fullLines = transformToFullTimelineLines()
        do {
            let wrapper = ["data": fullLines]
            let data = try encoder.encode(wrapper)
            let panel = NSSavePanel()
            panel.allowedFileTypes = ["json"]
            panel.nameFieldStringValue = "timelines_full.json"
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            print("Ошибка сохранения полного JSON: \(error)")
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 12) {
                compactControlPanel
                scrollBlock()
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .frame(minWidth: 800, minHeight: 300)
            .overlay(
                Group {
                    if isExporting {
                        ViewsFactory.customHUD()
                            .transition(.opacity)
                    }
                }
            )
            .padding()
            .frame(minWidth: 800, minHeight: 300)
            .overlay(
                Group {
                    if isExporting {
                        ViewsFactory.customHUD()
                            .transition(.opacity)
                    }
                }
            )
            .onAppear {
                parentWindowHeight = geo.size.height
                setupKeyboardShortcuts()
                
                NotificationCenter.default.addObserver(forName: .markupModeChanged, object: nil, queue: .main) { notification in
                    if let newMode = notification.object as? MarkupMode {
                        self.markupMode = newMode
                    } else {
                        self.markupMode = MarkupMode.current
                    }
                }
            }
            .onDisappear {
                if let monitor = keyEventMonitor {
                    NSEvent.removeMonitor(monitor)
                }
                NotificationCenter.default.removeObserver(self)
            }
            .onChange(of: geo.size) { newSize in
                parentWindowHeight = newSize.height
            }
        }
        .sheet(isPresented: $showAddLineSheet) {
            AddLineSheet { newLineName in
                timelineData.addLine(name: newLineName)
            }
        }
        .sheet(isPresented: $showLabelEditSheet) {
            LabelEditSheet(showLabelEditSheet: $showLabelEditSheet)
        }
        .sheet(isPresented: $showExportModeSheet) {
            ExportModeSelectionSheet { mode in
                performExport(mode: mode)
                showExportModeSheet = false
            }
        }
        
        

        .sheet(isPresented: $showLabelSelectionSheet) {
            LabelSelectionSheetView(
                uniqueLabels: uniqueLabelsFromTimelines(),
                onLabelSelected: { selectedLabel in
                    print("Выбран лейбл: \(selectedLabel.name), ID: \(selectedLabel.id)")
                    
                    let availableTags = tagsForLabel(selectedLabel)
                    print("Доступные теги для лейбла: \(availableTags.map { $0.name })")
                    
                    if !availableTags.isEmpty {
                        showLabelSelectionSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showMultiTagSelection(for: selectedLabel)
                        }
                    } else {
                        selectedExportType = .label(selectedLabel: selectedLabel)
                        showLabelSelectionSheet = false
                        showExportModeSheet = true
                    }
                },
                onSkip: {
                    showLabelSelectionSheet = false
                },
                showMultiSelection: true
            )
            .frame(width: 300, height: 300)
        }


        
        .sheet(item: $multiTagSelectionItem) { item in
                    if let label = item.label {
                        let availableTags = tagsForLabel(label)
                        
                        MultiTagSelectionSheetView(
                            availableTags: availableTags,
                            onDone: { selectedTags in
                                selectedExportType = .labelWithTags(selectedLabel: label, selectedTags: selectedTags)
                                multiTagSelectionItem = nil
                                showExportModeSheet = true
                            },
                            onSkip: {
                                selectedExportType = .label(selectedLabel: label)
                                multiTagSelectionItem = nil
                                showExportModeSheet = true
                            }
                        )
                        .frame(width: 400, height: 300)
                    }
                }
                
                // Заменяем sheet для мультивыбора лейблов
                .sheet(item: $multiLabelSelectionItem) { item in
                    if let tag = item.tag {
                        let availableLabels = labelsForTag(tag)
                        
                        MultiLabelSelectionSheetView(
                            availableLabels: availableLabels,
                            onDone: { selectedLabels in
                                selectedExportType = .tagWithLabels(selectedTag: tag, selectedLabels: selectedLabels)
                                multiLabelSelectionItem = nil
                                showExportModeSheet = true
                            },
                            onSkip: {
                                selectedExportType = .tag(selectedTag: tag)
                                multiLabelSelectionItem = nil
                                showExportModeSheet = true
                            }
                        )
                        .frame(width: 400, height: 300)
                    }
                }

        .sheet(isPresented: $showEventSelectionSheet) {
            EventSelectionSheetView(timeEvents: uniqueEventsFromTimelines()) { selectedEvent in
                selectedExportType = .timeEvent(selectedEvent: selectedEvent)
                showEventSelectionSheet = false
                showExportModeSheet = true
            }
            .frame(width: 300, height: 300) // Фиксированный размер вместо динамического
        }

        .sheet(isPresented: $showTagSelectionSheet) {
            TagSelectionSheetView(
                uniqueTags: uniqueTagsFromTimelines(),
                onSelect: { selectedTag in
                    selectedExportType = .tag(selectedTag: selectedTag)
                    showTagSelectionSheet = false
                    showExportModeSheet = true
                },
                onSelectWithLabels: { selectedTag in
                    showTagSelectionSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showMultiLabelSelection(for: selectedTag)
                    }
                }
            )
            .frame(width: 300, height: 300) // Фиксированный размер вместо динамического
        }
    }
    
    struct LabelEditSheet: View {
        @ObservedObject var timelineData = TimelineDataManager.shared
        @Binding var showLabelEditSheet: Bool
        
        var body: some View {
            if let lineIDString = UserDefaults.standard.string(forKey: "editingStampLineID"),
               let stampIDString = UserDefaults.standard.string(forKey: "editingStampID"),
               let lineID = UUID(uuidString: lineIDString),
               let stampID = UUID(uuidString: stampIDString) {
                
                if let lineIndex = timelineData.lines.firstIndex(where: { $0.id == lineID }),
                   let stampIndex = timelineData.lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) {
                    
                    let currentLabels = timelineData.lines[lineIndex].stamps[stampIndex].labels
                    let stampName = timelineData.lines[lineIndex].stamps[stampIndex].label
                    let tagId = timelineData.lines[lineIndex].stamps[stampIndex].idTag
                    
                    if let tag = TagLibraryManager.shared.findTagById(tagId) {
                        LabelSelectionSheet(
                            stampName: stampName,
                            initialLabels: currentLabels,
                            tag: tag,
                            tagLibrary: TagLibraryManager.shared,
                            isDop: true,
                            onDone: { newLabels in
                                timelineData.updateStampLabels(lineID: lineID,
                                                               stampID: stampID,
                                                               newLabels: newLabels)
                                showLabelEditSheet = false
                            }, onCancel: { return }
                        )
                    } else {
                        Text(^String.Titles.fullControlExportErrorStampNotFound)
                    }
                } else {
                    Text(^String.Titles.fullControlExportErrorStampNotFound)
                }
            } else {
                Text(^String.Titles.fullControlExportErrorStampNotFound)
            }
        }
    }
    
    func showMultiTagSelection(for label: Label) {
            multiTagSelectionItem = MultiSelectionItem(label: label)
        }
        
        // В функции где показываем мультивыбор лейблов (замена showMultiLabelSelectionSheet = true)
        func showMultiLabelSelection(for tag: Tag) {
            multiLabelSelectionItem = MultiSelectionItem(tag: tag)
        }
    
    func uniqueEventsFromTimelines() -> [TimeEvent] {
        let eventIDs = Set(timelineData.lines.flatMap { line in
            line.stamps.flatMap { stamp in
                stamp.timeEvents
            }
        })
        
        return TagLibraryManager.shared.allTimeEvents.filter { event in
            eventIDs.contains(event.id)
        }
    }
    
    func transformToFullTimelineLines() -> [FullTimelineLine] {
        let tagLibrary = TagLibraryManager.shared
        
        return TimelineDataManager.shared.lines.map { line in
            let fullStamps = line.stamps.map { stamp -> FullTimelineStamp in
                let tag = tagLibrary.findTagById(stamp.idTag)
                var tagGroup: TagGroupInfo? = nil
                if let tagID = tag?.id {
                    for group in tagLibrary.allTagGroups {
                        if group.tags.contains(tagID) {
                            tagGroup = TagGroupInfo(id: group.id, name: group.name)
                            break
                        }
                    }
                }
                
                let fullTag = FullTagWithGroup(
                    id: tag?.id ?? "",
                    primaryID: tag?.primaryID,
                    name: tag?.name ?? stamp.label,
                    description: tag?.description ?? "",
                    color: tag?.color ?? "FFFFFF",
                    defaultTimeBefore: tag?.defaultTimeBefore ?? 0,
                    defaultTimeAfter: tag?.defaultTimeAfter ?? 0,
                    collection: tag?.collection ?? "",
                    hotkey: tag?.hotkey,
                    labelHotkeys: tag?.labelHotkeys,
                    group: tagGroup
                )
                
                let fullLabels = stamp.labels.compactMap { labelID -> FullLabelWithGroup? in
                    guard let label = tagLibrary.findLabelById(labelID) else { return nil }
                    
                    var labelGroup: LabelGroupInfo? = nil
                    for group in tagLibrary.allLabelGroups {
                        if group.lables.contains(labelID) {
                            labelGroup = LabelGroupInfo(id: group.id, name: group.name)
                            break
                        }
                    }
                    
                    return FullLabelWithGroup(
                        id: label.id,
                        name: label.name,
                        description: label.description,
                        group: labelGroup
                    )
                }
                
                let fullTimeEvents = stamp.timeEvents.compactMap { eventID in
                    tagLibrary.allTimeEvents.first(where: { $0.id == eventID })
                }
                
                return FullTimelineStamp(
                    id: stamp.id,
                    timeStart: stamp.timeStart,
                    timeFinish: stamp.timeFinish,
                    tag: fullTag,
                    labels: fullLabels,
                    timeEvents: fullTimeEvents,
                    position: stamp.position
                )
            }
            
            return FullTimelineLine(id: line.id, name: line.name, stamps: fullStamps)
        }
    }
    
    func uniqueLabelsFromTimelines() -> [Label] {
        let labelIDs = timelineData.lines.flatMap { line in
            line.stamps.flatMap { stamp in
                stamp.labels
            }
        }
        
        let uniqueLabelIDs = Array(Set(labelIDs))
        
        let labels = TagLibraryManager.shared.allLabels.filter { label in
            return uniqueLabelIDs.contains(label.id)
        }
        
        return labels
    }

    func labelsForTag(_ tag: Tag) -> [Label] {
        let labelIDs = timelineData.lines.flatMap { line in
            line.stamps.filter { $0.idTag == tag.id }
                .flatMap { $0.labels }
        }
        
        let uniqueLabelIDs = Array(Set(labelIDs))
        print("Для тега \(tag.name) найдены лейблы с ID: \(uniqueLabelIDs)")
        
        let labels = TagLibraryManager.shared.allLabels.filter { uniqueLabelIDs.contains($0.id) }
        print("Найдены лейблы: \(labels.map { $0.name })")
        
        return labels
    }

    func tagsForLabel(_ label: Label) -> [Tag] {
        let tagIDs = timelineData.lines.flatMap { line in
            line.stamps.filter { $0.labels.contains(label.id) }
                .map { $0.idTag }
        }
        
        let uniqueTagIDs = Array(Set(tagIDs))
        print("Для лейбла \(label.name) найдены теги с ID: \(uniqueTagIDs)")
        
        let tags = TagLibraryManager.shared.allTags.filter { uniqueTagIDs.contains($0.id) }
        print("Найдены теги: \(tags.map { $0.name })")
        
        return tags
    }
    
    func uniqueTagsFromTimelines() -> [Tag] {
        let tagIDs = timelineData.lines.flatMap { line in
            line.stamps.flatMap { stamp in
                [stamp.idTag]
            }
        }
        
        let uniqueTagIDs = Array(Set(tagIDs))
        
        let tags = TagLibraryManager.shared.allTags.filter { tag in
            return uniqueTagIDs.contains { $0 == tag.id }
        }
        
        return tags
    }
    
}

// Sheet для выбора лейблов
// Модифицируйте LabelSelectionSheetView
struct LabelSelectionSheetView: View {
    let uniqueLabels: [Label]
    let onLabelSelected: (Label) -> Void
    let onSkip: () -> Void
    let showMultiSelection: Bool
    
    var body: some View {
        VStack {
            Text(^String.Titles.selectLabelForExport)
                .font(.headline)
                .padding()
            
            List(uniqueLabels, id: \.id) { label in
                if showMultiSelection {
                    Button(action: {
                        onLabelSelected(label)
                    }) {
                        HStack {
                            Text(label.name)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                } else {
                    Button(action: {
                        onLabelSelected(label)
                    }) {
                        Text(label.name)
                    }
                }
            }
            
            Button(^String.Titles.skip) {
                onSkip()
            }
            .padding()
        }
        .frame(width: 300, height: 300)
    }
}

struct MultiTagSelectionSheetView: View {
    let availableTags: [Tag]
    @State private var selectedTags: Set<String> = []
    let onDone: ([Tag]) -> Void
    let onSkip: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            Text(^String.Titles.selectTagsForExport)
                .font(.headline)
                .padding()
            
            if availableTags.isEmpty {
                Text(^String.Titles.noAvailableTags)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List(availableTags, id: \.id) { tag in
                    HStack {
                        Image(systemName: selectedTags.contains(tag.id) ? "checkmark.square.fill" : "square")
                            .foregroundColor(selectedTags.contains(tag.id) ? .blue : .secondary)
                        Text(tag.name)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedTags.contains(tag.id) {
                            selectedTags.remove(tag.id)
                        } else {
                            selectedTags.insert(tag.id)
                        }
                    }
                }
            }
            
            HStack {
                Button(^String.Titles.skip) {
                    onSkip()
                }
                
                Spacer()
                
                Button(^String.Titles.done) {
                    let selected = availableTags.filter { selectedTags.contains($0.id) }
                    onDone(selected)
                }
                .disabled(selectedTags.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
        .onAppear {
            print("MultiTagSelectionSheetView появился")
            print("Доступные теги: \(availableTags.map { $0.name })")
        }
    }
}

// Обновите MultiLabelSelectionSheetView аналогичным образом
struct MultiLabelSelectionSheetView: View {
    let availableLabels: [Label]
    @State private var selectedLabels: Set<String> = []
    let onDone: ([Label]) -> Void
    let onSkip: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            Text(^String.Titles.selectLabelsForExport)
                .font(.headline)
                .padding()
            
            if availableLabels.isEmpty {
                Text(^String.Titles.noAvailableLabels)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List(availableLabels, id: \.id) { label in
                    HStack {
                        Image(systemName: selectedLabels.contains(label.id) ? "checkmark.square.fill" : "square")
                            .foregroundColor(selectedLabels.contains(label.id) ? .blue : .secondary)
                        Text(label.name)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedLabels.contains(label.id) {
                            selectedLabels.remove(label.id)
                        } else {
                            selectedLabels.insert(label.id)
                        }
                    }
                }
            }
            
            HStack {
                Button(^String.Titles.skip) {
                    onSkip()
                }
                
                Spacer()
                
                Button(^String.Titles.done) {
                    let selected = availableLabels.filter { selectedLabels.contains($0.id) }
                    onDone(selected)
                }
                .disabled(selectedLabels.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
        .onAppear {
            print("MultiLabelSelectionSheetView появился")
            print("Доступные лейблы: \(availableLabels.map { $0.name })")
        }
    }
}

// MARK: - TimelineDropDelegate
struct TimelineDropDelegate: DropDelegate {
    let currentLine: TimelineLine
    let timelineData: TimelineDataManager
    
    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [.text]).first else {
            return false
        }
        
        itemProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { (item, error) in
            if let data = item as? Data,
               let draggedLineIDString = String(data: data, encoding: .utf8),
               let draggedLineID = UUID(uuidString: draggedLineIDString),
               draggedLineID != currentLine.id {
                
                DispatchQueue.main.async {
                    reorderTimelines(draggedID: draggedLineID, targetID: currentLine.id)
                }
            }
        }
        
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // Можно добавить визуальную обратную связь при наведении
    }
    
    func dropExited(info: DropInfo) {
        // Можно добавить визуальную обратную связь при выходе
    }
    
    private func reorderTimelines(draggedID: UUID, targetID: UUID) {
        guard let draggedIndex = timelineData.lines.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = timelineData.lines.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        
        let draggedLine = timelineData.lines.remove(at: draggedIndex)
        let newTargetIndex = draggedIndex < targetIndex ? targetIndex - 1 : targetIndex
        timelineData.lines.insert(draggedLine, at: newTargetIndex)
        timelineData.updateTimelines()
    }
}

// MARK: - Custom Button Styles
struct CompactButtonStyle: ButtonStyle {
    let icon: String
    let color: Color
    let showText: Bool
    let text: String
    
    init(icon: String, color: Color, showText: Bool = false, text: String = ^String.Titles.report) {
        self.icon = icon
        self.color = color
        self.showText = showText
        self.text = text
    }
    
    func makeBody(configuration: Configuration) -> some View {
        if showText {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(text)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        } else {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .padding(6)
                .background(color.opacity(0.1))
                .foregroundColor(color)
                .cornerRadius(6)
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

struct ExportButtonStyle: ButtonStyle {
    let icon: String
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
            configuration.label
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .cornerRadius(8)
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ZoomButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Image(systemName: "minus.magnifyingglass")
            .font(.system(size: 14, weight: .medium))
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .foregroundColor(.primary)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

