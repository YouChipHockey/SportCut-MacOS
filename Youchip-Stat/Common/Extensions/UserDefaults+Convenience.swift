//
//  NSError+Convenience.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 13.06.2024.
//

import Foundation

extension UserDefaults {
    enum Keys {
        static let collections = "savedCollections"
        static let lastSelectedCollection = "lastSelectedCollection"
        static let collectionsBookmarksLoaded = "collectionsBookmarksLoaded"
        static let collectionsDeduplicationDone = "collectionsDeduplicationDone"

    }
    
    func saveCollectionBookmark(_ bookmark: CollectionBookmark) {
        // Save only id and name to CollectionsBookmarks.json (single source of truth)
        CollectionsBookmarksManager.shared.saveCollection(id: bookmark.id, name: bookmark.name)
        
        // Keep UserDefaults for backward compatibility during migration
        var collections = getCollectionBookmarksFromUserDefaults()
        if let index = collections.firstIndex(where: { $0.id == bookmark.id }) {
            collections[index] = bookmark
        } else {
            collections.append(bookmark)
        }
        
        if let encoded = try? JSONEncoder().encode(collections) {
            set(encoded, forKey: Keys.collections)
        }
    }
    
    func getCollectionBookmarks() -> [CollectionBookmark] {
        // Load from CollectionsBookmarks.json (single source of truth)
        // Migrate from UserDefaults only once on first launch
        if !bool(forKey: Keys.collectionsBookmarksLoaded) {
            // First time loading - migrate from UserDefaults if needed
            migrateFromUserDefaultsIfNeeded()
            set(true, forKey: Keys.collectionsBookmarksLoaded)
        }
        
        // Always load fresh data from CollectionsBookmarks.json
        return CollectionsBookmarksManager.shared.loadCollectionBookmarks()
    }
    
    func removeCollectionBookmark(named name: String) {
        // Find collection by name
        let collections = getCollectionBookmarks()
        if let collectionToRemove = collections.first(where: { $0.name == name }) {
            // Remove from CollectionsBookmarks.json
            CollectionsBookmarksManager.shared.removeCollection(id: collectionToRemove.id)
            
            // Remove from UserDefaults for backward compatibility
            var userDefaultsCollections = getCollectionBookmarksFromUserDefaults()
            userDefaultsCollections.removeAll { $0.name == name }
            
            if let encoded = try? JSONEncoder().encode(userDefaultsCollections) {
                set(encoded, forKey: Keys.collections)
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Migrates collections from UserDefaults to CollectionsBookmarks.json if needed
    private func migrateFromUserDefaultsIfNeeded() {
        // Check if CollectionsBookmarks.json already exists
        let collectionsBookmarks = CollectionsBookmarksManager.shared.loadCollections()
        if !collectionsBookmarks.isEmpty {
            // Already migrated
            return
        }
        
        // Load from UserDefaults
        guard let data = data(forKey: Keys.collections),
              let userDefaultsCollections = try? JSONDecoder().decode([CollectionBookmark].self, from: data) else {
            return
        }
        
        // Migrate to CollectionsBookmarks.json
        for bookmark in userDefaultsCollections {
            CollectionsBookmarksManager.shared.saveCollection(id: bookmark.id, name: bookmark.name)
        }
        
        print("✅ CollectionsBookmarks: Migrated \(userDefaultsCollections.count) collections from UserDefaults")
    }
    
    /// Gets collection bookmarks from UserDefaults (for backward compatibility)
    private func getCollectionBookmarksFromUserDefaults() -> [CollectionBookmark] {
        guard let data = data(forKey: Keys.collections),
              let collections = try? JSONDecoder().decode([CollectionBookmark].self, from: data) else {
            return []
        }
        return collections
    }
}
