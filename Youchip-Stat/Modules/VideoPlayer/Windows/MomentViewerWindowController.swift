//
//  MomentViewerWindowController.swift
//  Youchip-Stat
//

import Cocoa
import SwiftUI
import AVFoundation

class MomentViewerWindowController: NSWindowController {
    
    init(asset: AVAsset, startTime: Double, duration: Double, tagName: String, lineName: String) {
        let view = MomentViewerView(
            asset: asset,
            startTime: startTime,
            duration: duration,
            tagName: tagName,
            lineName: lineName
        )
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = "Момент: \(tagName)"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = NSSize(width: min(screenFrame.width * 0.6, 960),
                                    height: min(screenFrame.height * 0.6, 540))
            window.setContentSize(windowSize)
            window.center()
        } else {
            window.setContentSize(NSSize(width: 960, height: 540))
            window.center()
        }
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}
