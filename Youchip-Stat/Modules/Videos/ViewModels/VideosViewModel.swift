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
                    self?.importFile(file: file)
                case let .fileNotDownloaded(file):
                    self?.action.send(.showFilesDownload(files: [file]))
                case .fileDownloading:
                    self?.action.send(.showFilesDownloading)
                }
            }
        }
    }
    
    private func importFile(file: URL) {
        guard !file.isFileSizeZero(), let filesFile = filesManager.importFile(url: file) else {
            action.send(.showError(error: ^String.Alerts.alertsFileErrorTitle))
            return
        }
        var file = filesFile
        guard let url = file.url else { return }
        filesPreviewManager.saveThumbnail(for: url) { [weak self] in
            file.updateDateOpened()
            DispatchQueue.main.async { [weak self] in
                self?.openVideo(file: url)
            }
        }
    }
    
    private func handleAction(_ action: VideosActions) {
        switch action {
        case .openFiles:
            openFiles()
        case .openImages(let image):
            break
//            openImages(image: image)
        case .openVideo(let file):
            guard let url = file.url else { return }
            openVideo(file: url)
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
        }
    }
    
    private func openVideo(file: URL) {
        let playerManager = VideoPlayerManager.shared
        playerManager.loadVideo(from: file)

        DispatchQueue.main.async {
            let playerWindow = VideoPlayerWindowController()
            let controlWindow = VideoControlWindowController()
            playerWindow.showWindow(nil)
            controlWindow.showWindow(nil)
        }
    }
}
