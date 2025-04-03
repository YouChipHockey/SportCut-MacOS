import Foundation
import SwiftUI
import Combine
import Cocoa

// MARK: - Tag Models
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

// MARK: - Label Models
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

// MARK: - Timeline Models
struct TimelineStamp: Identifiable, Codable {
    let id: UUID
    var idTag: String
    var timeStart: String
    var timeFinish: String
    var colorHex: String
    var label: String
    var labels: [String]
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

// MARK: - Managers
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
    
    private func loadJSON<T: Decodable>(filename: String) -> T? {
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

class WindowsManager {
    static let shared = WindowsManager()
    
    var videoWindow: VideoPlayerWindowController?
    var controlWindow: FullControlWindowController?
    var tagLibraryWindow: TagLibraryWindowController?
    private var isClosing = true
    
    func closeAll() {
        videoWindow?.window?.delegate = nil
        controlWindow?.window?.delegate = nil
        tagLibraryWindow?.window?.delegate = nil
        videoWindow?.close()
        controlWindow?.close()
        tagLibraryWindow?.close()
        
        VideoPlayerManager.shared.deleteVideo()
        isClosing = true
    }
    
    func openVideo(filesFile: FilesFile) {
        guard let file = filesFile.url, isClosing else { return }
        
        UserDefaults.standard.set("", forKey: "editingStampLineID")
        UserDefaults.standard.set("", forKey: "editingStampID")
        isClosing = false
        
        TimelineDataManager.shared.currentBookmark = filesFile.videoData.bookmark
        TimelineDataManager.shared.lines = filesFile.videoData.timelines
        TimelineDataManager.shared.selectedLineID = filesFile.videoData.timelines.first?.id
        VideoPlayerManager.shared.loadVideo(from: file)
        
        videoWindow = VideoPlayerWindowController()
        controlWindow = FullControlWindowController()
        tagLibraryWindow = TagLibraryWindowController()
        
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let bottomHeight = screenFrame.height / 3
            let topHeight = screenFrame.height - bottomHeight - 40
            
            let timelineRect = NSRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: screenFrame.width,
                height: bottomHeight
            )
            controlWindow?.window?.setFrame(timelineRect, display: true)
            
            let libraryRect = NSRect(
                x: screenFrame.minX,
                y: screenFrame.minY + bottomHeight,
                width: screenFrame.width / 3,
                height: topHeight
            )
            tagLibraryWindow?.window?.setFrame(libraryRect, display: true)
            
            let videoRect = NSRect(
                x: screenFrame.minX + screenFrame.width / 3,
                y: screenFrame.minY + bottomHeight,
                width: (screenFrame.width * 2) / 3,
                height: topHeight
            )
            videoWindow?.window?.setFrame(videoRect, display: true)
        }
        
        videoWindow?.showWindow(nil)
        controlWindow?.showWindow(nil)
        tagLibraryWindow?.showWindow(nil)
    }
}

// MARK: - Helper Functions
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