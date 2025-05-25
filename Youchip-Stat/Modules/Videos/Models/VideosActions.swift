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
    case openGuide
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
    case saveVideoMetadata(url: URL, team1: String, team2: String, score: String, dateTime: Date)
    case showRenameSheet(file: FilesFile)
    case renameVideo(file: FilesFile, team1: String, team2: String, score: String)
    case renameSimpleVideo(file: FilesFile, newName: String)
    case showAuthSheet
    case updateLimitInfo
    
}
