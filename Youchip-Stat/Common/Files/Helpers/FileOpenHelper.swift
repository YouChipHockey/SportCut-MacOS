//
//  FileOpenHelper.swift
//  printer
//
//  Created by Сергей Бекезин on 22.08.2024.
//

import Foundation

class FileOpenHelper {
    
    static let shared = FileOpenHelper()
    
    private let filesPreviewManager = VideosPreviewManager.shared
    private let filesManager = VideoFilesManager.shared
    
    private var appearFile: FilesFile?

    var openFileHandler: ((FilesFile?) -> Void)?
    
    func openFileOnAppear(_ url: URL) {
        let openedFile = VideoFilesManager.shared.importFile(url: url)
        VideosPreviewManager.shared.saveThumbnail(for: url) { [weak self] in
            self?.openFileHandler?(openedFile)
        }
    }
    
    func handleFilesAppear() {
        guard let file = appearFile else { return }
        openFileHandler?(file)
        appearFile = nil
    }
    
}
