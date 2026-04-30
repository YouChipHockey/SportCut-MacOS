import Foundation
import AppKit
import Combine

final class InMemoryStorageManager {
    
    static let shared = InMemoryStorageManager()
    
    private let userDefaults = UserDefaults.standard
    private let fileManager = FileManager.default
    /// Platform guard for CFPreferences payload size.
    /// Keep a small safety margin below the 4 MB hard limit.
    private let maxUserDefaultsBlobSize = 4_000_000
    
    private var saveToDiskTimer: Timer?
    private var pendingSave = false
    private let saveToDiskInterval: TimeInterval = 30.0
    
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    deinit {
        saveToDiskTimer?.invalidate()
    }
    
    @objc private func applicationWillTerminate() {
        saveToDiskTimer?.invalidate()
        saveToDiskImmediate()
        CollectionsBookmarksManager.shared.saveToFileImmediate()
    }
    
    func saveTimelines(_ timelines: [TimelineLine], for videoId: String) {
        let key = "timeline_\(videoId)"
        if let data = try? JSONEncoder().encode(timelines) {
            if data.count > maxUserDefaultsBlobSize {
                // Large timelines must bypass UserDefaults to avoid CFPreferences
                // hard-limit warnings/errors and UI stalls on save.
                userDefaults.removeObject(forKey: key)
                saveTimelineDataToFile(data, videoId: videoId)
            } else {
                userDefaults.set(data, forKey: key)
                scheduleSaveToDisk()
            }
        }
    }
    
    func loadTimelines(for videoId: String) -> [TimelineLine] {
        let key = "timeline_\(videoId)"
        guard let data = userDefaults.data(forKey: key),
              let timelines = try? JSONDecoder().decode([TimelineLine].self, from: data) else {
            return loadTimelinesFromFile(for: videoId)
        }
        return timelines
    }
    
    func deleteTimelines(for videoId: String) {
        let key = "timeline_\(videoId)"
        userDefaults.removeObject(forKey: key)
        deleteTimelinesFile(for: videoId)
    }
    
    func saveCollection(_ collection: CollectionData) {
        let key = "collection_\(collection.id)"
        if let data = try? JSONEncoder().encode(collection) {
            userDefaults.set(data, forKey: key)
            scheduleSaveToDisk()
        }
    }
    
    func loadCollection(id: String) -> CollectionData? {
        let key = "collection_\(id)"
        guard let data = userDefaults.data(forKey: key),
              let collection = try? JSONDecoder().decode(CollectionData.self, from: data) else {
            return loadCollectionFromFile(id: id)
        }
        return collection
    }
    
    func deleteCollection(id: String) {
        let key = "collection_\(id)"
        userDefaults.removeObject(forKey: key)
        scheduleSaveToDisk()
    }
    
    private func scheduleSaveToDisk() {
        guard !pendingSave else { return }
        pendingSave = true
        
        saveToDiskTimer?.invalidate()
        saveToDiskTimer = Timer.scheduledTimer(withTimeInterval: saveToDiskInterval, repeats: false) { [weak self] _ in
            self?.saveToDiskImmediate()
        }
    }
    
