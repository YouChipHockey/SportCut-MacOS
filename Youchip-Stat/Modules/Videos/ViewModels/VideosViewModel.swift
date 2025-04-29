//
//  VideosViewModel.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Combine
import Foundation
import AppKit
import SwiftUI
import QuickLookThumbnailing

class VideosViewModel: ObservableObject {
    
    @Published var state = VideosState()
    
    let action = PassthroughSubject<VideosActions, Never>()
    private var observables: [AnyCancellable] = []
    
    private let filesManager = VideoFilesManager.shared
    let filesPreviewManager = VideosPreviewManager.shared
    private let filePicker = FilesDocumentPickerHelper()
    private let fileOpenHelper = FileOpenHelper.shared
    private let cloudFilesHelper = AppCloudFilesHelper()
    
    init() {
        state.files = filesManager.files
        filesManager.updateFiles = { [weak self] files in
            DispatchQueue.main.async { [weak self] in
                self?.state.files = files
            }
        }
        action
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                self?.handleAction(action)
            }
            .store(in: &observables)
    }
    
    deinit {
        observables.removeAll()
    }
    
    private func openFiles() {
        filePicker.importFile(pick: .videos) { [weak self] response in
            DispatchQueue.main.async { [weak self] in
                switch response {
                case let .file(file):
                    // Updated to show metadata sheet instead of importing directly
                    self?.showMetadataSheet(for: file)
                case let .fileNotDownloaded(file):
                    self?.action.send(.showFilesDownload(files: [file]))
                case .fileDownloading:
                    self?.action.send(.showFilesDownloading)
                }
            }
        }
    }
    
    // New method to show metadata sheet
    private func showMetadataSheet(for file: URL) {
        state.videoMetadata = VideoMetadata(url: file)
        state.showMetadataSheet = true
    }
    
    // Updated method to import file with metadata
    private func importFile(with metadata: VideoMetadata) {
        guard let url = metadata.url, !url.isFileSizeZero() else {
            action.send(.showError(error: ^String.Alerts.alertsFileErrorTitle))
            return
        }
        
        // Generate the new file name based on metadata
        let newFileName = metadata.generateFileName()
        
        // Import and rename the file
        guard let filesFile = filesManager.importFile(url: url, newName: newFileName) else {
            action.send(.showError(error: ^String.Alerts.alertsFileErrorTitle))
            return
        }
        
        var file = filesFile
        guard let fileUrl = file.url else { return }
        
        filesPreviewManager.saveThumbnail(for: fileUrl) {
            file.updateDateOpened()
            DispatchQueue.main.async {
                WindowsManager.shared.openVideo(id: file.videoData.id)
            }
        }
    }
    
    // Handle rename request
    private func showRenameSheet(for file: FilesFile) {
        // Simply show the current name in a text field
        state.fileToRename = file
        state.newFileName = file.name  // We'll add this property to VideosState
        state.showRenameSheet = true
    }
    
    // Rename existing video with a single name parameter
    private func renameVideo(file: FilesFile, newName: String) {
        filesManager.renameFile(file: file, newName: newName)
    }
    
    private func handleAction(_ action: VideosActions) {
        switch action {
        case .openFiles:
            openFiles()
        case .openImages(let image):
            break
//            openImages(image: image)
        case .openVideo(let id):
            WindowsManager.shared.openVideo(id: id)
        case .deleteFile(let file):
            filesManager.removeFile(file: file)
        case .openFileFromHelper:
            fileOpenHelper.handleFilesAppear()
        case .showError(let error):
            state.showError = true
            state.errorTitle = error
        case let .showFilesDownload(files):
            cloudFilesHelper.setCloudFiles(files)
            state.showFilesDownloadAlert = true
        case .showFilesDownloading:
            state.showFilesDownloadingAlert = true
        case .downloadFiles:
            cloudFilesHelper.downloadFiles()
        case let .importFile(file):
            break
//            importFile(file: file)
            
        // New cases for metadata and renaming
        case let .saveVideoMetadata(url, team1, team2, score):
            let metadata = VideoMetadata(team1: team1, team2: team2, score: score, url: url)
            importFile(with: metadata)
            state.showMetadataSheet = false
            
        case .showRenameSheet(let file):
            showRenameSheet(for: file)
            
        // Fix the pattern to match the action type signature
        case let .renameVideo(file, team1, team2, score):
            // Generate filename from team info
            let metadata = VideoMetadata(team1: team1, team2: team2, score: score)
            let newFileName = metadata.generateFileName()
            renameVideo(file: file, newName: newFileName)
            state.showRenameSheet = false
        case .renameSimpleVideo(file: let file, newName: let newName):
            renameVideo(file: file, newName: newName)
            state.showRenameSheet = false
        case .refreshFiles:
            state.files = filesManager.files
        }
    }
}
