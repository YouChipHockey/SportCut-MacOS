//
//  ViewerWindowController.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import Cocoa
import SwiftUI

class ViewerWindowController: NSWindowController {
    
    private let videoID: String
    
    init(videoID: String) {
        self.videoID = videoID
        let view = ViewerView(videoID: videoID)
        let hostingController = FirstMouseHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = ^String.Titles.view
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = NSSize(width: screenFrame.width, height: screenFrame.height)
            window.setContentSize(windowSize)
            window.center()
        } else {
            window.setContentSize(NSSize(width: 1200, height: 800))
            window.center()
        }
        
        super.init(window: window)
        window.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension ViewerWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .stopViewerPlayer, object: nil)
        NotificationCenter.default.post(name: .closeViewerWindow, object: nil)
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        
    }
    
    func windowDidResignKey(_ notification: Notification) {
        
    }
}
