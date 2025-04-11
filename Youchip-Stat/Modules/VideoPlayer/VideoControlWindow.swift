import SwiftUI
import AVKit
import Cocoa
import AVFoundation  // для работы с AVAssetExportSession

// MARK: - Модели данных

struct Tag: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let color: String
    let defaultTimeBefore: Double
    let defaultTimeAfter: Double
    let collection: String?
    let lablesGroup: [String]
}

struct TagGroup: Decodable, Identifiable {
    let id: String
    let name: String
    let tags: [String]
}

struct TagsData: Decodable {
    let tags: [Tag]
}

struct TagGroupsData: Decodable {
    let tagGroups: [TagGroup]
}

struct Label: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
}

struct LabelGroupData: Decodable, Identifiable {
    let id: String
    let name: String
    let lables: [String]
}

struct LabelGroupsData: Decodable {
    let labelGroups: [LabelGroupData]
}

struct LabelsData: Decodable {
    let labels: [Label]
}

func loadJSON<T: Decodable>(filename: String) -> T? {
    guard let url = Bundle.main.url(forResource: filename, withExtension: nil) else {
        print("Не найден файл \(filename)")
        return nil
    }
    do {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let loaded = try decoder.decode(T.self, from: data)
        return loaded
    } catch {
        print("Ошибка декодирования \(filename): \(error)")
        return nil
    }
}

// MARK: - Менеджер библиотеки тегов

class TagLibraryManager: ObservableObject {
    static let shared = TagLibraryManager()
    @Published var tags: [Tag] = []
    @Published var tagGroups: [TagGroup] = []
    @Published var labelGroups: [LabelGroupData] = []
    @Published var labels: [Label] = []
    private init() {
        if let loadedTags: TagsData = loadJSON(filename: "tags.json") {
            self.tags = loadedTags.tags
        }
        if let loadedTagGroups: TagGroupsData = loadJSON(filename: "tagsGroups.json") {
            self.tagGroups = loadedTagGroups.tagGroups
        }
        if let loadedLabelGroups: LabelGroupsData = loadJSON(filename: "labelsGroups.json") {
            self.labelGroups = loadedLabelGroups.labelGroups
        }
        if let loadedLabels: LabelsData = loadJSON(filename: "labels.json") {
            self.labels = loadedLabels.labels
        }
    }
}

func secondsToTimeString(_ seconds: Double) -> String {
    let hours = Int(seconds / 3600)
    let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
    let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
    return String(format: "%02d:%02d:%02d", hours, minutes, secs)
}

func timeStringToSeconds(_ time: String) -> Double {
    let components = time.split(separator: ":").map { Double($0) ?? 0 }
    if components.count == 3 {
        return components[0] * 3600 + components[1] * 60 + components[2]
    } else if components.count == 2 {
        return components[0] * 60 + components[1]
    }
    return 0
}

// MARK: - Расширение для цвета из HEX

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct TimelineStamp: Identifiable, Codable {
    let id: UUID
    var idTag: String
    var timeStart: String
    var timeFinish: String
    var colorHex: String
    var label: String
    var labels: [String]
    var color: Color {
        Color(hex: colorHex)
    }
    var startSeconds: Double {
        timeStringToSeconds(timeStart)
    }
    var finishSeconds: Double {
        timeStringToSeconds(timeFinish)
    }
    var duration: Double {
        finishSeconds - startSeconds
    }
    init(id: UUID = UUID(), idTag: String, timeStart: String, timeFinish: String, colorHex: String, label: String, labels: [String]) {
        self.id = id
        self.idTag = idTag
        self.timeStart = timeStart
        self.timeFinish = timeFinish
        self.colorHex = colorHex
        self.label = label
        self.labels = labels
    }
}

struct TimelineLine: Identifiable, Codable {
    var id = UUID()
    var name: String
    var stamps: [TimelineStamp] = []
}

// MARK: - Менеджер таймлайнов

