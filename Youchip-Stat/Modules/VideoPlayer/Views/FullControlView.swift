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
                fileName = "\(lineName)_фильм.mp4"
            } else {
                fileName = "timeline_фильм.mp4"
            }
        case .tag(let selectedTag):
            let groupName = segments.first?.groupName ?? "group"
            fileName = "\(groupName)_\(selectedTag.name)_фильм.mp4"
        case .timeEvent(let selectedEvent):
            fileName = "событие_\(selectedEvent.name)_фильм.mp4"
        case .allTimelines:
            fileName = "все моменты.mp4"
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
                let lineName = segment.lineName ?? "таймлайн"
                fileName = "\(lineName)_\(segment.tagName)_\(index + 1).mp4"
                
            case .allTimelines:
                let lineName = segment.lineName ?? "таймлайн"
                fileName = "\(lineName)_\(segment.tagName)_\(index + 1).mp4"
                
            case .tag(let selectedTag):
                let groupName = segment.groupName ?? "group"
                fileName = "\(groupName)_\(selectedTag.name)_\(index + 1).mp4"
                
            case .timeEvent(let selectedEvent):
                fileName = "событие_\(selectedEvent.name)_\(index + 1).mp4"
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
                                print("Фильм экспортирован и сохранён по \(url)")
                            } catch {
                                print("Ошибка сохранения фильма: \(error)")
                            }
                        }
                    case .failure(let error):
                        print("Ошибка экспорта фильма: \(error)")
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
    
    @ViewBuilder
    private func scrollBlock() -> some View {
        ScrollView(.vertical) {
            ScrollViewReader { scrollProxy in
                timelineContent(proxy: scrollProxy)
            }
        }
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
                Text("")
                    .frame(width: 75, height: 30, alignment: .leading)
                    .background(Color.gray.opacity(0.05))
                    .id("header-row")
                
                ForEach(timelineData.lines) { line in
                    if markupMode == .standard {
                        HStack {
                            Text(line.name)
                                .font(.headline)
                                .padding(4)
                                .background((line.id == timelineData.selectedLineID) ? Color.blue.opacity(0.2) : Color.clear)
                                .cornerRadius(4)
                                .lineLimit(1)
                                .onTapGesture { timelineData.selectLine(line.id) }
                            
                            Button(action: {
                                showEditNameSheet = true
                            }) {
                                Image(systemName: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .help("Редактировать название таймлайна")
                        }
                        .frame(width: 75, height: 30, alignment: .leading)
                        .contextMenu {
                            Button("Редактировать название") {
                                showEditNameSheet = true
                            }
                            Button("Удалить таймлайн") {
                                let isSelectedLine = (TimelineDataManager.shared.selectedLineID == line.id)
                                TimelineDataManager.shared.lines.removeAll { $0.id == line.id }
                                if isSelectedLine {
                                    TimelineDataManager.shared.selectedLineID = nil
                                }
                                TimelineDataManager.shared.updateTimelines()
                            }
                        }
                        .id("name-\(line.id)")
                    } else {
                        Text(line.name)
                            .font(.headline)
                            .padding(4)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(width: 75, height: 30, alignment: .leading)
                            .id("name-\(line.id)")
                    }
                }
            }
            .frame(width: 75)
            .padding(.trailing, 5)
            
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
                            if duration > 0 {
                                let position = (videoManager.currentTime / duration) * gridWidth
                                VStack {
                                    
                                    ZStack {
                                        Rectangle()
                                            .fill(Color.red)
                                            .frame(width: 15, height: 15)
                                            .rotationEffect(.degrees(45))
                                        
                                        Rectangle()
                                            .fill(Color.clear)
                                            .frame(width: 30, height: 30)
                                            .contentShape(Rectangle())
                                            .gesture(
                                                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                                                    .onChanged { value in
                                                        if videoManager.player?.timeControlStatus == .playing {
                                                            videoManager.player?.pause()
                                                        }
                                                        let newPosition = max(0, min(value.location.x, gridWidth))
                                                        let newTime = (newPosition / gridWidth) * duration
                                                        videoManager.currentTime = newTime
                                                    }
                                                    .onEnded { value in
                                                        let newPosition = max(0, min(value.location.x, gridWidth))
                                                        let newTime = (newPosition / gridWidth) * duration
                                                        videoManager.currentTime = newTime
                                                        videoManager.seek(to: newTime)
                                                        if videoManager.playbackSpeed > 0 {
                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                                videoManager.player?.play()
                                                            }
                                                        }
                                                    }
                                            )
                                            .onHover { isHovering in
                                                if isHovering {
                                                    NSCursor.pointingHand.push()
                                                } else {
                                                    NSCursor.pop()
                                                }
                                            }
                                    }
                                    .position(x: position, y: 23)
                                    Rectangle()
                                        .fill(Color.red)
                                        .frame(width: 2)
                                        .position(x: position, y: 15 * CGFloat(timelineData.lines.count + 1) - 10)
                                        .frame(height: 30 * CGFloat(timelineData.lines.count) + 3)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        .frame(width: gridWidth)
                    }
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
    
    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(action: { videoManager.seek(by: -10) }) {
                        Image(systemName: "gobackward.10")
                        Text("10s")
                    }
                    Button(action: { videoManager.togglePlayPause() }) {
                        Image(systemName: "playpause")
                    }
                    Button(action: { videoManager.seek(by: 10) }) {
                        Text("10s")
                        Image(systemName: "goforward.10")
                    }
                    Menu {
                        ForEach([0.5, 1.0, 2.0, 5.0], id: \.self) { speed in
                            Button(String(format: "%.1fx", speed)) {
                                videoManager.changePlaybackSpeed(to: speed)
                            }
                        }
                    } label: {
                        Text("Speed x\(String(format: "%.1f", videoManager.playbackSpeed))")
                    }
                    Spacer()
                }
                HStack {
                    Text("Таймлайны:")
                    if markupMode == .standard {
                        Button {
                            showAddLineSheet = true
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.title2)
                        }
                        .help("Добавить таймлайн")
                    }
                    Menu {
                        Button(action: {
                            WindowsManager.shared.setMarkupMode(.standard)
                        }) {
                            HStack {
                                Text("Стандартный режим")
                                if markupMode == .standard {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Button(action: {
                            WindowsManager.shared.setMarkupMode(.tagBased)
                        }) {
                            HStack {
                                Text("Режим по тегам")
                                if markupMode == .tagBased {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        if markupMode == .standard {
                            Text("Стандартный режим")
                        } else {
                            Text("Режим по тегам")
                        }
                    }
                    .help("Режим разметки")
                    Button("Скачать упрощенный JSON") {
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
                    Button("Скачать полный JSON") {
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
                    Menu("Нарезки") {
                        Button("Экспорт текущего таймлайна") {
                            selectedExportType = .currentTimeline
                            showExportModeSheet = true
                        }
                        Button("Экспорт всего") {
                            selectedExportType = .allTimelines
                            showExportModeSheet = true
                        }
                        Button("Экспорт тегов") {
                            showTagSelectionSheet = true
                        }
                        Button("Экспорт событий") {
                            showEventSelectionSheet = true
                        }
                    }
                    Button("Отчет") {
                        WindowsManager.shared.showAnalytics()
                    }
                    Button("Мои скриншоты") {
                        WindowsManager.shared.showScreenshots()
                    }
                    Button("Отобразить на карте") {
                        WindowsManager.shared.showFieldMapVisualizationPicker()
                    }
                    Button("Настроить визуализацию") {
                        WindowsManager.shared.showFieldMapConfigurationWindow()
                    }
                    Spacer()
                }
                
                HStack {
                    Button {
                        timelineScale = max(1.0, timelineScale - 0.5)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .help("Отдалить таймлайн")
                    
                    Button {
                        timelineScale += 0.5
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .help("Приблизить таймлайн")
                    
                    Text(String(format: "%.1fx", timelineScale))
                        .padding(.leading, 8)
                }
                .frame(maxHeight: 20)
                .padding(.horizontal)
                scrollBlock()
            }
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
                            isDop: true
                        ) { newLabels in
                            timelineData.updateStampLabels(lineID: lineID,
                                                           stampID: stampID,
                                                           newLabels: newLabels)
                        }
                    }
                } else {
                    Text("Ошибка: не найден таймстемп")
                }
            } else {
                Text("Ошибка: не найден таймстемп")
            }
        }
        .sheet(isPresented: $showExportModeSheet) {
            ExportModeSelectionSheet { mode in
                performExport(mode: mode)
                showExportModeSheet = false
            }
        }
        .sheet(isPresented: $showEventSelectionSheet) {
            let maxSheetHeight = parentWindowHeight * 0.8
            
            EventSelectionSheetView(timeEvents: uniqueEventsFromTimelines()) { selectedEvent in
                selectedExportType = .timeEvent(selectedEvent: selectedEvent)
                showEventSelectionSheet = false
                showExportModeSheet = true
            }
            .frame(height: maxSheetHeight)
        }
        .sheet(isPresented: $showTagSelectionSheet) {
            let maxSheetHeight = parentWindowHeight * 0.8
            
            TagSelectionSheetView(uniqueTags: uniqueTagsFromTimelines()) { selectedTag in
                selectedExportType = .tag(selectedTag: selectedTag)
                showTagSelectionSheet = false
                showExportModeSheet = true
            }
            .frame(height: maxSheetHeight)
        }
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
