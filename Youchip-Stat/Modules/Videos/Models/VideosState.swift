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
    
    // Live Stream State
    var showLiveSourceSelection: Bool = false
    var showLiveMetadataSheet: Bool = false
    var isLiveSessionConfigured: Bool = false
    
    /// Set when the user triggers "append to existing video" from the video list.
    var appendVideoFile: FilesFile? = nil
    /// Pre-loaded video URL selected in the LiveSourceSelectionView (new session with pre-existing base video).
    var preloadedVideoForLive: URL? = nil
    
}
