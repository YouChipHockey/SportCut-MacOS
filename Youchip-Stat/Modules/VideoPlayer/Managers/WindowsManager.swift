import SwiftUI
import AppKit
import AVKit
import Foundation

class WindowsManager {
    static let shared = WindowsManager()
    
    var videoWindow: VideoPlayerWindowController?
    var controlWindow: FullControlWindowController?
    var tagLibraryWindow: TagLibraryWindowController?
    var analyticsWindow: AnalyticsWindowController?
    private var isClosing = true
    
    // Add a property to store the collection window delegate
    private var collectionWindowDelegate: CollectionWindowDelegate?
    
    func closeAll() {
        videoWindow?.window?.delegate = nil
        controlWindow?.window?.delegate = nil
        tagLibraryWindow?.window?.delegate = nil
        analyticsWindow?.window?.delegate = nil
        
        videoWindow?.close()
        controlWindow?.close()
        tagLibraryWindow?.close()
        analyticsWindow?.close()
        
        VideoPlayerManager.shared.deleteVideo()
        isClosing = true
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
    
    func openVideo(id: String) {
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
            
            videoWindow = VideoPlayerWindowController()
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
}
