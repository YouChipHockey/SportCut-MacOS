//
//  VideoFilesManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Foundation

struct VideosData: Codable {
    
    var bookmark: Data
    var id: String
    var timelines: [TimelineLine]
    var customName: String?
    
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
            var file = FilesFile(videoData: VideosData(bookmark: bookmark, id: id, timelines: []))
            if videosData.first(where: { $0.bookmark == bookmark}) == nil {
                file.updateDateOpened()
                file.updateDateModified()
                files.append(file)
                videosData.append(VideosData(bookmark: file.videoData.bookmark, id: id, timelines: []))
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
        return files
    }
    
    @discardableResult
    func importFile(url: URL, newName: String) -> FilesFile? {
        if let file = importFile(url: url) {
            // Update the custom name in videoData
            if let index = videosData.firstIndex(where: { $0.bookmark == file.videoData.bookmark }) {
                videosData[index].customName = newName
                saveBookmarks()
            }
            
            // Update the custom name in file
            var updatedFile = file
            updatedFile.videoData.customName = newName
            
            // Update the file in the files array
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
        videosData.remove(at: bookmarkIndex)
        files.remove(at: fileIndex)
        saveBookmarks()
        updateFiles?(files)
    }
    
    func updateTimelines(for bookmark: Data, with timelines: [TimelineLine]) {
        if let index = videosData.firstIndex(where: { $0.bookmark == bookmark }) {
            videosData[index].timelines = timelines
            saveBookmarks()
        }
        if let index = files.firstIndex(where: { $0.videoData.bookmark == bookmark }) {
            files[index].videoData.timelines = timelines
            updateFiles?(files)
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
    
    private func saveBookmarks() {
        do {
            let encoded = try JSONEncoder().encode(videosData)
            UserDefaults.standard.set(encoded, forKey: "videosData")
        } catch {
            print("Ошибка кодирования: \(error)")
        }
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
        if let data = UserDefaults.standard.data(forKey: "videosData") {
            do {
                let videosData = try JSONDecoder().decode([VideosData].self, from: data)
                self.videosData = videosData
            } catch {
                print("Ошибка декодирования: \(error)")
            }
        }
    }
    
}

