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
import FirebaseAnalytics

class VideosViewModel: ObservableObject {
    
    @Published var state = VideosState()
    
    let action = PassthroughSubject<VideosActions, Never>()
    private var observables: [AnyCancellable] = []
    
    let filesManager = VideoFilesManager.shared
    let filesPreviewManager = VideosPreviewManager.shared
    private let filePicker = FilesDocumentPickerHelper()
    private let fileOpenHelper = FileOpenHelper.shared
    private let cloudFilesHelper = AppCloudFilesHelper()
    private let projectExportManager = ProjectExportManager.shared
    private let downloadManager = VideoDownloadManager.shared
    
    private let maxFreeVideos = 3
    private let addedVideosCountKey = "added_videos_count"
    
    @Published var authManager = AuthManager()
    
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
        
        updateLimitInfo()
    }
    
    deinit {
        observables.removeAll()
    }
    
    private func updateLimitInfo() {
        let addedVideosCount = UserDefaults.standard.integer(forKey: addedVideosCountKey)
        let remainingVideos = max(0, maxFreeVideos - addedVideosCount)
        
        if authManager.isAuthValid {
            if let deadlineString = UserDefaults.standard.string(forKey: "auth_deadline"),
               let deadline = formatAuthDate(deadlineString) {
                state.limitInfoText = "\(^String.Titles.subscriptionActiveUntil) \(deadline)"
            } else {
                state.limitInfoText = ^String.Titles.subscriptionActive
            }
        } else {
            state.limitInfoText = String(format: ^String.Titles.videoUploadLimit, remainingVideos, maxFreeVideos)
        }
    }
    
    private func formatAuthDate(_ dateString: String) -> String? {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        
        guard let date = inputFormatter.date(from: dateString) else { return nil }
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "dd.MM.yyyy"
        outputFormatter.locale = Locale(identifier: "ru_RU")
        
        return outputFormatter.string(from: date)
    }
    
    private func canAddMoreVideos() -> Bool {
        if authManager.isAuthValid {
            return true
        } else {
            let addedVideosCount = UserDefaults.standard.integer(forKey: addedVideosCountKey)
            return addedVideosCount < maxFreeVideos
        }
    }
    
    private func incrementAddedVideosCount() {
        let currentCount = UserDefaults.standard.integer(forKey: addedVideosCountKey)
        UserDefaults.standard.set(currentCount + 1, forKey: addedVideosCountKey)
        updateLimitInfo()
    }
    
    private func openFiles() {
        if !canAddMoreVideos() {
            action.send(.showError(error: ^String.Titles.videoUploadLimitReached))
            return
        }
        
        filePicker.importFile(pick: .videos) { [weak self] response in
            DispatchQueue.main.async { [weak self] in
                switch response {
                case let .file(file):
                    self?.showMetadataSheet(for: file)
                case let .fileNotDownloaded(file):
                    self?.action.send(.showFilesDownload(files: [file]))
                case .fileDownloading:
                    self?.action.send(.showFilesDownloading)
                }
            }
        }
    }
    
    private func showMetadataSheet(for file: URL) {
        state.videoMetadata = VideoMetadata(url: file)
        state.showMetadataSheet = true
    }
    
    private func importFile(with metadata: VideoMetadata) {
        guard let url = metadata.url, !url.isFileSizeZero() else {
            action.send(.showError(error: ^String.Titles.alertsFileErrorTitle))
            return
        }

        let newFileName = metadata.generateFileName()
        guard let filesFile = filesManager.importFile(url: url, newName: newFileName) else {
            action.send(.showError(error: ^String.Titles.alertsFileErrorTitle))
            return
        }

        var file = filesFile
        guard let fileUrl = file.url else { return }

        if !authManager.isAuthValid {
            incrementAddedVideosCount()
        }

        filesPreviewManager.saveThumbnail(for: fileUrl) {
            file.updateDateOpened()
            DispatchQueue.main.async { [weak self] in
                self?.logVideoOpenEvent(id: file.videoData.id)
                WindowsManager.shared.openVideo(id: file.videoData.id)
            }
        }
    }
    
    private func showRenameSheet(for file: FilesFile) {
        state.fileToRename = file
        state.newFileName = file.name
        state.showRenameSheet = true
    }
    
    private func renameVideo(file: FilesFile, newName: String) {
        filesManager.renameFile(file: file, newName: newName)
    }
    
    private func logVideoOpenEvent(id: String) {
        guard let file = filesManager.files.first(where: { $0.videoData.id == id }),
              let deviceID = UserDefaults.standard.string(forKey: "device_code") else {
            return
        }
        
        let videoName = file.name
        
        Analytics.logEvent("video_opened", parameters: [
            "device_id": deviceID,
            "video_name": videoName
        ])
    }
    
    private func handleAction(_ action: VideosActions) {
        switch action {
        case .openFiles:
            openFiles()
        case .openImages(let image):
            break
        case .openVideo(let id):
            guard let file = filesManager.files.first(where: { $0.videoData.id == id }) else { return }
            if file.isBroken {
                state.fileToRebind = file
                state.showRebindAlert = true
            } else {
                logVideoOpenEvent(id: id)
                WindowsManager.shared.openVideo(id: id)
            }
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
        case .openGuide:
            let url = URL(string: "https://\(URLConstants.siteHost)/guides")!
            NSWorkspace.shared.open(url)
        case let .importFile(file):
            break
        case let .saveVideoMetadata(url, team1, team2, score, dateTime):
            let metadata = VideoMetadata(
                team1: team1,
                team2: team2,
                score: score,
                url: url,
                dateTime: dateTime
            )
            importFile(with: metadata)
            state.showMetadataSheet = false
            
        case .showRenameSheet(let file):
            showRenameSheet(for: file)
            
        case let .renameVideo(file, team1, team2, score):
            let metadata = VideoMetadata(team1: team1, team2: team2, score: score)
            let newFileName = metadata.generateFileName()
            renameVideo(file: file, newName: newFileName)
            state.showRenameSheet = false
        case .renameSimpleVideo(file: let file, newName: let newName):
            renameVideo(file: file, newName: newName)
            state.showRenameSheet = false
        case .refreshFiles:
            state.files = filesManager.files
        case .showAuthSheet:
            state.showAuthSheet = true
        case .updateLimitInfo:
            updateLimitInfo()
        case .toggleFavorite(let file):
            filesManager.toggleFavorite(for: file)
        case .showRebindAlert(let file):
            state.fileToRebind = file
            state.showRebindAlert = true
        case .rebindVideo(let file, let newURL):
            if filesManager.rebindVideo(file: file, newURL: newURL) {
                state.showRebindAlert = false
                state.fileToRebind = nil
                logVideoOpenEvent(id: file.id)
                WindowsManager.shared.openVideo(id: file.id)
            } else {
                self.action.send(.showError(error: "Не удалось перепривязать видео"))
            }
            
        case .exportProject(let file):
            projectExportManager.exportProject(file: file)
            
        case .importProject:
            projectExportManager.importProject { [weak self] projectData in
                DispatchQueue.main.async {
                    if let projectData = projectData {
                        self?.state.importedProjectData = projectData
                        self?.state.showProjectImportSheet = true
                    }
                }
            }
            
        case .showProjectImportSheet(let projectData):
            if let projectData {
                state.importedProjectData = projectData
            }
            state.showProjectImportSheet = projectData != nil
            
        case .bindVideoToProject(let projectData, let videoURL):
            state.importedProjectData = projectData
            state.showVideoBindingSheet = true
            
        case .createProjectFromImport(let projectData, let videoBookmark):
            if let newFile = projectExportManager.createProjectFromImport(projectData: projectData, videoBookmark: videoBookmark) {
                state.showProjectImportSheet = false
                state.importedProjectData = nil
                state.showVideoBindingSheet = false
                
                if videoBookmark != nil {
                    logVideoOpenEvent(id: newFile.id)
                    WindowsManager.shared.openVideo(id: newFile.id)
                }
            } else {
                self.action.send(.showError(error: "Не удалось создать проект"))
            }
            
        case .showDownloadFromURLSheet:
            state.showDownloadFromURLSheet = true
            
        case .fetchVideoFormats(let urlString, let ext):
            Task {
                do {
                    try await downloadManager.fetchFormats(for: urlString, ext: ext)
                } catch {
                    await MainActor.run {
                        downloadManager.downloadState = .error(message: error.localizedDescription)
                    }
                }
            }
            
        case .downloadVideoFromURL(let quality):
            if !canAddMoreVideos() {
                self.action.send(.showError(error: ^String.Titles.videoUploadLimitReached))
                return
            }
            
            Task {
                do {
                    let url = try await downloadManager.downloadVideo(
                        quality: quality,
                        filename: downloadManager.suggestedFilename
                    )
                    
                    await MainActor.run {
                        state.downloadedVideoURL = url
                    }
                } catch {
                    await MainActor.run {
                        downloadManager.downloadState = .error(message: error.localizedDescription)
                    }
                }
            }
            
        case .cancelVideoDownload:
            downloadManager.cancelDownload()
            
        case .addDownloadedVideoWithServerName(let url, let serverTitle):
            let fileName = serverTitle ?? "Video_\(Date().timeIntervalSince1970)"
            guard let filesFile = filesManager.importFile(url: url, newName: fileName) else {
                self.action.send(.showError(error: ^String.Titles.alertsFileErrorTitle))
                return
            }
            
            var file = filesFile
            guard let fileUrl = file.url else { return }
            
            if !authManager.isAuthValid {
                incrementAddedVideosCount()
            }
            
            filesPreviewManager.saveThumbnail(for: fileUrl) {
                file.updateDateOpened()
                DispatchQueue.main.async { [weak self] in
                    self?.logVideoOpenEvent(id: file.videoData.id)
                    WindowsManager.shared.openVideo(id: file.videoData.id)
                }
            }
            
        // MARK: - Live Stream Actions
            
        case .showLiveSourceSelection:
            if !canAddMoreVideos() {
                self.action.send(.showError(error: ^String.Titles.videoUploadLimitReached))
                return
            }
            state.appendVideoFile = nil
            state.preloadedVideoForLive = nil
            state.showLiveSourceSelection = true
            
        case .liveSourceConfigured(let preloadedURL):
            state.showLiveSourceSelection = false
            
            if let appendFile = state.appendVideoFile {
                // Append mode: skip metadata sheet, open directly with existing project.
                state.appendVideoFile = nil
                state.isLiveSessionConfigured = false
                WindowsManager.shared.openLiveVideoAppending(file: appendFile)
            } else {
                // New session: always show metadata sheet; carry the optional preloaded URL.
                state.preloadedVideoForLive = preloadedURL
                state.isLiveSessionConfigured = true
                state.showLiveMetadataSheet = true
            }
            
        case .startLiveWithMetadata(let team1, let team2, let score, let dateTime):
            let metadata = VideoMetadata(team1: team1, team2: team2, score: score, dateTime: dateTime)
            let preloadedURL = state.preloadedVideoForLive
            state.preloadedVideoForLive = nil
            // Reset flag before closing sheet so onDismiss doesn't trigger cancelLiveSetup
            state.isLiveSessionConfigured = false
            startLiveStream(with: metadata, preloadedURL: preloadedURL)
            state.showLiveMetadataSheet = false
            
        case .cancelLiveSetup:
            state.showLiveSourceSelection = false
            state.showLiveMetadataSheet = false
            state.isLiveSessionConfigured = false
            state.appendVideoFile = nil
            state.preloadedVideoForLive = nil
            LiveStreamManager.shared.fullCleanup()
            
            
        case .appendToVideo(let file):
            if file.isBroken {
                self.action.send(.showError(error: ^String.Titles.videoUnavailable))
                return
            }
            state.appendVideoFile = file
            state.preloadedVideoForLive = nil
            state.showLiveSourceSelection = true
        }
    }
    
    // MARK: - Live Stream
    
    private func startLiveStream(with metadata: VideoMetadata, preloadedURL: URL? = nil) {
        let newFileName = metadata.generateFileName()
        let videoId = filesManager.generate32CharacterCode()
        
        if !authManager.isAuthValid {
            incrementAddedVideosCount()
        }
        
        if let preloadedURL = preloadedURL {
            WindowsManager.shared.openLiveVideoWithPreload(videoId: videoId, fileName: newFileName, preloadedVideoURL: preloadedURL)
        } else {
            WindowsManager.shared.openLiveVideo(videoId: videoId, fileName: newFileName)
        }
    }
}
