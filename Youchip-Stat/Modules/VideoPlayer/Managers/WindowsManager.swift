//
//  CustomCollectionManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI
import AppKit
import AVKit
import Foundation

class WindowsManager: NSObject {
    
    var currentVideoId = ""
    static let shared = WindowsManager()
    
    private func ensureScreenshotsTimelineExists() {
        let timelineData = TimelineDataManager.shared
        let screenshotsID = ScreenshotConstants.screenshotsTimelineID
        
        if let existingLine = timelineData.lines.first(where: { $0.id == screenshotsID }) {
            if let index = timelineData.lines.firstIndex(where: { $0.id == screenshotsID }), index != 0 {
                let line = timelineData.lines.remove(at: index)
                timelineData.lines.insert(line, at: 0)
                timelineData.updateTimelines()
            }
            return
        }
        
        let screenshotsLine = TimelineLine(id: screenshotsID, name: ScreenshotConstants.screenshotsGroupName, stamps: [], tagIdForMode: "")
        timelineData.lines.insert(screenshotsLine, at: 0)
        timelineData.updateTimelines()
    }
    
    var videoWindow: VideoPlayerWindowController?
    var controlWindow: FullControlWindowController?
    var tagLibraryWindow: TagLibraryWindowController?
    var analyticsWindow: AnalyticsWindowController?
    var screenshotsWindow: ScreenshotsWindowController?
    var fieldMapConfigurationWindow: FieldMapConfigurationWindowController?
    var viewerWindow: ViewerWindowController?
    var sportCutWindow: SportCutWindowController?
    /// After opening SportCut from markup, main view starts playback of this playlist.
    private(set) var pendingSportCutAutoplayPlaylistID: UUID?
    var reviewVideoWindow: ReviewVideoWindowController?
    var markupMirrorVideoWindow: MirroredVideoWindowController?
    var viewerMirrorVideoWindow: MirroredVideoWindowController?
    var sportCutMirrorVideoWindow: MirroredVideoWindowController?

    private var fieldMapWindow: NSWindowController?

    private var editorWindowControllers: [NSWindowController] = []
    private var momentViewerControllers: [NSWindowController] = []
    private var isClosing = true
    private var isWindowsLocked = false
    
    /// Tracks whether the current session is a live stream
    private(set) var isLiveSession: Bool = false
    private var liveVideoId: String?
    private var liveFileName: String?
    
    /// Whether the current live session is appending to an existing video project.
    private var isAppendingToFile: Bool = false
    private var appendingFile: FilesFile? = nil
    
