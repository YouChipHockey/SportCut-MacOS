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

class TagLibraryManager: ObservableObject {
    static let shared = TagLibraryManager()
    @Published var tags: [Tag] = []
    @Published var tagGroups: [TagGroup] = []
    @Published var labelGroups: [LabelGroupData] = []
    @Published var labels: [Label] = []
    @Published var timeEvents: [TimeEvent] = []
    @Published var allTags: [Tag] = []
    @Published var allTagGroups: [TagGroup] = []
    @Published var allLabelGroups: [LabelGroupData] = []
    @Published var allLabels: [Label] = []
    @Published var allTimeEvents: [TimeEvent] = []
    @Published var selectedTimeEvents: Set<String> = []
    
    private var defaultTags: [Tag] = []
    private var defaultTagGroups: [TagGroup] = []
    private var defaultLabelGroups: [LabelGroupData] = []
    private var defaultLabels: [Label] = []
    private var defaultTimeEvents: [TimeEvent] = []
    
    @Published var currentCollectionType: TagCollection = .standard
    
    private init() {
        if let loadedTags: TagsData = loadJSON(filename: "tags.json") {
            self.tags = loadedTags.tags
            self.defaultTags = loadedTags.tags
        }
        if let loadedTagGroups: TagGroupsData = loadJSON(filename: "tagsGroups.json") {
            self.tagGroups = loadedTagGroups.tagGroups
            self.defaultTagGroups = loadedTagGroups.tagGroups
        }
        if let loadedLabelGroups: LabelGroupsData = loadJSON(filename: "labelsGroups.json") {
            self.labelGroups = loadedLabelGroups.labelGroups
            self.defaultLabelGroups = loadedLabelGroups.labelGroups
        }
        if let loadedLabels: LabelsData = loadJSON(filename: "labels.json") {
            self.labels = loadedLabels.labels
            self.defaultLabels = loadedLabels.labels
        }
        if let loadedTimeEvents: TimeEventsData = loadJSON(filename: "timeEvents.json") {
            self.timeEvents = loadedTimeEvents.events
            self.defaultTimeEvents = loadedTimeEvents.events
        }
        
        NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleTagUpdated),
                name: .tagUpdated,
                object: nil
            )
        
        allTags = tags
        allTagGroups = tagGroups
        allLabelGroups = labelGroups
        allLabels = labels
        allTimeEvents = timeEvents
        loadAllUserCollections()
    }
    
    func findTagById(_ id: String) -> Tag? {
        return allTags.first(where: { $0.id == id })
    }
    
    func findLabelById(_ id: String) -> Label? {
        return allLabels.first(where: { $0.id == id })
    }
    
    func findLabelsForTag(_ tag: Tag) -> [Label] {
        let labelGroupIds = tag.lablesGroup
        let relevantLabelIds = allLabelGroups.filter { labelGroupIds.contains($0.id) }
            .flatMap { $0.lables }
        return allLabels.filter { label in relevantLabelIds.contains(label.id) }
    }
    
    private func loadAllUserCollections() {
        let userCollections = UserDefaults.standard.getCollectionBookmarks()
        
        for collection in userCollections {
            let collectionManager = CustomCollectionManager()
            if collectionManager.loadCollectionFromBookmarks(named: collection.name) {
                allTags.append(contentsOf: collectionManager.tags)
                allTagGroups.append(contentsOf: collectionManager.tagGroups)
                allLabelGroups.append(contentsOf: collectionManager.labelGroups)
                allLabels.append(contentsOf: collectionManager.labels)
                allTimeEvents.append(contentsOf: collectionManager.timeEvents)
            }
        }
        
        allTags = Array(Dictionary(grouping: allTags, by: { $0.id }).values.compactMap { $0.first })
        allTagGroups = Array(Dictionary(grouping: allTagGroups, by: { $0.id }).values.compactMap { $0.first })
        allLabelGroups = Array(Dictionary(grouping: allLabelGroups, by: { $0.id }).values.compactMap { $0.first })
        allLabels = Array(Dictionary(grouping: allLabels, by: { $0.id }).values.compactMap { $0.first })
        allTimeEvents = Array(Dictionary(grouping: allTimeEvents, by: { $0.id }).values.compactMap { $0.first })
    }
    
    func findOrCreateTimeEvent(id: String, name: String) -> TimeEvent {
        if let existingEvent = allTimeEvents.first(where: { $0.id == id }) {
            return existingEvent
        } else {
            let newEvent = TimeEvent(id: id, name: name)
            allTimeEvents.append(newEvent)
            return newEvent
        }
    }
    
    func toggleTimeEvent(id: String) {
        if selectedTimeEvents.contains(id) {
            selectedTimeEvents.remove(id)
        } else {
            selectedTimeEvents.insert(id)
        }
    }
    
    @objc private func handleTagUpdated(_ notification: Notification) {
        guard let originalID = notification.userInfo?["originalID"] as? String,
              let newID = notification.userInfo?["newID"] as? String else {
            return
        }
        
        for i in 0..<allTagGroups.count {
            if let tagIndex = allTagGroups[i].tags.firstIndex(where: { $0 == originalID }) {
                var updatedTags = allTagGroups[i].tags
                updatedTags[tagIndex] = newID
                allTagGroups[i] = TagGroup(
                    id: allTagGroups[i].id,
                    name: allTagGroups[i].name,
                    tags: updatedTags
                )
            }
        }
        
        refreshGlobalPools()
    }
    
    func refreshGlobalPools() {
        let standardTags = tags
        let standardTagGroups = tagGroups
        let standardLabelGroups = labelGroups
        let standardLabels = labels
        let standardTimeEvents = timeEvents
        
        allTags = standardTags
        allTagGroups = standardTagGroups
        allLabelGroups = standardLabelGroups
        allLabels = standardLabels
        allTimeEvents = standardTimeEvents
        loadAllUserCollections()
        applyHotkeysFromCurrentCollection()
    }
    
    func restoreDefaultData() {
        tags = defaultTags
        tagGroups = defaultTagGroups
        labelGroups = defaultLabelGroups
        labels = defaultLabels
        timeEvents = defaultTimeEvents
        currentCollectionType = .standard
        
        selectedTimeEvents.removeAll()
        refreshGlobalPools()
    }
    
    func applyHotkeysFromCurrentCollection() {
        HotKeyManager.shared.clearHotkeys()
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
    
    func darken(by amount: CGFloat) -> Color {
        let uiColor = NSColor(self)
        guard let adjustedColor = uiColor.adjustBrightness(by: -amount) else {
            return self
        }
        return Color(adjustedColor)
    }
}


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
    let primaryID: String?
    var timeStart: String
    var timeFinish: String
    var colorHex: String
    var label: String
    var isActiveForMapView: Bool?
    var labels: [String]
    var timeEvents: [String]
    var position: CGPoint?
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
    
    init(id: UUID = UUID(), idTag: String, primaryID: String?, timeStart: String, timeFinish: String, colorHex: String, label: String, labels: [String], timeEvents: [String] = [], position: CGPoint? = nil, isActiveForMapView: Bool? = nil) {
        self.id = id
        self.primaryID = primaryID
        self.idTag = idTag
        self.timeStart = timeStart
        self.timeFinish = timeFinish
        self.colorHex = colorHex
        self.label = label
        self.labels = labels
        self.timeEvents = timeEvents
        self.position = position
        self.isActiveForMapView = isActiveForMapView
    }
}


