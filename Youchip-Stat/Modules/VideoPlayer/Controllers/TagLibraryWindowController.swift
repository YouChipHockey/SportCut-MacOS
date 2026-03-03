//
//  TagLibraryWindowController.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

class TagLibraryWindowController: NSWindowController, NSWindowDelegate {
    private let notificationSubscriptions = ProjectNotificationSubscriptions()
    
    init() {
        let view = TagLibraryView()
            .environmentObject(notificationSubscriptions)
        let hostingController = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hostingController)
        w.title = ^String.Titles.tagLibrary
        super.init(window: w)
        w.styleMask.insert(NSWindow.StyleMask.closable)
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
        ActiveWindowManager.shared.registerAllowedWindow(self)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func windowWillClose(_ notification: Notification) {
        ActiveWindowManager.shared.unregisterAllowedWindow(self)
        WindowsManager.shared.closeAll()
    }
    
    func cancelNotificationSubscriptions() {
        notificationSubscriptions.cancelAll()
    }
}
