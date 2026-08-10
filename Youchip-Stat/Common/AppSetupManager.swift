//
//  AppSetupManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Foundation
import AppKit
import Firebase
import FirebaseCore
import FirebaseInstallations

/// Режим внешнего вида приложения: как в системе / светлая / тёмная.
enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

class AppSetupManager {

    static let appearanceKey = "appAppearanceMode"

    class func setup() {
        LanguageManager.shared.setupAtLaunch()
        TimelineMigrationManager.shared.migrateIfNeeded()
        DataSyncManager.shared.synchronizeOnAppLaunch()
        FirebaseApp.configure()
        setupMenu()
        setupBaseAppearence()
    }

    class func setAppearance(name: NSAppearance.Name) {
        NSApp.appearance = NSAppearance(named: name)
    }

    /// Текущий выбранный режим (по умолчанию тёмный — как было раньше).
    class func currentAppearanceMode() -> AppAppearanceMode {
        AppAppearanceMode(rawValue: UserDefaults.standard.string(forKey: appearanceKey) ?? "") ?? .dark
    }

    /// Сохраняет и применяет режим внешнего вида ко всем окнам приложения.
    class func applyAppearanceMode(_ mode: AppAppearanceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: appearanceKey)
        NSApp.appearance = mode.appearance
    }
    
    private class func setupMenu() {
        let application = NSApplication.shared
        application.menu = NSMenu()
        
        let mainMenu = NSMenuItem(title: ^String.Titles.rootYouChipTitle, action: nil, keyEquivalent: "")
        application.menu?.addItem(mainMenu)
        application.menu?.setSubmenu(NSMenu(), for: mainMenu)

        // «Настройки…» (⌘,) — открывает единый экран настроек. Цель — nil, чтобы событие
        // прошло по responder chain до AppDelegate (он может быть ещё не назначен на момент сборки меню).
        let settingsItem = NSMenuItem(title: ^String.Titles.settingsMenuItem,
                                      action: #selector(AppDelegate.openSettings),
                                      keyEquivalent: ",")
        settingsItem.target = nil
        mainMenu.submenu?.addItem(settingsItem)

        mainMenu.submenu?.addItem(.separator())

        let quitItem = NSMenuItem(title: ^String.Titles.macQuitAppTitle, action: nil, keyEquivalent: "q")
        quitItem.target = application
        quitItem.action = #selector(application.terminate)
        mainMenu.submenu?.addItem(quitItem)
    }
    
    private class func setupBaseAppearence() {
        NSApp.appearance = currentAppearanceMode().appearance
    }
    
}
