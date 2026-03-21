//
//  SportCutWindowController.swift
//  Youchip-Stat
//

import Cocoa
import SwiftUI

class SportCutWindowController: NSWindowController {
    
    private let session: SportCutSession
    
    init(session: SportCutSession) {
        self.session = session
        let view = SportCutMainView(sessionID: session.id)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = "Просмотр: \(session.name)"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            window.setContentSize(NSSize(width: screenFrame.width, height: screenFrame.height))
            window.center()
        } else {
            window.setContentSize(NSSize(width: 1400, height: 900))
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

extension SportCutWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        WindowsManager.shared.sportCutWindowDidClose()
    }
}
