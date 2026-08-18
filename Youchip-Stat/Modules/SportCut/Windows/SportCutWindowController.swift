//
//  SportCutWindowController.swift
//  Youchip-Stat
//

import Cocoa
import SwiftUI

/// Custom NSWindow that intercepts close when the drawing editor is active.
private class SportCutWindow: NSWindow {
    override func close() {
        if WindowsManager.shared.cancelSportCutDrawingEditorIfActive() {
            return
        }
        super.close()
    }

    override func performClose(_ sender: Any?) {
        if WindowsManager.shared.cancelSportCutDrawingEditorIfActive() {
            return
        }
        super.performClose(sender)
    }
}

class SportCutWindowController: NSWindowController {
    
    private let session: SportCutSession

    var hostedSessionID: UUID { session.id }
    
    init(session: SportCutSession) {
        self.session = session
        let view = SportCutMainView(sessionID: session.id)
        let hostingController = FirstMouseHostingController(rootView: view)
        let window = SportCutWindow(contentViewController: hostingController)
        
        window.title = String.Titles.sportCutWindowTitlePrefix.format(session.name)
        window.tabbingMode = .disallowed
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
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if WindowsManager.shared.cancelSportCutDrawingEditorIfActive() {
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        WindowsManager.shared.sportCutWindowDidClose()
    }
}
