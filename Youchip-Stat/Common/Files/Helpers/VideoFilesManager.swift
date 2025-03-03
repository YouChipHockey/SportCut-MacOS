//
//  VideoFilesManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Foundation

class VideoFilesManager {
    
    static let shared = VideoFilesManager()
    
    let fileManager = FileManager.default
    
    @Published private(set) var files: [FilesFile] = []
    @Published private(set) var bookmarks: [Data] = []
    
    var updateFiles: (([FilesFile]) -> Void)?
    
    init() {
        fileManager.createDirectoryIfNeeded(url: .appDocumentsDirectory)
        fileManager.createDirectoryIfNeeded(url: .previewsDirectory)
        readFiles()
        filterFiles()
    }
    
    @discardableResult
    func importFile(url: URL) -> FilesFile? {
        if let bookmark = url.makeBookmark() {
            var file = FilesFile(bookmark: bookmark)
            if !bookmarks.contains(bookmark) {
                file.updateDateOpened()
                file.updateDateModified()
                files.append(file)
                bookmarks.append(file.bookmark)
                saveBookmarks()
                updateFiles?(files)
            }
            return file
        } else {
            return nil
        }
    }
    
    func removeFile(file: FilesFile) {
        guard let fileIndex = files.firstIndex(of: file), let bookmarkIndex = bookmarks.firstIndex(of: file.bookmark) else {
            do {
                guard let url = file.url else { return }
                try fileManager.removeItem(at: url)
            } catch {
                print(error.localizedDescription)
            }
            return
        }
        bookmarks.remove(at: bookmarkIndex)
        files.remove(at: fileIndex)
        saveBookmarks()
        updateFiles?(files)
    }
    
    // MARK: - Helpers
    
    private func readFiles() {
        loadBookmarks()
        files = resolveBookmarks()
    }
    
    private func resolveBookmarks() -> [FilesFile] {
        var resolvedURLs: [FilesFile] = []
        for bookmark in bookmarks {
            resolvedURLs.append(FilesFile(bookmark: bookmark))
        }
        return resolvedURLs
    }
    
    private func saveBookmarks() {
        UserDefaults.standard.set(bookmarks, forKey: "bookmarks")
    }
    
    private func filterFiles() {
        var seenURLs = Set<URL>()
        files = files.filter { file in
            if let url = file.url {
                if seenURLs.contains(url) {
                    return false
                } else {
                    seenURLs.insert(url)
                    return true
                }
            } else {
                return false
            }
        }
    }
    
    private func loadBookmarks() {
        if let bookmarksData = UserDefaults.standard.array(forKey: "bookmarks") as? [Data] {
            bookmarks = bookmarksData
        }
    }
    
}