    func saveToDiskImmediate() {
        guard pendingSave else { return }
        pendingSave = false
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.saveTimelinesToDisk()
            self?.saveCollectionsToDisk()
        }
    }
    
    private func saveTimelinesToDisk() {
        let timelinesDirectory = getTimelinesDirectory()
        fileManager.createDirectoryIfNeeded(url: timelinesDirectory)
        
        let keys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("timeline_") }
        
        for key in keys {
            guard let data = userDefaults.data(forKey: key) else { continue }
            let videoId = String(key.dropFirst("timeline_".count))
            let fileURL = timelinesDirectory.appendingPathComponent("\(videoId).json")
            try? data.write(to: fileURL)
        }
    }
    
    private func saveCollectionsToDisk() {
        let keys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("collection_") }
        let existingCollectionIds = Set(keys.map { String($0.dropFirst("collection_".count)) })
        
        let collectionsDirectory = getCollectionsDirectory()
        guard fileManager.fileExists(atPath: collectionsDirectory.path) else { return }
        
        do {
            let folderContents = try fileManager.contentsOfDirectory(at: collectionsDirectory, includingPropertiesForKeys: nil)
            
            for folderURL in folderContents where folderURL.hasDirectoryPath {
                let folderId = folderURL.lastPathComponent
                if !existingCollectionIds.contains(folderId) {
                    try? fileManager.removeItem(at: folderURL)
                }
            }
        } catch {}
        
        for key in keys {
            guard let data = userDefaults.data(forKey: key),
                  let collection = try? JSONDecoder().decode(CollectionData.self, from: data) else {
                continue
            }
            saveCollectionToFile(collection)
        }
    }
    
    private func loadTimelinesFromFile(for videoId: String) -> [TimelineLine] {
        let fileURL = getTimelinesDirectory().appendingPathComponent("\(videoId).json")
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let timelines = try? JSONDecoder().decode([TimelineLine].self, from: data) else {
            return []
        }
        
        let key = "timeline_\(videoId)"
        if data.count <= maxUserDefaultsBlobSize {
            userDefaults.set(data, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
        return timelines
    }

    private func saveTimelineDataToFile(_ data: Data, videoId: String) {
        let timelinesDirectory = getTimelinesDirectory()
        fileManager.createDirectoryIfNeeded(url: timelinesDirectory)
        let fileURL = timelinesDirectory.appendingPathComponent("\(videoId).json")
        try? data.write(to: fileURL, options: .atomic)
    }
    
    private func deleteTimelinesFile(for videoId: String) {
        let fileURL = getTimelinesDirectory().appendingPathComponent("\(videoId).json")
        try? fileManager.removeItem(at: fileURL)
    }
    
    private func loadCollectionFromFile(id: String) -> CollectionData? {
        let collectionFolderUrl = getCollectionsDirectory().appendingPathComponent(id, isDirectory: true)
        
        guard fileManager.fileExists(atPath: collectionFolderUrl.path) else {
            return nil
        }
        
        let tagGroupsURL = collectionFolderUrl.appendingPathComponent("tagGroups.json")
        let tagsURL = collectionFolderUrl.appendingPathComponent("tags.json")
        let labelGroupsURL = collectionFolderUrl.appendingPathComponent("labelGroups.json")
        let labelsURL = collectionFolderUrl.appendingPathComponent("labels.json")
        let timeEventsURL = collectionFolderUrl.appendingPathComponent("timeEvents.json")
        let playFieldURL = collectionFolderUrl.appendingPathComponent("playField.json")
        
        guard let tagGroupsData = try? Data(contentsOf: tagGroupsURL),
              let tagsData = try? Data(contentsOf: tagsURL),
              let labelGroupsData = try? Data(contentsOf: labelGroupsURL),
              let labelsData = try? Data(contentsOf: labelsURL),
              let tagGroups = try? JSONDecoder().decode(TagGroupsData.self, from: tagGroupsData),
              let tags = try? JSONDecoder().decode(TagsData.self, from: tagsData),
              let labelGroups = try? JSONDecoder().decode(LabelGroupsData.self, from: labelGroupsData),
              let labels = try? JSONDecoder().decode(LabelsData.self, from: labelsData) else {
            return nil
        }
        
        let timeEvents: [TimeEvent]
        if fileManager.fileExists(atPath: timeEventsURL.path),
           let timeEventsData = try? Data(contentsOf: timeEventsURL),
           let decoded = try? JSONDecoder().decode(TimeEventsData.self, from: timeEventsData) {
            timeEvents = decoded.events
        } else {
            timeEvents = []
        }
        
        let playField: PlayField?
        if fileManager.fileExists(atPath: playFieldURL.path),
           let playFieldData = try? Data(contentsOf: playFieldURL),
           let decoded = try? JSONDecoder().decode(PlayField.self, from: playFieldData) {
            playField = decoded
        } else {
            playField = nil
        }
        
        let collection = CollectionData(
            id: id,
            tagGroups: tagGroups.tagGroups,
            tags: tags.tags,
            labelGroups: labelGroups.labelGroups,
            labels: labels.labels,
            timeEvents: timeEvents,
            playField: playField
        )
        
        let key = "collection_\(id)"
        if let data = try? JSONEncoder().encode(collection) {
            userDefaults.set(data, forKey: key)
        }
        
        return collection
    }
    
    private func saveCollectionToFile(_ collection: CollectionData) {
        let collectionFolderUrl = getCollectionsDirectory().appendingPathComponent(collection.id, isDirectory: true)
        
        fileManager.createDirectoryIfNeeded(url: collectionFolderUrl)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        if let tagGroupsData = try? encoder.encode(TagGroupsData(tagGroups: collection.tagGroups)) {
            try? tagGroupsData.write(to: collectionFolderUrl.appendingPathComponent("tagGroups.json"))
        }
        
        if let tagsData = try? encoder.encode(TagsData(tags: collection.tags)) {
            try? tagsData.write(to: collectionFolderUrl.appendingPathComponent("tags.json"))
        }
        
        if let labelGroupsData = try? encoder.encode(LabelGroupsData(labelGroups: collection.labelGroups)) {
            try? labelGroupsData.write(to: collectionFolderUrl.appendingPathComponent("labelGroups.json"))
        }
        
        if let labelsData = try? encoder.encode(LabelsData(labels: collection.labels)) {
            try? labelsData.write(to: collectionFolderUrl.appendingPathComponent("labels.json"))
        }
        
        if !collection.timeEvents.isEmpty,
           let timeEventsData = try? encoder.encode(TimeEventsData(events: collection.timeEvents)) {
            try? timeEventsData.write(to: collectionFolderUrl.appendingPathComponent("timeEvents.json"))
        }
        
        if let playField = collection.playField,
           let playFieldData = try? encoder.encode(playField) {
            try? playFieldData.write(to: collectionFolderUrl.appendingPathComponent("playField.json"))
        }
    }
    
    private func getTimelinesDirectory() -> URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("YouChip-Stat/Timelines", isDirectory: true)
    }
    
    private func getCollectionsDirectory() -> URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("YouChip-Stat/Collections", isDirectory: true)
    }
}

struct CollectionData: Codable {
    let id: String
    var tagGroups: [TagGroup]
    var tags: [Tag]
    var labelGroups: [LabelGroupData]
    var labels: [Label]
    var timeEvents: [TimeEvent]
    var playField: PlayField?
}
