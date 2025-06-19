//
//  NSError+Convenience.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 13.06.2024.
//

import Foundation

extension UserDefaults {
    private enum Keys {
        static let collections = "savedCollections"
    }
    
    func saveCollectionBookmark(_ bookmark: CollectionBookmark) {
        var collections = getCollectionBookmarks()
        if let index = collections.firstIndex(where: { $0.name == bookmark.name }) {
            collections[index] = bookmark
        } else {
            collections.append(bookmark)
        }
        
        if let encoded = try? JSONEncoder().encode(collections) {
            set(encoded, forKey: Keys.collections)
        }
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
        collections.removeAll { $0.name == name }
        
        if let encoded = try? JSONEncoder().encode(collections) {
            set(encoded, forKey: Keys.collections)
        }
    }
}
