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
    var showRebindAlert: Bool = false
    var fileToRebind: FilesFile? = nil    
    var showProjectImportSheet = false
    var importedProjectData: ProjectImportModel? = nil
    var showVideoBindingSheet = false
    
    // URL Download State
    var showDownloadFromURLSheet: Bool = false
    var downloadedVideoURL: URL? = nil
    
}
