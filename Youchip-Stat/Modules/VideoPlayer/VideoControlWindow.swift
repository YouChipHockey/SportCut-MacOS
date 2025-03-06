import SwiftUI
import AVKit
import Cocoa

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
    init(id: UUID = UUID(), timeStart: String, timeFinish: String, colorHex: String, label: String, labels: [String]) {
        self.id = id
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
    func addStampToSelectedLine(name: String, timeStart: String, timeFinish: String, color: String, labels: [String]) {
        guard let lineID = selectedLineID,
              let idx = lines.firstIndex(where: { $0.id == lineID }) else { return }
        let stamp = TimelineStamp(timeStart: timeStart, timeFinish: timeFinish, colorHex: color, label: name, labels: labels)
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

class WindowsManager {
    static let shared = WindowsManager()
    
    var videoWindow: VideoPlayerWindowController?
    var controlWindow: FullControlWindowController?
    var tagLibraryWindow: TagLibraryWindowController?
    private var isClosing = false
    
    func closeAll() {
        videoWindow?.window?.delegate = nil
        controlWindow?.window?.delegate = nil
        tagLibraryWindow?.window?.delegate = nil
        videoWindow?.close()
        controlWindow?.close()
        tagLibraryWindow?.close()
        
        VideoPlayerManager.shared.deleteVideo()
    }
    
    func openVideo(filesFile: FilesFile) {
        guard let file = filesFile.url else { return }
        
        TimelineDataManager.shared.currentBookmark = filesFile.videoData.bookmark
        TimelineDataManager.shared.lines = filesFile.videoData.timelines
        TimelineDataManager.shared.selectedLineID = filesFile.videoData.timelines.first?.id
        VideoPlayerManager.shared.loadVideo(from: file)
        
        videoWindow = VideoPlayerWindowController()
        controlWindow = FullControlWindowController()
        tagLibraryWindow = TagLibraryWindowController()
        
        // 3. Позиционируем окна на экране
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            
            // Высота нижней трети
            let bottomHeight = screenFrame.height / 3
            // Высота верхних двух третей
            let topHeight = screenFrame.height - bottomHeight
            
            // Окно таймлайна (нижняя треть, на всю ширину)
            let timelineRect = NSRect(
                x: screenFrame.minX,
                y: screenFrame.minY,           // снизу
                width: screenFrame.width,
                height: bottomHeight
            )
            controlWindow?.window?.setFrame(timelineRect, display: true)
            
            // Окно библиотеки (левая часть верхних 2/3)
            let libraryRect = NSRect(
                x: screenFrame.minX,
                y: screenFrame.minY + bottomHeight,
                width: screenFrame.width / 3,
                height: topHeight
            )
            tagLibraryWindow?.window?.setFrame(libraryRect, display: true)
            
            // Окно видео (правая часть верхних 2/3)
            let videoRect = NSRect(
                x: screenFrame.minX + screenFrame.width / 3,
                y: screenFrame.minY + bottomHeight,
                width: (screenFrame.width * 2) / 3,
                height: topHeight
            )
            videoWindow?.window?.setFrame(videoRect, display: true)
        }
        
        // 4. Показываем окна
        videoWindow?.showWindow(nil)
        controlWindow?.showWindow(nil)
        tagLibraryWindow?.showWindow(nil)
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
    @State private var showLabelEditSheet = false
    @State private var editingStampLineID: UUID?
    @State private var editingStampID: UUID?
    
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
    
    var body: some View {
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
                        Button("\(String(format: "%.1f", speed))x") {
                            videoManager.changePlaybackSpeed(to: speed)
                        }
                    }
                } label: {
                    Text("Speed x\(String(format: "%.1f", videoManager.playbackSpeed))")
                }
                Spacer()
            }
            Slider(value: $sliderValue, in: 0...(videoManager.videoDuration > 0 ? videoManager.videoDuration : 1), onEditingChanged: { editing in
                if !editing { videoManager.seek(to: sliderValue) }
                isDraggingSlider = editing
            })
            .onReceive(videoManager.$currentTime) { current in
                if !isDraggingSlider { sliderValue = current }
            }
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
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(timelineData.lines) { line in
                        TimelineLineView(line: line, isSelected: (line.id == timelineData.selectedLineID), onSelect: { timelineData.selectLine(line.id) }, onEditLabelsRequest: { stampID in
                            editingStampLineID = line.id
                            editingStampID = stampID
                            showLabelEditSheet = true
                        })
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .frame(minWidth: 800, minHeight: 300)
        .sheet(isPresented: $showAddLineSheet) {
            AddLineSheet { newLineName in
                timelineData.addLine(name: newLineName)
            }
        }
        .sheet(isPresented: $showLabelEditSheet) {
            if let lineID = editingStampLineID,
               let stampID = editingStampID,
               let lineIndex = timelineData.lines.firstIndex(where: { $0.id == lineID }),
               let stampIndex = timelineData.lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) {
                let currentLabels = timelineData.lines[lineIndex].stamps[stampIndex].labels
                let stampName = timelineData.lines[lineIndex].stamps[stampIndex].label
                LabelSelectionSheet(stampName: stampName, initialLabels: currentLabels, tag: nil, tagLibrary: TagLibraryManager.shared) { newLabels in
                    timelineData.updateStampLabels(lineID: lineID, stampID: stampID, newLabels: newLabels)
                }
            } else {
                Text("Ошибка: не найден таймстемп")
            }
        }
    }
}

class FullControlWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let view = FullControlView()
        let hostingController = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hostingController)
        w.title = "Таймлайны"
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

struct TimelineLineView: View {
    @ObservedObject var videoManager = VideoPlayerManager.shared
    let line: TimelineLine
    let isSelected: Bool
    let onSelect: () -> Void
    let onEditLabelsRequest: (UUID) -> Void
    var body: some View {
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
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 30)
                let sortedStamps = line.stamps.sorted { $0.duration > $1.duration }
                ForEach(sortedStamps) { stamp in
                    let total = max(1, videoManager.videoDuration)
                    let startRatio = stamp.startSeconds / total
                    let durationRatio = stamp.duration / total
                    let stampWidth = durationRatio * geo.size.width
                    let stampX = startRatio * geo.size.width
                    Rectangle()
                        .fill(stamp.color)
                        .frame(width: stampWidth, height: 30)
                        .position(x: stampX + stampWidth / 2, y: 15)
                        .onTapGesture { videoManager.seek(to: stamp.startSeconds) }
                        .contextMenu {
                            Text("Stamp: \(stamp.label)")
                            if !stamp.labels.isEmpty {
                                ForEach(stamp.labels, id: \.self) { lbl in
                                    Text(lbl)
                                }
                                Divider()
                            }
                            Button("Удалить тег") {
                                TimelineDataManager.shared.removeStamp(lineID: line.id, stampID: stamp.id)
                            }
                            Button("Редактировать лейблы") { onEditLabelsRequest(stamp.id) }
                        }
                }
            }
            .frame(height: 30)
        }
    }
}

struct TagLibraryView: View {
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    @State private var showLabelSheet = false
    @State private var selectedTag: Tag? = nil
    var body: some View {
        VStack(alignment: .leading) {
            Text("Группы тегов")
                .font(.headline)
                .padding()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tagLibrary.tagGroups) { group in
                        DisclosureGroup(group.name) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 10) {
                                ForEach(group.tags, id: \.self) { tagID in
                                    if let tag = tagLibrary.tags.first(where: { $0.id == tagID }) {
                                        Button(tag.name) {
                                            videoManager.player?.pause()
                                            selectedTag = tag
                                            showLabelSheet = true
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .sheet(isPresented: $showLabelSheet) {
            if let tag = selectedTag {
                LabelSelectionSheet(stampName: tag.name, initialLabels: [], tag: tag, tagLibrary: tagLibrary) { selectedLabels in
                    let currentTime = videoManager.currentTime
                    let startTime = max(0, currentTime - tag.defaultTimeBefore)
                    let finishTime = startTime + tag.defaultTimeBefore + tag.defaultTimeAfter
                    let timeStartString = secondsToTimeString(startTime)
                    let timeFinishString = secondsToTimeString(finishTime)
                    timelineData.addStampToSelectedLine(name: tag.name, timeStart: timeStartString, timeFinish: timeFinishString, color: tag.color, labels: selectedLabels)
                }
            } else {
                Text("Не выбран тег").padding()
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
    @Environment(\.dismiss) private var dismiss
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
                Button("Отмена") { dismiss() }
                Button("Добавить") {
                    onAdd(lineName)
                    dismiss()
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
    let onDone: ([String]) -> Void
    @State var selectedLabels: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    var filteredLabelGroups: [LabelGroupData] {
        if let tag = tag {
            return tagLibrary.labelGroups.filter { tag.lablesGroup.contains($0.id) }
        } else {
            return tagLibrary.labelGroups
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Таймстемп: \(stampName)")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(filteredLabelGroups) { group in
                        DisclosureGroup(group.name) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                                ForEach(group.lables, id: \.self) { labelID in
                                    if let label = tagLibrary.labels.first(where: { $0.id == labelID }) {
                                        Toggle(isOn: Binding(
                                            get: { selectedLabels.contains(label.id) },
                                            set: { newValue in
                                                if newValue { selectedLabels.insert(label.id) } else { selectedLabels.remove(label.id) }
                                            }
                                        )) {
                                            Text(label.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                Button("Добавить") {
                    onDone(Array(selectedLabels))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 300, minHeight: 400)
        .onAppear { selectedLabels = Set(initialLabels) }
    }
}
