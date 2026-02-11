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

    }
    
    func saveCollectionBookmark(_ bookmark: CollectionBookmark) {
        var collections = getCollectionBookmarks()
        if let index = collections.firstIndex(where: { $0.id == bookmark.id }) {
            collections[index] = bookmark
        } else {
            collections.append(bookmark)
        }
        
        if let encoded = try? JSONEncoder().encode(collections) {
            set(encoded, forKey: Keys.collections)
        }
        
        // Save to backup file
        CollectionsBackupManager.shared.saveCollection(bookmark)
    }
    
    func getCollectionBookmarks() -> [CollectionBookmark] {
        guard let data = data(forKey: Keys.collections),
              let collections = try? JSONDecoder().decode([CollectionBookmark].self, from: data) else {
            return []
        }
        return collections
    }
    
    func removeCollectionBookmark(named name: String) {
        var collections = getCollectionBookmarks()
        let collectionToRemove = collections.first(where: { $0.name == name })
        collections.removeAll { $0.name == name }
        
        if let encoded = try? JSONEncoder().encode(collections) {
            set(encoded, forKey: Keys.collections)
        }
        
        // Remove from backup file
        if let collection = collectionToRemove {
            CollectionsBackupManager.shared.removeCollection(id: collection.id)
        }
    }
}
