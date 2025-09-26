//
//  ViewerWindowController.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import Cocoa
import SwiftUI

class ViewerWindowController: NSWindowController {
    
    private let videoID: String
    
    init(videoID: String) {
        self.videoID = videoID
        let view = ViewerView(videoID: videoID)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        
        window.title = "Просмотр"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        
        // Устанавливаем размер окна как у основных окон
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = NSSize(width: screenFrame.width, height: screenFrame.height)
            window.setContentSize(windowSize)
            window.center()
        } else {
            window.setContentSize(NSSize(width: 1200, height: 800))
            window.center()
        }
        
        super.init(window: window)
        
        // Настраиваем делегат окна
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

// MARK: - NSWindowDelegate
extension ViewerWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Очистка ресурсов при закрытии окна
        // Отправляем уведомление для остановки плеера
        NotificationCenter.default.post(name: .stopViewerPlayer, object: nil)
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Окно стало активным
        print("Viewer window became key")
    }
    
    func windowDidResignKey(_ notification: Notification) {
        // Окно потеряло фокус
        print("Viewer window resigned key")
    }
}
