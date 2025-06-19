//
//  FieldMapConfigurationWindowController.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/9/25.
//

import Cocoa
import SwiftUI

class FieldMapConfigurationWindowController: NSWindowController, NSWindowDelegate {
    
    private var windowContent: NSHostingController<AnyView>?
    
    init() {
        super.init(window: NSWindow())
        
        let content = FieldMapConfigurationView()
        let hosting = NSHostingController(rootView: AnyView(content))
        self.window = NSWindow(contentViewController: hosting)
        self.windowContent = hosting
        self.window?.title = "Настройка визуализации карты поля"
        self.window?.styleMask = [.titled, .closable, .miniaturizable]
        self.window?.center()
        self.window?.delegate = self
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        
        if let window = self.window, let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            window.setFrame(screenFrame, display: true)
        }
    }
    
    func windowWillClose(_ notification: Notification) { }
    
}