    private var collectionWindowDelegate: CollectionWindowDelegate?
    
    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .closeViewerWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.viewerWindow = nil
            self?.viewerMirrorVideoWindow?.close()
            self?.viewerMirrorVideoWindow = nil
        }
    }
    
    func toggleMarkupMirrorVideoWindow() {
        if let existing = markupMirrorVideoWindow {
            existing.close()
            markupMirrorVideoWindow = nil
            return
        }
        let controller = MirroredVideoWindowController(mode: .markup)
        markupMirrorVideoWindow = controller
        positionMirrorWindow(controller.window, beside: videoWindow?.window)
        controller.showWindow(nil)
    }
    
    func toggleViewerMirrorVideoWindow(playlistManager: VideoPlaylistManager) {
        if let existing = viewerMirrorVideoWindow {
            existing.close()
            viewerMirrorVideoWindow = nil
            return
        }
        let controller = MirroredVideoWindowController(mode: .viewer(playlistManager))
        viewerMirrorVideoWindow = controller
        positionMirrorWindow(controller.window, beside: viewerWindow?.window)
        controller.showWindow(nil)
    }

    func toggleSportCutMirrorVideoWindow(playerManager: SportCutPlayerManager) {
        if let existing = sportCutMirrorVideoWindow {
            existing.close()
            sportCutMirrorVideoWindow = nil
            return
        }
        let controller = MirroredVideoWindowController(mode: .sportCut(playerManager))
        sportCutMirrorVideoWindow = controller
        positionMirrorWindow(controller.window, beside: sportCutWindow?.window)
        controller.showWindow(nil)
    }
    
    func mirroredVideoWindowDidClose(mode: MirroredVideoWindowController.Mode) {
        switch mode {
        case .markup:
            markupMirrorVideoWindow = nil
        case .viewer:
            viewerMirrorVideoWindow = nil
        case .sportCut:
            sportCutMirrorVideoWindow = nil
        }
    }

    func sportCutWindowDidClose() {
        sportCutMirrorVideoWindow?.close()
        sportCutMirrorVideoWindow = nil
        sportCutWindow = nil
        activeSportCutSessionID = nil
        activeSportCutPlayerManager = nil
    }
    
    private func positionMirrorWindow(_ window: NSWindow?, beside host: NSWindow?) {
        guard let mirror = window else { return }
        let hostFrame = host?.frame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 120, y: 120, width: 900, height: 600)
        let targetContentWidth = min(max(hostFrame.width * 0.55, 480), 960)
        let targetContentHeight = targetContentWidth * 9 / 16
        mirror.setContentSize(NSSize(width: targetContentWidth, height: targetContentHeight))
        let size = mirror.frame.size
        var origin = NSPoint(
            x: hostFrame.maxX + 12,
            y: hostFrame.midY - size.height / 2
        )
        if let screen = host?.screen ?? NSScreen.main {
            let vf = screen.visibleFrame
            origin.x = min(origin.x, vf.maxX - size.width - 8)
            origin.x = max(origin.x, vf.minX + 8)
            origin.y = max(vf.minY + 8, min(origin.y, vf.maxY - size.height - 8))
        }
        mirror.setFrame(NSRect(origin: origin, size: size), display: true)
    }
    
    func closeAll() {
        tagLibraryWindow?.cancelNotificationSubscriptions()
        
        videoWindow?.window?.delegate = nil
        controlWindow?.window?.delegate = nil
        tagLibraryWindow?.window?.delegate = nil
        analyticsWindow?.window?.delegate = nil
        screenshotsWindow?.window?.delegate = nil
        fieldMapConfigurationWindow = nil
        reviewVideoWindow?.window?.delegate = nil
        
        markupMirrorVideoWindow?.window?.delegate = nil
        viewerMirrorVideoWindow?.window?.delegate = nil
        sportCutMirrorVideoWindow?.window?.delegate = nil
        markupMirrorVideoWindow?.close()
        viewerMirrorVideoWindow?.close()
        sportCutMirrorVideoWindow?.close()
        markupMirrorVideoWindow = nil
        viewerMirrorVideoWindow = nil
        sportCutMirrorVideoWindow = nil
        
        let momentControllers = momentViewerControllers
        momentViewerControllers.removeAll()
        for mc in momentControllers {
            (mc as? MomentViewerWindowController)?.stopPlaybackForClose()
            mc.close()
        }
        
        NotificationCenter.default.post(name: .stopViewerPlayer, object: nil)
        viewerWindow?.close()
        viewerWindow = nil
        
        fieldMapConfigurationWindow?.close()
        videoWindow?.close()
        controlWindow?.close()
        tagLibraryWindow?.close()
        analyticsWindow?.close()
        screenshotsWindow?.close()
        
        // Close review window without triggering its delegate (to avoid double exitReviewMode).
        reviewVideoWindow?.window?.delegate = nil
        reviewVideoWindow?.close()
        reviewVideoWindow = nil
        
        ScreenshotsMetadataManager.shared.clearScreenshots()
        
        HotKeyManager.shared.clearHotkeys()
        HotKeyManager.shared.suspendKeyboardMonitoring()
        
        // If this was a live session, finalize the recording and import the video
        if isLiveSession {
            finalizeLiveSession()
        } else {
            VideoPlayerManager.shared.deleteVideo()
        }
        
        isClosing = true
    }
    
    // MARK: - Live Stream
    
    func openLiveVideo(videoId: String, fileName: String) {
        currentVideoId = videoId
        isLiveSession = true
        liveVideoId = videoId
        liveFileName = fileName
        isAppendingToFile = false
        appendingFile = nil
        
        guard isClosing else { return }
        
        UserDefaults.standard.set("", forKey: "editingStampLineID")
        UserDefaults.standard.set("", forKey: "editingStampID")
        isClosing = false
        
        VideoMarkupActivityBanner.shared.clearTagMarkupHistoryForNewVideoSession()
        
        TimelineDataManager.shared.currentBookmark = nil
        TimelineDataManager.shared.lines = []
        TimelineDataManager.shared.selectedLineID = nil
        ensureScreenshotsTimelineExists()
        
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let screenshotsDir = documentsDir.appendingPathComponent("Screenshots").appendingPathComponent(videoId)
        if !fileManager.fileExists(atPath: screenshotsDir.path) {
            try? fileManager.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)
        }
        ScreenshotsMetadataManager.shared.loadScreenshots(from: screenshotsDir)
        
        VideoPlayerManager.shared.startLiveMode()
        LiveStreamManager.shared.startLiveStream(videoId: videoId)
        
        openLiveWindows()
    }
    
    /// Opens a live session that appends new recording to an existing video project.
    /// The existing project's timelines are loaded; the preloaded video seeds the review player.
    func openLiveVideoAppending(file: FilesFile) {
        guard let videoURL = file.url else { return }
        
        let existingId = file.id
        let existingTimelines = VideoFilesManager.shared.loadTimelines(for: existingId)
        
        currentVideoId = existingId
        isLiveSession = true
        liveVideoId = existingId
        liveFileName = file.name
        isAppendingToFile = true
        appendingFile = file
        
        guard isClosing else { return }
        
        UserDefaults.standard.set("", forKey: "editingStampLineID")
        UserDefaults.standard.set("", forKey: "editingStampID")
        isClosing = false
        
        VideoMarkupActivityBanner.shared.clearTagMarkupHistoryForNewVideoSession()
        
        // Load existing timelines from the project being appended to.
        TimelineDataManager.shared.currentBookmark = nil
        TimelineDataManager.shared.lines = existingTimelines
        TimelineDataManager.shared.selectedLineID = nil
        ensureScreenshotsTimelineExists()
        
        // Use the existing project's screenshots folder.
        let screenshotsDir = file.screenshotsFolder
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: screenshotsDir.path) {
            try? fileManager.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)
        }
        ScreenshotsMetadataManager.shared.loadScreenshots(from: screenshotsDir)
        
        VideoPlayerManager.shared.startLiveMode()
        LiveStreamManager.shared.startLiveStream(videoId: existingId, preloadedVideoURL: videoURL)
        
        openLiveWindows()
    }
    
    /// Opens a new live session (fresh project) with an optional pre-existing video seeding the review player.
    func openLiveVideoWithPreload(videoId: String, fileName: String, preloadedVideoURL: URL?) {
        currentVideoId = videoId
        isLiveSession = true
        liveVideoId = videoId
        liveFileName = fileName
        isAppendingToFile = false
        appendingFile = nil
        
        guard isClosing else { return }
        
        UserDefaults.standard.set("", forKey: "editingStampLineID")
        UserDefaults.standard.set("", forKey: "editingStampID")
        isClosing = false
        
        VideoMarkupActivityBanner.shared.clearTagMarkupHistoryForNewVideoSession()
        
        TimelineDataManager.shared.currentBookmark = nil
        TimelineDataManager.shared.lines = []
        TimelineDataManager.shared.selectedLineID = nil
        ensureScreenshotsTimelineExists()
        
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let screenshotsDir = documentsDir.appendingPathComponent("Screenshots").appendingPathComponent(videoId)
        if !fileManager.fileExists(atPath: screenshotsDir.path) {
            try? fileManager.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)
        }
        ScreenshotsMetadataManager.shared.loadScreenshots(from: screenshotsDir)
        
        VideoPlayerManager.shared.startLiveMode()
        LiveStreamManager.shared.startLiveStream(videoId: videoId, preloadedVideoURL: preloadedVideoURL)
        
        openLiveWindows()
    }
    
    private func openLiveWindows() {
        videoWindow = VideoPlayerWindowController(id: currentVideoId)
        controlWindow = FullControlWindowController()
        tagLibraryWindow = TagLibraryWindowController()
        
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let bottomHeight = screenFrame.height * 0.4
            let topHeight = screenFrame.height - bottomHeight - 40
            
            let timelineRect = NSRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: bottomHeight)
            controlWindow?.window?.setFrame(timelineRect, display: true)
            
            let libraryRect = NSRect(x: screenFrame.minX, y: screenFrame.minY + bottomHeight, width: screenFrame.width / 3, height: topHeight)
            tagLibraryWindow?.window?.setFrame(libraryRect, display: true)
            
            let videoRect = NSRect(x: screenFrame.minX + screenFrame.width / 3, y: screenFrame.minY + bottomHeight, width: (screenFrame.width * 2) / 3, height: topHeight)
            videoWindow?.window?.setFrame(videoRect, display: true)
        }
        
        videoWindow?.showWindow(nil)
        controlWindow?.showWindow(nil)
        tagLibraryWindow?.showWindow(nil)
    }
    
    /// Копирует все файлы скриншотов из папки live-сессии в папку импортированного видео (у импорта новый id).
    private func copyLiveScreenshotsToImportedVideo(liveVideoId: String, importedScreenshotsFolder: URL) {
        guard !liveVideoId.isEmpty,
              let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let liveScreenshotsFolder = documentsDir.appendingPathComponent("Screenshots").appendingPathComponent(liveVideoId)
        guard FileManager.default.fileExists(atPath: liveScreenshotsFolder.path) else { return }
        do {
            let items = try FileManager.default.contentsOfDirectory(at: liveScreenshotsFolder, includingPropertiesForKeys: nil)
            for item in items where item.isFileURL {
                let dest = importedScreenshotsFolder.appendingPathComponent(item.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.removeItem(at: dest)
                }
                try? FileManager.default.copyItem(at: item, to: dest)
            }
        } catch {
            print("WindowsManager: Failed to copy live screenshots: \(error.localizedDescription)")
        }
    }
    
    /// Finalize the live recording: stop capture, write final file, import or update the video project.
    private func finalizeLiveSession() {
        if isAppendingToFile, let file = appendingFile {
            finalizeAppendSession(existingFile: file)
        } else {
            finalizeNewSession()
        }
    }

    /// Stops live stream, finalizes recording and switches current windows to normal markup mode.
    func stopLiveSessionAndSwitchToMarkupMode() {
        guard isLiveSession else { return }
        let timelines = TimelineDataManager.shared.lines
        let liveId = liveVideoId ?? ""
        let fileName = liveFileName ?? "Live_\(Date().timeIntervalSince1970)"
        let appendTarget = appendingFile
        let wasAppending = isAppendingToFile
        
        if VideoPlayerManager.shared.isReviewMode {
            VideoPlayerManager.shared.exitReviewMode()
            closeReviewWindow()
        }
        
        VideoPlayerManager.shared.endLiveMode()
        
        LiveStreamManager.shared.stopAndFinalize { [weak self] fileURL in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                defer {
                    self.isLiveSession = false
                    self.isAppendingToFile = false
                    self.appendingFile = nil
                    self.liveVideoId = nil
                    self.liveFileName = nil
                    self.setMarkupMode(.standard)
                    LiveStreamManager.shared.fullCleanup()
                }
                
                guard let finalURL = fileURL else {
                    print("WindowsManager: stop live failed - no file produced")
                    return
                }
                
                if wasAppending, let existing = appendTarget {
                    VideoFilesManager.shared.updateVideoURL(for: existing, newURL: finalURL)
                    VideoFilesManager.shared.saveTimelines(timelines, for: existing.id)
                    
                    self.currentVideoId = existing.id
                    TimelineDataManager.shared.currentBookmark = existing.videoData.bookmark
                    TimelineDataManager.shared.lines = timelines
                    TimelineDataManager.shared.selectedLineID = timelines.first?.id
                    self.ensureScreenshotsTimelineExists()
                    ScreenshotsMetadataManager.shared.loadScreenshots(from: existing.screenshotsFolder)
                    VideoPlayerManager.shared.transitionToStaticVideo(url: finalURL)
                    HotKeyManager.shared.resumeKeyboardMonitoring()
                    return
                }
                
                guard let importedFile = VideoFilesManager.shared.importFile(url: finalURL, newName: fileName) else {
                    print("WindowsManager: import failed after stopping live")
                    return
                }
                
                VideoFilesManager.shared.updateTimelines(
                    forVideoId: importedFile.videoData.id,
                    with: timelines
                )
                self.copyLiveScreenshotsToImportedVideo(
                    liveVideoId: liveId,
                    importedScreenshotsFolder: importedFile.screenshotsFolder
                )

                self.currentVideoId = importedFile.id
                TimelineDataManager.shared.currentBookmark = importedFile.videoData.bookmark
                TimelineDataManager.shared.currentVideoId = importedFile.videoData.id
                TimelineDataManager.shared.lines = timelines
                TimelineDataManager.shared.selectedLineID = timelines.first?.id
                self.ensureScreenshotsTimelineExists()
                ScreenshotsMetadataManager.shared.loadScreenshots(from: importedFile.screenshotsFolder)
                VideoPlayerManager.shared.transitionToStaticVideo(url: finalURL)
                HotKeyManager.shared.resumeKeyboardMonitoring()
            }
        }
    }
    
    private func finalizeNewSession() {
        let videoId = liveVideoId ?? ""
        let fileName = liveFileName ?? "Live_\(Date().timeIntervalSince1970)"
        let timelines = TimelineDataManager.shared.lines
        
        VideoPlayerManager.shared.endLiveMode()
        
        LiveStreamManager.shared.stopAndFinalize { [weak self] fileURL in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let url = fileURL {
                    if let filesFile = VideoFilesManager.shared.importFile(url: url, newName: fileName) {
                        VideoFilesManager.shared.updateTimelines(
                            forVideoId: filesFile.videoData.id,
                            with: timelines
                        )
                        self.copyLiveScreenshotsToImportedVideo(liveVideoId: videoId, importedScreenshotsFolder: filesFile.screenshotsFolder)
                        print("WindowsManager: Live recording imported as '\(fileName)' with \(timelines.count) timelines")
                    }
                } else {
                    print("WindowsManager: Live recording finalization failed - no file produced")
                }
                
                self.isLiveSession = false
                self.liveVideoId = nil
                self.liveFileName = nil
                
                LiveStreamManager.shared.fullCleanup()
            }
        }
    }
    
    private func finalizeAppendSession(existingFile: FilesFile) {
        let timelines = TimelineDataManager.shared.lines
        
        VideoPlayerManager.shared.endLiveMode()
        
        LiveStreamManager.shared.stopAndFinalize { [weak self] fileURL in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let url = fileURL {
                    // Update the existing project's video to the combined (old + new) file.
                    VideoFilesManager.shared.updateVideoURL(for: existingFile, newURL: url)
                    // Save the merged timelines back to the existing project's ID.
                    VideoFilesManager.shared.saveTimelines(timelines, for: existingFile.id)
                    print("WindowsManager: Append session finalized for '\(existingFile.name)' with \(timelines.count) timelines")
                } else {
                    print("WindowsManager: Append session finalization failed - no file produced")
                }
                
                self.isLiveSession = false
                self.isAppendingToFile = false
                self.appendingFile = nil
                self.liveVideoId = nil
                self.liveFileName = nil
                
                LiveStreamManager.shared.fullCleanup()
            }
        }
    }
    
    // MARK: - Review Window
    
    func openReviewWindow() {
        guard reviewVideoWindow == nil else {
            reviewVideoWindow?.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = ReviewVideoWindowController()
        reviewVideoWindow = controller
        
        // Position the review window: place it alongside the live video window.
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let bottomHeight = screenFrame.height * 0.4
            let topHeight = screenFrame.height - bottomHeight - 40
            
            // Split the top-right 2/3 into two equal halves (live left, review right).
            let halfWidth = (screenFrame.width * 2) / 3 / 2
            let leftStartX = screenFrame.minX + screenFrame.width / 3
            
            // Move live video window to left half.
            let liveRect = NSRect(
                x: leftStartX,
                y: screenFrame.minY + bottomHeight,
                width: halfWidth,
                height: topHeight
            )
            videoWindow?.window?.setFrame(liveRect, display: true)
            
            // Place review window in right half.
            let reviewRect = NSRect(
                x: leftStartX + halfWidth,
                y: screenFrame.minY + bottomHeight,
                width: halfWidth,
                height: topHeight
            )
            controller.window?.setFrame(reviewRect, display: true)
        }
        
        controller.showWindow(nil)
    }
    
    func closeReviewWindow() {
        reviewVideoWindow?.window?.delegate = nil
        reviewVideoWindow?.close()
        reviewVideoWindow = nil
        restoreLiveVideoWindowFrameAfterReview()
    }

    /// Called when user closes the review window directly.
    func reviewWindowDidCloseByUser() {
        reviewVideoWindow = nil
        restoreLiveVideoWindowFrameAfterReview()
    }

    private func restoreLiveVideoWindowFrameAfterReview() {
        // Restore live video window to its original 2/3 width.
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let bottomHeight = screenFrame.height * 0.4
            let topHeight = screenFrame.height - bottomHeight - 40
            let videoRect = NSRect(
                x: screenFrame.minX + screenFrame.width / 3,
                y: screenFrame.minY + bottomHeight,
                width: (screenFrame.width * 2) / 3,
                height: topHeight
            )
            videoWindow?.window?.setFrame(videoRect, display: true)
        }
    }
    
    func showFieldMapVisualizationPicker() {
        let controller = FieldMapVisualizationWindowController()
        controller.showWindow(nil)
    }
    
    func showFieldMapVisualization(collection: CollectionBookmark, mode: VisualizationMode, stamps: [TimelineStamp]) {
        let view = FieldMapVisualizationView(collection: collection, mode: mode, stamps: stamps)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = ^String.Titles.fieldMapVisualization
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = NSSize(width: screenFrame.width * 0.7, height: screenFrame.height * 0.7)
            window.setContentSize(windowSize)
            window.center()
        } else {
            window.setContentSize(NSSize(width: 800, height: 600))
            window.center()
        }
        
        window.makeKeyAndOrderFront(nil)
    }
    
    func showScreenshots() {
        if screenshotsWindow != nil {
            screenshotsWindow?.close()
            return
        }
        guard let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == currentVideoId }) else {
            return
        }
        screenshotsWindow = ScreenshotsWindowController(screenshotsFolder: filesFile.screenshotsFolder)
    }
    
    func showAnalytics() {
        analyticsWindow = AnalyticsWindowController()
    }
    
    func setMarkupMode(_ mode: MarkupMode) {
        MarkupMode.current = mode
    }
    
    func openCustomCollectionsWindow(withExistingCollection existingCollection: CollectionBookmark? = nil) {
        VideoPlayerManager.shared.player?.pause()
        
        let view: AnyView
        
        if let existingCollection = existingCollection {
            view = AnyView(CreateCustomCollectionsView(existingCollection: existingCollection))
        } else {
            view = AnyView(CreateCustomCollectionsView())
        }
        
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = existingCollection != nil ?
        "\(^String.Titles.editingCollection): \(existingCollection?.name ?? "")" :
        ^String.Titles.creatingNewCollection
        
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            window.setFrame(screenFrame, display: true)
        } else {
            window.center()
            window.setContentSize(NSSize(width: 850, height: 600))
        }
        NotificationCenter.default.addObserver(forName: .collectionDataChanged, object: nil, queue: .main) { _ in
            TagLibraryManager.shared.refreshGlobalPools()
        }
        
        self.collectionWindowDelegate = CollectionWindowDelegate()
        window.delegate = self.collectionWindowDelegate
        NotificationCenter.default.post(name: .collectionEditorOpened, object: nil)
        window.makeKeyAndOrderFront(nil)
    }
    
    func showFieldMapConfigurationWindow() {
        if fieldMapConfigurationWindow != nil {
            if let window = fieldMapConfigurationWindow?.window {
                maximizeWindowToFullScreen(window)
            }
            fieldMapConfigurationWindow?.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        fieldMapConfigurationWindow = FieldMapConfigurationWindowController()
        if let window = fieldMapConfigurationWindow?.window {
            maximizeWindowToFullScreen(window)
        }
        
        fieldMapConfigurationWindow?.showWindow(nil)
        fieldMapConfigurationWindow?.window?.makeKeyAndOrderFront(nil)
    }
    
    private func maximizeWindowToFullScreen(_ window: NSWindow) {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            window.setFrame(screenFrame, display: true)
        }
    }
    
    func openVideo(id: String) {
        currentVideoId = id
        guard let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == id }) else { 
            return
        }
        guard let file = filesFile.url, isClosing else { 
            return
        }
        
        let loadedTimelines = filesFile.timelines
        let timelineNames = loadedTimelines.map { $0.name }
        let uniqueNames = Set(timelineNames)
        if timelineNames.count != uniqueNames.count {
            let nameCounts = Dictionary(grouping: loadedTimelines, by: { $0.name }).mapValues { $0.count }
        }
        
        UserDefaults.standard.set("", forKey: "editingStampLineID")
        UserDefaults.standard.set("", forKey: "editingStampID")
        isClosing = false
        
        VideoMarkupActivityBanner.shared.clearTagMarkupHistoryForNewVideoSession()
        
        TimelineDataManager.shared.currentBookmark = filesFile.videoData.bookmark
        TimelineDataManager.shared.currentVideoId = filesFile.videoData.id
        
        if MarkupMode.current == .standard {
            TimelineDataManager.shared.lines = loadedTimelines
            TimelineDataManager.shared.selectedLineID = loadedTimelines.first?.id
        } else {
            TimelineDataManager.shared.lines = loadedTimelines
            TimelineDataManager.shared.selectedLineID = nil
        }
        
        ensureScreenshotsTimelineExists()
        ScreenshotsMetadataManager.shared.loadScreenshots(from: filesFile.screenshotsFolder)
        
        VideoPlayerManager.shared.loadVideo(from: file)
        
        HotKeyManager.shared.resumeKeyboardMonitoring()
        
        videoWindow = VideoPlayerWindowController(id: id)
        controlWindow = FullControlWindowController()
        tagLibraryWindow = TagLibraryWindowController()
        
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let bottomHeight = screenFrame.height * 0.4
            let topHeight = screenFrame.height - bottomHeight - 40
            
            let timelineRect = NSRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: screenFrame.width,
                height: bottomHeight
            )
            controlWindow?.window?.setFrame(timelineRect, display: true)
            
            let libraryRect = NSRect(
                x: screenFrame.minX,
                y: screenFrame.minY + bottomHeight,
                width: screenFrame.width / 3,
                height: topHeight
            )
            tagLibraryWindow?.window?.setFrame(libraryRect, display: true)
            
            let videoRect = NSRect(
                x: screenFrame.minX + screenFrame.width / 3,
                y: screenFrame.minY + bottomHeight,
                width: (screenFrame.width * 2) / 3,
                height: topHeight
            )
            videoWindow?.window?.setFrame(videoRect, display: true)
        }
        
        videoWindow?.showWindow(nil)
        controlWindow?.showWindow(nil)
        tagLibraryWindow?.showWindow(nil)
    }
    
    func showFieldMapSelection(tag: Tag, imageBookmark: Data, onSave: @escaping (CGPoint) -> Void) {
        let controller = FieldMapSelectionWindowController(tag: tag, imageBookmark: imageBookmark, onSave: onSave)
        fieldMapWindow = controller
        
        lockMainWindows(true)
        
        controller.showWindow(nil)
        controller.window?.center()
    }
    
    func lockMainWindows(_ locked: Bool) {
        isWindowsLocked = locked
        tagLibraryWindow?.window?.ignoresMouseEvents = locked
    }
    
    func fieldMapWindowDidClose() {
        lockMainWindows(false)
        fieldMapWindow = nil
    }
    
    /// Возвращает true, если ключевое окно — таймлайн (control) или библиотека тегов (tag library). Используется для пробела = play/pause.
    func isControlOrTagLibraryWindowKey() -> Bool {
        guard let keyWindow = NSApplication.shared.keyWindow else { return false }
        return keyWindow === controlWindow?.window || keyWindow === tagLibraryWindow?.window
    }
    
    /// Возвращает true, если ключевое окно — окно пересмотра записи.
    func isReviewWindowKey() -> Bool {
        guard let keyWindow = NSApplication.shared.keyWindow else { return false }
        return keyWindow === reviewVideoWindow?.window
    }

    /// Ключевое окно — режим просмотра SportCut (включая открытый с sheet поверх него).
    func isSportCutKeyWindow() -> Bool {
        guard let scWin = sportCutWindow?.window else { return false }
        guard let keyWindow = NSApplication.shared.keyWindow else { return false }
        if keyWindow === scWin { return true }
        if keyWindow.sheetParent === scWin { return true }
        return false
    }
    
    // MARK: - Moment Viewer
    
    /// Открывает окно просмотра момента для указанного тега. Асинхронно получает подходящий AVAsset из текущего режима.
    func openMomentViewer(
        stampStart: Double,
        stampDuration: Double,
        tagName: String,
        lineName: String,
        lineID: UUID? = nil,
        stampID: UUID? = nil
    ) {
        VideoPlayerManager.shared.player?.pause()

        let clipStart = max(0, stampStart)
        let clipDuration = max(stampDuration, 0.5)
        
        VideoPlayerManager.shared.assetForMomentViewer { [weak self] asset in
            guard let self = self, let asset = asset else { return }
            DispatchQueue.main.async {
                let controller = MomentViewerWindowController(
                    asset: asset,
                    startTime: clipStart,
                    duration: clipDuration,
                    tagName: tagName,
                    lineName: lineName,
                    lineID: lineID,
                    stampID: stampID
                )
                self.momentViewerControllers.append(controller)
                controller.showWindow(nil)
            }
        }
    }
    
    func showReportWindow(htmlString: String, teamName: String, opponentName: String) {
        let view = WebViewWrapper(htmlString: htmlString)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = String.Titles.aiReportTitle.format(teamName, opponentName)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            window.setFrame(screenFrame, display: true)
        } else {
            window.center()
            window.setContentSize(NSSize(width: 1200, height: 800))
        }
        
        window.makeKeyAndOrderFront(nil)
    }
    
    func showViewerWindow() {
        VideoPlayerManager.shared.player?.pause()

        viewerWindow = nil
        viewerWindow?.close()
        
        viewerWindow = ViewerWindowController(videoID: currentVideoId)
        viewerWindow?.showWindow(nil)
    }
    
    func consumePendingSportCutAutoplayPlaylistID() -> UUID? {
        let id = pendingSportCutAutoplayPlaylistID
        pendingSportCutAutoplayPlaylistID = nil
        return id
    }

    func sportCutSessionsForCurrentMarkupProject() -> [SportCutSession] {
        guard let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == currentVideoId }) else {
            return []
        }
        let pid = filesFile.id
        return SportCutSessionManager.shared.sessions.filter { sess in
            sess.sources.contains { $0.projectID == pid }
        }
    }

    /// Creates a new viewing session with the current markup project (previous behavior).
    func showSportCutNewSessionFromMarkup() {
        VideoPlayerManager.shared.player?.pause()

        guard let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == currentVideoId }) else {
            return
        }

        sportCutWindow?.close()
        sportCutWindow = nil

        let sessionName = filesFile.name
        var session = SportCutSessionManager.shared.createSession(name: sessionName)
        SportCutSessionManager.shared.addProjectSource(to: &session, file: filesFile)

        if session.playlistGroups.isEmpty {
            SportCutSessionManager.shared.addPlaylistGroup(to: &session, name: "Основная")
        }

        sportCutWindow = SportCutWindowController(session: session)
        sportCutWindow?.showWindow(nil)
    }

    func showSportCutFromMarkup() {
        showSportCutNewSessionFromMarkup()
    }

    func openSportCutSessionFromMarkup(existingSessionID: UUID) {
        VideoPlayerManager.shared.player?.pause()

        guard let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == currentVideoId }),
              var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == existingSessionID }) else { return }
        SportCutSessionManager.shared.syncProjectSource(from: filesFile, in: &session)
        guard let refreshed = SportCutSessionManager.shared.sessions.first(where: { $0.id == existingSessionID }) else { return }
        sportCutWindow?.close()
        sportCutWindow = nil
        sportCutWindow = SportCutWindowController(session: refreshed)
        sportCutWindow?.showWindow(nil)
    }

    /// Добавляет новый плейлист с тегами из разметки в указанную сессию и открывает окно SportCut.
    private func addMarkupStampsAsNewPlaylistAndOpenWindow(
        sessionID: UUID,
        projectID: String,
        pairs: [(TimelineLine, TimelineStamp)]
    ) {
        guard !pairs.isEmpty else { return }
        guard var mutable = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
              let source = mutable.sources.first(where: { $0.projectID == projectID }) else { return }

        let sortedPairs = pairs.sorted { $0.1.timeStartSeconds < $1.1.timeStartSeconds }
        let events = sortedPairs.map { SportCutEvent.from(stamp: $0.1, line: $0.0, source: source) }
        var eventComments: [String: String] = [:]
        for (line, stamp) in sortedPairs {
            let ev = SportCutEvent.from(stamp: stamp, line: line, source: source)
            if let raw = stamp.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                eventComments[ev.hiddenKey] = raw
            }
        }

        if mutable.playlistGroups.isEmpty {
            SportCutSessionManager.shared.addPlaylistGroup(to: &mutable, name: "Основная")
        }
        let df = DateFormatter()
        df.locale = Locale.current
        df.timeStyle = .short
        df.dateStyle = .short
        let playlistName = "Теги (\(df.string(from: Date())))"
        let newPlaylist = SportCutPlaylist(name: playlistName, events: events, eventComments: eventComments)
        mutable.playlistGroups[0].playlists.append(newPlaylist)
        SportCutSessionManager.shared.updateSession(mutable)

        let playlistID = newPlaylist.id
        pendingSportCutAutoplayPlaylistID = playlistID

        sportCutWindow?.close()
        sportCutWindow = nil
        guard let opened = SportCutSessionManager.shared.sessions.first(where: { $0.id == mutable.id }) else { return }
        sportCutWindow = SportCutWindowController(session: opened)
        sportCutWindow?.showWindow(nil)

        TimelineDataManager.shared.clearSportCutExportSelection()
    }

    /// При `forceNewSession == true` всегда создаётся новая сессия (кнопка «Новая сессия просмотра»). Иначе плейлист добавляется в уже существующую сессию с этим проектом, если она есть.
    func openSportCutFromTimelineStamps(_ pairs: [(TimelineLine, TimelineStamp)], forceNewSession: Bool = false) {
        VideoPlayerManager.shared.player?.pause()

        guard !pairs.isEmpty else { return }
        guard let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == currentVideoId }) else { return }
        let pid = filesFile.id

        if forceNewSession {
            sportCutWindow?.close()
            sportCutWindow = nil
            var session = SportCutSessionManager.shared.createSession(name: filesFile.name)
            SportCutSessionManager.shared.addProjectSource(to: &session, file: filesFile)
            if session.playlistGroups.isEmpty {
                SportCutSessionManager.shared.addPlaylistGroup(to: &session, name: "Основная")
            }
            addMarkupStampsAsNewPlaylistAndOpenWindow(sessionID: session.id, projectID: pid, pairs: pairs)
            return
        }

        if var existing = SportCutSessionManager.shared.sessions.first(where: { sess in
            sess.sources.contains { $0.projectID == pid }
        }) {
            SportCutSessionManager.shared.syncProjectSource(from: filesFile, in: &existing)
        } else {
            var s = SportCutSessionManager.shared.createSession(name: filesFile.name)
            SportCutSessionManager.shared.addProjectSource(to: &s, file: filesFile)
            if s.playlistGroups.isEmpty {
                SportCutSessionManager.shared.addPlaylistGroup(to: &s, name: "Основная")
            }
        }

        guard let sessionID = SportCutSessionManager.shared.sessions.first(where: { sess in
            sess.sources.contains { $0.projectID == pid }
        })?.id else { return }

        addMarkupStampsAsNewPlaylistAndOpenWindow(sessionID: sessionID, projectID: pid, pairs: pairs)
    }

    func openSportCutFromSelectedStamps(forceNewSession: Bool = true) {
        let ids = TimelineDataManager.shared.stampsSelectedForSportCut
        guard !ids.isEmpty else { return }
        var pairs: [(TimelineLine, TimelineStamp)] = []
        for line in TimelineDataManager.shared.lines {
            for stamp in line.stamps where ids.contains(stamp.id) {
                pairs.append((line, stamp))
            }
        }
        openSportCutFromTimelineStamps(pairs, forceNewSession: forceNewSession)
    }

    // MARK: - Markup multi-selection → SportCut playlist

    private var activeSportCutPlayerManager: SportCutPlayerManager?
    private var activeSportCutSessionID: UUID?

    func registerActiveSportCut(sessionID: UUID, playerManager: SportCutPlayerManager) {
        activeSportCutSessionID = sessionID
        activeSportCutPlayerManager = playerManager
        HotKeyManager.shared.resumeKeyboardMonitoring()
    }

    func unregisterActiveSportCut(sessionID: UUID) {
        if activeSportCutSessionID == sessionID {
            activeSportCutSessionID = nil
            activeSportCutPlayerManager = nil
        }
    }

    /// Если открыт редактор рисунка SportCut — закрывает его и возвращает `true` (окно закрывать не нужно).
    @discardableResult
    func cancelSportCutDrawingEditorIfActive() -> Bool {
        guard let pm = activeSportCutPlayerManager, pm.isEditorMode else { return false }
        pm.cancelEditor()
        return true
    }

    private func stampStartForMarkupRef(_ ref: MarkupStampRef) -> Double {
        guard let line = TimelineDataManager.shared.lines.first(where: { $0.id == ref.lineID }),
              let st = line.stamps.first(where: { $0.id == ref.stampID }) else { return 0 }
        return st.timeStartSeconds
    }

    /// Все выбранные ⌘-штампы или только кликнутый тег.
    func makeMarkupPlaylistDragPayload(line: TimelineLine, stamp: TimelineStamp) -> MarkupStampsBatchPlaylistDragPayload? {
        guard !currentVideoId.isEmpty else { return nil }
        let bulk = TimelineDataManager.shared.stampsSelectedForSportCut
        var refs: [MarkupStampRef] = []
        if !bulk.isEmpty, bulk.contains(stamp.id) {
            for ln in TimelineDataManager.shared.lines {
                for st in ln.stamps where bulk.contains(st.id) {
                    refs.append(MarkupStampRef(lineID: ln.id, stampID: st.id))
                }
            }
        } else {
            refs = [MarkupStampRef(lineID: line.id, stampID: stamp.id)]
        }
        refs.sort { stampStartForMarkupRef($0) < stampStartForMarkupRef($1) }
        return MarkupStampsBatchPlaylistDragPayload(markupProjectID: currentVideoId, stampRefs: refs)
    }

    func encodeMarkupPlaylistDragData(line: TimelineLine, stamp: TimelineStamp) -> Data? {
        guard let p = makeMarkupPlaylistDragPayload(line: line, stamp: stamp) else { return nil }
        return try? JSONEncoder().encode(p)
    }

    func encodeMarkupPlaylistDragDataForSelectionOnly() -> Data? {
        guard !currentVideoId.isEmpty else { return nil }
        let bulk = TimelineDataManager.shared.stampsSelectedForSportCut
        guard !bulk.isEmpty else { return nil }
        var refs: [MarkupStampRef] = []
        for ln in TimelineDataManager.shared.lines {
            for st in ln.stamps where bulk.contains(st.id) {
                refs.append(MarkupStampRef(lineID: ln.id, stampID: st.id))
            }
        }
        refs.sort { stampStartForMarkupRef($0) < stampStartForMarkupRef($1) }
        let payload = MarkupStampsBatchPlaylistDragPayload(markupProjectID: currentVideoId, stampRefs: refs)
        return try? JSONEncoder().encode(payload)
    }

    func resolveMarkupPlaylistEvents(payload: MarkupStampsBatchPlaylistDragPayload, sessionID: UUID) -> [SportCutEvent]? {
        guard let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == payload.markupProjectID }) else { return nil }
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return nil }
        if !session.sources.contains(where: { $0.projectID == filesFile.id }) {
            SportCutSessionManager.shared.addProjectSource(to: &session, file: filesFile)
        }
        SportCutSessionManager.shared.syncProjectSource(from: filesFile, in: &session)
        guard let refreshed = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }),
              let source = refreshed.sources.first(where: { $0.projectID == filesFile.id }) else { return nil }
        var events: [SportCutEvent] = []
        for ref in payload.stampRefs {
            guard let line = TimelineDataManager.shared.lines.first(where: { $0.id == ref.lineID }),
                  let stamp = line.stamps.first(where: { $0.id == ref.stampID }) else { continue }
            events.append(SportCutEvent.from(stamp: stamp, line: line, source: source))
        }
        return events.isEmpty ? nil : events
    }

    func appendEventsToSportCutPlaylist(events: [SportCutEvent], sessionID: UUID, groupIndex: Int, playlistID: UUID) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        guard groupIndex < session.playlistGroups.count,
              let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var pl = session.playlistGroups[groupIndex].playlists[pi]
        let existing = Set(pl.events.map(\.hiddenKey))
        let added = events.filter { !existing.contains($0.hiddenKey) }
        for ev in added {
            pl.events.append(ev)
        }
        pl.mergeMarkupComments(for: added, session: session)
        session.playlistGroups[groupIndex].playlists[pi] = pl
        SportCutSessionManager.shared.updateSession(session)
        if !added.isEmpty {
            TimelineDataManager.shared.clearSportCutExportSelection()
        }
    }

    func insertMarkupEventsIntoSportCutPlaylist(events: [SportCutEvent], sessionID: UUID, groupIndex: Int, playlistID: UUID, at index: Int) {
        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }
        guard groupIndex < session.playlistGroups.count,
              let pi = session.playlistGroups[groupIndex].playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var playlist = session.playlistGroups[groupIndex].playlists[pi]
        var plEvents = playlist.events
        let existing = Set(plEvents.map(\.hiddenKey))
        let added = events.filter { !existing.contains($0.hiddenKey) }
        var insertAt = min(max(0, index), plEvents.count)
        for ev in added {
            plEvents.insert(ev, at: insertAt)
            insertAt += 1
        }
        playlist.events = plEvents
        playlist.mergeMarkupComments(for: added, session: session)
        session.playlistGroups[groupIndex].playlists[pi] = playlist
        SportCutSessionManager.shared.updateSession(session)
        if !added.isEmpty {
            TimelineDataManager.shared.clearSportCutExportSelection()
        }
    }

    private func sportCutPlaylistGroupIndex(session: SportCutSession, playlistID: UUID) -> Int? {
        for (gi, g) in session.playlistGroups.enumerated() where g.playlists.contains(where: { $0.id == playlistID }) {
            return gi
        }
        return nil
    }

    func appendStampsToSportCutSession(pairs: [(TimelineLine, TimelineStamp)], sessionID: UUID) {
        VideoPlayerManager.shared.player?.pause()
        guard !currentVideoId.isEmpty, !pairs.isEmpty else { return }
        let refs = pairs.map { MarkupStampRef(lineID: $0.0.id, stampID: $0.1.id) }
        let payload = MarkupStampsBatchPlaylistDragPayload(markupProjectID: currentVideoId, stampRefs: refs)
        guard let events = resolveMarkupPlaylistEvents(payload: payload, sessionID: sessionID) else { return }

        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }

        if session.playlistGroups.isEmpty {
            SportCutSessionManager.shared.addPlaylistGroup(to: &session, name: "Основная")
        }
        let groupIndex = 0
        let playlistName = "\(session.playlistGroups[groupIndex].playlists.count + 1)"
        var newPlaylist = SportCutPlaylist(name: playlistName, events: events)
        newPlaylist.mergeMarkupComments(for: events, session: session)
        session.playlistGroups[groupIndex].playlists.append(newPlaylist)
        SportCutSessionManager.shared.updateSession(session)

        if activeSportCutSessionID != sessionID {
            openSportCutSessionFromMarkup(existingSessionID: sessionID)
        }
    }

    func appendMarkupSelectionToSportCutSession(sessionID: UUID) {
        VideoPlayerManager.shared.player?.pause()
        guard let payload = buildMarkupPayloadFromBulkSelection() else { return }
        guard let events = resolveMarkupPlaylistEvents(payload: payload, sessionID: sessionID) else { return }

        guard var session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else { return }

        // Создаём новый плейлист в первой группе
        if session.playlistGroups.isEmpty {
            SportCutSessionManager.shared.addPlaylistGroup(to: &session, name: "Основная")
        }
        let groupIndex = 0
        let playlistName = "\(session.playlistGroups[groupIndex].playlists.count + 1)"
        var newPlaylist = SportCutPlaylist(name: playlistName, events: events)
        newPlaylist.mergeMarkupComments(for: events, session: session)
        session.playlistGroups[groupIndex].playlists.append(newPlaylist)
        SportCutSessionManager.shared.updateSession(session)
        TimelineDataManager.shared.clearSportCutExportSelection()

        // Открыть окно сессии если ещё не открыто
        if activeSportCutSessionID != sessionID {
            openSportCutSessionFromMarkup(existingSessionID: sessionID)
        }
    }

    func appendMarkupSelectionToOpenSportCutPlaylist() {
        VideoPlayerManager.shared.player?.pause()
        guard let payload = buildMarkupPayloadFromBulkSelection() else { return }
        appendMarkupPayloadUsingOpenSportCutWindow(payload)
    }

    func appendSingleMarkupStampToOpenSportCutPlaylist(line: TimelineLine, stamp: TimelineStamp) {
        VideoPlayerManager.shared.player?.pause()
        guard let payload = makeMarkupPlaylistDragPayload(line: line, stamp: stamp) else { return }
        appendMarkupPayloadUsingOpenSportCutWindow(payload)
    }

    private func buildMarkupPayloadFromBulkSelection() -> MarkupStampsBatchPlaylistDragPayload? {
        guard !currentVideoId.isEmpty else { return nil }
        let bulk = TimelineDataManager.shared.stampsSelectedForSportCut
        guard !bulk.isEmpty else { return nil }
        var refs: [MarkupStampRef] = []
        for ln in TimelineDataManager.shared.lines {
            for st in ln.stamps where bulk.contains(st.id) {
                refs.append(MarkupStampRef(lineID: ln.id, stampID: st.id))
            }
        }
        guard !refs.isEmpty else { return nil }
        refs.sort { stampStartForMarkupRef($0) < stampStartForMarkupRef($1) }
        return MarkupStampsBatchPlaylistDragPayload(markupProjectID: currentVideoId, stampRefs: refs)
    }

    private func appendMarkupPayloadUsingOpenSportCutWindow(_ payload: MarkupStampsBatchPlaylistDragPayload) {
        guard let sessionID = activeSportCutSessionID,
              let pm = activeSportCutPlayerManager,
              let session0 = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID }) else {
            var pairs: [(TimelineLine, TimelineStamp)] = []
            for ref in payload.stampRefs {
                guard let ln = TimelineDataManager.shared.lines.first(where: { $0.id == ref.lineID }),
                      let st = ln.stamps.first(where: { $0.id == ref.stampID }) else { continue }
                pairs.append((ln, st))
            }
            pairs.sort { $0.1.timeStartSeconds < $1.1.timeStartSeconds }
            openSportCutFromTimelineStamps(pairs)
            return
        }

        guard let events = resolveMarkupPlaylistEvents(payload: payload, sessionID: sessionID) else { return }

        let targetPlaylistID: UUID
        let targetGroup: Int
        if let pid = pm.currentPlaylistID,
           let gi = sportCutPlaylistGroupIndex(session: session0, playlistID: pid) {
            targetPlaylistID = pid
            targetGroup = gi
        } else if let g0 = session0.playlistGroups.first, !g0.playlists.isEmpty, let lastPl = g0.playlists.last {
            targetGroup = 0
            targetPlaylistID = lastPl.id
        } else {
            var pairs: [(TimelineLine, TimelineStamp)] = []
            for ref in payload.stampRefs {
                guard let ln = TimelineDataManager.shared.lines.first(where: { $0.id == ref.lineID }),
                      let st = ln.stamps.first(where: { $0.id == ref.stampID }) else { continue }
                pairs.append((ln, st))
            }
            pairs.sort { $0.1.timeStartSeconds < $1.1.timeStartSeconds }
            openSportCutFromTimelineStamps(pairs)
            return
        }

        appendEventsToSportCutPlaylist(events: events, sessionID: sessionID, groupIndex: targetGroup, playlistID: targetPlaylistID)
    }
    
    func showMomentViewer(asset: AVAsset, startTime: Double, duration: Double, tagName: String, lineName: String) {
        let controller = MomentViewerWindowController(
            asset: asset,
            startTime: startTime,
            duration: duration,
            tagName: tagName,
            lineName: lineName
        )
        momentViewerControllers.append(controller)
        controller.showWindow(nil)
    }
    
    func unregisterMomentViewer(_ controller: NSWindowController) {
        momentViewerControllers.removeAll { $0 === controller }
    }

}

