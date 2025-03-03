//
//  URL+Convenience.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Foundation

extension URL {
    
    static var appTemporaryDirectory: URL {
        return URL(fileURLWithPath: NSTemporaryDirectory())
    }
    static var documentDirectory: URL {
        return URL(fileURLWithPath: NSTemporaryDirectory())
    }
    static var appDocumentsDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    static var filesDirectory: URL {
        return appDocumentsDirectory.appendingPathComponent("Files")
    }
    static var previewsDirectory: URL {
        return .appTemporaryDirectory.appendingPathComponent("Preview")
    }
    
}

extension URL {
    
    var fileUrl: URL {
        return standardizedFileURL
    }
    
    var fileName: String {
        return deletingPathExtension().lastPathComponent
    }
    
    func fixedFile() -> URL {
        var index = 0
        var fixedFile = self
        while FileManager.default.fileExists(atPath: fixedFile.path) {
            index += 1
            fixedFile = addIndex(index)
        }
        return fixedFile.fileUrl
    }
    
    func addIndex(_ index: Int) -> URL {
        return updateFileName(String(format: "%@ (%d)", fileName, index))
    }
    
    func updateFileName(_ fileName: String) -> URL {
        return deletingLastPathComponent()
            .appendingPathComponent(fileName)
            .appendingPathExtension(pathExtension)
            .fileUrl
    }
    
    func makePreviewName() -> String {
        let lastPath = self.lastPathComponent
        guard let range = lastPath.range(of: ".", options: .backwards) else {
            return lastPath
        }
        return lastPath.replacingCharacters(in: range, with: "@$@") + ".png"
    }
    
    func makeBookmark() -> Data? {
        do {
            return try self.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            return nil
        }
    }
    
    func isExist() -> Bool {
        FileManager.default.fileExists(atPath: self.path)
    }
    
    func isFileSizeZero() -> Bool {
        do {
            let fileAttributes = try self.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = fileAttributes.fileSize { return fileSize == 0 }
            return false
        } catch {
            return false
        }
    }
    
}

extension URL {
    
    func isFileInFolder(_ folder: URL) -> Bool {
        return deletingLastPathComponent().fileUrl == folder.fileUrl
    }
    
}

extension URL {
    
    var pdfFile: URL {
        return updatePathExtension(format: .pdf)
    }
    var pptxFile: URL {
        return updatePathExtension(format: .pptx)
    }
    var jpgFile: URL {
        return updatePathExtension(format: .jpg)
    }
    var rtfFile: URL {
        return updatePathExtension(format: .rtf)
    }
    var txtFile: URL {
        return updatePathExtension(format: .txt)
    }
    
    func updatePathExtension(format: FilesFileFormat) -> URL {
        return deletingPathExtension().appendingPathExtension(format.rawValue)
    }
    
}

extension URL {
    
    var ubiquitousStatus: URLUbiquitousItemDownloadingStatus? {
        let values = try? resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        return values?.ubiquitousItemDownloadingStatus
    }
    
    var isDownloading: Bool {
        let values = try? resourceValues(forKeys: [.ubiquitousItemIsDownloadingKey])
        return values?.ubiquitousItemIsDownloading ?? false
    }
    
}
