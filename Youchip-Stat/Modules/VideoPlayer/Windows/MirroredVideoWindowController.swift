//
//  MirroredVideoWindowController.swift
//  Youchip-Stat
//

import SwiftUI
import AppKit
import AVFoundation

final class MirroredVideoWindowController: NSWindowController, NSWindowDelegate {
    
    enum Mode {
        case markup
        case viewer(VideoPlaylistManager)
        case sportCut(SportCutPlayerManager)
    }
    
    private let mode: Mode
    
    init(mode: Mode) {
        self.mode = mode
        
        let rootView: AnyView
        switch mode {
        case .markup:
            rootView = AnyView(MirrorMarkupVideoContentView())
        case .viewer(let pm):
            rootView = AnyView(MirrorViewerVideoContentView(playlistManager: pm))
        case .sportCut(let playerManager):
            rootView = AnyView(MirrorSportCutVideoContentView(playerManager: playerManager))
        }
        
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = ^String.Titles.videoMirrorWindowTitle
        window.tabbingMode = .disallowed
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 720, height: 405))
        
        super.init(window: window)
        window.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowsManager.shared.mirroredVideoWindowDidClose(mode: mode)
    }
}
