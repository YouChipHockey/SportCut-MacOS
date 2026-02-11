//
//  CollectionsBackupManager.swift
//  Youchip-Stat
//
//  Created on 11.02.2026.
//

import Foundation

/// Manages backup of collection metadata (id and name) to a separate file
class CollectionsBackupManager {
    
    static let shared = CollectionsBackupManager()
    
    private let fileManager = FileManager.default
    
    /// Structure for storing collection metadata in backup file
    struct CollectionInfo: Codable, Equatable {
        let id: String
        let name: String
    }
    
    private var collectionsBackupFile: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("YouChip-Stat/CollectionsBackup.json")
    }
    
    private init() {
        createBackupDirectoryIfNeeded()
    }
    
    // MARK: - Public Methods
    
    /// Saves collection info to backup file
    func saveCollection(_ collection: CollectionBookmark) {
        var collections = loadCollections()
        
        // Update or add collection
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index] = CollectionInfo(id: collection.id, name: collection.name)
        } else {
            collections.append(CollectionInfo(id: collection.id, name: collection.name))
        }
        
        saveCollections(collections)
        
        // Trigger backup to Application Support
        DataSyncManager.shared.backupToApplicationSupport()
    }
    
    /// Removes collection from backup file
    func removeCollection(id: String) {
        var collections = loadCollections()
        collections.removeAll { $0.id == id }
        saveCollections(collections)
    }
    
    /// Loads all collections from backup file
    func loadCollections() -> [CollectionInfo] {
        guard fileManager.fileExists(atPath: collectionsBackupFile.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: collectionsBackupFile)
            let decoder = JSONDecoder()
            return try decoder.decode([CollectionInfo].self, from: data)
        } catch {
            print("❌ CollectionsBackup: Error loading collections - \(error.localizedDescription)")
            return []
        }
    }
    
    /// Restores collections from backup file to UserDefaults
    /// Returns true if restoration was performed
    func restoreCollectionsToUserDefaults() -> Bool {
        let backupCollections = loadCollections()
        
        guard !backupCollections.isEmpty else {
            return false
        }
        
        // Check if UserDefaults already has collections
        let existingCollections = UserDefaults.standard.getCollectionBookmarks()
        guard existingCollections.isEmpty else {
            // UserDefaults already has data, don't restore
            return false
        }
        
        print("🔄 CollectionsBackup: Restoring \(backupCollections.count) collections from backup")
        
        // Try to restore bookmarks from files
        var restoredCount = 0
        for collectionInfo in backupCollections {
            let collectionManager = CustomCollectionManager()
            if collectionManager.loadCollectionFromBookmarks(named: collectionInfo.name) {
                // Collection file exists, create bookmark
                let collectionFolderUrlString = URLConstants.getCollecitonFolderStringUrl(with: collectionInfo.id)
                let collectionFolderUrl = URL.appDocumentsDirectory
                    .appendingPathComponent(collectionFolderUrlString, isDirectory: true)
                
                // Check if collection folder exists
                guard fileManager.fileExists(atPath: collectionFolderUrl.path) else {
                    print("⚠️ CollectionsBackup: Collection folder not found for \(collectionInfo.name)")
                    continue
                }
                
                // Create bookmarks for collection files
                do {
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
                        print("⚠️ CollectionsBackup: Required files missing for \(collectionInfo.name)")
                        continue
                    }
                    
                    let tagGroupsBookmark = try tagGroupsURL.bookmarkData()
                    let tagsBookmark = try tagsURL.bookmarkData()
                    let labelGroupsBookmark = try labelGroupsURL.bookmarkData()
                    let labelsBookmark = try labelsURL.bookmarkData()
                    let timeEventsBookmark = fileManager.fileExists(atPath: timeEventsURL.path) ? try timeEventsURL.bookmarkData() : Data()
                    let playFieldBookmark = fileManager.fileExists(atPath: playFieldURL.path) ? try playFieldURL.bookmarkData() : nil
                    
                    let bookmark = CollectionBookmark(
                        id: collectionInfo.id,
                        name: collectionInfo.name,
                        tagGroupsBookmark: tagGroupsBookmark,
                        tagsBookmark: tagsBookmark,
                        labelGroupsBookmark: labelGroupsBookmark,
                        labelsBookmark: labelsBookmark,
                        timeEventsBookmark: timeEventsBookmark,
                        playFieldBookmark: playFieldBookmark
                    )
                    
                    UserDefaults.standard.saveCollectionBookmark(bookmark)
                    restoredCount += 1
                } catch {
                    print("❌ CollectionsBackup: Error creating bookmark for \(collectionInfo.name) - \(error.localizedDescription)")
                }
            }
        }
        
        if restoredCount > 0 {
            print("✅ CollectionsBackup: Restored \(restoredCount) collections to UserDefaults")
        }
        
        return restoredCount > 0
    }
    
    /// Syncs all collections from UserDefaults to backup file
    func syncFromUserDefaults() {
        let userDefaultsCollections = UserDefaults.standard.getCollectionBookmarks()
        let backupCollections = userDefaultsCollections.map { CollectionInfo(id: $0.id, name: $0.name) }
        saveCollections(backupCollections)
    }
    
    // MARK: - Private Methods
    
    private func createBackupDirectoryIfNeeded() {
        let directory = collectionsBackupFile.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
    
    private func saveCollections(_ collections: [CollectionInfo]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(collections)
            try data.write(to: collectionsBackupFile)
        } catch {
            print("❌ CollectionsBackup: Error saving collections - \(error.localizedDescription)")
        }
    }
}
