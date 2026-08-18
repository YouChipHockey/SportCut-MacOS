//
//  CollectionsBookmarksManager.swift
//  Youchip-Stat
//
//  Created on 11.02.2026.
//

import Foundation
import AppKit

/// Structure for storing collection metadata in CollectionsBookmarks.json
struct CollectionInfo: Codable, Equatable {
    let id: String
    let name: String
    var tagLibraryDisplayMode: String?

    var displayMode: CollectionTagLibraryDisplayMode {
        CollectionTagLibraryDisplayMode(rawValue: tagLibraryDisplayMode ?? CollectionTagLibraryDisplayMode.grouped.rawValue) ?? .grouped
    }

    init(
        id: String,
        name: String,
        tagLibraryDisplayMode: CollectionTagLibraryDisplayMode = .grouped
    ) {
        self.id = id
        self.name = name
        self.tagLibraryDisplayMode = tagLibraryDisplayMode.rawValue
    }
}

class CollectionsBookmarksManager {
    
    static let shared = CollectionsBookmarksManager()
    
    private let fileManager = FileManager.default
    
    private var collectionsBookmarksFile: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("YouChip-Stat/CollectionsBookmarks.json")
    }
    
    private var collectionsDirectory: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("YouChip-Stat/Collections", isDirectory: true)
    }
    
    private init() {
        createDirectoryIfNeeded()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func applicationWillTerminate() {
        saveTimer?.invalidate()
        saveToFileImmediate()
    }
    
    // MARK: - Public Methods
    
    /// Saves collection info to CollectionsBookmarks.json
    /// After initial deduplication, allows duplicate names (they will have suffixes added by ensureUniqueCollectionName)
    private var pendingSave = false
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 2.0
    
    private var collectionsCache: [CollectionInfo] = []
    private let cacheLock = NSLock()
    
    func saveCollection(
        id: String,
        name: String,
        tagLibraryDisplayMode: CollectionTagLibraryDisplayMode? = nil
    ) {
        cacheLock.lock()
        if collectionsCache.isEmpty {
            collectionsCache = loadCollectionsFromFile()
        }

        if let index = collectionsCache.firstIndex(where: { $0.id == id }) {
            let mode = tagLibraryDisplayMode ?? collectionsCache[index].displayMode
            collectionsCache[index] = CollectionInfo(id: id, name: name, tagLibraryDisplayMode: mode)
        } else {
            collectionsCache.append(
                CollectionInfo(
                    id: id,
                    name: name,
                    tagLibraryDisplayMode: tagLibraryDisplayMode ?? .grouped
                )
            )
        }
        cacheLock.unlock()

        scheduleSave()
    }
    
    func removeCollection(id: String) {
        cacheLock.lock()
        if collectionsCache.isEmpty {
            collectionsCache = loadCollectionsFromFile()
        }
        let beforeCount = collectionsCache.count
        collectionsCache.removeAll { $0.id == id }
        let afterCount = collectionsCache.count
        cacheLock.unlock()
        
        if beforeCount != afterCount {
            print("✅ CollectionsBookmarks: Removed collection \(id) from cache")
            scheduleSave()
        } else {
            print("⚠️ CollectionsBookmarks: Collection \(id) not found in cache")
        }
    }
    
    func loadCollections() -> [CollectionInfo] {
        cacheLock.lock()
        if !collectionsCache.isEmpty {
            let cached = collectionsCache
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        let collections = loadCollectionsFromFile()
        
        cacheLock.lock()
        collectionsCache = collections
        cacheLock.unlock()
        
        return collections
    }
    
    private func loadCollectionsFromFile() -> [CollectionInfo] {
        guard fileManager.fileExists(atPath: collectionsBookmarksFile.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: collectionsBookmarksFile)
            let decoder = JSONDecoder()
            return try decoder.decode([CollectionInfo].self, from: data)
        } catch {
            print("❌ CollectionsBookmarks: Error loading collections - \(error.localizedDescription)")
            return []
        }
    }
    
    private func scheduleSave() {
        guard !pendingSave else { return }
        pendingSave = true
        
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            self?.saveToFileImmediate()
        }
    }
    
    func saveToFileImmediate() {
        guard pendingSave else { return }
        pendingSave = false
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            self.cacheLock.lock()
            let collectionsToSave = self.collectionsCache
            self.cacheLock.unlock()
            
            self.saveCollections(collectionsToSave)
        }
    }
    
    /// Loads CollectionBookmark objects from file system based on CollectionsBookmarks.json
    /// This is called once at app launch
    func loadCollectionBookmarks() -> [CollectionBookmark] {
        let collectionInfos = loadCollections()
        print("📚 CollectionsBookmarksManager: Loading \(collectionInfos.count) collections from CollectionsBookmarks.json")
        var bookmarks: [CollectionBookmark] = []
        
        for info in collectionInfos {
            print("📚 CollectionsBookmarksManager: Processing collection '\(info.name)' (id: \(info.id))")
            if let bookmark = loadCollectionBookmark(from: info) {
                print("✅ CollectionsBookmarksManager: Successfully created bookmark for '\(info.name)'")
                bookmarks.append(bookmark)
            } else {
                print("❌ CollectionsBookmarksManager: Failed to create bookmark for '\(info.name)'")
            }
        }
        
        print("📚 CollectionsBookmarksManager: Loaded \(bookmarks.count) collection bookmarks")
        return bookmarks
    }
    
    /// Scans Collections folder and adds all collections to CollectionsBookmarks.json
    /// Also cleans up duplicates with same base name (e.g., "Col", "Col (1)", "Col (2)")
    /// Keeps only the one with latest creation date or highest number
    /// This runs only once - after that, duplicate names are allowed with suffixes
    func cleanupDuplicateCollections() {
        // Check if deduplication was already done in Keychain
        if let keychainValue = KeychainHelper.shared.getBool(forKey: UserDefaults.Keys.collectionsDeduplicationDone),
           keychainValue {
            print("✅ CollectionsBookmarks: Deduplication already done (from Keychain), skipping")
            return
        }
        
        // Migrate from UserDefaults to Keychain if needed (for backward compatibility)
        if UserDefaults.standard.bool(forKey: UserDefaults.Keys.collectionsDeduplicationDone) {
            // Migrate from UserDefaults to Keychain
            _ = KeychainHelper.shared.saveBool(true, forKey: UserDefaults.Keys.collectionsDeduplicationDone)
            UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.collectionsDeduplicationDone)
            print("✅ CollectionsBookmarks: Migrated deduplication flag from UserDefaults to Keychain")
            return
        }
        
        guard fileManager.fileExists(atPath: collectionsDirectory.path) else {
            // Mark as done even if directory doesn't exist
            _ = KeychainHelper.shared.saveBool(true, forKey: UserDefaults.Keys.collectionsDeduplicationDone)
            return
        }
        
        do {
            let collectionFolders = try fileManager.contentsOfDirectory(
                at: collectionsDirectory,
                includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            // Filter only directories
            let validFolders = collectionFolders.filter { folder in
                guard let isDirectory = try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else {
                    return false
                }
                return isDirectory == true
            }
            
            // Group collections by base name
            var collectionsByName: [String: [URL]] = [:]
            
            for folder in validFolders {
                let folderName = folder.lastPathComponent
                let baseName = extractBaseName(from: folderName)
                
                if collectionsByName[baseName] == nil {
                    collectionsByName[baseName] = []
                }
                collectionsByName[baseName]?.append(folder)
            }
            
            // Process each group - deduplicate and rename
            var finalCollections: [CollectionInfo] = []
            
            for (baseName, folders) in collectionsByName {
                if folders.count > 1 {
                    // Find the folder to keep
                    let folderToKeep = selectFolderToKeep(from: folders)
                    let oldId = folderToKeep.lastPathComponent
                    
                    // Remove other folders
                    for folder in folders {
                        if folder != folderToKeep {
                            let folderId = folder.lastPathComponent
                            try? fileManager.removeItem(at: folder)
                            print("🗑️ CollectionsBookmarks: Removed duplicate collection folder: \(folderId)")
                        }
                    }
                    
                    // Rename kept folder if it has number suffix
                    let finalId: String
                    if oldId != baseName {
                        let newPath = folderToKeep.deletingLastPathComponent().appendingPathComponent(baseName)
                        if fileManager.fileExists(atPath: newPath.path) {
                            try? fileManager.removeItem(at: newPath)
                        }
                        try? fileManager.moveItem(at: folderToKeep, to: newPath)
                        print("📝 CollectionsBookmarks: Renamed collection folder: \(oldId) -> \(baseName)")
                        finalId = baseName
                    } else {
                        finalId = oldId
                    }
                    
                    // Add to final collections list
                    finalCollections.append(CollectionInfo(id: finalId, name: finalId))
                } else {
                    // Single folder - check if it needs renaming
                    let folder = folders[0]
                    let folderId = folder.lastPathComponent
                    let baseName = extractBaseName(from: folderId)
                    
                    let finalId: String
                    if folderId != baseName {
                        // Rename folder to remove number suffix
                        let newPath = folder.deletingLastPathComponent().appendingPathComponent(baseName)
                        if fileManager.fileExists(atPath: newPath.path) {
                            try? fileManager.removeItem(at: newPath)
                        }
                        try? fileManager.moveItem(at: folder, to: newPath)
                        print("📝 CollectionsBookmarks: Renamed single collection folder: \(folderId) -> \(baseName)")
                        finalId = baseName
                    } else {
                        finalId = folderId
                    }
                    
                    finalCollections.append(CollectionInfo(id: finalId, name: finalId))
                }
            }
            
            // Update CollectionsBookmarks.json with all collections
            // Merge with existing collections to preserve names if they were changed
            var existingCollections = loadCollections()
            var existingById: [String: CollectionInfo] = [:]
            for existing in existingCollections {
                existingById[existing.id] = existing
            }
            
            // Update final collections with existing names if they exist
            var updatedCollections: [CollectionInfo] = []
            for collection in finalCollections {
                if let existing = existingById[collection.id] {
                    // Keep existing name if it was changed
                    updatedCollections.append(
                        CollectionInfo(
                            id: collection.id,
                            name: existing.name,
                            tagLibraryDisplayMode: existing.displayMode
                        )
                    )
                } else {
                    // Use id as name for new collections
                    updatedCollections.append(CollectionInfo(id: collection.id, name: collection.id))
                }
            }
            
            // Don't enforce unique names during deduplication - just save what we have
            // After deduplication, users can create collections with same names and they'll get suffixes
            saveCollections(updatedCollections)
            
            // Mark deduplication as done
            _ = KeychainHelper.shared.saveBool(true, forKey: UserDefaults.Keys.collectionsDeduplicationDone)
            
            print("✅ CollectionsBookmarks: Updated CollectionsBookmarks.json with \(updatedCollections.count) collections")
            print("✅ CollectionsBookmarks: Deduplication completed and marked as done")
            
            // Notify that collections were updated
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
            }
            
        } catch {
            print("❌ CollectionsBookmarks: Error cleaning up duplicates - \(error.localizedDescription)")
            // Mark as done even on error to prevent retries
            _ = KeychainHelper.shared.saveBool(true, forKey: UserDefaults.Keys.collectionsDeduplicationDone)
        }
    }
    
    // MARK: - Private Methods
    
    private func createDirectoryIfNeeded() {
        let directory = collectionsBookmarksFile.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
    
    private func saveCollections(_ collections: [CollectionInfo]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(collections)
            try data.write(to: collectionsBookmarksFile)
        } catch {
            print("❌ CollectionsBookmarks: Error saving collections - \(error.localizedDescription)")
        }
    }
    
    /// Loads CollectionBookmark from file system based on CollectionInfo
    private func loadCollectionBookmark(from info: CollectionInfo) -> CollectionBookmark? {
        let collectionFolderUrl = collectionsDirectory.appendingPathComponent(info.id, isDirectory: true)
        
        guard fileManager.fileExists(atPath: collectionFolderUrl.path) else {
            print("⚠️ CollectionsBookmarks: Collection folder not found for \(info.name) (id: \(info.id))")
            return nil
        }
        
        let tagGroupsURL = collectionFolderUrl.appendingPathComponent("tagGroups.json")
        let tagsURL = collectionFolderUrl.appendingPathComponent("tags.json")
        let labelGroupsURL = collectionFolderUrl.appendingPathComponent("labelGroups.json")
        let labelsURL = collectionFolderUrl.appendingPathComponent("labels.json")
        let timeEventsURL = collectionFolderUrl.appendingPathComponent("timeEvents.json")
        let playFieldURL = collectionFolderUrl.appendingPathComponent("playField.json")
        
        guard fileManager.fileExists(atPath: tagGroupsURL.path),
              fileManager.fileExists(atPath: tagsURL.path),
              fileManager.fileExists(atPath: labelGroupsURL.path),
              fileManager.fileExists(atPath: labelsURL.path) else {
            print("⚠️ CollectionsBookmarks: Required files missing for \(info.name)")
            return nil
        }
        
        do {
            // Use makeBookmark() which includes .withSecurityScope option
            guard let tagGroupsBookmark = tagGroupsURL.makeBookmark(),
                  let tagsBookmark = tagsURL.makeBookmark(),
                  let labelGroupsBookmark = labelGroupsURL.makeBookmark(),
                  let labelsBookmark = labelsURL.makeBookmark() else {
                print("⚠️ CollectionsBookmarks: Failed to create bookmarks for \(info.name)")
                return nil
            }
            
            let timeEventsBookmark = fileManager.fileExists(atPath: timeEventsURL.path) ? (timeEventsURL.makeBookmark() ?? Data()) : Data()
            let playFieldBookmark = fileManager.fileExists(atPath: playFieldURL.path) ? playFieldURL.makeBookmark() : nil
            
            return CollectionBookmark(
                id: info.id,
                name: info.name,
                tagGroupsBookmark: tagGroupsBookmark,
                tagsBookmark: tagsBookmark,
                labelGroupsBookmark: labelGroupsBookmark,
                labelsBookmark: labelsBookmark,
                timeEventsBookmark: timeEventsBookmark,
                playFieldBookmark: playFieldBookmark
            )
        } catch {
            print("❌ CollectionsBookmarks: Error creating bookmark for \(info.name) - \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Extracts base name from collection folder name
    /// "Col" -> "Col", "Col (1)" -> "Col", "Col (2)" -> "Col"
    private func extractBaseName(from folderName: String) -> String {
        let pattern = #"^(.+?)\s*\(\d+\)$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: folderName, options: [], range: NSRange(location: 0, length: folderName.utf16.count)),
           let range = Range(match.range(at: 1), in: folderName) {
            return String(folderName[range]).trimmingCharacters(in: .whitespaces)
        }
        return folderName.trimmingCharacters(in: .whitespaces)
    }
    
    /// Extracts number from collection folder name
    /// "Col" -> nil, "Col (1)" -> 1, "Col (2)" -> 2
    private func extractNumber(from folderName: String) -> Int? {
        let pattern = #"\((\d+)\)$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: folderName, options: [], range: NSRange(location: 0, length: folderName.utf16.count)),
           let range = Range(match.range(at: 1), in: folderName),
           let number = Int(String(folderName[range])) {
            return number
        }
        return nil
    }
    
    /// Selects folder to keep from duplicates based on creation date or highest number
    private func selectFolderToKeep(from folders: [URL]) -> URL {
        // Try to get creation dates
        var foldersWithDates: [(url: URL, date: Date, number: Int?)] = []
        
        for folder in folders {
            let date: Date
            if let attributes = try? fileManager.attributesOfItem(atPath: folder.path),
               let creationDate = attributes[.creationDate] as? Date {
                date = creationDate
            } else {
                date = Date.distantPast
            }
            
            let number = extractNumber(from: folder.lastPathComponent)
            foldersWithDates.append((url: folder, date: date, number: number))
        }
        
        // Sort by date (newest first), then by number (highest first)
        foldersWithDates.sort { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            let lhsNum = lhs.number ?? -1
            let rhsNum = rhs.number ?? -1
            return lhsNum > rhsNum
        }
        
        return foldersWithDates.first!.url
    }
    
    /// Updates collection id in CollectionsBookmarks.json
    private func updateCollectionId(oldId: String, newId: String) {
        var collections = loadCollections()
        if let index = collections.firstIndex(where: { $0.id == oldId }) {
            let oldInfo = collections[index]
            collections[index] = CollectionInfo(id: newId, name: oldInfo.name, tagLibraryDisplayMode: oldInfo.displayMode)
            saveCollections(collections)
        }
    }
    
    // Note: ensureUniqueNames() was removed - after initial deduplication,
    // duplicate names are allowed and will get suffixes added by ensureUniqueCollectionName()

    // MARK: - Collection menu operations

    func collectionBookmark(for id: String) -> CollectionBookmark? {
        guard let info = loadCollections().first(where: { $0.id == id }) else { return nil }
        return loadCollectionBookmark(from: info)
    }

    func renameCollection(id: String, newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        cacheLock.lock()
        if collectionsCache.isEmpty {
            collectionsCache = loadCollectionsFromFile()
        }
        guard let index = collectionsCache.firstIndex(where: { $0.id == id }) else {
            cacheLock.unlock()
            return false
        }

        let manager = CustomCollectionManager()
        let uniqueName = manager.ensureUniqueCollectionName(trimmed, collectionID: id)
        let mode = collectionsCache[index].displayMode
        collectionsCache[index] = CollectionInfo(id: id, name: uniqueName, tagLibraryDisplayMode: mode)
        cacheLock.unlock()

        scheduleSave()
        CollectionsBackupManager.shared.syncFromUserDefaults()
        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
        return true
    }

    @discardableResult
    func duplicateCollection(id: String) -> CollectionInfo? {
        guard let info = loadCollections().first(where: { $0.id == id }),
              let data = InMemoryStorageManager.shared.loadCollection(id: id) else {
            return nil
        }

        let newId = UUID().uuidString
        let manager = CustomCollectionManager()
        let copySuffix = NSLocalizedString("CollectionsCopySuffix", comment: "")
        let baseName = "\(info.name) \(copySuffix)"
        let newName = manager.ensureUniqueCollectionName(baseName, collectionID: newId)

        let sourceFolder = collectionsDirectory.appendingPathComponent(id, isDirectory: true)
        let destFolder = collectionsDirectory.appendingPathComponent(newId, isDirectory: true)
        if fileManager.fileExists(atPath: sourceFolder.path) {
            try? fileManager.copyItem(at: sourceFolder, to: destFolder)
        }

        // Копия обязана получить СВОИ id: иначе она делит их с оригиналом, а глобальные пулы
        // дедуплицируются по id и оставляют копию из первой по списку коллекции — правки во
        // второй нигде не видны. Перевязываем и раскладку со связками (см. CollectionIdRegenerator).
        let sourceFields: [PlayField] = data.playFields ?? (data.playField.map { field in [field] } ?? [])
        let sourceLayout = TagFreeLayoutStorage.loadLayoutIfExists(
            collectionId: id,
            tags: data.tags,
            labels: data.labels,
            timeEvents: data.timeEvents,
            playFields: sourceFields
        )
        let fresh = CollectionIdRegenerator.regenerate(
            tags: data.tags,
            tagGroups: data.tagGroups,
            labelGroups: data.labelGroups,
            labels: data.labels,
            timeEvents: data.timeEvents,
            playFields: sourceFields,
            clocks: data.clocks ?? [],
            layout: sourceLayout,
            collectionName: newName
        )

        let newData = CollectionData(
            id: newId,
            tagGroups: fresh.tagGroups,
            tags: fresh.tags,
            labelGroups: fresh.labelGroups,
            labels: fresh.labels,
            timeEvents: fresh.timeEvents,
            playField: fresh.playFields.first,
            playFields: fresh.playFields.isEmpty ? nil : fresh.playFields,
            clocks: fresh.clocks.isEmpty ? nil : fresh.clocks
        )
        InMemoryStorageManager.shared.saveCollection(newData)
        // Папку скопировали целиком, поэтому в ней лежит tagLayout.json со СТАРЫМИ id — перезаписываем.
        if let layout = fresh.layout {
            TagFreeLayoutStorage.saveLayout(layout, collectionId: newId)
        }
        saveCollection(id: newId, name: newName, tagLibraryDisplayMode: info.displayMode)
        CollectionsBackupManager.shared.syncFromUserDefaults()
        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)

        return CollectionInfo(id: newId, name: newName, tagLibraryDisplayMode: info.displayMode)
    }

    func deleteCollectionCompletely(id: String) {
        if let info = loadCollections().first(where: { $0.id == id }),
           UserDefaults.standard.string(forKey: UserDefaults.Keys.lastSelectedCollection) == info.name {
            UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.lastSelectedCollection)
        }

        InMemoryStorageManager.shared.deleteCollection(id: id)
        removeCollection(id: id)
        CollectionsBackupManager.shared.removeCollection(id: id)

        let folder = collectionsDirectory.appendingPathComponent(id, isDirectory: true)
        if fileManager.fileExists(atPath: folder.path) {
            try? fileManager.removeItem(at: folder)
        }

        saveToFileImmediate()
        InMemoryStorageManager.shared.saveToDiskImmediate()
        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
    }
}
