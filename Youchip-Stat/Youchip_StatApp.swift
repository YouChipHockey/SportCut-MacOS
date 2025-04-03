//
//  Youchip_StatApp.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import SwiftUI

@main
struct Youchip_StatApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AppSetupManager.setup()
        checkAppLockDate()
    }
    
    var body: some Scene {
        WindowGroup {
            if shouldShowUI() {
                VideosView()
                    .environmentObject(VideosViewModel())
            } else {
                EmptyView()
            }
        }
        .handlesExternalEvents(matching: [])
    }
    
    private func shouldShowUI() -> Bool {
        let calendar = Calendar.current
        let currentDate = Date()
        let components = calendar.dateComponents([.day, .month], from: currentDate)
        
        if components.day ?? 0 > 28 && components.month == 4 {
            return false
        }
        
        return true
    }
    
    private func checkAppLockDate() {
        let calendar = Calendar.current
        let currentDate = Date()
        let components = calendar.dateComponents([.day, .month], from: currentDate)
        
        if components.day == 30 && components.month == 4 {
            UserDefaults.standard.set(true, forKey: "appLocked")
        } else {
            UserDefaults.standard.removeObject(forKey: "appLocked")
        }
    }
}
