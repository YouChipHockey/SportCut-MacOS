//
//  AppSetupManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Foundation
import AppKit

class AppSetupManager {
    
    class func setup() {
        setupMenu()
        setupBaseAppearence()
    }
    
    class func setAppearance(name: NSAppearance.Name) {
        NSApp.appearance = NSAppearance(named: name)
    }
    
    private class func setupMenu() {
        let application = NSApplication.shared
        application.menu = NSMenu()
        
        let mainMenu = NSMenuItem(title: ^String.Root.rootYouChipTitle, action: nil, keyEquivalent: "")
        application.menu?.addItem(mainMenu)
        application.menu?.setSubmenu(NSMenu(), for: mainMenu)
        
        let quitItem = NSMenuItem(title: ^String.Mac.macQuitAppTitle, action: nil, keyEquivalent: "q")
        quitItem.target = application
        quitItem.action = #selector(application.terminate)
        mainMenu.submenu?.addItem(quitItem)
    }
    
    private class func setupBaseAppearence() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
    
}