class TimelineDataManager: ObservableObject {
    static let shared = TimelineDataManager()
    @Published var lines: [TimelineLine] = []
    @Published var selectedLineID: UUID? = nil
    var currentBookmark: Data?
    init() {
        lines = []
        if let first = lines.first {
            selectedLineID = first.id
        }
    }
    func selectLine(_ lineID: UUID) {
        selectedLineID = lineID
    }
    func removeStamp(lineID: UUID, stampID: UUID) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        lines[lineIndex].stamps.removeAll(where: { $0.id == stampID })
        updateTimelines()
    }
    func addLine(name: String) {
        let newLine = TimelineLine(name: name)
        lines.append(newLine)
        selectedLineID = newLine.id
        updateTimelines()
    }
    func addStampToSelectedLine(idTag: String, name: String, timeStart: String, timeFinish: String, color: String, labels: [String]) {
        guard let lineID = selectedLineID,
              let idx = lines.firstIndex(where: { $0.id == lineID }) else { return }
        let stamp = TimelineStamp(idTag: idTag, timeStart: timeStart, timeFinish: timeFinish, colorHex: color, label: name, labels: labels)
        lines[idx].stamps.append(stamp)
        updateTimelines()
    }
    func updateStampLabels(lineID: UUID, stampID: UUID, newLabels: [String]) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        guard let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else { return }
        lines[lineIndex].stamps[stampIndex].labels = newLabels
        updateTimelines()
    }
    
    func updateTimelines() {
        guard let currentBookmark = currentBookmark else { return }
        VideoFilesManager.shared.updateTimelines(for: currentBookmark, with: lines)
    }
}

class VideoPlayerManager: ObservableObject {
    static let shared = VideoPlayerManager()
    @Published var player: AVPlayer?
    @Published var playbackSpeed: Double = 1.0
    @Published var currentTime: Double = 0.0
    var videoDuration: Double {
        player?.currentItem?.duration.seconds ?? 0
    }
    private var timeObserverToken: Any?
    func loadVideo(from url: URL) {
        player = AVPlayer(url: url)
        player?.play()
        startTimeObserver()
    }
    func deleteVideo() {
        player?.pause()
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player = nil
        currentTime = 0.0
        playbackSpeed = 1.0
    }
    private func startTimeObserver() {
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = CMTimeGetSeconds(time)
        }
    }
    func togglePlayPause() {
        guard let player = player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }
    func seek(by seconds: Double) {
        seek(to: currentTime + seconds)
    }
    func seek(to time: Double) {
        guard let player = player else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime)
    }
    func changePlaybackSpeed(to speed: Double) {
        playbackSpeed = speed
        player?.rate = Float(speed)
    }
}

// MARK: - Представление видео

struct VideoPlayerWindow: View {
    @ObservedObject var videoManager = VideoPlayerManager.shared
    var body: some View {
        VStack {
            if let player = videoManager.player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
            } else {
                Text("Видео не загружено")
                    .foregroundColor(.gray)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

class FullControlWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let view = FullControlView()
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Таймлайны"
        super.init(window: window)
        window.styleMask.insert(.closable)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowsManager.shared.closeAll()
    }
}

class VideoPlayerWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let view = VideoPlayerWindow()
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Видео"
        super.init(window: window)
        window.styleMask.insert(.closable)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func windowWillClose(_ notification: Notification) {
        WindowsManager.shared.closeAll()
    }
}

struct FullTimelineStamp: Codable {
    let id: UUID
    let timeStart: String
    let timeFinish: String
    let tag: Tag
    let labels: [Label]
}

struct FullTimelineLine: Codable {
    let id: UUID
    let name: String
    let stamps: [FullTimelineStamp]
}


struct FullControlView: View {
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    @State private var sliderValue: Double = 0.0
    @State private var isDraggingSlider = false
    @State private var showAddLineSheet = false
    @State private var isExporting: Bool = false
    @State private var showLabelEditSheet = false
    @State private var editingStampLineID: UUID?
    @State private var editingStampID: UUID?
    @State private var timelineScale: CGFloat = 1.0
    @GestureState private var magnifyScale: CGFloat = 1.0
    
    enum ExportMode { case film, playlist }
    enum CutsExportType {
        case currentTimeline
        case allTimelines
        case tag(selectedTag: Tag)
    }
    struct ExportSegment {
        let timeRange: CMTimeRange
        let lineName: String?
        let tagName: String
        let groupName: String?
    }
    @State private var selectedExportType: CutsExportType?
    @State private var showExportModeSheet: Bool = false
    @State private var showTagSelectionSheet: Bool = false
    @State private var parentWindowHeight: CGFloat = 600

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
                    let possibleGroup = tagLibrary.tagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                    
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
                    let possibleGroup = tagLibrary.tagGroups.first(where: { $0.tags.contains(stamp.idTag) })
                    
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
            let possibleGroup = tagLibrary.tagGroups.first(where: { $0.tags.contains(selectedTag.id) })
            
