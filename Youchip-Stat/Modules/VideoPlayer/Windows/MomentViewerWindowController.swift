//
//  MomentViewerWindowController.swift
//  Youchip-Stat
//

import Cocoa
import SwiftUI
import AVFoundation

class MomentViewerWindowController: NSWindowController, NSWindowDelegate {
    
    private let session: MomentViewerSession
    
    init(asset: AVAsset, startTime: Double, duration: Double, tagName: String, lineName: String, lineID: UUID? = nil, stampID: UUID? = nil, allowsRefresh: Bool = false, assetProvider: ((@escaping (AVAsset?) -> Void) -> Void)? = nil) {
        let assetSeconds = CMTimeGetSeconds(asset.duration)
        let session = MomentViewerSession(
            asset: asset,
            startTime: startTime,
            duration: duration,
            sourceAssetDuration: assetSeconds.isFinite ? assetSeconds : (startTime + duration + 1),
            tagName: tagName,
            lineName: lineName,
            lineID: lineID,
            stampID: stampID,
            allowsRefresh: allowsRefresh,
            assetProvider: assetProvider
        )
        self.session = session
        
        let view = MomentViewerView(session: session)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = String.Titles.momentWindowTitlePrefix.format(tagName)
        window.tabbingMode = .disallowed
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
        window.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
    
    /// Stops audio and releases the player (e.g. when closing the whole markup session).
    func stopPlaybackForClose() {
        session.invalidate()
    }
    
    func windowWillClose(_ notification: Notification) {
        session.invalidate()
        WindowsManager.shared.unregisterMomentViewer(self)
    }
}
