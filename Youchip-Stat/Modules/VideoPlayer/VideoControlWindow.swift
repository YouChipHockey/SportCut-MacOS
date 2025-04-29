import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

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
    
    // The currently displayed collection data
    @Published var tags: [Tag] = []
    @Published var tagGroups: [TagGroup] = []
    @Published var labelGroups: [LabelGroupData] = []
    @Published var labels: [Label] = []
    @Published var timeEvents: [TimeEvent] = []
    
    // Global pools containing data from all collections
    @Published var allTags: [Tag] = []
    @Published var allTagGroups: [TagGroup] = []
    @Published var allLabelGroups: [LabelGroupData] = []
    @Published var allLabels: [Label] = []
    @Published var allTimeEvents: [TimeEvent] = []
    
    // Track selected time events
    @Published var selectedTimeEvents: Set<String> = []
    
    // Add default data storage for proper restoration
    private var defaultTags: [Tag] = []
    private var defaultTagGroups: [TagGroup] = []
    private var defaultLabelGroups: [LabelGroupData] = []
    private var defaultLabels: [Label] = []
    private var defaultTimeEvents: [TimeEvent] = []
    
    // Add property to track current collection
    @Published var currentCollectionType: TagCollection = .standard
    
    private init() {
        // Load standard collection
        if let loadedTags: TagsData = loadJSON(filename: "tags.json") {
            self.tags = loadedTags.tags
            self.defaultTags = loadedTags.tags  // Store default data
        }
        if let loadedTagGroups: TagGroupsData = loadJSON(filename: "tagsGroups.json") {
            self.tagGroups = loadedTagGroups.tagGroups
            self.defaultTagGroups = loadedTagGroups.tagGroups  // Store default data
        }
        if let loadedLabelGroups: LabelGroupsData = loadJSON(filename: "labelsGroups.json") {
            self.labelGroups = loadedLabelGroups.labelGroups
            self.defaultLabelGroups = loadedLabelGroups.labelGroups  // Store default data
        }
        if let loadedLabels: LabelsData = loadJSON(filename: "labels.json") {
            self.labels = loadedLabels.labels
            self.defaultLabels = loadedLabels.labels  // Store default data
        }
        // Load time events from standard collection
        if let loadedTimeEvents: TimeEventsData = loadJSON(filename: "timeEvents.json") {
            self.timeEvents = loadedTimeEvents.events
            self.defaultTimeEvents = loadedTimeEvents.events  // Store default data
        }
        
        // Initialize all pools with standard collection
        allTags = tags
        allTagGroups = tagGroups
        allLabelGroups = labelGroups
        allLabels = labels
        allTimeEvents = timeEvents
        
        // Load and merge all user collections
        loadAllUserCollections()
    }
    
    // Find tags and labels by ID from the global pool
    func findTagById(_ id: String) -> Tag? {
        return allTags.first(where: { $0.id == id })
    }
    
    func findLabelById(_ id: String) -> Label? {
        return allLabels.first(where: { $0.id == id })
    }
    
    // Find all labels for a specific tag from the global pool
    func findLabelsForTag(_ tag: Tag) -> [Label] {
        let labelGroupIds = tag.lablesGroup
        let relevantLabelIds = allLabelGroups.filter { labelGroupIds.contains($0.id) }
            .flatMap { $0.lables }
        return allLabels.filter { label in relevantLabelIds.contains(label.id) }
    }
    
    // Load all user collections and merge them into the global pools
    private func loadAllUserCollections() {
        let userCollections = UserDefaults.standard.getCollectionBookmarks()
        
        for collection in userCollections {
            let collectionManager = CustomCollectionManager()
            if collectionManager.loadCollectionFromBookmarks(named: collection.name) {
                // Add to global pools
                allTags.append(contentsOf: collectionManager.tags)
                allTagGroups.append(contentsOf: collectionManager.tagGroups)
                allLabelGroups.append(contentsOf: collectionManager.labelGroups)
                allLabels.append(contentsOf: collectionManager.labels)
                allTimeEvents.append(contentsOf: collectionManager.timeEvents)
            }
        }
        
        // Remove duplicates based on ID
        allTags = Array(Dictionary(grouping: allTags, by: { $0.id }).values.compactMap { $0.first })
        allTagGroups = Array(Dictionary(grouping: allTagGroups, by: { $0.id }).values.compactMap { $0.first })
        allLabelGroups = Array(Dictionary(grouping: allLabelGroups, by: { $0.id }).values.compactMap { $0.first })
        allLabels = Array(Dictionary(grouping: allLabels, by: { $0.id }).values.compactMap { $0.first })
        allTimeEvents = Array(Dictionary(grouping: allTimeEvents, by: { $0.id }).values.compactMap { $0.first })
    }
    
    // Find or create a time event
    func findOrCreateTimeEvent(id: String, name: String) -> TimeEvent {
        if let existingEvent = allTimeEvents.first(where: { $0.id == id }) {
            return existingEvent
        } else {
            let newEvent = TimeEvent(id: id, name: name)
            allTimeEvents.append(newEvent)
            return newEvent
        }
    }
    
    // Toggle selection state of a time event
    func toggleTimeEvent(id: String) {
        if selectedTimeEvents.contains(id) {
            selectedTimeEvents.remove(id)
        } else {
            selectedTimeEvents.insert(id)
        }
    }
    
    // Refresh the global pools (call when collections are added/modified)
    func refreshGlobalPools() {
        // Save current standard collection
        let standardTags = tags
        let standardTagGroups = tagGroups
        let standardLabelGroups = labelGroups
        let standardLabels = labels
        let standardTimeEvents = timeEvents
        
        // Reset global pools to standard collection
        allTags = standardTags
        allTagGroups = standardTagGroups
        allLabelGroups = standardLabelGroups
        allLabels = standardLabels
        allTimeEvents = standardTimeEvents
        
        // Add all user collections to global pools
        loadAllUserCollections()
        
        // Apply hotkeys from the newly refreshed global pool
        applyHotkeysFromCurrentCollection()
    }
    
    // Add method to restore default data
    func restoreDefaultData() {
        // Restore default data to current display
        tags = defaultTags
        tagGroups = defaultTagGroups
        labelGroups = defaultLabelGroups
        labels = defaultLabels
        timeEvents = defaultTimeEvents
        
        // Set current collection type to standard
        currentCollectionType = .standard
        
        // Clear selected time events
        selectedTimeEvents.removeAll()
        
        // Refresh global pools
        refreshGlobalPools()
    }
    
    // Add method to apply hotkeys from current tags
    func applyHotkeysFromCurrentCollection() {
        // Only register hotkeys from the current active collection
        HotKeyManager.shared.clearHotkeys() // First clear any existing hotkeys
        HotKeyManager.shared.registerHotkeys(from: tags, for: currentCollectionType)
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
    
    // Add darken method that was missing
    func darken(by amount: CGFloat) -> Color {
        let uiColor = NSColor(self)
        guard let adjustedColor = uiColor.adjustBrightness(by: -amount) else {
            return self
        }
        return Color(adjustedColor)
    }
}