            for line in timelineData.lines {
                for stamp in line.stamps {
                    if stamp.label == selectedTag.name {
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
    
    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 10) {
                
                // --- Кнопки управления видео (Play/Pause/Seek) ---
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
                
                // --- Слайдер по времени видео ---
                Slider(value: $sliderValue, in: 0...(videoManager.videoDuration > 0 ? videoManager.videoDuration : 1), onEditingChanged: { editing in
                    if !editing { videoManager.seek(to: sliderValue) }
                    isDraggingSlider = editing
                })
                .onReceive(videoManager.$currentTime) { current in
                    if !isDraggingSlider { sliderValue = current }
                }
                
                // --- Кнопки \"Таймлайны / JSON / Нарезки\" ---
                HStack {
                    Text("Таймлайны:")
                    Button {
                        showAddLineSheet = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                    }
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
                            let data = try encoder.encode(fullLines)
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
                    }
                    if #available(macOS 12.0, *) {
                        Button("Отчет") {
                            WindowsManager.shared.showAnalytics()
                        }
                    }
                    Spacer()
                }
                
                // --- Кнопки зума таймлайнов (\"–\" и \"+\") и отображение фактического значения ---
                HStack {
                    Button {
                        // Уменьшаем масштаб, минимум 1.0
                        timelineScale = max(1.0, timelineScale - 0.5)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .help("Отдалить таймлайн")
                    
                    Button {
                        // Увеличиваем
                        timelineScale += 0.5
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .help("Приблизить таймлайн")
                    
                    Text(String(format: "%.1fx", timelineScale))
                        .padding(.leading, 8)
                }
                
                // --- Горизонтальный скролл для таймлайнов, с поддержкой pinch ---
                ScrollView(.vertical) {
//                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 65) {
                            ForEach(timelineData.lines) { line in
                                TimelineLineView(
                                    line: line,
                                    scale: timelineScale * magnifyScale, // совмещаем кнопки + жест
                                    isSelected: (line.id == timelineData.selectedLineID),
                                    onSelect: { timelineData.selectLine(line.id) },
                                    onEditLabelsRequest: { stampID in
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            showLabelEditSheet = true
                                        }
                                        UserDefaults.standard.set(line.id.uuidString, forKey: "editingStampLineID")
                                        UserDefaults.standard.set(stampID.uuidString, forKey: "editingStampID")
                                    }
                                )
                            }
                        .gesture(
                            MagnificationGesture()
                                .updating($magnifyScale) { current, gestureState, _ in
                                    // временно применяем scale к жесту
                                    gestureState = current
                                }
                                .onEnded { final in
                                    // фиксируем итоговый масштаб
                                    let newScale = timelineScale * final
                                    timelineScale = max(1.0, newScale)
                                }
                        )
                            Spacer()
                                .frame(height: 50)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .onAppear {
                parentWindowHeight = geo.size.height
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
                    
                    if let tag = TagLibraryManager.shared.tags.first(where: { $0.id == timelineData.lines[lineIndex].stamps[stampIndex].idTag }) {
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
    
    func transformToFullTimelineLines() -> [FullTimelineLine] {
        let tagLibrary = TagLibraryManager.shared
        return TimelineDataManager.shared.lines.map { line in
            let fullStamps = line.stamps.map { stamp -> FullTimelineStamp in
                let fullTag = tagLibrary.tags.first(where: { $0.name == stamp.label }) ?? Tag(id: "", name: stamp.label, description: "", color: "FFFFFF", defaultTimeBefore: 0, defaultTimeAfter: 0, collection: "", lablesGroup: [])
                let fullLabels = stamp.labels.compactMap { labelID in
                    tagLibrary.labels.first(where: { $0.id == labelID })
                }
                return FullTimelineStamp(id: stamp.id, timeStart: stamp.timeStart, timeFinish: stamp.timeFinish, tag: fullTag, labels: fullLabels)
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
        
        let tags = TagLibraryManager.shared.tags.filter { tag in
            return uniqueTagIDs.contains { $0 == tag.id }
        }
        
        return tags
    }
}

struct TimelineLineView: View {
    @ObservedObject var videoManager = VideoPlayerManager.shared
    
    let line: TimelineLine
    
    // Новое поле: масштаб
    let scale: CGFloat
    
    let isSelected: Bool
    let onSelect: () -> Void
    let onEditLabelsRequest: (UUID) -> Void
    
    @ObservedObject var tagLibrary = TagLibraryManager.shared

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.headline)
                    .padding(4)
                    .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
                    .cornerRadius(4)
                    .onTapGesture { onSelect() }
                    .contextMenu {
                        Button("Удалить таймлайн") {
                            TimelineDataManager.shared.lines.removeAll { $0.id == line.id }
                            TimelineDataManager.shared.updateTimelines()
                        }
                    }
                
                ScrollView(.horizontal) {
                    let baseWidth = geometry.size.width
                    let totalDuration = max(1, videoManager.videoDuration)
                    let computedWidth = baseWidth * max(scale, 1.0)  // ширина не меньше базовой
                    
                    HStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: computedWidth, height: 30)
                            
                            ForEach(line.stamps.sorted { $0.duration > $1.duration }) { stamp in
                                let startRatio = stamp.startSeconds / totalDuration
                                let durationRatio = stamp.duration / totalDuration
                                
                                let stampWidth = durationRatio * computedWidth
                                let stampX = startRatio * computedWidth
                                
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(stamp.color)
                                        .frame(height: 30)
                                    
                                    StampLabelsOverlayView(stamp: stamp, maxWidth: stampWidth)
                                        .frame(height: 30)
                                }
                                .frame(width: stampWidth, height: 30)
                                .position(x: stampX + stampWidth / 2, y: 15)
                                .onTapGesture {
                                    videoManager.seek(to: stamp.startSeconds)
                                }
                                .contextMenu {
                                    Text("Тег: \(stamp.label)")
                                    if !stamp.labels.isEmpty {
                                        ForEach(stamp.labels, id: \.self) { labelID in
                                            if let label = tagLibrary.labels.first(where: { $0.id == labelID }) {
                                                if let group = tagLibrary.labelGroups.first(where: { $0.lables.contains(label.id) }) {
                                                    Text("\(label.name) (\(group.name))")
                                                } else {
                                                    Text(label.name)
                                                }
                                            }
                                        }
                                        Divider()
                                    }
                                    Button("Удалить тег") {
                                        TimelineDataManager.shared.removeStamp(lineID: line.id, stampID: stamp.id)
                                    }
                                    Button("Редактировать лейблы") {
                                        onEditLabelsRequest(stamp.id)
                                    }
                                }
                            }
                        }
                        .frame(width: computedWidth, height: 30)
                    }
                }
                .frame(height: 30)
            }
        }
    }
}

