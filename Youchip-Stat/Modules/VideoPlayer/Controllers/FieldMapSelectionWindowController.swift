//
//  FieldMapSelectionWindowController.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

class FieldMapSelectionWindowController: NSWindowController, NSWindowDelegate {
    
    init(tag: Tag, imageBookmark: Data, onSave: @escaping (CGPoint) -> Void) {
        let view = FieldMapSelectionView(tag: tag, imageBookmark: imageBookmark, onSave: onSave)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "\(^String.Titles.selectMapPositionForTag) \(tag.name)"
        super.init(window: window)
        window.styleMask = [.titled, .closable, .resizable]
        window.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowsManager.shared.fieldMapWindowDidClose()
    }
    
}