// Helper extension for NSColor to adjust brightness
extension NSColor {
    func adjustBrightness(by amount: CGFloat) -> NSColor? {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        self.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        b = max(0, min(1, b + amount))
        return NSColor(hue: h, saturation: s, brightness: b, alpha: a)
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
    var timeEvents: [String] // Added timeEvents array to store selected event IDs
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
    init(id: UUID = UUID(), idTag: String, timeStart: String, timeFinish: String, colorHex: String, label: String, labels: [String], timeEvents: [String] = []) {
        self.id = id
        self.idTag = idTag
        self.timeStart = timeStart
        self.timeFinish = timeFinish
        self.colorHex = colorHex
        self.label = label
        self.labels = labels
        self.timeEvents = timeEvents
    }
}

// MARK: - Менеджер таймлайнов

class TimelineDataManager: ObservableObject {
    static let shared = TimelineDataManager()
    @Published var lines: [TimelineLine] = []
    @Published var selectedLineID: UUID? = nil
    @Published var selectedStampID: UUID? = nil  // Track the selected stamp
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
    func selectStamp(stampID: UUID?) {
        selectedStampID = stampID
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
        
        // Get currently selected time events
        let selectedEvents = Array(TagLibraryManager.shared.selectedTimeEvents)
        
        let stamp = TimelineStamp(
            idTag: idTag, 
            timeStart: timeStart, 
            timeFinish: timeFinish, 
            colorHex: color, 
            label: name, 
            labels: labels,
            timeEvents: selectedEvents
        )
        lines[idx].stamps.append(stamp)
        updateTimelines()
    }
    func updateStampLabels(lineID: UUID, stampID: UUID, newLabels: [String]) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        guard let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else { return }
        lines[lineIndex].stamps[stampIndex].labels = newLabels
        updateTimelines()
    }
    
    // Check if a stamp overlaps with other stamps in its timeline
    func stampHasOverlaps(lineID: UUID, stampID: UUID) -> Bool {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              let stamp = lines[lineIndex].stamps.first(where: { $0.id == stampID }) else {
            return false
        }
        
        return lines[lineIndex].stamps.contains { otherStamp in
            guard otherStamp.id != stampID else { return false }
            
            // Check for time overlap
            let stampStart = stamp.startSeconds
            let stampEnd = stamp.finishSeconds
            let otherStart = otherStamp.startSeconds
            let otherEnd = otherStamp.finishSeconds
            
            // Overlap occurs when one stamp starts before the other ends
            return (stampStart < otherEnd && otherStart < stampEnd)
        }
    }
    
    // Update stamp time boundaries
    func updateStampTime(lineID: UUID, stampID: UUID, newStart: Double? = nil, newEnd: Double? = nil) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else {
            return
        }
        
        var stamp = lines[lineIndex].stamps[stampIndex]
        
        if let newStartTime = newStart {
            // Ensure we don't make the stamp shorter than 0.5 seconds
            let limitedStart = min(newStartTime, stamp.finishSeconds - 0.5)
            stamp.timeStart = secondsToTimeString(limitedStart)
        }
        
        if let newEndTime = newEnd {
            // Ensure we don't make the stamp shorter than 0.5 seconds
            let limitedEnd = max(newEndTime, stamp.startSeconds + 0.5)
            stamp.timeFinish = secondsToTimeString(limitedEnd)
        }
        
        lines[lineIndex].stamps[stampIndex] = stamp
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
    
