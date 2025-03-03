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
    case openImages(image: NSImage)
    case openVideo(file: FilesFile)
    case deleteFile(file: FilesFile)
    case showError(error: String)
    
    case showFilesDownload(files: [URL])
    case showFilesDownloading
    
    case downloadFiles
    
    case importFile(file: URL)
    
}
