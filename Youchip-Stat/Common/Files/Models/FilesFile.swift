//
//  FilesFile.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Foundation
import AppKit

struct FilesFile {
    
    var url: URL? {
        get {
            do {
                var isStale = false
                let restoredUrl = try URL(resolvingBookmarkData: videoData.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                guard restoredUrl.startAccessingSecurityScopedResource() else { return nil }
                return restoredUrl
            } catch {
                return nil
            }
        }
        set {
            if let newUrl = newValue {
                do {
                    videoData.bookmark = try newUrl.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                } catch {
                    print("Failed to create bookmark data: \(error)")
                }
            }
        }
    }
    
    var dateAdded: Date { url?.dateAdded ?? Date() }
    var dateOpened: Date { url?.dateOpened ?? Date() }
    var dateModified: Date { url?.dateModified  ?? Date() }
    
    var isFile: Bool { !(url?.isFolder ?? true) }
    var isFolder: Bool { url?.isFolder ?? false }
    
    var name: String { url?.fileName  ?? "" }
    var pathExtension: String { url?.pathExtension  ?? "" }
    var lastPathComponent: String { url?.lastPathComponent  ?? "" }
    var sizeString: String { url?.sizeString ?? "" }
    var size: UInt64 { url?.sizeByets ?? 0 }
    
    var customName: String?
    
    var videoData: VideosData
    
    var preview: NSImage?
    
    init(videoData: VideosData) {
        self.videoData = videoData
    }
    
    mutating func updateBookmark() {
        guard let bookmarkData = try? self.url!.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        videoData.bookmark = bookmarkData
    }
    
}

extension FilesFile: Equatable {
    
    static func == (lhs: FilesFile, rhs: FilesFile) -> Bool {
        return lhs.url == rhs.url
    }
    
}

extension FilesFile: Hashable {
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url?.absoluteString)
    }
    
}

extension FilesFile {
    
    var fileKind: FilesFileKind {
        if url?.isFolder ?? false {
            return .folder
        }
        let pathExtension = pathExtension.lowercased()
        let fileFormat = FilesFileFormat(pathExtension: pathExtension)
        return fileFormat.kind
    }
    var isArchive: Bool {
        return fileKind == .archives
    }
    var availableInOffice: Bool {
        return [.spreadsheets, .documents, .presentations, .pdf].contains(fileKind)
    }
    
}

extension Array where Element == FilesFile {
    
    func sortedFiles() -> [FilesFile] {
        return sorted { lhs, rhs in
            return lhs.dateOpened > rhs.dateOpened
        }
    }
    
}

extension URL {
    
    var dateAdded: Date {
        return resourceValues(for: .creationDateKey)?.creationDate ?? Date()
    }
    var dateOpened: Date {
        return resourceValues(for: .contentAccessDateKey)?.contentAccessDate ?? Date()
    }
    var dateModified: Date {
        return resourceValues(for: .contentModificationDateKey)?.contentModificationDate ?? Date()
    }
    var isFolder: Bool {
        return resourceValues(for: .isDirectoryKey)?.isDirectory ?? false
    }
    var isHidden: Bool {
        return resourceValues(for: .isHiddenKey)?.isHidden ?? false
    }
    var size: Int {
        return resourceValues(for: .fileSizeKey)?.fileSize ?? 0
    }
    var sizeString: String {
        return size.sizeString
    }
    var sizeByets: UInt64 {
        do {
            let filePath = self.path
            let attr = try FileManager.default.attributesOfItem(atPath: filePath)
            return attr[FileAttributeKey.size] as! UInt64
        } catch {
            return 0
        }
    }
    
    private func resourceValues(for key: URLResourceKey) -> URLResourceValues? {
        return try? resourceValues(forKeys: [key])
    }
    
}

extension Int {
    
    var sizeString: String {
        return ReadableUnit(bytes: self).getReadableUnit()
    }
    
}

extension FilesFile {
    
    mutating func updateDateOpened() {
        updateResourceValues { resourceValues in
            resourceValues.contentAccessDate = Date()
        }
    }
    
    mutating func updateDateModified() {
        updateResourceValues { resourceValues in
            resourceValues.contentModificationDate = Date()
        }
    }
    
    private mutating func updateResourceValues(updateHandler: (inout URLResourceValues) -> Void) {
        var resourceValues = URLResourceValues()
        updateHandler(&resourceValues)
        try? url?.setResourceValues(resourceValues)
    }
    
}

private struct ReadableUnit {
    
    private let bytes: Int
    
    private let kilobyte = 1_024
    
    private var kilobytes: Int {
        return bytes / kilobyte
    }
    private var megabytes: Int {
        return kilobytes / kilobyte
    }
    private var gigabytes: Int {
        return megabytes / kilobyte
    }
    
    public init(bytes: Int) {
        self.bytes = bytes
    }
    
    func getReadableUnit() -> String {
        let format = "%d %@"
        switch bytes {
        case Int(kilobyte) ..< powInt(kilobyte, raise: 2):
            return String(format: format, kilobytes, "kB")
        case powInt(kilobyte, raise: 2) ..< powInt(kilobyte, raise: 3):
            return String(format: format, megabytes, "mB")
        case powInt(kilobyte, raise: 3) ... Int.max:
            return String(format: format, gigabytes, "gB")
        default:
            return String(format: format, bytes, "B")
        }
    }
    
    // MARK: - Helpers
    
    private func powInt(_ int: Int, raise: Int) -> Int {
        return Int(pow(Double(int), Double(raise)))
    }
    
}
