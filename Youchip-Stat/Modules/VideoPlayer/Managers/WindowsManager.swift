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
    
    func openVideo(filesFile: FilesFile) {
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
