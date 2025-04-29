//
//  VideosState.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Foundation

struct VideosState {
    var files: [FilesFile] = []
    var showHUD = false
    var showError = false
    var errorTitle = ""
    var showFilesDownloadAlert = false
    var showFilesDownloadingAlert = false
    
    // New properties for metadata sheet
    var showMetadataSheet = false
    var videoMetadata = VideoMetadata()
    
    // Properties for rename sheet
    var showRenameSheet = false
    var fileToRename: FilesFile? = nil
    var newFileName: String = ""
}
