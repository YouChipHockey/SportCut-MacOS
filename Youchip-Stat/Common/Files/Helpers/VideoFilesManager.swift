//
//  VideoFilesManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Foundation

struct VideosData: Codable, Equatable {
    
    var bookmark: Data
    var id: String
    var customName: String?
    var isFavorite: Bool?
    
    init(bookmark: Data, id: String, customName: String? = nil, isFavorite: Bool? = nil) {
        self.bookmark = bookmark
        self.id = id
        self.customName = customName
        self.isFavorite = isFavorite ?? false
    }
    
    static func == (lhs: VideosData, rhs: VideosData) -> Bool {
        return lhs.bookmark == rhs.bookmark &&
               lhs.id == rhs.id &&
               lhs.customName == rhs.customName &&
               lhs.isFavorite == rhs.isFavorite
    }
}

class VideoFilesManager {
    
    static let shared = VideoFilesManager()
    
    let fileManager = FileManager.default
    
    @Published private(set) var files: [FilesFile] = []
    @Published private(set) var videosData: [VideosData] = []
    
    var updateFiles: (([FilesFile]) -> Void)?
    
    init() {
        fileManager.createDirectoryIfNeeded(url: .appDocumentsDirectory)
        fileManager.createDirectoryIfNeeded(url: .previewsDirectory)
        readFiles()
        filterFiles()
        
        checkAndCleanDuplicatesOnce()
    }
    
    private func checkAndCleanDuplicatesOnce() {
        let cleanupKey = "videosDataDuplicationCleanupDone_v1"
        if UserDefaults.standard.bool(forKey: cleanupKey) {
            return
        }
        saveBookmarks()
        UserDefaults.standard.set(true, forKey: cleanupKey)
    }
    
    func generate32CharacterCode() -> String {
        let uuid = UUID().uuidString
        let cleanUUID = uuid.replacingOccurrences(of: "-", with: "")
        return cleanUUID
    }
    
    @discardableResult
    func importFile(url: URL) -> FilesFile? {
        if let bookmark = url.makeBookmark() {
            let id = generate32CharacterCode()
            var file = FilesFile(videoData: VideosData(bookmark: bookmark, id: id))
            if videosData.first(where: { $0.bookmark == bookmark}) == nil {
                file.updateDateOpened()
                file.updateDateModified()
                files.append(file)
                videosData.append(VideosData(bookmark: file.videoData.bookmark, id: id))
                saveBookmarks()
                updateFiles?(files)
            }
            return file
        } else {
            return nil
        }
    }
    
    func refreshFiles() -> [FilesFile] {
        readFiles()
        filterFiles()
        updateFiles?(files) // Notify UI about file list update
        return files
    }
    
    func addFileWithData(_ file: FilesFile, videoData: VideosData) {
        files.append(file)
        videosData.append(videoData)
        saveBookmarks()
        updateFiles?(files)
    }
    
    @discardableResult
    func importFile(url: URL, newName: String) -> FilesFile? {
        if let file = importFile(url: url) {
            if let index = videosData.firstIndex(where: { $0.bookmark == file.videoData.bookmark }) {
                videosData[index].customName = newName
                saveBookmarks()
            }
            var updatedFile = file
            updatedFile.videoData.customName = newName
            
            if let fileIndex = files.firstIndex(where: { $0.videoData.bookmark == file.videoData.bookmark }) {
                files[fileIndex] = updatedFile
                updateFiles?(files)
            }
            
            return updatedFile
        }
        return nil
    }
    
