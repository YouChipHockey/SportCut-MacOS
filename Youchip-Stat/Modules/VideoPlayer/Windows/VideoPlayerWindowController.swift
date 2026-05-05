//
//  VideoPlayerWindowController.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

class VideoPlayerWindowController: NSWindowController, NSWindowDelegate {
    
    init(id: String) {
        let view = VideoPlayerWindow(id: id)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = ^String.Titles.video
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
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if VideoPlayerManager.shared.isVideoPlayerInEditorMode {
            NotificationCenter.default.post(name: .editorModeChanged, object: false)
            return false
        }
        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        VideoPlayerManager.shared.isVideoPlayerInEditorMode = false
        ActiveWindowManager.shared.unregisterAllowedWindow(self)
        WindowsManager.shared.closeAll()
    }
    
}
