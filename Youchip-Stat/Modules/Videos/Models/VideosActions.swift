//
//  VideosActions.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Foundation
import AppKit

enum VideosActions {
    
    case openFiles
    case openFileFromHelper
    case refreshFiles
    case openImages(image: NSImage)
    case openVideo(id: String)
    case deleteFile(file: FilesFile)
    case showError(error: String)
    
    case showFilesDownload(files: [URL])
    case showFilesDownloading
    
    case downloadFiles
    
    case importFile(file: URL)
    
    // New actions for video metadata and renaming
    case saveVideoMetadata(url: URL, team1: String, team2: String, score: String)
    case showRenameSheet(file: FilesFile)
    // Keep the original action for metadata-based renaming
    case renameVideo(file: FilesFile, team1: String, team2: String, score: String)
    // Add new action for simple renaming
    case renameSimpleVideo(file: FilesFile, newName: String)
}