struct TagLibraryView: View {
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    
    @State private var showLabelSheet = false
    @State private var selectedTag: Tag? = nil
    @State private var hoveredTagID: String? = nil

    func makeHyphenatedString(_ text: String, width: CGFloat, fontSize: CGFloat = 14, locale: Locale = Locale(identifier: "ru")) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.hyphenationFactor = 1.0
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: NSFont.systemFont(ofSize: fontSize)
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Группы тегов")
                .font(.headline)
                .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tagLibrary.tagGroups) { group in
                        DisclosureGroup(isExpanded: .constant(true)) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                                ForEach(group.tags, id: \.self) { tagID in
                                    if let tag = tagLibrary.tags.first(where: { $0.id == tagID }) {
                                        Button {
                                            // При нажатии: ставим selectedTag и показываем Sheet
                                            videoManager.player?.pause()
                                            selectedTag = tag
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                showLabelSheet = true
                                            }
                                        } label: {
                                            Text(tag.name)
                                                .lineLimit(nil)
                                                .multilineTextAlignment(.center)
                                                .frame(width: 135)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .padding(5)
                                                .foregroundColor(Color(hex: tag.color).isDark ? .white : .black)
                                        }
                                        .background(Color(hex: tag.color))
                                        .cornerRadius(4)
                                        // Подсветка на ховер
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(hoveredTagID == tag.id ? Color.blue : Color.clear,
                                                        lineWidth: 2)
                                        )
                                        .onHover { hovering in
                                            // При наведении: ставим hoveredTagID = tag.id, иначе сбрасываем
                                            if hovering {
                                                hoveredTagID = tag.id
                                            } else if hoveredTagID == tag.id {
                                                hoveredTagID = nil
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        } label: {
                            Text(group.name)
                                .font(.headline)
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        // Когда showLabelSheet == true, открываем окно выбора лейблов
        .sheet(isPresented: $showLabelSheet) {
            if timelineData.selectedLineID != nil, let tag = selectedTag {
                LabelSelectionSheet(
                    stampName: tag.name,
                    initialLabels: [],
                    tag: tag,
                    tagLibrary: tagLibrary
                ) { selectedLabels in
                    let currentTime = videoManager.currentTime
                    let startTime = max(0, currentTime - tag.defaultTimeBefore)
                    let finishTime = startTime + tag.defaultTimeBefore + tag.defaultTimeAfter
                    let timeStartString = secondsToTimeString(startTime)
                    let timeFinishString = secondsToTimeString(finishTime)

                    timelineData.addStampToSelectedLine(
                        idTag: tag.id,
                        name: tag.name,
                        timeStart: timeStartString,
                        timeFinish: timeFinishString,
                        color: tag.color,
                        labels: selectedLabels
                    )
                }
            } else {
                Text("""
                     Тег не может быть добавлен до выбора таймлайна.
                     Выберите его, нажав на название таймлайна.
                     Если таймлайна нет, то сначала создайте его, нажав на 􀁌
                     """)
                .padding()
                .multilineTextAlignment(.center)
            }
        }
    }
}

class TagLibraryWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let view = TagLibraryView()
        let hostingController = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hostingController)
        w.title = "Библиотека тегов"
        super.init(window: w)
        w.styleMask.insert(.closable)
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func windowWillClose(_ notification: Notification) {
        WindowsManager.shared.closeAll()
    }
}

