//
//  AppCloudFilesHelper.swift
//  smm-printer-mac
//
//  Created by tpe on 09.09.2024.
//

import Foundation

class AppCloudFilesHelper {
    
    private var cloudFiles: [URL] = []
    
    func setCloudFiles(_ files: [URL]) {
        cloudFiles = files
    }
    
    func downloadFiles() {
        cloudFiles.forEach { file in
            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        }
    }
    
}
