//
//  TelestrationModeWindowController.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 3/20/26.
//

import SwiftUI
import AVKit
import Cocoa

class TelestrationModeWindowController: NSWindowController, NSWindowDelegate {
    
    private var telestrationViewModel: TelestrationModeViewModel?
    private var exporter = TelestrationExporter()
    
    init(videoURL: URL, clipStartTime: Double, clipEndTime: Double, stampLabel: String) {
        let viewModel = TelestrationModeViewModel(
            videoURL: videoURL,
            clipStartTime: clipStartTime,
            clipEndTime: clipEndTime,
            frameRate: Double(VideoPlayerManager.shared.getCurrentFrameRate())
        )
        
        let telestrationView = TelestrationModeView(
            viewModel: viewModel,
            onClose: { [weak viewModel] in
                viewModel?.stop()
                NSApp.keyWindow?.close()
            },
            onExport: { [weak viewModel] in
                guard let viewModel = viewModel else { return }
                let exporter = TelestrationExporter()
                
                viewModel.runTracking {
                    exporter.exportAnnotatedClip(viewModel: viewModel) { result in
                        switch result {
                        case .success(let url):
                            exporter.showSaveDialog(for: url)
                        case .failure(let error):
                            DispatchQueue.main.async {
                                let alert = NSAlert()
                                alert.messageText = "Export Error"
                                alert.informativeText = error.localizedDescription
                                alert.alertStyle = .warning
                                alert.runModal()
                            }
                        }
                    }
                }
            }
        )
        
        let hostingController = NSHostingController(rootView: telestrationView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Telestration — \(stampLabel)"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        
        super.init(window: window)
        
        self.telestrationViewModel = viewModel
        window.delegate = self
        
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = NSSize(width: screenFrame.width * 0.8, height: screenFrame.height * 0.8)
            window.setContentSize(windowSize)
            window.center()
        } else {
            window.setContentSize(NSSize(width: 1200, height: 800))
            window.center()
        }
        
        window.makeKeyAndOrderFront(nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowWillClose(_ notification: Notification) {
        telestrationViewModel?.stop()
        telestrationViewModel = nil
    }
}
