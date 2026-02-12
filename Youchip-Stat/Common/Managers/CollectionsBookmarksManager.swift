//
//  CollectionsBookmarksManager.swift
//  Youchip-Stat
//
//  Created on 11.02.2026.
//

import Foundation

/// Manages collection bookmarks metadata (id and name) in CollectionsBookmarks.json file
/// This is the single source of truth for collection bookmarks
class CollectionsBookmarksManager {
    
    static let shared = CollectionsBookmarksManager()
    
    private let fileManager = FileManager.default
    
    /// Structure for storing collection metadata in CollectionsBookmarks.json
    struct CollectionInfo: Codable, Equatable {
        let id: String
        let name: String
    }
    
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
    }
    
    // MARK: - Public Methods
    
    /// Saves collection info to CollectionsBookmarks.json
    /// After initial deduplication, allows duplicate names (they will have suffixes added by ensureUniqueCollectionName)
    func saveCollection(id: String, name: String) {
        var collections = loadCollections()
        
        // Update or add collection
        if let index = collections.firstIndex(where: { $0.id == id }) {
            collections[index] = CollectionInfo(id: id, name: name)
        } else {
            collections.append(CollectionInfo(id: id, name: name))
        }
        
        // After deduplication is done, don't remove duplicates - allow them to exist
        // The ensureUniqueCollectionName() in CustomCollectionManager will add suffixes for new collections
        // But we don't remove existing ones here
        saveCollections(collections)
        
        // Trigger backup to Application Support
        DataSyncManager.shared.backupToApplicationSupport()
    }
    
    /// Removes collection from CollectionsBookmarks.json
    func removeCollection(id: String) {
        var collections = loadCollections()
        collections.removeAll { $0.id == id }
        saveCollections(collections)
    }
    
    /// Loads all collections from CollectionsBookmarks.json
    func loadCollections() -> [CollectionInfo] {
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
                    updatedCollections.append(CollectionInfo(id: collection.id, name: existing.name))
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
            collections[index] = CollectionInfo(id: newId, name: oldInfo.name)
            saveCollections(collections)
        }
    }
    
    // Note: ensureUniqueNames() was removed - after initial deduplication,
    // duplicate names are allowed and will get suffixes added by ensureUniqueCollectionName()
}