struct AddLineSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var lineName: String = ""
    let onAdd: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Добавить таймлайн")
                .font(.headline)
            TextField("Название таймлайна", text: $lineName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            HStack {
                Button("Отмена") {
                    presentationMode.wrappedValue.dismiss()
                }
                Button("Добавить") {
                    onAdd(lineName)
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(lineName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

struct LabelSelectionSheet: View {
    let stampName: String
    let initialLabels: [String]
    let tag: Tag?
    let tagLibrary: TagLibraryManager
    var isDop: Bool = false
    let onDone: ([String]) -> Void

    @State private var selectedLabels: Set<String> = []
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Таймстемп: \(stampName)")
                .font(.headline)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(filteredLabelGroups) { group in
                        DisclosureGroup(isExpanded: .constant(true)) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)],
                                spacing: 16
                            ) {
                                ForEach(group.lables, id: \.self) { labelID in
                                    if let label = tagLibrary.labels.first(where: { $0.id == labelID }) {
                                        Button {
                                            if selectedLabels.contains(label.id) {
                                                selectedLabels.remove(label.id)
                                            } else {
                                                selectedLabels.insert(label.id)
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(
                                                    systemName: selectedLabels.contains(label.id)
                                                    ? "checkmark.square"
                                                    : "square"
                                                )
                                                Text(label.name)
                                                    .lineLimit(1)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(selectedLabels.contains(label.id)
                                                        ? Color.blue.opacity(0.2)
                                                        : Color.gray.opacity(0.1))
                                            .cornerRadius(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        } label: {
                            Text(group.name)
                                .font(.subheadline)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Отмена") {
                    presentationMode.wrappedValue.dismiss()
                }
                Button("Добавить") {
                    onDone(Array(selectedLabels))
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: isDop ? 0 : 400)
        .onAppear {
            selectedLabels = Set(initialLabels)
        }
    }

    var filteredLabelGroups: [LabelGroupData] {
        if let tag = tag {
            return tagLibrary.labelGroups.filter { tag.lablesGroup.contains($0.id) }
        } else {
            return tagLibrary.labelGroups
        }
    }
}

struct ExportModeSelectionSheet: View {
    let onSelect: (FullControlView.ExportMode) -> Void
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 20) {
            Text("Экспортировать как:")
                .font(.headline)
            HStack(spacing: 20) {
                Button("Фильм") {
                    onSelect(.film)
                    presentationMode.wrappedValue.dismiss()
                }
                Button("Плейлист") {
                    onSelect(.playlist)
                    presentationMode.wrappedValue.dismiss()
                }
            }
            Button("Отмена") {
                presentationMode.wrappedValue.dismiss()
            }
        }
        .padding()
        .frame(width: 300)
    }
}

struct TagSelectionSheetView: View {
    let uniqueTags: [Tag]
    let onSelect: (Tag) -> Void
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Выберите тег для экспорта")
                .font(.headline)
            
            List(tagLibrary.tagGroups) { group in
                Section(header: Text(group.name).font(.subheadline).bold()) {
                    ForEach(group.tags, id: \.self) { tagID in
                        if let tag = tagLibrary.tags.first(where: { $0.id == tagID }), uniqueTags.contains(where: { $0.id == tag.id }) {
                            Button(tag.name) {
                                onSelect(tag)
                            }
                        }
                    }
                }
            }
            .frame(width: 300)
        }
        .padding()
    }
}

// New view for displaying stamp label chips with dynamic font sizing.
struct StampLabelsOverlayView: View {
    let stamp: TimelineStamp
    let maxWidth: CGFloat
    @ObservedObject var tagLibrary = TagLibraryManager.shared

    @State private var displayedLabels: [Label] = []
    @State private var fontSize: CGFloat = 12 // start at 12, can reduce

    var body: some View {
        GeometryReader { proxy in
            let finalWidth = proxy.size.width
            HStack(spacing: 4) {
                ForEach(displayedLabels, id: \.id) { label in
                    LabelChip(label: label, baseColor: stamp.color, fontSize: fontSize)
                }
            }
            .frame(height: proxy.size.height, alignment: .center)
            .onAppear {
                updateDisplayedLabels(finalWidth: finalWidth)
            }
            .onChange(of: finalWidth) { newValue in
                updateDisplayedLabels(finalWidth: newValue)
            }
            .onChange(of: stamp.labels) { _ in
                updateDisplayedLabels(finalWidth: finalWidth)
            }
        }
    }

    private func updateDisplayedLabels(finalWidth: CGFloat) {
        let stampLabels = stamp.labels.compactMap { labelID in
            tagLibrary.labels.first(where: { $0.id == labelID })
        }
        var testFont: CGFloat = 12
        let labelChips = stampLabels.map { LabelChip(label: $0, baseColor: stamp.color, fontSize: testFont) }

        let totalWidthOfAll = labelChips.reduce(0) { partialResult, chip in
            let textWidth = chip.label.name.size(withSystemFontSize: testFont).width + 20 // icon + padding
            return partialResult + textWidth + 4 // spacing
        }
        if totalWidthOfAll <= finalWidth {
            displayedLabels = stampLabels
            fontSize = testFont
            return
        }
        let firstLabelWidth = stampLabels.first.map {
            $0.name.size(withSystemFontSize: testFont).width + 20
        } ?? 0
        if firstLabelWidth > finalWidth {
            testFont = 10
            let newFirstWidth = stampLabels.first.map {
                $0.name.size(withSystemFontSize: testFont).width + 20
            } ?? 0
            if newFirstWidth > finalWidth {
                displayedLabels = []
                return
            } else {
                displayedLabels = [stampLabels.first!]
                fontSize = testFont
                return
            }
        } else {
            var listToShow: [Label] = []
            var currentWidth: CGFloat = 0
            for lb in stampLabels {
                let neededWidth = lb.name.size(withSystemFontSize: testFont).width + 20 + 4
                if currentWidth + neededWidth <= finalWidth {
                    listToShow.append(lb)
                    currentWidth += neededWidth
                } else {
                    break
                }
            }
            displayedLabels = listToShow
            fontSize = testFont
        }
    }
}

extension String {
    func size(withSystemFontSize fontSize: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attString = NSAttributedString(string: self, attributes: attributes)
        let rect = attString.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin
        )
        return rect.size
    }
}

struct LabelChip: View {
    let label: Label
    let baseColor: Color
    let fontSize: CGFloat

    var body: some View {
        let textColor = baseColor.isDark ? Color.white : Color.black
        let backgroundColor = baseColor.darken(by: 0.2)
        HStack(spacing: 3) {
            Image(systemName: "tag.fill")
            Text(label.name)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor)
        .cornerRadius(8)
        .foregroundColor(textColor)
        .font(.system(size: fontSize))
    }
}

extension Color {
    func darken(by amount: CGFloat) -> Color {
        let uiColor = NSColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        brightness = max(brightness - amount, 0)
        return Color(hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness), opacity: Double(alpha))
    }
}