    func removeFile(file: FilesFile) {
        guard let fileIndex = files.firstIndex(of: file), let bookmarkIndex = videosData.firstIndex(where: {$0.bookmark ==  file.videoData.bookmark}) else {
            do {
                guard let url = file.url else { return }
                try fileManager.removeItem(at: url)
            } catch {
                print(error.localizedDescription)
            }
            return
        }
        
        // IMPORTANT: Backup timeline BEFORE deleting video
        // This allows restoring timeline even after repeated deletion
        let videoDataToBackup = videosData[bookmarkIndex]
        let timelines = loadTimelines(for: videoDataToBackup.id)
        if !timelines.isEmpty {
            let videoDataWithTimelines = DataSyncManager.VideosDataWithTimelines(
                bookmark: videoDataToBackup.bookmark,
                id: videoDataToBackup.id,
                timelines: timelines,
                customName: videoDataToBackup.customName,
                isFavorite: videoDataToBackup.isFavorite
            )
            DataSyncManager.shared.backupTimelinesForVideo(videoDataWithTimelines)
        }
        
        // Delete timeline file
        deleteTimelinesFile(for: videoDataToBackup.id)
        
        videosData.remove(at: bookmarkIndex)
        files.remove(at: fileIndex)
        saveBookmarks()
        updateFiles?(files)
    }
    
    func updateTimelines(for bookmark: Data, with timelines: [TimelineLine]) {
        guard let videoData = videosData.first(where: { $0.bookmark == bookmark }) else {
            return
        }
        
        saveTimelines(timelines, for: videoData.id)
        DataSyncManager.shared.backupToApplicationSupport()
    }
    
    // MARK: - Timeline File Management
    
