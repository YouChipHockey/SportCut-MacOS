import SwiftUI
import AppKit
import AVKit
import Foundation

class WindowsManager: NSObject {
    var currentVideoId = ""
    static let shared = WindowsManager()
    
    var videoWindow: VideoPlayerWindowController?
    var controlWindow: FullControlWindowController?
    var tagLibraryWindow: TagLibraryWindowController?
    var analyticsWindow: AnalyticsWindowController?
    var screenshotsWindow: ScreenshotsWindowController?
    var fieldMapConfigurationWindow: FieldMapConfigurationWindowController?

    private var fieldMapWindow: NSWindowController?

    private var editorWindowControllers: [NSWindowController] = []
    private var isClosing = true
    private var isWindowsLocked = false
    
    private var collectionWindowDelegate: CollectionWindowDelegate?
    
    func closeAll() {
        videoWindow?.window?.delegate = nil
        controlWindow?.window?.delegate = nil
        tagLibraryWindow?.window?.delegate = nil
        analyticsWindow?.window?.delegate = nil
        screenshotsWindow?.window?.delegate = nil
        fieldMapConfigurationWindow = nil
        
        fieldMapConfigurationWindow?.close()
        videoWindow?.close()
        controlWindow?.close()
        tagLibraryWindow?.close()
        analyticsWindow?.close()
        screenshotsWindow?.close()
        
        VideoPlayerManager.shared.deleteVideo()
        isClosing = true
    }
    
    func showFieldMapVisualizationPicker() {
        let controller = FieldMapVisualizationWindowController()
        controller.showWindow(nil)
    }
    
    func showFieldMapVisualization(collection: CollectionBookmark, mode: VisualizationMode, stamps: [TimelineStamp]) {
        let view = FieldMapVisualizationView(collection: collection, mode: mode, stamps: stamps)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = "Визуализация карты поля"
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
        if mode == .tagBased {
            print("Tag-based markup mode activated. Each tag will have its own timeline.")
        } else {
            print("Standard markup mode activated. Full timeline editing enabled.")
        }
    }
    
    func openCustomCollectionsWindow(withExistingCollection existingCollection: CollectionBookmark? = nil) {
        let view: AnyView
        
        if let existingCollection = existingCollection {
            view = AnyView(CreateCustomCollectionsView(existingCollection: existingCollection))
        } else {
            view = AnyView(CreateCustomCollectionsView())
        }
        
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = existingCollection != nil ?
        "Редактирование коллекции: \(existingCollection?.name ?? "")" :
        "Создание новой коллекции"
        
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
        guard let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == id }) else { return }
        guard let file = filesFile.url, isClosing else { return }
        
        UserDefaults.standard.set("", forKey: "editingStampLineID")
        UserDefaults.standard.set("", forKey: "editingStampID")
        isClosing = false
        
        TimelineDataManager.shared.currentBookmark = filesFile.videoData.bookmark
        
        if MarkupMode.current == .standard {
            TimelineDataManager.shared.lines = filesFile.videoData.timelines
            TimelineDataManager.shared.selectedLineID = filesFile.videoData.timelines.first?.id
        } else {
            TimelineDataManager.shared.lines = filesFile.videoData.timelines
            TimelineDataManager.shared.selectedLineID = nil
        }
        
        VideoPlayerManager.shared.loadVideo(from: file)
        
        videoWindow = VideoPlayerWindowController(id: id)
        controlWindow = FullControlWindowController()
        tagLibraryWindow = TagLibraryWindowController()
        
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let bottomHeight = screenFrame.height / 3
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

}
