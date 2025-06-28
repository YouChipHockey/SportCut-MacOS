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
    init() {
        let view = TagLibraryView()
        let hostingController = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hostingController)
        w.title = ^String.Titles.tagLibrary
        super.init(window: w)
        w.styleMask.insert(.closable)
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func windowWillClose(_ notification: Notification) {
        WindowsManager.shared.closeAll()
    }
}