class TimelineDataManager: ObservableObject {
    static let shared = TimelineDataManager()
    @Published var lines: [TimelineLine] = []
    @Published var selectedLineID: UUID? = nil
    @Published var selectedStampID: UUID? = nil
    var currentBookmark: Data?
    
    init() {
        lines = []
        if let first = lines.first {
            selectedLineID = first.id
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTagUpdated),
            name: .tagUpdated,
            object: nil
        )
    }
    
    func selectLine(_ lineID: UUID) {
        if MarkupMode.current == .standard {
            selectedLineID = lineID
        }
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
        guard MarkupMode.current == .standard else { return }
        
        let newLine = TimelineLine(name: name)
        lines.append(newLine)
        selectedLineID = newLine.id
        updateTimelines()
    }
    
    func findOrCreateTimelineForTag(tag: Tag) -> UUID {
        if let existingLine = lines.first(where: { $0.tagIdForMode == tag.id }) {
            return existingLine.id
        }
        let newLine = TimelineLine(name: tag.name, tagIdForMode: tag.id)
        lines.append(newLine)
        return newLine.id
    }
    
    func updateTagReferences(originalID: String, newID: String) {
        var updated = false
        
        for lineIndex in 0..<lines.count {
            for stampIndex in 0..<lines[lineIndex].stamps.count {
                if lines[lineIndex].stamps[stampIndex].idTag == originalID {
                    lines[lineIndex].stamps[stampIndex].idTag = newID
                    updated = true
                }
            }
            
            if lines[lineIndex].tagIdForMode == originalID {
                lines[lineIndex].tagIdForMode = newID
                updated = true
            }
        }
        
        if updated {
            updateTimelines()
        }
    }
    
    func addStampToSelectedLine(idTag: String, primaryId: String?, name: String, timeStart: String, timeFinish: String, color: String, labels: [String], position: CGPoint? = nil) {
        if MarkupMode.current == .standard {
            guard let lineID = selectedLineID,
                  let idx = lines.firstIndex(where: { $0.id == lineID }) else { return }
            
            let selectedEvents = Array(TagLibraryManager.shared.selectedTimeEvents)
            
            let stamp = TimelineStamp(
                idTag: idTag,
                primaryID: primaryId,
                timeStart: timeStart,
                timeFinish: timeFinish,
                colorHex: color,
                label: name,
                labels: labels,
                timeEvents: selectedEvents,
                position: position,
                isActiveForMapView: position != nil
            )
            lines[idx].stamps.append(stamp)
            
        } else {
            if let tag = TagLibraryManager.shared.findTagById(idTag) {
                let lineID = findOrCreateTimelineForTag(tag: tag)
                
                if let idx = lines.firstIndex(where: { $0.id == lineID }) {
                    let selectedEvents = Array(TagLibraryManager.shared.selectedTimeEvents)
                    
                    let stamp = TimelineStamp(
                        idTag: idTag,
                        primaryID: primaryId,
                        timeStart: timeStart,
                        timeFinish: timeFinish,
                        colorHex: color,
                        label: name,
                        labels: labels,
                        timeEvents: selectedEvents,
                        position: position,
                        isActiveForMapView: position != nil
                    )
                    lines[idx].stamps.append(stamp)
                }
            }
        }
        
        updateTimelines()
    }
    
    func updateStampLabels(lineID: UUID, stampID: UUID, newLabels: [String]) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        guard let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else { return }
        lines[lineIndex].stamps[stampIndex].labels = newLabels
        updateTimelines()
    }
    
    func stampHasOverlaps(lineID: UUID, stampID: UUID) -> Bool {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              let stamp = lines[lineIndex].stamps.first(where: { $0.id == stampID }) else {
            return false
        }
        
        return lines[lineIndex].stamps.contains { otherStamp in
            guard otherStamp.id != stampID else { return false }
            
            let stampStart = stamp.startSeconds
            let stampEnd = stamp.finishSeconds
            let otherStart = otherStamp.startSeconds
            let otherEnd = otherStamp.finishSeconds
            return (stampStart < otherEnd && otherStart < stampEnd)
        }
    }
    
    func updateStampTime(lineID: UUID, stampID: UUID, newStart: Double? = nil, newEnd: Double? = nil) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else {
            return
        }
        
        var stamp = lines[lineIndex].stamps[stampIndex]
        
        if let newStartTime = newStart {
            let limitedStart = min(newStartTime, stamp.finishSeconds - 0.5)
            stamp.timeStart = secondsToTimeString(limitedStart)
        }
        
        if let newEndTime = newEnd {
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
    
    @objc private func handleTagUpdated(_ notification: Notification) {
        guard let originalID = notification.userInfo?["originalID"] as? String,
              let newID = notification.userInfo?["newID"] as? String else {
            return
        }
        
        var updated = false
        
        guard let updatedTag = TagLibraryManager.shared.findTagById(newID) else { return }
        
        for lineIndex in 0..<lines.count {
            for stampIndex in 0..<lines[lineIndex].stamps.count {
                if lines[lineIndex].stamps[stampIndex].idTag == originalID {
                    lines[lineIndex].stamps[stampIndex].idTag = newID
                    lines[lineIndex].stamps[stampIndex].label = updatedTag.name
                    updated = true
                }
            }
            
            if lines[lineIndex].tagIdForMode == originalID {
                lines[lineIndex].tagIdForMode = newID
                if lines[lineIndex].name == lines[lineIndex].tagIdForMode {
                    lines[lineIndex].name = updatedTag.name
                }
                
                updated = true
            }
        }
        
        if updated {
            updateTimelines()
        }
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
    func seek(to time: Double) {
        guard let player = player else { return }
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.startTimeObserver()
        }
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
    func changePlaybackSpeed(to speed: Double) {
        playbackSpeed = speed
        player?.rate = Float(speed)
    }
    
    func getCurrentFrameRate() -> Float {
        guard let player = player,
              let asset = player.currentItem?.asset,
              let track = asset.tracks(withMediaType: .video).first else {
            return 30
        }
        
        return track.nominalFrameRate
    }
}

struct VideoPlayerWindow: View {
    let id: String
    
    @ObservedObject var videoManager = VideoPlayerManager.shared
    
    @State private var showScreenshotNameSheet = false
    @State private var tempScreenshotImage: NSImage?
    @State private var currentScreenshotName: String = ""
    @State private var screenshotImage: URL? = nil
    
    init(id: String) {
        self.id = id
    }

    var body: some View {
        VStack {
            if let player = videoManager.player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .overlay(
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button(action: takeScreenshot) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 18))
                                        .padding(10)
                                        .background(Color.black.opacity(0.6))
                                        .foregroundColor(.white)
                                        .clipShape(Circle())
                                        .shadow(radius: 3)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .padding()
                                .padding(.bottom, 40)
                                .help("Создать скриншот и открыть редактор")
                            }
                        }
                    )
            } else {
                Text("Видео не загружено")
                    .foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $showScreenshotNameSheet) {
            ScreenshotNameSheet { name in
                currentScreenshotName = name
                saveScreenshot(with: name)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func takeScreenshot() {
        guard let player = videoManager.player,
              let asset = player.currentItem?.asset else {
            return
        }
        player.pause()
        let currentTime = player.currentTime()
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: currentTime, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            tempScreenshotImage = nsImage
            showScreenshotNameSheet = true
        } catch {
            print("Ошибка создания скриншота: \(error.localizedDescription)")
        }
    }

    private func saveScreenshot(with name: String) {
        guard let nsImage = tempScreenshotImage,
              let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == id }) else {
            return
        }
        
        let screenshotsFolder = filesFile.screenshotsFolder
        let fileName = name.hasSuffix(".png") ? name : "\(name).png"
        let fileURL = screenshotsFolder.appendingPathComponent(fileName)
        
        if let imageData = nsImage.pngData() {
            try? imageData.write(to: fileURL)
            screenshotImage = fileURL
            openEditorInNewWindow(with: fileURL, screenshotsFolder: screenshotsFolder)
        }
    }
    
    private func openEditorInNewWindow(with imageUrl: URL, screenshotsFolder: URL) {
        let editorViewModel = EditorViewModel(file: imageUrl, screenshotsFolder: screenshotsFolder)
        
        let editorView = EditorView()
            .environmentObject(editorViewModel)
            
        let hostingController = NSHostingController(rootView: editorView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Редактирование скриншота"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
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
    init(id: String) {
        let view = VideoPlayerWindow(id: id)
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
                        return nil // Consume the event
                    }
                }
                return event // Let regular delete behavior pass through
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
                
                // Register for markup mode changes
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
                // Remove notification observers
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

struct TimelineLineView: View {
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    
    let line: TimelineLine
    let scale: CGFloat
    let widthMax: CGFloat
    
    let isSelected: Bool
    let onSelect: () -> Void
    let onEditLabelsRequest: (UUID) -> Void
    
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @State private var isDraggingOver = false
    @State private var isResizing = false
    @State private var resizingSide: ResizingSide = .none
    @State private var initialDragLocation: CGPoint = .zero
    @State private var initialStartTime: Double = 0
    @State private var initialEndTime: Double = 0
    @Binding var scrollOffset: CGFloat
    
    enum ResizingSide {
        case left, right, none
    }
    
    private func getOverlapCount(stamp: TimelineStamp, stamps: [TimelineStamp], stampIndex: Int) -> Int {
        var count = 0
        
        for i in 0..<stampIndex {
            let olderStamp = stamps[i]
            
            let stampStart = stamp.startSeconds
            let stampEnd = stamp.finishSeconds
            let olderStart = olderStamp.startSeconds
            let olderEnd = olderStamp.finishSeconds
            
            if stampStart < olderEnd && olderStart < stampEnd {
                count += 1
            }
        }
        
        return count
    }
    
    var body: some View {
        GeometryReader { geometry in
            
            
            let baseWidth = geometry.size.width
            let totalDuration = max(1, videoManager.videoDuration)
            let computedWidth = baseWidth * max(scale, 1.0)
            
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(isDraggingOver ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        .frame(width: widthMax, height: 30)
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
                            timelineData.selectStamp(stampID: nil)
                        }
                    ForEach(Array(line.stamps.enumerated()), id: \.element.id) { index, stamp in
                        let startRatio = stamp.startSeconds / totalDuration
                        let durationRatio = stamp.duration / totalDuration
                        
                        let stampWidth = durationRatio * widthMax
                        let stampX = startRatio * widthMax
                        
                        let isSelected = timelineData.selectedStampID == stamp.id
                        let overlapCount = getOverlapCount(stamp: stamp, stamps: line.stamps, stampIndex: index)
                        let hasOverlaps = overlapCount > 0
                        
                        let borderColor = (hasOverlaps && !isSelected) ? Color.red :
                        (isSelected && hasOverlaps) ? Color.red :
                        (isSelected) ? Color.blue : Color.clear
                        let heightReduction = CGFloat(overlapCount * 6)
                        let stampHeight: CGFloat = 30 - heightReduction
                        let verticalOffset = (30 - stampHeight) / 2
                        
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(stamp.color)
                                .frame(height: stampHeight)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
                                )
                            StampLabelsOverlayView(
                                stamp: stamp,
                                maxWidth: stampWidth,
                                isResizing: isResizing
                            )
                            .frame(height: stampHeight)
                        }
                        .frame(width: stampWidth, height: stampHeight)
                        .position(x: stampX + stampWidth / 2, y: 15)
                        .onTapGesture {
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
                            menuForTag(stamp: stamp)
                        }
                    }
                }
            }
            .frame(width: widthMax, height: 30)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        scrollOffset = value.translation.width
                    }
            )
        }
    }
    
    @ViewBuilder
    private func menuForTag(stamp: TimelineStamp) -> some View {
        Text("Тег: \(stamp.label)")
        
        if let position = stamp.position {
            Text("Позиция: x: \(String(format: "%.2f", position.x)), y: \(String(format: "%.2f", position.y))")
        }
        
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
        if !stamp.timeEvents.isEmpty {
            Text("События:")
            ForEach(stamp.timeEvents, id: \.self) { eventID in
                if let event = tagLibrary.allTimeEvents.first(where: { $0.id == eventID }) {
                    Text("• \(event.name)")
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
            id: UUID(),
            idTag: stamp.idTag,
            primaryID: stamp.primaryID,
            timeStart: stamp.timeStart,
            timeFinish: stamp.timeFinish,
            colorHex: stamp.colorHex,
            label: stamp.label,
            labels: stamp.labels,
            timeEvents: stamp.timeEvents,
            position: stamp.position
        )
        
        timelineData.lines[destLineIndex].stamps.append(newStamp)
        timelineData.lines[sourceLineIndex].stamps.remove(at: stampIndex)
        timelineData.updateTimelines()
    }
}

// MARK: - Hotkey Manager
class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    
    private var localMonitorForKeyEvents: Any?
    private var globalMonitorForKeyEvents: Any?
    private var registeredHotkeys: [String: Tag] = [:]
    private var registeredLabelHotkeys: [String: (labelId: String, tagId: String)] = [:]
    
    @Published var isEnabled = true
    @Published var hotKeySelectedTag: Tag? = nil
    @Published var hotKeySelectedLabelId: String? = nil
    @Published var isLabelHotkeyMode = false
    @Published var blockedSheetActive = false
    private var activeCollection: TagCollection = .standard
    
    private init() {
        setupKeyboardMonitoring()
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
    
    @objc private func sheetWillAppear(_ notification: Notification) {}
    
    @objc private func sheetDidDisappear(_ notification: Notification) {}
    
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
                  !self.blockedSheetActive,
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
            if let labelInfo = registeredLabelHotkeys[hotkeyString] {
                hotKeySelectedLabelId = labelInfo.labelId
                NotificationCenter.default.post(name: .labelHotkeyPressed, object: labelInfo)
                return true
            }
        } else {
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
        registeredHotkeys.removeAll()
        registeredLabelHotkeys.removeAll()
        activeCollection = collection
        for tag in tags {
            if let hotkey = tag.hotkey, !hotkey.isEmpty {
                registeredHotkeys[hotkey.lowercased()] = tag
            }
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
        if event.modifierFlags.contains(.control) { components.append("ctrl") }
        if event.modifierFlags.contains(.option) { components.append("alt") }
        if event.modifierFlags.contains(.shift) { components.append("shift") }
        if event.modifierFlags.contains(.command) { components.append("cmd") }
        let keyCode = event.keyCode
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

extension Notification.Name {
    static let showLabelSheet = Notification.Name("showLabelSheet")
    static let labelHotkeyPressed = Notification.Name("labelHotkeyPressed")
    static let tagUpdated = Notification.Name("tagUpdated")
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

struct TagLibraryView: View {
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @ObservedObject var hotkeyManager = HotKeyManager.shared
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    @State private var activeCollection: TagCollection = .standard
    @State private var markupMode = MarkupMode.current
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
    @State private var showCollectionsList = false
    @State private var currentTagForMap: Tag? = nil
    @State private var currentSelectedLabels: [String] = []
    @State private var fieldMapBookmark: Data? = nil
    
    func loadUserCollections() {
        userCollections = UserDefaults.standard.getCollectionBookmarks()
    }
    
    func backupDefaultData() {}
    
    func restoreDefaultData() {
        tagLibrary.restoreDefaultData()
        hotkeyManager.registerHotkeys(from: tagLibrary.tags, for: .standard)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if #available(macOS 14.0, *) {
                modernHeaderView
            } else {
                legacyHeaderView
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    timeEventsSection
                    tagGroupsSection
                }
            }
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
    
    private var modernHeaderView: some View {
        HStack {
            collectionTitleView
            Spacer()
            collectionsMenuButton
        }
        .padding(.horizontal)
    }
    
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
                    .frame(width:20)
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
            
            let hasValidTimeline = timelineData.selectedLineID != nil &&
            timelineData.lines.contains(where: { $0.id == timelineData.selectedLineID })
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showLabelSheet = true
            }
        } label: {
            VStack(alignment: .center, spacing: 2) {
                HStack(alignment: .center, spacing: 4) {
                    Text(tag.name)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                    if let hotkey = tag.hotkey, !hotkey.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "button.roundedtop.horizontal.fill")
                                .font(.system(size: 9))
                            Text(hotkey)
                                .font(.system(size: 9, weight: .light))
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(3)
                    }
                }
                .frame(width: 135, alignment: .leading)
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
    
    private func addTagToTimeline(tag: Tag, selectedLabels: [String]) {
        if tag.mapEnabled == true {
            let collectionManager = CustomCollectionManager()
            if let collectionName = tagLibrary.currentCollectionType.name,
               collectionManager.loadCollectionFromBookmarks(named: collectionName),
               let playField = collectionManager.playField,
               let imageBookmark = playField.imageBookmark {
                
                showFieldMapSelection(tag: tag, imageBookmark: imageBookmark, selectedLabels: selectedLabels)
                return
            }
        }
        
        proceedWithTagAddition(tag: tag, selectedLabels: selectedLabels, coordinates: nil)
    }
    
    private func showFieldMapSelection(tag: Tag, imageBookmark: Data, selectedLabels: [String]) {
        WindowsManager.shared.showFieldMapSelection(tag: tag, imageBookmark: imageBookmark) { [self] coordinates in
            proceedWithTagAddition(tag: tag, selectedLabels: selectedLabels, coordinates: coordinates)
        }
    }
    
    private func proceedWithTagAddition(tag: Tag, selectedLabels: [String], coordinates: CGPoint?) {
        let currentTime = videoManager.currentTime
        let startTime = max(0, currentTime - tag.defaultTimeBefore)
        let finishTime = startTime + tag.defaultTimeBefore + tag.defaultTimeAfter
        let timeStartString = secondsToTimeString(startTime)
        let timeFinishString = secondsToTimeString(finishTime)
        
        // Calculate field coordinates if normalized coordinates are provided
        var fieldPosition: CGPoint? = nil
        if let normalizedCoords = coordinates {
            // Get field dimensions from the collection
            let collectionManager = CustomCollectionManager()
            if let collectionName = tagLibrary.currentCollectionType.name,
               collectionManager.loadCollectionFromBookmarks(named: collectionName),
               let playField = collectionManager.playField {
                
                // Convert normalized coordinates (0-1) to field coordinates
                // by multiplying with field dimensions
                let fieldWidth = CGFloat(playField.width)
                let fieldHeight = CGFloat(playField.height)
                
                let fieldX = normalizedCoords.x * fieldWidth
                let fieldY = normalizedCoords.y * fieldHeight
                
                fieldPosition = CGPoint(x: fieldX, y: fieldY)
                
                print("Field position selected for tag '\(tag.name)': " +
                      "normalized: x: \(normalizedCoords.x), y: \(normalizedCoords.y), " +
                      "field position: x: \(fieldX), y: \(fieldY)")
            }
        }
        
        timelineData.addStampToSelectedLine(
            idTag: tag.id,
            primaryId: tag.primaryID,
            name: tag.name,
            timeStart: timeStartString,
            timeFinish: timeFinishString,
            color: tag.color,
            labels: selectedLabels,
            position: fieldPosition
        )
        
        if videoManager.playbackSpeed > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                videoManager.player?.play()
            }
        }
    }
    
    @ViewBuilder
    private var stampLabelSheet: some View {
        if markupMode == .tagBased {
            if let tag = selectedTag {
                let hasLabels = !tagLibrary.allLabelGroups.filter({ tag.lablesGroup.contains($0.id) }).isEmpty
                
                if hasLabels {
                    LabelSelectionSheet(
                        stampName: tag.name,
                        initialLabels: [],
                        tag: tag,
                        tagLibrary: TagLibraryManager.shared
                    ) { selectedLabels in
                        addTagToTimeline(tag: tag, selectedLabels: selectedLabels)
                    }
                } else {
                    VStack {
                        Text("Добавление тега...")
                            .onAppear {
                                addTagToTimeline(tag: tag, selectedLabels: [])
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showLabelSheet = false
                                }
                            }
                    }
                }
            }
        } else {
            if let selectedLineID = timelineData.selectedLineID,
               timelineData.lines.contains(where: { $0.id == selectedLineID }),
               let tag = selectedTag {
                let hasLabels = !tagLibrary.allLabelGroups.filter({ tag.lablesGroup.contains($0.id) }).isEmpty
                
                if hasLabels {
                    LabelSelectionSheet(
                        stampName: tag.name,
                        initialLabels: [],
                        tag: tag,
                        tagLibrary: TagLibraryManager.shared
                    ) { selectedLabels in
                        addTagToTimeline(tag: tag, selectedLabels: selectedLabels)
                    }
                } else {
                    VStack {
                        Text("Добавление тега...")
                            .onAppear {
                                addTagToTimeline(tag: tag, selectedLabels: [])
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showLabelSheet = false
                                }
                            }
                    }
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
        markupMode = MarkupMode.current
        NotificationCenter.default.addObserver(forName: .markupModeChanged, object: nil, queue: .main) { notification in
            if let newMode = notification.object as? MarkupMode {
                self.markupMode = newMode
            } else {
                self.markupMode = MarkupMode.current
            }
        }
        NotificationCenter.default.addObserver(forName: .collectionDataChanged, object: nil, queue: .main) { _ in
            loadUserCollections()
            if self.isUserCollectionActive, let currentCollection = self.selectedUserCollection,
               let updatedCollection = UserDefaults.standard.getCollectionBookmarks().first(where: { $0.name == currentCollection.name }) {
                self.selectedUserCollection = updatedCollection
                self.loadUserCollection(updatedCollection)
            }
        }
        NotificationCenter.default.addObserver(forName: .showLabelSheet, object: nil, queue: .main) { notification in
            if let tag = notification.object as? Tag {
                self.selectedTag = tag
                let hasValidTimeline = timelineData.selectedLineID != nil &&
                timelineData.lines.contains(where: { $0.id == timelineData.selectedLineID })
                if hasValidTimeline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.showLabelSheet = true
                    }
                }
            }
        }
    }
    
    private func onDisappearCleanup() {
        NotificationCenter.default.removeObserver(self, name: .collectionDataChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: .showLabelSheet, object: nil)
    }
    
    func loadUserCollection(_ collection: CollectionBookmark) {
        let collectionManager = CustomCollectionManager()
        if collectionManager.loadCollectionFromBookmarks(named: collection.name) {
            tagLibrary.tags = collectionManager.tags
            tagLibrary.tagGroups = collectionManager.tagGroups
            tagLibrary.labelGroups = collectionManager.labelGroups
            tagLibrary.labels = collectionManager.labels
            tagLibrary.timeEvents = collectionManager.timeEvents
            tagLibrary.selectedTimeEvents.removeAll()
            tagLibrary.currentCollectionType = .user(name: collection.name)
            HotKeyManager.shared.clearHotkeys()
            HotKeyManager.shared.registerHotkeys(from: collectionManager.tags, for: .user(name: collection.name))
        } else {
            tagLibrary.tags = []
            tagLibrary.tagGroups = []
            tagLibrary.labelGroups = []
            tagLibrary.labels = []
            tagLibrary.timeEvents = []
            tagLibrary.selectedTimeEvents.removeAll()
            HotKeyManager.shared.clearHotkeys()
        }
    }
    
    private func deleteCollection(_ collection: CollectionBookmark) {
        UserDefaults.standard.removeCollectionBookmark(named: collection.name)
        
        let collectionsFolder = URL.appDocumentsDirectory
            .appendingPathComponent("YouChip-Stat/Collections/\(collection.name)", isDirectory: true)
            .fixedFile()
        
        try? FileManager.default.removeItem(at: collectionsFolder)
        
        if isUserCollectionActive && selectedUserCollection?.name == collection.name {
            isUserCollectionActive = false
            selectedUserCollection = nil
            restoreDefaultData()
        }
        
        loadUserCollections()
        tagLibrary.refreshGlobalPools()
        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
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
    @State private var markupMode = MarkupMode.current
    @ObservedObject var timelineData = TimelineDataManager.shared
    @State private var hotkeyObserver: Any? = nil
    @State private var keyEventMonitor: Any? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if markupMode == .tagBased && tag != nil {
                Text("Тег будет добавлен в таймлайн: \(tag?.name ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            } else if markupMode == .standard && timelineData.selectedLineID == nil {
                Text("Выберите таймлайн перед добавлением тега")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(.bottom, 4)
            }
            
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
            markupMode = MarkupMode.current
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
        hotkeyManager.enableLabelHotkeyMode()
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .labelHotkeyPressed,
            object: nil,
            queue: .main
        ) { notification in
            if let labelInfo = notification.object as? (labelId: String, tagId: String),
               labelInfo.tagId == tag?.id {
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
            if event.keyCode == 36 || event.keyCode == 76 {
                completeSelection()
                return nil
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
        hotkeyManager.disableLabelHotkeyMode()
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
    let onSelect: (ExportMode) -> Void
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
            
            List {
                ForEach(tagGroupsWithTags(), id: \.name) { groupInfo in
                    Section(header: Text(groupInfo.name).font(.subheadline).bold()) {
                        ForEach(groupInfo.tags) { tag in
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
    
    private func tagGroupsWithTags() -> [TagGroupWithTags] {
        let allGroups = tagLibrary.allTagGroups
        var groupsWithTags: [String: (name: String, tags: [Tag])] = [:]
        groupsWithTags["uncategorized"] = ("Без группы", [])
        for tag in uniqueTags {
            var foundGroup = false
            
            for group in allGroups {
                if group.tags.contains(tag.id) {
                    if groupsWithTags[group.id] == nil {
                        groupsWithTags[group.id] = (group.name, [])
                    }
                    groupsWithTags[group.id]?.tags.append(tag)
                    foundGroup = true
                    break
                }
            }
            
            if !foundGroup {
                groupsWithTags["uncategorized"]?.tags.append(tag)
            }
        }
        
        return groupsWithTags.values
            .filter { !$0.tags.isEmpty }
            .map { TagGroupWithTags(name: $0.name, tags: $0.tags) }
            .sorted { $0.name < $1.name }
    }
    
    struct TagGroupWithTags {
        let name: String
        let tags: [Tag]
    }
}

struct StampLabelsOverlayView: View {
    let stamp: TimelineStamp
    let maxWidth: CGFloat
    let isResizing: Bool
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    
    @State private var displayedLabels: [Label] = []
    @State private var displayedTimeEvents: [TimeEvent] = []
    @State private var fontSize: CGFloat = 12
    
    init(stamp: TimelineStamp, maxWidth: CGFloat, isResizing: Bool = false) {
        self.stamp = stamp
        self.maxWidth = maxWidth
        self.isResizing = isResizing
    }
    
    var body: some View {
        GeometryReader { proxy in
            if !isResizing {
                let finalWidth = proxy.size.width
                let labelsWidth = finalWidth * 0.5
                let eventsWidth = finalWidth * 0.5
                
                HStack(spacing: 2) {
                    HStack(spacing: 4) {
                        ForEach(displayedLabels, id: \.id) { label in
                            LabelChip(label: label, baseColor: stamp.color, fontSize: fontSize)
                        }
                    }
                    .frame(width: labelsWidth, alignment: .leading)
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
    
    private func updateDisplayedItems(finalWidth: CGFloat) {
        let labelsWidth = finalWidth * 0.5
        let eventsWidth = finalWidth * 0.5
        updateDisplayedLabels(availableWidth: labelsWidth)
        updateDisplayedTimeEvents(availableWidth: eventsWidth)
    }
    
    private func updateDisplayedLabels(availableWidth: CGFloat) {
        let stampLabels = stamp.labels.compactMap { labelID in
            tagLibrary.findLabelById(labelID)
        }
        
        if stampLabels.isEmpty {
            displayedLabels = []
            return
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
        
        if let firstLabel = stampLabels.first {
            let firstLabelWidth = firstLabel.name.size(withSystemFontOfSize: testFont).width + 20
            
            if firstLabelWidth > availableWidth {
                testFont = 10
                let newFirstWidth = firstLabel.name.size(withSystemFontOfSize: testFont).width + 20
                
                if newFirstWidth > availableWidth {
                    displayedLabels = []
                    return
                } else {
                    displayedLabels = [firstLabel]
                    fontSize = testFont
                    return
                }
            }
        }
        
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
    
    private func updateDisplayedTimeEvents(availableWidth: CGFloat) {
        let events = stamp.timeEvents.compactMap { eventID in
            tagLibrary.allTimeEvents.first(where: { $0.id == eventID })
        }
        if events.isEmpty {
            displayedTimeEvents = []
            return
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
        
        if let firstEvent = events.first {
            let firstEventWidth = firstEvent.name.size(withSystemFontOfSize: testFont).width + 20
            
            if firstEventWidth > availableWidth {
                testFont = 10
                let newFirstWidth = firstEvent.name.size(withSystemFontOfSize: testFont).width + 20
                
                if newFirstWidth > availableWidth {
                    displayedTimeEvents = []
                    return
                } else {
                    displayedTimeEvents = [firstEvent]
                    fontSize = testFont
                    return
                }
            }
        }
        
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

class FocusStateManager: ObservableObject {
    static let shared = FocusStateManager()
    @Published var isAnyTextFieldFocused = false
    
    func setFocused(_ focused: Bool) {
        isAnyTextFieldFocused = false
    }
}

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
                DispatchQueue.main.async {
                    focusManager.setFocused(false)
                }
            }
            .onDisappear {
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                }
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
            if let responder = nsView.window?.firstResponder,
               let textField = responder as? NSTextField {
                var currentView: NSView? = textField
                var isInOurHierarchy = false
                
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
            
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if FocusTrackingView.nsView?.window == nil {
                    if self.parent.isFocused {
                        self.parent.isFocused = false
                        self.parent.focusManager.setFocused(false)
                    }
                    return
                }
                
                if let window = FocusTrackingView.nsView?.window,
                   let responder = window.firstResponder {
                    
                    let isTextFieldFocused = responder is NSTextField || responder is NSTextView
                    
                    if !isTextFieldFocused && self.parent.isFocused {
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

struct TimeGridView: View {
    let duration: Double
    let interval: Double
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        Canvas { context, size in
            let numberOfLines = Int(duration / interval) + 1
            for i in 0..<numberOfLines {
                let timePosition = Double(i) * interval
                let xPosition = (timePosition / duration) * Double(width)
                var path = Path()
                path.move(to: CGPoint(x: xPosition, y: 0))
                path.addLine(to: CGPoint(x: xPosition, y: height))
                context.stroke(
                    path,
                    with: .color(Color.gray.opacity(0.3)),
                    lineWidth: 1.0
                )
            }
        }
        .frame(width: width, height: height)
    }
}

struct TimelineTimestampsHeaderView: View {
    let duration: Double
    let interval: Double
    let width: CGFloat
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.gray.opacity(0.05))
                .frame(width: width, height: 30)
            ForEach(0..<(Int(duration / interval) + 1), id: \.self) { i in
                let timePosition = Double(i) * interval
                let xPosition = (timePosition / duration) * Double(width)
                
                Text(secondsToTimeString(timePosition))
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .position(x: CGFloat(xPosition), y: 5)
            }
        }
        .frame(width: width, height: 30)
    }
}

struct EventSelectionSheetView: View {
    let timeEvents: [TimeEvent]
    let onSelect: (TimeEvent) -> Void
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Выберите событие для экспорта")
                .font(.headline)
            
            List {
                Section(header: Text("Доступные события").font(.subheadline).bold()) {
                    ForEach(timeEvents) { event in
                        Button(event.name) {
                            onSelect(event)
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


extension DispatchWorkItem {
    private static var previousItem: DispatchWorkItem?
    
    static func cancelPreviousAndScheduleNew(after delay: TimeInterval = 0.1, action: @escaping () -> Void) {
        previousItem?.cancel()
        let newItem = DispatchWorkItem(block: action)
        previousItem = newItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: newItem)
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }
}

class FieldMapSelectionWindowController: NSWindowController {
    init(tag: Tag, imageBookmark: Data, onSave: @escaping (CGPoint) -> Void) {
        let view = FieldMapSelectionView(tag: tag, imageBookmark: imageBookmark, onSave: onSave)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Выбор позиции на карте для тега: \(tag.name)"
        super.init(window: window)
        window.styleMask = [.titled, .closable, .resizable]
        window.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension FieldMapSelectionWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        WindowsManager.shared.fieldMapWindowDidClose()
    }
}

struct FieldMapSelectionView: View {
    let tag: Tag
    let imageBookmark: Data
    let onSave: (CGPoint) -> Void
    
    @State private var selectedCoordinate: CGPoint? = nil
    @State private var fieldImage: NSImage? = nil
    @State private var imageSize: CGSize = .zero
    @State private var originalImageSize: CGSize = .zero
    @State private var normalizedCoordinate: CGPoint? = nil
    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        VStack(spacing: 16) {
            if let image = fieldImage {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(
                            GeometryReader { geo in
                                Color.clear.onAppear {
                                    originalImageSize = image.size
                                    imageSize = geo.size
                                }
                                .onChange(of: geo.size) { newSize in
                                    imageSize = newSize
                                    updateSelectedCoordinateForNewSize()
                                }
                            }
                        )
                        .overlay(
                            ZStack {
                                if let coordinate = selectedCoordinate {
                                    Circle()
                                        .fill(Color(hex: tag.color))
                                        .frame(width: 20, height: 20)
                                        .position(coordinate)
                                    
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .frame(width: 20, height: 20)
                                        .position(coordinate)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    if value.location.x >= 0 && value.location.x <= imageSize.width &&
                                       value.location.y >= 0 && value.location.y <= imageSize.height {
                                        selectedCoordinate = value.location
                                        normalizedCoordinate = CGPoint(
                                            x: value.location.x / imageSize.width,
                                            y: value.location.y / imageSize.height
                                        )
                                    }
                                }
                        )
                }
                .padding()
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
            } else {
                Text("Не удалось загрузить карту поля")
                    .foregroundColor(.red)
                    .padding()
            }
            
            HStack {
                Button("Отмена") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Сохранить") {
                    if let normalized = normalizedCoordinate {
                        onSave(normalized)
                    }
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.return)
                .disabled(selectedCoordinate == nil)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            loadFieldImage()
        }
    }
    
    private func updateSelectedCoordinateForNewSize() {
        guard let normalized = normalizedCoordinate else { return }
        selectedCoordinate = CGPoint(
            x: normalized.x * imageSize.width,
            y: normalized.y * imageSize.height
        )
    }
    
    private func loadFieldImage() {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: imageBookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if url.startAccessingSecurityScopedResource() {
                if let image = NSImage(contentsOf: url) {
                    fieldImage = image
                    originalImageSize = image.size
                }
                url.stopAccessingSecurityScopedResource()
            }
        } catch {
            print("Error loading field image: \(error)")
        }
    }
}
