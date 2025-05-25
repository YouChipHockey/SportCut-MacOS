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
    var showMetadataSheet = false
    var videoMetadata = VideoMetadata()
    var showRenameSheet = false
    var fileToRename: FilesFile? = nil
    var newFileName: String = ""
    var limitInfoText: String = ""
    var showAuthSheet: Bool = false
    
}
