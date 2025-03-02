//
//  AppDelegate.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Cocoa
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        closeAllSheetsAndModals()
        return .terminateNow
    }
    
//    func application(_ application: NSApplication, open urls: [URL]) {
//        guard let url = urls.first else { return }
//        FileOpenHelper.shared.openFileOnAppear(url)
//    }
    
//    func applicationDidBecomeActive(_ notification: Notification) {
//        AppNavigator.shared.fixRootViewAppear()
//    }
    
    private func closeAllSheetsAndModals() {
        for window in NSApplication.shared.windows {
            if window.isSheet {
                window.sheetParent?.endSheet(window)
            }
            if window.isModalPanel {
                window.performClose(nil)
            }
        }
    }

}
