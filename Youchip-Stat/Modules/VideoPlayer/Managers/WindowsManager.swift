import SwiftUI
import AppKit
import AVKit
import Foundation

extension NSNotification.Name {
    static let collectionDataChanged = NSNotification.Name("collectionDataChanged")
    static let collectionEditorOpened = NSNotification.Name("collectionEditorOpened") // Add new notification
    static let collectionEditorClosed = NSNotification.Name("collectionEditorClosed") // Add new notification
}

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
    
    @available(macOS 12.0, *)
    func showAnalytics() {
        analyticsWindow = AnalyticsWindowController()
    }
    
    func openCustomCollectionsWindow(withExistingCollection existingCollection: CollectionBookmark? = nil) {
        // Create the appropriate view based on whether we're editing or creating a new collection
        let view: AnyView
        
        if let existingCollection = existingCollection {
            // For editing an existing collection
            view = AnyView(CreateCustomCollectionsView(existingCollection: existingCollection))
        } else {
            // For creating a new collection
            view = AnyView(CreateCustomCollectionsView())
        }
        
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        
        // Set the appropriate title based on the mode
        window.title = existingCollection != nil ?
            "Редактирование коллекции: \(existingCollection?.name ?? "")" :
            "Создание новой коллекции"
        
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        
        // Получаем размер главного экрана
        if let screen = NSScreen.main {
            // Получаем размер экрана с учетом панели задач и т.д.
            let screenFrame = screen.visibleFrame
            
            // Устанавливаем размер окна равным размеру экрана
            window.setFrame(screenFrame, display: true)
        } else {
            // Если не удалось получить размер экрана, используем резервные значения
            window.center()
            window.setContentSize(NSSize(width: 850, height: 600))
        }
        
        // Add notification observer to refresh collections after window closes
        NotificationCenter.default.addObserver(forName: .collectionDataChanged, object: nil, queue: .main) { _ in
            // Refresh the global pools in TagLibraryManager
            TagLibraryManager.shared.refreshGlobalPools()
        }
        
        // Create and store a strong reference to the delegate
        self.collectionWindowDelegate = CollectionWindowDelegate()
        window.delegate = self.collectionWindowDelegate
        
        // Notify that the collection editor is open
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
        TimelineDataManager.shared.lines = filesFile.videoData.timelines
        TimelineDataManager.shared.selectedLineID = filesFile.videoData.timelines.first?.id
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

class CollectionWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        print("Collection editor window closing")
        NotificationCenter.default.post(name: .collectionEditorClosed, object: nil)
    }
}
