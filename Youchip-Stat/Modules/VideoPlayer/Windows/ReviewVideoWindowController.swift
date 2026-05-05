//
//  ReviewVideoWindowController.swift
//  Youchip-Stat
//

import Cocoa
import SwiftUI

class ReviewVideoWindowController: NSWindowController, NSWindowDelegate {
    
    init() {
        let view = ReviewVideoView()
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Пересмотр"
        window.tabbingMode = .disallowed
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
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
    
    func windowWillClose(_ notification: Notification) {
        // When user manually closes review window, exit review mode.
        if VideoPlayerManager.shared.isReviewMode {
            VideoPlayerManager.shared.exitReviewMode()
            WindowsManager.shared.reviewWindowDidCloseByUser()
        }
    }
}