    // New function to get frame rate if available
    func getCurrentFrameRate() -> Float {
        guard let player = player,
              let asset = player.currentItem?.asset,
              let track = asset.tracks(withMediaType: .video).first else {
            return 30 // Default to standard frame rate
        }
        
        return track.nominalFrameRate
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


struct FullControlView: View {
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    @ObservedObject var focusManager = FocusStateManager.shared
    @ObservedObject var hotkeyManager = HotKeyManager.shared // Add hotkey manager
    
    @State private var sliderValue: Double = 0.0
    @State private var isDraggingSlider = false
    @State private var showAddLineSheet = false
    @State private var isExporting: Bool = false
    @State private var showLabelEditSheet = false
    @State private var editingStampLineID: UUID?
    @State private var editingStampID: UUID?
    @State private var timelineScale: CGFloat = 1.0
    @GestureState private var magnifyScale: CGFloat = 1.0
    @State private var keyEventMonitor: Any?
    
    private func setupKeyboardShortcuts() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't process keyboard shortcuts if any text field is focused
            if focusManager.isAnyTextFieldFocused {
                return event
            }
            
            switch event.keyCode {
            case 53: // ESC key
                // Clear the selection
                timelineData.selectStamp(stampID: nil)
                return nil
            case 51: // DELETE key
                // Only respond to Option+Delete combination for tag deletion
                if event.modifierFlags.contains(.option) {
                    if let stampID = timelineData.selectedStampID {
                        // Find which line contains this stamp
                        for line in timelineData.lines {
                            if line.stamps.contains(where: { $0.id == stampID }) {
                                timelineData.removeStamp(lineID: line.id, stampID: stampID)
                                break
                            }
                        }
                        return nil // Consume the event
                    }
                }
                return event // Let regular delete behavior pass through
            default:
                return event
            }
        }
    }
    
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
                setupKeyboardShortcuts()
            }
            .onDisappear {
                if let monitor = keyEventMonitor {
                    NSEvent.removeMonitor(monitor)
                }
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
                let fullTag = tagLibrary.findTagById(stamp.idTag) ?? Tag(id: "", name: stamp.label, description: "", color: "FFFFFF", defaultTimeBefore: 0, defaultTimeAfter: 0, collection: "", lablesGroup: [], hotkey: "", labelHotkeys: [:])
                let fullLabels = stamp.labels.compactMap { labelID in
                    tagLibrary.findLabelById(labelID)
                }
                let fullTimeEvents = stamp.timeEvents.compactMap { eventID in
                    tagLibrary.allTimeEvents.first(where: { $0.id == eventID })
                }
                return FullTimelineStamp(id: stamp.id, timeStart: stamp.timeStart, timeFinish: stamp.timeFinish, tag: fullTag, labels: fullLabels, timeEvents: fullTimeEvents)
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

struct TimelineLineView: View {
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    
    let line: TimelineLine
    
    // Новое поле: масштаб
    let scale: CGFloat
    
    let isSelected: Bool
    let onSelect: () -> Void
    let onEditLabelsRequest: (UUID) -> Void
    
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    
    // Drag-n-drop state
    @State private var isDraggingOver = false
    
    // Resizing state
    @State private var isResizing = false
    @State private var resizingSide: ResizingSide = .none
    @State private var initialDragLocation: CGPoint = .zero
    @State private var initialStartTime: Double = 0
    @State private var initialEndTime: Double = 0
    
    // State for editing timeline name
    @State private var showEditNameSheet = false
    
    enum ResizingSide {
        case left, right, none
    }
    
    // Function to check if a stamp overlaps with older stamps
    // Returns the number of overlaps with older stamps
    private func getOverlapCount(stamp: TimelineStamp, stamps: [TimelineStamp], stampIndex: Int) -> Int {
        var count = 0
        
        for i in 0..<stampIndex {
            let olderStamp = stamps[i]
            
            let stampStart = stamp.startSeconds
            let stampEnd = stamp.finishSeconds
            let olderStart = olderStamp.startSeconds
            let olderEnd = olderStamp.finishSeconds
            
            // Check for overlap with older stamp
            if stampStart < olderEnd && olderStart < stampEnd {
                count += 1
            }
        }
        
        return count
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(line.name)
                        .font(.headline)
                        .padding(4)
                        .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(4)
                        .onTapGesture { onSelect() }
                    
                    Button(action: {
                        showEditNameSheet = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Редактировать название таймлайна")
                }
                .contextMenu {
                    Button("Редактировать название") {
                        showEditNameSheet = true
                    }
                    Button("Удалить таймлайн") {
                        // First check if this is the selected timeline
                        let isSelectedLine = (TimelineDataManager.shared.selectedLineID == line.id)
                        
                        // Remove the timeline
                        TimelineDataManager.shared.lines.removeAll { $0.id == line.id }
                        
                        // If we just removed the selected timeline, clear the selection
                        if isSelectedLine {
                            TimelineDataManager.shared.selectedLineID = nil
                        }
                        
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
                                .fill(isDraggingOver ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                .frame(width: computedWidth, height: 30)
                                .onDrop(
                                    of: [.init(UTType.plainText.identifier)],
                                    isTargeted: $isDraggingOver
                                ) { providers, _ in
                                    if let provider = providers.first {
                                        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { (data, error) in
                                            if let stampData = data as? Data,
                                               let stampInfo = try? JSONDecoder().decode(StampDragInfo.self, from: stampData) {
                                                DispatchQueue.main.async {
                                                    transferStamp(stampInfo, to: line.id)
                                                }
                                            }
                                        }
                                        return true
                                    }
                                    return false
                                }
                                .onTapGesture {
                                    // Clear selection when clicking timeline background
                                    timelineData.selectStamp(stampID: nil)
                                }
                            
                            // We need to preserve the original order of stamps because newer stamps 
                            // should appear on top but be shorter
                            ForEach(Array(line.stamps.enumerated()), id: \.element.id) { index, stamp in
                                let startRatio = stamp.startSeconds / totalDuration
                                let durationRatio = stamp.duration / totalDuration
                                
                                let stampWidth = durationRatio * computedWidth
                                let stampX = startRatio * computedWidth
                                
                                let isSelected = timelineData.selectedStampID == stamp.id
                                
                                // Calculate how many older stamps this one overlaps with
                                let overlapCount = getOverlapCount(stamp: stamp, stamps: line.stamps, stampIndex: index)
                                let hasOverlaps = overlapCount > 0
                                
                                // Determine border color based on selection and overlap
                                let borderColor = (hasOverlaps && !isSelected) ? Color.red : 
                                                  (isSelected && hasOverlaps) ? Color.red : 
                                                  (isSelected) ? Color.blue : Color.clear
                                
                                // Reduce height by 6 pixels for each overlapping older stamp
                                let heightReduction = CGFloat(overlapCount * 6)
                                let stampHeight: CGFloat = 30 - heightReduction
                                
                                // Calculate vertical position - center in the timeline
                                let verticalOffset = (30 - stampHeight) / 2
                                
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(stamp.color)
                                        .frame(height: stampHeight)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 2)
                                                .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
                                        )
                                    
                                    // Pass isResizing state to StampLabelsOverlayView
                                    StampLabelsOverlayView(
                                        stamp: stamp, 
                                        maxWidth: stampWidth,
                                        isResizing: isResizing
                                    )
                                    .frame(height: stampHeight)
                                    
                                    if isSelected {
                                        
                                        // Right resize handle
                                        Rectangle()
                                            .fill(borderColor)
                                            .frame(width: 8, height: stampHeight)
                                            .contentShape(Rectangle().size(width: 10, height: stampHeight))
                                            .position(x: stampWidth - 2, y: stampHeight/2)
                                            .onHover { hovering in
                                                if hovering && !isResizing {
                                                    NSCursor.resizeLeftRight.push()
                                                } else if !hovering && !isResizing {
                                                    NSCursor.pop()
                                                }
                                            }
                                            .gesture(
                                                DragGesture()
                                                    .onChanged { value in
                                                        if (!isResizing) {
                                                            // Start resizing
                                                            isResizing = true
                                                            resizingSide = .right
                                                            initialDragLocation = CGPoint(x: value.location.x, y: value.location.y)
                                                            initialStartTime = stamp.startSeconds
                                                            initialEndTime = stamp.finishSeconds
                                                            NSCursor.resizeLeftRight.push()
                                                        } else if resizingSide == .right {
                                                            // Continue resizing
                                                            let dragDelta = value.location.x - initialDragLocation.x
                                                            let timeDelta = (dragDelta / computedWidth) * totalDuration
                                                            let newEndTime = initialEndTime + timeDelta
                                                            
                                                            if newEndTime > initialStartTime + 1 {
                                                                timelineData.updateStampTime(
                                                                    lineID: line.id, 
                                                                    stampID: stamp.id, 
                                                                    newEnd: newEndTime
                                                                )
                                                            }
                                                        }
                                                    }
                                                    .onEnded { _ in
                                                        isResizing = false
                                                        resizingSide = .none
                                                        NSCursor.pop()
                                                    }
                                            )
                                        
                                        Rectangle()
                                            .fill(borderColor)
                                            .frame(width: 8, height: stampHeight)
                                            .contentShape(Rectangle().size(width: 10, height: stampHeight))
                                            .position(x: 2, y: stampHeight/2)
                                            .onHover { hovering in
                                                if hovering && !isResizing {
                                                    NSCursor.resizeLeftRight.push()
                                                } else if !hovering && !isResizing {
                                                    NSCursor.pop()
                                                }
                                            }
                                            .gesture(
                                                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                                                    .onChanged { value in
                                                        if (!isResizing) {
                                                            // Start resizing
                                                            isResizing = true
                                                            resizingSide = .left
                                                            initialDragLocation = value.startLocation
                                                            initialStartTime = stamp.startSeconds
                                                            initialEndTime = stamp.finishSeconds
                                                            NSCursor.resizeLeftRight.push()
                                                        } else if resizingSide == .left {
                                                            // Continue resizing left side only
                                                            let dragDelta = value.location.x - value.startLocation.x
                                                            let timeDelta = (dragDelta / computedWidth) * totalDuration
                                                            let newStartTime = initialStartTime + timeDelta
                                                            
                                                            // Only update if we don't make it too short
                                                            if newStartTime < initialEndTime - 1 {
                                                                timelineData.updateStampTime(
                                                                    lineID: line.id,
                                                                    stampID: stamp.id,
                                                                    newStart: newStartTime
                                                                )
                                                            }
                                                        }
                                                    }
                                                    .onEnded { _ in
                                                        isResizing = false
                                                        resizingSide = .none
                                                        NSCursor.pop()
                                                    }
                                            )
                                    }
                                }
                                .frame(width: stampWidth, height: stampHeight)
                                .position(x: stampX + stampWidth / 2, y: 15)
                                .onTapGesture {
                                    // Seek to the timestamp and select it
                                    videoManager.seek(to: stamp.startSeconds)
                                    timelineData.selectStamp(stampID: stamp.id)
                                }
                                .onDrag {
                                    let stampInfo = StampDragInfo(
                                        lineID: line.id,
                                        stampID: stamp.id
                                    )
                                    if let data = try? JSONEncoder().encode(stampInfo) {
                                        return NSItemProvider(item: data as NSData, typeIdentifier: UTType.plainText.identifier)
                                    }
                                    return NSItemProvider()
                                }
                                .contextMenu {
                                    Text("Тег: \(stamp.label)")
                                    if !stamp.labels.isEmpty {
                                        ForEach(stamp.labels, id: \.self) { labelID in
                                            if let label = tagLibrary.findLabelById(labelID) {
                                                if let group = tagLibrary.allLabelGroups.first(where: { $0.lables.contains(label.id) }) {
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
                                        if timelineData.selectedStampID == stamp.id {
                                            timelineData.selectStamp(stampID: nil)
                                        }
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
        .sheet(isPresented: $showEditNameSheet) {
            EditTimelineNameSheet(lineName: line.name) { newName in
                if let index = timelineData.lines.firstIndex(where: { $0.id == line.id }) {
                    timelineData.lines[index].name = newName
                    timelineData.updateTimelines()
                }
            }
        }
    }
    
    private func transferStamp(_ stampInfo: StampDragInfo, to destLineID: UUID) {
        guard let sourceLineIndex = timelineData.lines.firstIndex(where: { $0.id == stampInfo.lineID }),
              let destLineIndex = timelineData.lines.firstIndex(where: { $0.id == destLineID }),
              let stampIndex = timelineData.lines[sourceLineIndex].stamps.firstIndex(where: { $0.id == stampInfo.stampID }) else {
            return
        }
        
        if stampInfo.lineID == destLineID {
            return
        }
        
        let stamp = timelineData.lines[sourceLineIndex].stamps[stampIndex]
        
        let newStamp = TimelineStamp(
            id: UUID(), // Новый ID для нового тега
            idTag: stamp.idTag,
            timeStart: stamp.timeStart,
            timeFinish: stamp.timeFinish,
            colorHex: stamp.colorHex,
            label: stamp.label,
            labels: stamp.labels
        )
        
        timelineData.lines[destLineIndex].stamps.append(newStamp)
        timelineData.lines[sourceLineIndex].stamps.remove(at: stampIndex)
        timelineData.updateTimelines()
    }
}

struct StampDragInfo: Codable {
    let lineID: UUID
    let stampID: UUID
}

// MARK: - Hotkey Manager
class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
        
        private var localMonitorForKeyEvents: Any?
        private var globalMonitorForKeyEvents: Any?
        private var registeredHotkeys: [String: Tag] = [:] // Maps hotkey to tag
        private var registeredLabelHotkeys: [String: (labelId: String, tagId: String)] = [:] // Maps hotkey to label ID and tag ID
        
        @Published var isEnabled = true
        @Published var hotKeySelectedTag: Tag? = nil
        @Published var hotKeySelectedLabelId: String? = nil
        @Published var isLabelHotkeyMode = false // Track if we're in label hotkey mode
        @Published var blockedSheetActive = false // Track if a sheet that should block hotkeys is active
        private var activeCollection: TagCollection = .standard // Track the active collection
        
        private init() {
            setupKeyboardMonitoring()
            
            // Listen for sheets being presented/dismissed
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(sheetWillAppear),
                name: NSWindow.willBeginSheetNotification,
                object: nil
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(sheetDidDisappear),
                name: NSWindow.didEndSheetNotification,
                object: nil
            )
            
            // Register to listen for specific sheet notifications
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(addLineSheetAppeared),
                name: NSNotification.Name("AddLineSheetAppeared"),
                object: nil
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(editTimelineSheetAppeared),
                name: NSNotification.Name("EditTimelineSheetAppeared"),
                object: nil
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(sheetDismissed),
                name: NSNotification.Name("SheetDismissed"),
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(collectionEditorOpened),
                name: .collectionEditorOpened,
                object: nil
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(collectionEditorClosed),
                name: .collectionEditorClosed,
                object: nil
            )
        }

        // Add these methods to HotKeyManager
        @objc private func collectionEditorOpened() {
            isEnabled = false
            print("HotKey manager disabled: Collection editor opened")
        }

        @objc private func collectionEditorClosed() {
            isEnabled = true
            print("HotKey manager enabled: Collection editor closed")
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc private func sheetWillAppear(_ notification: Notification) {
            // We no longer set a general flag here
            // Only specific sheets will block hotkeys
        }
        
        @objc private func sheetDidDisappear(_ notification: Notification) {
            // We'll handle this through the specific notifications instead
        }
        
        @objc private func addLineSheetAppeared() {
            blockedSheetActive = true
        }
        
        @objc private func editTimelineSheetAppeared() {
            blockedSheetActive = true
        }
        
        @objc private func sheetDismissed() {
            blockedSheetActive = false
        }
        
    func setupKeyboardMonitoring() {
        removeMonitors()
        
        localMonitorForKeyEvents = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  self.isEnabled,
                  !self.blockedSheetActive, // Check this flag instead of activeSheetPresented
                  !FocusStateManager.shared.isAnyTextFieldFocused else {
                return event
            }
            return self.handleHotkey(event) ? nil : event
        }
    }
        
        private func removeMonitors() {
            if let localMonitor = localMonitorForKeyEvents {
                NSEvent.removeMonitor(localMonitor)
                localMonitorForKeyEvents = nil
            }
        }
        
        private func handleHotkey(_ event: NSEvent) -> Bool {
            let hotkeyString = hotkeyStringFromEvent(event)
            
            if isLabelHotkeyMode {
                // When in label hotkey mode, check for label hotkeys
                if let labelInfo = registeredLabelHotkeys[hotkeyString] {
                    hotKeySelectedLabelId = labelInfo.labelId
                    NotificationCenter.default.post(name: .labelHotkeyPressed, object: labelInfo)
                    return true
                }
            } else {
                // Regular tag hotkey mode
                if let tag = registeredHotkeys[hotkeyString] {
                    DispatchQueue.main.async {
                        self.selectTag(tag)
                    }
                    return true
                }
            }
            return false
        }
    
    func registerHotkeys(from tags: [Tag], for collection: TagCollection) {
        // Clear existing hotkeys
        registeredHotkeys.removeAll()
        registeredLabelHotkeys.removeAll()
        activeCollection = collection
        
        // Register hotkeys for the provided tags
        for tag in tags {
            if let hotkey = tag.hotkey, !hotkey.isEmpty {
                registeredHotkeys[hotkey.lowercased()] = tag
            }
            
            // Also register label hotkeys, but they'll only be used when in label hotkey mode
            if let labelHotkeys = tag.labelHotkeys {
                for (labelId, hotkey) in labelHotkeys {
                    if !hotkey.isEmpty {
                        registeredLabelHotkeys[hotkey.lowercased()] = (labelId: labelId, tagId: tag.id)
                    }
                }
            }
        }
        
        print("Registered tag hotkeys for \(collection): \(registeredHotkeys.keys.joined(separator: ", "))")
        print("Registered label hotkeys for \(collection): \(registeredLabelHotkeys.keys.joined(separator: ", "))")
    }
    
    func clearHotkeys() {
        registeredHotkeys.removeAll()
        registeredLabelHotkeys.removeAll()
    }
    
    private func hotkeyStringFromEvent(_ event: NSEvent) -> String {
        var components: [String] = []
        
        // Add modifier keys
        if event.modifierFlags.contains(.control) { components.append("ctrl") }
        if event.modifierFlags.contains(.option) { components.append("alt") }
        if event.modifierFlags.contains(.shift) { components.append("shift") }
        if event.modifierFlags.contains(.command) { components.append("cmd") }
        
        // Use keyCode instead of character representation
        // This ensures layout independence
        let keyCode = event.keyCode
        
        // Map common key codes to their English representations
        let keyChar: String
        switch keyCode {
        case 0: keyChar = "a"
        case 1: keyChar = "s"
        case 2: keyChar = "d"
        case 3: keyChar = "f"
        case 4: keyChar = "h"
        case 5: keyChar = "g"
        case 6: keyChar = "z"
        case 7: keyChar = "x"
        case 8: keyChar = "c"
        case 9: keyChar = "v"
        case 11: keyChar = "b"
        case 12: keyChar = "q"
        case 13: keyChar = "w"
        case 14: keyChar = "e"
        case 15: keyChar = "r"
        case 16: keyChar = "y"
        case 17: keyChar = "t"
        case 18: keyChar = "1"
        case 19: keyChar = "2"
        case 20: keyChar = "3"
        case 21: keyChar = "4"
        case 22: keyChar = "6"
        case 23: keyChar = "5"
        case 24: keyChar = "="
        case 25: keyChar = "9"
        case 26: keyChar = "7"
        case 27: keyChar = "-"
        case 28: keyChar = "8"
        case 29: keyChar = "0"
        case 30: keyChar = "]"
        case 31: keyChar = "o"
        case 32: keyChar = "u"
        case 33: keyChar = "["
        case 34: keyChar = "i"
        case 35: keyChar = "p"
        case 37: keyChar = "l"
        case 38: keyChar = "j"
        case 39: keyChar = "'"
        case 40: keyChar = "k"
        case 41: keyChar = ";"
        case 42: keyChar = "\\"
        case 43: keyChar = ","
        case 44: keyChar = "/"
        case 45: keyChar = "n"
        case 46: keyChar = "m"
        case 47: keyChar = "."
        case 50: keyChar = "`"
        default:
            // For any other keys, use a special format
            keyChar = "key-\(keyCode)"
        }
        
        components.append(keyChar)
        return components.joined(separator: "+")
    }
    
    private func selectTag(_ tag: Tag) {
        print("Hotkey activated for tag: \(tag.name)")
        VideoPlayerManager.shared.player?.pause()
        NotificationCenter.default.post(name: .showLabelSheet, object: tag)
    }
    
    // Add these methods to control label hotkey mode
    func enableLabelHotkeyMode() {
        isLabelHotkeyMode = true
        print("Switched to label hotkey mode")
    }
    
    func disableLabelHotkeyMode() {
        isLabelHotkeyMode = false
        hotKeySelectedLabelId = nil
        print("Switched back to tag hotkey mode")
    }
}

// Add a new notification name for showing the label sheet
extension Notification.Name {
    static let showLabelSheet = Notification.Name("showLabelSheet")
    static let labelHotkeyPressed = Notification.Name("labelHotkeyPressed")
}

struct TagLibraryView: View {
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @ObservedObject var hotkeyManager = HotKeyManager.shared
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    @State private var activeCollection: TagCollection = .standard
    
    @State private var showLabelSheet = false
    @State private var selectedTag: Tag? = nil
    @State private var hoveredTagID: String? = nil
    @State private var showUserCollectionsMenu = false
    @State private var userCollections: [CollectionBookmark] = []
    @State private var selectedUserCollection: CollectionBookmark? = nil
    @State private var isUserCollectionActive = false
    @State private var defaultTagGroups: [TagGroup] = []
    @State private var defaultTags: [Tag] = []
    @State private var defaultLabelGroups: [LabelGroupData] = []
    @State private var defaultLabels: [Label] = []
    @State private var defaultTimeEvents: [TimeEvent] = []
    @State private var showDeleteAlert = false
    @State private var collectionToDelete: CollectionBookmark? = nil
    @State private var showCollectionsList = false // Added to control the display of collections list for older macOS

    func loadUserCollections() {
        userCollections = UserDefaults.standard.getCollectionBookmarks()
    }
    
    func backupDefaultData() {
        // This function is now redundant as defaults are stored in TagLibraryManager
    }
    
    func restoreDefaultData() {
        // Use the shared TagLibraryManager's method instead
        tagLibrary.restoreDefaultData()
        hotkeyManager.registerHotkeys(from: tagLibrary.tags, for: .standard)
    }

    var body: some View {
        VStack(alignment: .leading) {
            // Check macOS version and display appropriate UI
            if #available(macOS 14.0, *) {
                modernHeaderView
            } else {
                legacyHeaderView
            }
            
            // Tag groups and events content
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    timeEventsSection
                    tagGroupsSection
                }
            }
            
            // Show collections list as a sheet for older macOS
            if !showUserCollectionsMenu, showCollectionsList {
                legacyCollectionsListView
                    .background(Color(.windowBackgroundColor))
                    .frame(height: 300)
            }
        }
        .sheet(isPresented: $showLabelSheet) {
            stampLabelSheet
        }
        .onAppear(perform: onAppearSetup)
        .onDisappear(perform: onDisappearCleanup)
        .alert(isPresented: $showDeleteAlert) {
            deleteCollectionAlert
        }
    }
    
    // MARK: - Modern UI Components (macOS 14+)
    
    private var modernHeaderView: some View {
        HStack {
            collectionTitleView
            Spacer()
            collectionsMenuButton
        }
        .padding(.horizontal)
    }
    
    // Common components shared between both UI versions
    
    private var collectionTitleView: some View {
        HStack {
            Text(isUserCollectionActive ? 
                 "Пользовательская коллекция: \(selectedUserCollection?.name ?? "")" : 
                 "Группы тегов")
                .font(.headline)
            
            if isUserCollectionActive && selectedUserCollection != nil {
                collectionActionButtons
            }
        }
    }
    
    private var collectionActionButtons: some View {
        HStack(spacing: 8) {
            Button(action: {
                guard let collection = selectedUserCollection else { return }
                WindowsManager.shared.openCustomCollectionsWindow(withExistingCollection: collection)
            }) {
                Image(systemName: "pencil.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .help("Редактировать коллекцию")
            
            Button(action: {
                collectionToDelete = selectedUserCollection
                showDeleteAlert = true
            }) {
                Image(systemName: "trash.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Удалить коллекцию")
        }
    }
    
    private var collectionsMenuButton: some View {
        Menu {
            createCollectionButton
            Divider()
            standardCollectionButton
            userCollectionsSection
        } label: {
            HStack {
                Image(systemName: "folder.badge.plus")
                Text("Коллекции")
            }
        }
        .buttonStyle(.borderless)
        .help("Управление пользовательскими коллекциями тегов")
    }
    
    private var createCollectionButton: some View {
        Button(action: {
            WindowsManager.shared.openCustomCollectionsWindow()
        }) {
            HStack {
                Image(systemName: "plus")
                Text("Создать коллекцию")
            }
        }
    }
    
    private var standardCollectionButton: some View {
        Button(action: {
            isUserCollectionActive = false
            restoreDefaultData()
            selectedUserCollection = nil
        }) {
            HStack {
                Text("Стандартная коллекция")
                Spacer()
                if !isUserCollectionActive {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
    
    @ViewBuilder
    private var userCollectionsSection: some View {
        if !userCollections.isEmpty {
            Divider()
            Text("Пользовательские коллекции")
            
            ForEach(userCollections, id: \.name) { collection in
                userCollectionRow(for: collection)
            }
        }
    }
    
    private func userCollectionRow(for collection: CollectionBookmark) -> some View {
        HStack {
            Button(action: {
                selectedUserCollection = collection
                isUserCollectionActive = true
                loadUserCollection(collection)
            }) {
                HStack {
                    Text(collection.name)
                    Spacer()
                    if isUserCollectionActive && selectedUserCollection?.name == collection.name {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            // Context menu button
            Menu {
                Button(action: {
                    WindowsManager.shared.openCustomCollectionsWindow(withExistingCollection: collection)
                }) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Редактировать")
                    }
                }
                
                Button(action: {
                    collectionToDelete = collection
                    showDeleteAlert = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Удалить")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
        }
    }
    
    // MARK: - Legacy UI Components (macOS 13 and below)
    
    private var legacyHeaderView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                collectionTitleView
                Spacer()
                // Simple button that shows/hides the collections list
                Button(action: {
                    showCollectionsList.toggle()
                }) {
                    HStack {
                        Image(systemName: showCollectionsList ? "folder.badge.minus" : "folder.badge.plus")
                        Text("Коллекции")
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
        }
    }
    
    private var legacyCollectionsListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Управление коллекциями")
                    .font(.headline)
                Spacer()
                Button(action: {
                    showCollectionsList = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.borderless)
            }
            
            Divider()
            
            Button(action: {
                WindowsManager.shared.openCustomCollectionsWindow()
                showCollectionsList = false
            }) {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Создать новую коллекцию")
                    Spacer()
                }
                .padding(5)
            }
            .buttonStyle(.borderless)
            
            Button(action: {
                isUserCollectionActive = false
                restoreDefaultData()
                selectedUserCollection = nil
                showCollectionsList = false
            }) {
                HStack {
                    Text("Стандартная коллекция")
                    Spacer()
                    if !isUserCollectionActive {
                        Image(systemName: "checkmark")
                    }
                }
                .padding(5)
            }
            .buttonStyle(.borderless)
            .background(!isUserCollectionActive ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(4)
            
            if !userCollections.isEmpty {
                Divider()
                Text("Пользовательские коллекции:")
                    .font(.headline)
                    .padding(.top, 5)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(userCollections, id: \.name) { collection in
                            legacyCollectionRow(for: collection)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
        )
        .padding(.horizontal)
    }
    
    private func legacyCollectionRow(for collection: CollectionBookmark) -> some View {
        HStack {
            Button(action: {
                selectedUserCollection = collection
                isUserCollectionActive = true
                loadUserCollection(collection)
                showCollectionsList = false
            }) {
                Text(collection.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(5)
            .background(isUserCollectionActive && selectedUserCollection?.name == collection.name 
                       ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(4)
            
            Button(action: {
                WindowsManager.shared.openCustomCollectionsWindow(withExistingCollection: collection)
                showCollectionsList = false
            }) {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .help("Редактировать коллекцию")
            
            Button(action: {
                collectionToDelete = collection
                showDeleteAlert = true
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Удалить коллекцию")
        }
    }
    
    @ViewBuilder
    private var timeEventsSection: some View {
        if !tagLibrary.timeEvents.isEmpty {
            DisclosureGroup(isExpanded: .constant(true)) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(tagLibrary.timeEvents) { event in
                        timeEventButton(for: event)
                    }
                }
                .padding(.horizontal)
            } label: {
                Text("Общие события")
                    .font(.headline)
            }
            .padding(.horizontal)
        }
    }
    
    private func timeEventButton(for event: TimeEvent) -> some View {
        Button {
            tagLibrary.toggleTimeEvent(id: event.id)
        } label: {
            HStack {
                Image(systemName: tagLibrary.selectedTimeEvents.contains(event.id) ?
                      "checkmark.square.fill" : "square")
                    .foregroundColor(tagLibrary.selectedTimeEvents.contains(event.id) ?
                                     .blue : .gray)
                
                Text(event.name)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 135, alignment: .leading)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(BorderlessButtonStyle())
    }
    
    private var tagGroupsSection: some View {
        ForEach(tagLibrary.tagGroups) { group in
            tagGroupView(for: group)
        }
    }
    
    private func tagGroupView(for group: TagGroup) -> some View {
        DisclosureGroup(isExpanded: .constant(true)) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                ForEach(group.tags, id: \.self) { tagID in
                    if let tag = tagLibrary.tags.first(where: { $0.id == tagID }) {
                        tagButton(for: tag)
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
    
    private func tagButton(for tag: Tag) -> some View {
        Button {
            videoManager.player?.pause()
            selectedTag = tag
            
            // Let's verify that a valid timeline is selected before showing the sheet
            let hasValidTimeline = timelineData.selectedLineID != nil && 
                                   timelineData.lines.contains(where: { $0.id == timelineData.selectedLineID })
            
            // Only show the sheet after this validation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showLabelSheet = true
            }
        } label: {
            VStack(spacing: 2) {
                Text(tag.name)
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
                    .frame(width: 135)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Show hotkey if assigned
                 if let hotkey = tag.hotkey, !hotkey.isEmpty {
                    Text(hotkey)
                        .font(.system(size: 9, weight: .light))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(3)
                }
            }
            .padding(5)
                       .foregroundColor(Color(hex: tag.color).isDark ? .white : .black)
        }
        .background(Color(hex: tag.color))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(hoveredTagID == tag.id ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            if hovering {
                hoveredTagID = tag.id
            } else if hoveredTagID == tag.id {
                hoveredTagID = nil
            }
        }
    }
    
    @ViewBuilder
    private var stampLabelSheet: some View {
        // Check if the selected timeline still exists in the lines array
        if let selectedLineID = timelineData.selectedLineID, 
           timelineData.lines.contains(where: { $0.id == selectedLineID }),
           let tag = selectedTag {
            
            LabelSelectionSheet(
                stampName: tag.name,
                initialLabels: [],
                tag: tag,
                tagLibrary: TagLibraryManager.shared
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
    
    private var deleteCollectionAlert: Alert {
        Alert(
            title: Text("Удаление коллекции"),
            message: Text("Вы действительно хотите удалить коллекцию \"\(collectionToDelete?.name ?? "")\"?"),
            primaryButton: .destructive(Text("Удалить")) {
                if let collection = collectionToDelete {
                    deleteCollection(collection)
                }
            },
            secondaryButton: .cancel(Text("Отмена"))
        )
    }
    
    private func onAppearSetup() {
        loadUserCollections()
        backupDefaultData()
        restoreDefaultData()
        
        // Register hotkeys from the default collection
        HotKeyManager.shared.registerHotkeys(from: tagLibrary.tags, for: .standard)
        
        // Add observer for collection data changes
        NotificationCenter.default.addObserver(forName: .collectionDataChanged, object: nil, queue: .main) { _ in
            loadUserCollections()
            
            // If currently viewing a user collection that was updated, reload it
            if self.isUserCollectionActive, let currentCollection = self.selectedUserCollection,
               let updatedCollection = UserDefaults.standard.getCollectionBookmarks().first(where: { $0.name == currentCollection.name }) {
                self.selectedUserCollection = updatedCollection
                self.loadUserCollection(updatedCollection)
            }
        }
        
        // Add observer for showing label sheet when hotkey is pressed
        NotificationCenter.default.addObserver(forName: .showLabelSheet, object: nil, queue: .main) { notification in
            if let tag = notification.object as? Tag {
                self.selectedTag = tag
                
                // Let's verify that a valid timeline is selected before showing the sheet
                let hasValidTimeline = timelineData.selectedLineID != nil &&
                                      timelineData.lines.contains(where: { $0.id == timelineData.selectedLineID })
                
                // Only show the sheet after this validation
                if hasValidTimeline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.showLabelSheet = true
                    }
                }
            }
        }
    }
    
    private func onDisappearCleanup() {
        // Remove the observers when view disappears
        NotificationCenter.default.removeObserver(self, name: .collectionDataChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: .showLabelSheet, object: nil)
    }
    
    func loadUserCollection(_ collection: CollectionBookmark) {
        // Create a temporary CustomCollectionManager to load the collection
        let collectionManager = CustomCollectionManager()
        if collectionManager.loadCollectionFromBookmarks(named: collection.name) {
            // Replace the TagLibraryManager data with the loaded collection
            tagLibrary.tags = collectionManager.tags
            tagLibrary.tagGroups = collectionManager.tagGroups
            tagLibrary.labelGroups = collectionManager.labelGroups
            tagLibrary.labels = collectionManager.labels
            tagLibrary.timeEvents = collectionManager.timeEvents
            
            // Clear selected time events when changing collections
            tagLibrary.selectedTimeEvents.removeAll()
            
            // Set the current collection type to user collection
            tagLibrary.currentCollectionType = .user(name: collection.name)
            
            // Apply hotkeys from the newly loaded collection
            HotKeyManager.shared.clearHotkeys()
            HotKeyManager.shared.registerHotkeys(from: collectionManager.tags, for: .user(name: collection.name))
        } else {
            tagLibrary.tags = []
            tagLibrary.tagGroups = []
            tagLibrary.labelGroups = []
            tagLibrary.labels = []
            tagLibrary.timeEvents = []
            tagLibrary.selectedTimeEvents.removeAll()
            
            // Clear hotkeys when loading an empty collection
            HotKeyManager.shared.clearHotkeys()
        }
    }
    
    // Add function to delete a collection
    private func deleteCollection(_ collection: CollectionBookmark) {
        // Remove from UserDefaults
        UserDefaults.standard.removeCollectionBookmark(named: collection.name)
        
        let collectionsFolder = URL.appDocumentsDirectory
            .appendingPathComponent("YouChip-Stat/Collections/\(collection.name)", isDirectory: true)
            .fixedFile()
        
        try? FileManager.default.removeItem(at: collectionsFolder)
        
        // If we're currently viewing this collection, switch to standard collection
        if isUserCollectionActive && selectedUserCollection?.name == collection.name {
            isUserCollectionActive = false
            selectedUserCollection = nil
            restoreDefaultData()
        }
        
        // Refresh the collections list
        loadUserCollections()
        
        // Refresh global tag pools
        tagLibrary.refreshGlobalPools()
        
        // Notify that collections have changed
        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
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
            FocusAwareTextField(text: $lineName, placeholder: "Название таймлайна")
                .padding()
            HStack {
                Button("Отмена") {
                    NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
                    presentationMode.wrappedValue.dismiss()
                }
                Button("Добавить") {
                    onAdd(lineName)
                    NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(lineName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            NotificationCenter.default.post(name: NSNotification.Name("AddLineSheetAppeared"), object: nil)
        }
    }
}

struct EditTimelineNameSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var lineName: String
    let onSave: (String) -> Void
    
    init(lineName: String, onSave: @escaping (String) -> Void) {
        _lineName = State(initialValue: lineName)
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Редактировать название таймлайна")
                .font(.headline)
            
            FocusAwareTextField(text: $lineName, placeholder: "Название таймлайна")
                .padding()
            
            HStack {
                Button("Отмена") {
                    NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
                    presentationMode.wrappedValue.dismiss()
                }
                
                Button("Сохранить") {
                    if !lineName.isEmpty {
                        onSave(lineName)
                        NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .disabled(lineName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            NotificationCenter.default.post(name: NSNotification.Name("EditTimelineSheetAppeared"), object: nil)
        }
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
    @ObservedObject private var hotkeyManager = HotKeyManager.shared
    
    // For hotkey observation
    @State private var hotkeyObserver: Any? = nil
    @State private var keyEventMonitor: Any? = nil

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
                                    if let label = tagLibrary.findLabelById(labelID) {
                                        Button {
                                            if selectedLabels.contains(label.id) {
                                                selectedLabels.remove(label.id)
                                            } else {
                                                selectedLabels.insert(label.id)
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(
                                                    systemName: selectedLabels.contains(label.id)
                                                    ? "checkmark.square"
                                                    : "square"
                                                )
                                                Text(label.name)
                                                    .lineLimit(1)
                                                    .font(.system(size: 12))
                                                
                                                // Show hotkey if available
                                                if let tagHotkeys = tag?.labelHotkeys,
                                                   let hotkey = tagHotkeys[label.id], !hotkey.isEmpty {
                                                    Spacer()
                                                    Text(hotkey)
                                                        .font(.system(size: 9, weight: .light))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.black.opacity(0.15))
                                                        .cornerRadius(3)
                                                }
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(selectedLabels.contains(label.id)
                                                        ? Color.blue.opacity(0.2)
                                                        : Color.gray.opacity(0.1))
                                            .cornerRadius(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                }
                            }
                        } label: {
                            Text(group.name)
                                .font(.subheadline)
                                .bold()
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Отмена") {
                    dismissSheet()
                }
                Button("Добавить") {
                    completeSelection()
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: isDop ? 0 : 400)
        .onAppear {
            selectedLabels = Set(initialLabels)
            setupLabelHotkeys()
            setupEnterKeyMonitor()
        }
        .onDisappear {
            cleanupHotkeys()
            removeEnterKeyMonitor()
        }
    }

    var filteredLabelGroups: [LabelGroupData] {
        if let tag = tag {
            return tagLibrary.allLabelGroups.filter { tag.lablesGroup.contains($0.id) }
        } else {
            return tagLibrary.allLabelGroups
        }
    }
    
    private func setupLabelHotkeys() {
        // Enable label hotkey mode
        hotkeyManager.enableLabelHotkeyMode()
        
        // Setup observer for label hotkey presses
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .labelHotkeyPressed,
            object: nil,
            queue: .main
        ) { notification in
            if let labelInfo = notification.object as? (labelId: String, tagId: String),
               labelInfo.tagId == tag?.id {
                
                // Toggle the label selection state
                if selectedLabels.contains(labelInfo.labelId) {
                    selectedLabels.remove(labelInfo.labelId)
                } else {
                    selectedLabels.insert(labelInfo.labelId)
                }
            }
        }
    }
    
    private func setupEnterKeyMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Check if Enter or Return key is pressed (keyCode 36 is Return, 76 is Enter on numeric keypad)
            if event.keyCode == 36 || event.keyCode == 76 {
                completeSelection()
                return nil // Consume the event
            }
            return event
        }
    }
    
    private func removeEnterKeyMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }
    
    private func cleanupHotkeys() {
        // Disable label hotkey mode when sheet is dismissed
        hotkeyManager.disableLabelHotkeyMode()
        
        // Remove observer
        if let observer = hotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
            hotkeyObserver = nil
        }
    }
    
    private func dismissSheet() {
        presentationMode.wrappedValue.dismiss()
    }
    
    private func completeSelection() {
        onDone(Array(selectedLabels))
        dismissSheet()
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
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Выберите тег для экспорта")
                .font(.headline)
            
            List(tagLibrary.allTagGroups) { group in
                Section(header: Text(group.name).font(.subheadline).bold()) {
                    ForEach(group.tags, id: \.self) { tagID in
                        if let tag = tagLibrary.allTags.first(where: { $0.id == tagID }), uniqueTags.contains(where: { $0.id == tag.id }) {
                            Button(tag.name) {
                                onSelect(tag)
                            }
                        }
                    }
                }
            }
            .frame(width: 300)
            
            Button("Отмена") {
                presentationMode.wrappedValue.dismiss()
            }
            .padding(.top, 10)
        }
        .padding()
    }
}

// New view for displaying stamp label chips with dynamic font sizing.
struct StampLabelsOverlayView: View {
    let stamp: TimelineStamp
    let maxWidth: CGFloat
    // Add parameter to receive resizing state
    let isResizing: Bool
    @ObservedObject var tagLibrary = TagLibraryManager.shared

    @State private var displayedLabels: [Label] = []
    @State private var displayedTimeEvents: [TimeEvent] = []
    @State private var fontSize: CGFloat = 12 // start at 12, can reduce

    // Default parameter for isResizing for backward compatibility
    init(stamp: TimelineStamp, maxWidth: CGFloat, isResizing: Bool = false) {
        self.stamp = stamp
        self.maxWidth = maxWidth
        self.isResizing = isResizing
    }

    var body: some View {
        GeometryReader { proxy in
            // Only show content when not resizing
            if !isResizing {
                let finalWidth = proxy.size.width
                // Split the available width in half for labels and time events
                let labelsWidth = finalWidth * 0.5
                let eventsWidth = finalWidth * 0.5
                
                HStack(spacing: 2) {
                    // Labels section (leftside)
                    HStack(spacing: 4) {
                        ForEach(displayedLabels, id: \.id) { label in
                            LabelChip(label: label, baseColor: stamp.color, fontSize: fontSize)
                        }
                    }
                    .frame(width: labelsWidth, alignment: .leading)
                    
                    // Time events section (right side)
                    HStack(spacing: 4) {
                        ForEach(displayedTimeEvents, id: \.id) { event in
                            TimeEventChip(event: event, fontSize: fontSize)
                        }
                    }
                    .frame(width: eventsWidth, alignment: .trailing)
                }
                .frame(height: proxy.size.height, alignment: .center)
            }
        }
        .onAppear {
            updateDisplayedItems(finalWidth: maxWidth)
        }
        .onChange(of: maxWidth) { newValue in
            updateDisplayedItems(finalWidth: newValue)
        }
        .onChange(of: stamp.labels) { _ in
            updateDisplayedItems(finalWidth: maxWidth)
        }
        .onChange(of: stamp.timeEvents) { _ in
            updateDisplayedItems(finalWidth: maxWidth)
        }
    }
    
    // ...existing code for updateDisplayedItems, updateDisplayedLabels, updateDisplayedTimeEvents...
    private func updateDisplayedItems(finalWidth: CGFloat) {
        // Split the available width in half for labels and time events
        let labelsWidth = finalWidth * 0.5
        let eventsWidth = finalWidth * 0.5
        
        // Update displayed labels
        updateDisplayedLabels(availableWidth: labelsWidth)
        
        // Update displayed time events
        updateDisplayedTimeEvents(availableWidth: eventsWidth)
    }
    
    private func updateDisplayedLabels(availableWidth: CGFloat) {
        let stampLabels = stamp.labels.compactMap { labelID in
            tagLibrary.findLabelById(labelID)
        }
        
        var testFont: CGFloat = 12
        let totalWidthOfAll = stampLabels.reduce(0) { partialResult, label in
            let textWidth = label.name.size(withSystemFontOfSize: testFont).width + 20
            return partialResult + textWidth + 4
        }
        
        if totalWidthOfAll <= availableWidth {
            displayedLabels = stampLabels
            fontSize = testFont
            return
        }
        
        // Try to fit at least one label
        let firstLabelWidth = stampLabels.first.map {
            $0.name.size(withSystemFontOfSize: testFont).width + 20
        } ?? 0
        
        if firstLabelWidth > availableWidth {
            // Try with smaller font
            testFont = 10
            let newFirstWidth = stampLabels.first.map {
                $0.name.size(withSystemFontOfSize: testFont).width + 20
            } ?? 0
            
            if newFirstWidth > availableWidth {
                displayedLabels = []
                return
            } else {
                displayedLabels = [stampLabels.first!]
                fontSize = testFont
                return
            }
        } else {
            // Add as many labels as can fit
            var listToShow: [Label] = []
            var currentWidth: CGFloat = 0
            
            for lb in stampLabels {
                let neededWidth = lb.name.size(withSystemFontOfSize: testFont).width + 20 + 4
                if currentWidth + neededWidth <= availableWidth {
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
    
    private func updateDisplayedTimeEvents(availableWidth: CGFloat) {
        // Get time events from IDs
        let events = stamp.timeEvents.compactMap { eventID in
            tagLibrary.allTimeEvents.first(where: { $0.id == eventID })
        }
        
        var testFont: CGFloat = 12
        let totalWidthOfAll = events.reduce(0) { partialResult, event in
            let textWidth = event.name.size(withSystemFontOfSize: testFont).width + 20
            return partialResult + textWidth + 4
        }
        
        if totalWidthOfAll <= availableWidth {
            displayedTimeEvents = events
            return
        }
        
        // Try to fit at least one event
        let firstEventWidth = events.first.map {
            $0.name.size(withSystemFontOfSize: testFont).width + 20
        } ?? 0
        
        if firstEventWidth > availableWidth {
            // Try with smaller font
            testFont = 10
            let newFirstWidth = events.first.map {
                $0.name.size(withSystemFontOfSize: testFont).width + 20
            } ?? 0
            
            if newFirstWidth > availableWidth {
                displayedTimeEvents = []
                return
            } else {
                displayedTimeEvents = [events.first!]
                fontSize = testFont
                return
            }
        } else {
            // Add as many events as can fit
            var listToShow: [TimeEvent] = []
            var currentWidth: CGFloat = 0
            
            for event in events {
                let neededWidth = event.name.size(withSystemFontOfSize: testFont).width + 20 + 4
                if currentWidth + neededWidth <= availableWidth {
                    listToShow.append(event)
                    currentWidth += neededWidth
                } else {
                    break
                }
            }
            
            displayedTimeEvents = listToShow
        }
    }
}

struct TimeEventChip: View {
    let event: TimeEvent
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: fontSize))
            Text(event.name)
                .lineLimit(1)
                .font(.system(size: fontSize))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.yellow.opacity(0.3))
        .cornerRadius(8)
        .foregroundColor(.black)
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

extension String {
    func size(withAttributes attributes: [NSAttributedString.Key: Any]) -> CGSize {
        let string = self as NSString
        return string.size(withAttributes: attributes)
    }
    
    func size(withSystemFontOfSize fontSize: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes = [NSAttributedString.Key.font: font]
        return size(withAttributes: attributes)
    }
}

// Add a FocusState manager to track text field focus globally
class FocusStateManager: ObservableObject {
    static let shared = FocusStateManager()
    @Published var isAnyTextFieldFocused = false
    
    func setFocused(_ focused: Bool) {
        isAnyTextFieldFocused = false
    }
}

// This struct will be used to create a FocusAwareTextField component
struct FocusAwareTextField: View {
    @Binding var text: String
    var placeholder: String
    @ObservedObject private var focusManager = FocusStateManager.shared
    @State private var isFocused = false
    @State private var observer: Any? = nil
    
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .background(FocusTrackingView(isFocused: $isFocused, focusManager: focusManager))
            .onAppear {
                // Make sure to reset focus state when view appears
                DispatchQueue.main.async {
                    focusManager.setFocused(false)
                }
            }
            .onDisappear {
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                }
                // Ensure we release focus when the view disappears
                focusManager.setFocused(false)
            }
    }
}

struct FocusTrackingView: NSViewRepresentable {
    @Binding var isFocused: Bool
    var focusManager: FocusStateManager
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            // Find the parent NSTextField or NSTextView
            if let responder = nsView.window?.firstResponder,
               let textField = responder as? NSTextField {
                // If we find it and it's in our view hierarchy, we're focused
                var currentView: NSView? = textField
                var isInOurHierarchy = false
                
                // Walk up the view hierarchy to see if the first responder is in our view tree
                while let parent = currentView?.superview {
                    if parent == nsView.superview?.superview {
                        isInOurHierarchy = true
                        break
                    }
                    currentView = parent
                }
                
                if isInOurHierarchy {
                    self.isFocused = true
                    self.focusManager.setFocused(true)
                } else {
                    self.isFocused = false
                    self.focusManager.setFocused(false)
                }
            } else {
                // If the first responder isn't a text field or isn't in our hierarchy
                self.isFocused = false
                self.focusManager.setFocused(false)
            }
        }
    }
    
    class Coordinator: NSObject {
        var parent: FocusTrackingView
        var timer: Timer?
        
        init(parent: FocusTrackingView) {
            self.parent = parent
            super.init()
            
            // Create a timer to check focus state periodically
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                
                // Check if our view is still in window hierarchy
                if FocusTrackingView.nsView?.window == nil {
                    // View is not in window, ensure focus is released
                    if self.parent.isFocused {
                        self.parent.isFocused = false
                        self.parent.focusManager.setFocused(false)
                    }
                    return
                }
                
                // Check if first responder is our text field
                if let window = FocusTrackingView.nsView?.window,
                   let responder = window.firstResponder {
                    
                    let isTextFieldFocused = responder is NSTextField || responder is NSTextView
                    
                    if !isTextFieldFocused && self.parent.isFocused {
                        // Text field lost focus
                        self.parent.isFocused = false
                        self.parent.focusManager.setFocused(false)
                    }
                }
            }
        }
        
        deinit {
            timer?.invalidate()
            timer = nil
        }
    }
    
    // Store reference to the NSView for the Coordinator
    static var nsView: NSView? = nil
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.timer?.invalidate()
        coordinator.timer = nil
        self.nsView = nil
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(parent: self)
        Self.nsView = nil
        return coordinator
    }
}