    private var timelinesDirectory: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("YouChip-Stat/Timelines", isDirectory: true)
    }
    
    private func timelineFileURL(for videoId: String) -> URL {
        fileManager.createDirectoryIfNeeded(url: timelinesDirectory)
        return timelinesDirectory.appendingPathComponent("\(videoId).json")
    }
    
    /// Saves timelines to file for a specific video
    func saveTimelines(_ timelines: [TimelineLine], for videoId: String) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(timelines)
            let fileURL = timelineFileURL(for: videoId)
            try data.write(to: fileURL)
        } catch {
            print("❌ Error saving timelines for video \(videoId): \(error.localizedDescription)")
        }
    }
    
    /// Loads timelines from file for a specific video
    func loadTimelines(for videoId: String) -> [TimelineLine] {
        let fileURL = timelineFileURL(for: videoId)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode([TimelineLine].self, from: data)
        } catch {
            print("❌ Error loading timelines for video \(videoId): \(error.localizedDescription)")
            return []
        }
    }
    
    private func deleteTimelinesFile(for videoId: String) {
        let fileURL = timelineFileURL(for: videoId)
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
    }
    
    func renameFile(file: FilesFile, newName: String) {
        if let index = files.firstIndex(where: { $0.videoData.bookmark == file.videoData.bookmark }) {
            files[index].videoData.customName = newName
            
            if let dataIndex = videosData.firstIndex(where: { $0.bookmark == file.videoData.bookmark }) {
                videosData[dataIndex].customName = newName
                saveBookmarks()
                updateFiles?(files)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func readFiles() {
        loadBookmarks()
        files = resolveBookmarks()
    }
    
    private func resolveBookmarks() -> [FilesFile] {
        var resolvedURLs: [FilesFile] = []
        for videoData in videosData {
            resolvedURLs.append(FilesFile(videoData: videoData))
        }
        return resolvedURLs
    }
    
    func saveBookmarks() {
        var seenURLs = Set<String>()
        var seenIDs = Set<String>()
        let originalCount = videosData.count
        
        let deduplicatedData = videosData.filter { videoData in
            guard !seenIDs.contains(videoData.id) else {
                return false
            }
            seenIDs.insert(videoData.id)
            
            do {
                var isStale = false
                let resolvedURL = try URL(resolvingBookmarkData: videoData.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                let urlString = resolvedURL.path
                
                if seenURLs.contains(urlString) {
                    return false
                }
                seenURLs.insert(urlString)
                return true
            } catch {
                return true
            }
        }
        
        if deduplicatedData.count != originalCount {
            videosData = deduplicatedData
        }
        
        do {
            let encoded = try JSONEncoder().encode(videosData)
            UserDefaults.standard.set(encoded, forKey: "videosData")
            
            DataSyncManager.shared.backupToApplicationSupport()
        } catch {
            print("\(^String.Titles.fileManagerErrorEncoding) \(error)")
        }
    }
    
    private func filterFiles() {
        var seenURLs = Set<URL>()
        var seenBrokenIDs = Set<String>()
        files = files.filter { file in
            if let url = file.url {
                if seenURLs.contains(url) {
                    return false
                } else {
                    seenURLs.insert(url)
                    return true
                }
            } else {
                if seenBrokenIDs.contains(file.id) {
                    return false
                } else {
                    seenBrokenIDs.insert(file.id)
                    return true
                }
            }
        }
    }
    
    private func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: "videosData") {
            do {
                // Try to decode as old format (with timelines) first for migration
                if let oldVideosData = try? JSONDecoder().decode([VideosDataOldFormat].self, from: data) {
                    // Migrate old data: save timelines to files
                    migrateOldVideosData(oldVideosData)
                }
                
                // Decode as new format (without timelines)
                let videosData = try JSONDecoder().decode([VideosData].self, from: data)
                let migratedVideosData = videosData.map { videoData in
                    var migratedData = videoData
                    if migratedData.isFavorite == nil {
                        migratedData.isFavorite = false
                    }
                    return migratedData
                }
                
                var seenURLs = Set<String>()
                var seenIDs = Set<String>()
                let deduplicatedData = migratedVideosData.filter { videoData in
                    guard !seenIDs.contains(videoData.id) else {
                        return false
                    }
                    seenIDs.insert(videoData.id)
                    
                    do {
                        var isStale = false
                        let resolvedURL = try URL(resolvingBookmarkData: videoData.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                        let urlString = resolvedURL.path
                        
                        if seenURLs.contains(urlString) {
                            return false
                        }
                        seenURLs.insert(urlString)
                        return true
                    } catch {
                        return true
                    }
                }
                
                self.videosData = deduplicatedData
                
                if deduplicatedData.count != videosData.count || deduplicatedData != videosData {
                    saveBookmarks()
                }
            } catch {
                print("\(^String.Titles.fileManagerErrorDecoding) \(error)")
            }
        }
    }
    
    // MARK: - Migration
    
    private struct VideosDataOldFormat: Codable {
        var bookmark: Data
        var id: String
        var timelines: [TimelineLine]
        var customName: String?
        var isFavorite: Bool?
    }
    
    private func migrateOldVideosData(_ oldData: [VideosDataOldFormat]) {
        print("🔄 Migrating timelines from UserDefaults to files...")
        
        for oldVideoData in oldData {
            if !oldVideoData.timelines.isEmpty {
                saveTimelines(oldVideoData.timelines, for: oldVideoData.id)
            }
        }
        
        // Save migrated data without timelines
        let newVideosData = oldData.map { old in
            VideosData(
                bookmark: old.bookmark,
                id: old.id,
                customName: old.customName,
                isFavorite: old.isFavorite
            )
        }
        
        do {
            let encoded = try JSONEncoder().encode(newVideosData)
            UserDefaults.standard.set(encoded, forKey: "videosData")
            print("✅ Migration completed: \(oldData.count) videos migrated")
        } catch {
            print("❌ Error during migration: \(error.localizedDescription)")
        }
    }
    
    func toggleFavorite(for file: FilesFile) {
        if let index = files.firstIndex(where: { $0.id == file.id }) {
            let currentFavorite = isFavorite(file)
            files[index].videoData.isFavorite = !currentFavorite
            updateVideosData()
            saveBookmarks()
            updateFiles?(files)
        }
    }
    
    func isFavorite(_ file: FilesFile) -> Bool {
        return file.videoData.isFavorite ?? false
    }
    
    private func updateVideosData() {
        videosData = files.map { $0.videoData }
    }
    
    func rebindVideo(file: FilesFile, newURL: URL) -> Bool {
        guard let newBookmark = newURL.makeBookmark() else {
            return false
        }
        
        if let fileIndex = files.firstIndex(where: { $0.id == file.id }) {
            files[fileIndex].videoData.bookmark = newBookmark
            
            if let dataIndex = videosData.firstIndex(where: { $0.id == file.id }) {
                videosData[dataIndex].bookmark = newBookmark
                saveBookmarks()
                updateFiles?(files)
                return true
            }
        }
        
        return false
    }
    
}

