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
        
        let screenshotsLine = TimelineLine(id: screenshotsID, name: "Рисунки", stamps: [], tagIdForMode: "")
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

    private var fieldMapWindow: NSWindowController?

    private var editorWindowControllers: [NSWindowController] = []
    private var isClosing = true
    private var isWindowsLocked = false
    
    /// Tracks whether the current session is a live stream
    private(set) var isLiveSession: Bool = false
    private var liveVideoId: String?
    private var liveFileName: String?
    
    private var collectionWindowDelegate: CollectionWindowDelegate?
    
    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .closeViewerWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.viewerWindow = nil
        }
    }
    
    func closeAll() {
        videoWindow?.window?.delegate = nil
        controlWindow?.window?.delegate = nil
        tagLibraryWindow?.window?.delegate = nil
        analyticsWindow?.window?.delegate = nil
        screenshotsWindow?.window?.delegate = nil
        fieldMapConfigurationWindow = nil
        
        NotificationCenter.default.post(name: .stopViewerPlayer, object: nil)
        viewerWindow?.close()
        viewerWindow = nil
        
        fieldMapConfigurationWindow?.close()
        videoWindow?.close()
        controlWindow?.close()
        tagLibraryWindow?.close()
        analyticsWindow?.close()
        screenshotsWindow?.close()
        
        ScreenshotsMetadataManager.shared.clearScreenshots()
        
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
        
        guard isClosing else { return }
        
        UserDefaults.standard.set("", forKey: "editingStampLineID")
        UserDefaults.standard.set("", forKey: "editingStampID")
        isClosing = false
        
        // Initialize empty timelines for the live session
        TimelineDataManager.shared.currentBookmark = nil
        TimelineDataManager.shared.lines = []
        TimelineDataManager.shared.selectedLineID = nil
        
        ensureScreenshotsTimelineExists()
        
        // Create screenshots folder for this live session
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let screenshotsDir = documentsDir.appendingPathComponent("Screenshots").appendingPathComponent(videoId)
        if !fileManager.fileExists(atPath: screenshotsDir.path) {
            try? fileManager.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)
        }
        ScreenshotsMetadataManager.shared.loadScreenshots(from: screenshotsDir)
        
        // Start live mode in VideoPlayerManager (no AVPlayer - uses preview layer)
        VideoPlayerManager.shared.startLiveMode()
        
        // Start the actual capture and recording
        LiveStreamManager.shared.startLiveStream(videoId: videoId)
        
        // Create windows
        videoWindow = VideoPlayerWindowController(id: videoId)
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
    
    /// Finalize the live recording: stop capture, write final file, import as static video.
    private func finalizeLiveSession() {
        let videoId = liveVideoId ?? ""
        let fileName = liveFileName ?? "Live_\(Date().timeIntervalSince1970)"
        let timelines = TimelineDataManager.shared.lines
        
        VideoPlayerManager.shared.endLiveMode()
        
        LiveStreamManager.shared.stopAndFinalize { [weak self] fileURL in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let url = fileURL {
                    // Import the recorded video as a regular static video
                    if let filesFile = VideoFilesManager.shared.importFile(url: url, newName: fileName) {
                        // Restore timelines from the live session
                        VideoFilesManager.shared.updateTimelines(
                            for: filesFile.videoData.bookmark,
                            with: timelines
                        )
                        // Перенос скриншотов из папки live-сессии в папку импортированного видео (у импорта новый id — иначе иконки и картинки «пропадают»)
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
        
        TimelineDataManager.shared.currentBookmark = filesFile.videoData.bookmark
        
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
    
    func showReportWindow(htmlString: String, teamName: String, opponentName: String) {
        let view = WebViewWrapper(htmlString: htmlString)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = "ИИ Отчет: \(teamName) vs \(opponentName)"
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
        viewerWindow = nil
        viewerWindow?.close()
        
        viewerWindow = ViewerWindowController(videoID: currentVideoId)
        viewerWindow?.showWindow(nil)
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
    
    func isAllowedWindowActive() -> Bool {
        guard let activeWindow = currentActiveWindow else { return false }
        
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
        return currentActiveWindow?.windowController == WindowsManager.shared.viewerWindow
    }
}
