//
//  FullControlWindowController.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

class FullControlWindowController: NSWindowController, NSWindowDelegate {
    
    init() {
        let view = FullControlView()
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = ^String.Titles.timelines
        super.init(window: window)
        window.tabbingMode = .disallowed
        window.styleMask.insert(.closable)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        ActiveWindowManager.shared.registerAllowedWindow(self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowWillClose(_ notification: Notification) {
        ActiveWindowManager.shared.unregisterAllowedWindow(self)
        WindowsManager.shared.closeAll()
    }
    
}