class ActiveWindowManager {
    static let shared = ActiveWindowManager()
    
    private var allowedWindowControllers: [NSWindowController] = []
    private var currentActiveWindow: NSWindow?
    
    private init() {
        setupObservers()
    }
    
    func registerAllowedWindow(_ windowController: NSWindowController) {
        allowedWindowControllers.append(windowController)
    }
    
    func unregisterAllowedWindow(_ windowController: NSWindowController) {
        allowedWindowControllers.removeAll { $0 === windowController }
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        
    }
    
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        currentActiveWindow = window
    }
    
    @objc private func windowDidResignKey(_ notification: Notification) {
        currentActiveWindow = nil
    }
    
    /// Актуальное окно для клавиатуры: `keyWindow` или родитель sheet (кэш из уведомлений может рассинхронизироваться после смены key, например закрытие «Пересмотра» после live).
    private func resolvedKeyWindowForInput() -> NSWindow? {
        guard let keyWindow = NSApplication.shared.keyWindow else { return nil }
        if keyWindow.isSheet, let parent = keyWindow.sheetParent {
            return parent
        }
        return keyWindow
    }
    
    func isAllowedWindowActive() -> Bool {
        guard let activeWindow = resolvedKeyWindowForInput() ?? currentActiveWindow else { return false }
        
        let isDirectlyAllowed = allowedWindowControllers.contains { windowController in
            windowController.window == activeWindow
        }
        
        if isDirectlyAllowed {
            return true
        }
        if activeWindow.isSheet {
            if let sheetParent = activeWindow.sheetParent {
                return allowedWindowControllers.contains { windowController in
                    windowController.window == sheetParent
                }
            }
        }
        
        return false
    }
    
    func isViewerWindowActive() -> Bool {
        guard let w = resolvedKeyWindowForInput() else { return false }
        return w.windowController === WindowsManager.shared.viewerWindow
    }
    
    /// Проверяет, является ли активное окно окном разметчика (VideoPlayerWindowController, FullControlWindowController или TagLibraryWindowController)
    func isMarkerWindowActive() -> Bool {
        guard let activeWindow = resolvedKeyWindowForInput() else { return false }
        let windowsManager = WindowsManager.shared
        return activeWindow.windowController === windowsManager.videoWindow ||
               activeWindow.windowController === windowsManager.controlWindow ||
               activeWindow.windowController === windowsManager.tagLibraryWindow
    }
}
