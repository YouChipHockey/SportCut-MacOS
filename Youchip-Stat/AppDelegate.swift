//
//  AppDelegate.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Cocoa
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    /// Открывает единый экран настроек. Вызывается пунктом главного меню «Настройки…» (⌘,)
    /// и кнопкой-шестерёнкой в верхней панели.
    @objc func openSettings() {
        WindowsManager.shared.openSettingsWindow()
    }
    
    /// Идёт live-запись — выходим только после того, как она сохранена как проект.
    private var liveSaveWindow: NSWindow?
    private var didReplyToTerminate = false
    /// Страховка: если склейка зависнет, приложение всё равно закроется. Резервная копия сессии
    /// останется на диске, и её предложат восстановить при следующем запуске.
    private let liveSaveTimeout: TimeInterval = 300

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        closeAllSheetsAndModals()

        guard WindowsManager.shared.isLiveSession else { return .terminateNow }

        // Live-сессию не бросаем на восстановление: сохраняем так же, как при закрытии окон
        // разметки — остановка записи, склейка сегментов, импорт проекта с разметкой.
        didReplyToTerminate = false
        showLiveSaveProgressWindow()

        DispatchQueue.main.asyncAfter(deadline: .now() + liveSaveTimeout) { [weak self] in
            self?.replyToTerminate()
        }
        WindowsManager.shared.finalizeLiveSessionForQuit { [weak self] in
            self?.replyToTerminate()
        }
        return .terminateLater
    }

    private func replyToTerminate() {
        guard !didReplyToTerminate else { return }
        didReplyToTerminate = true
        liveSaveWindow?.orderOut(nil)
        liveSaveWindow = nil
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }

    private func showLiveSaveProgressWindow() {
        let content = VStack(spacing: 14) {
            ProgressView()
            Text(^String.Titles.liveQuitSaving)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(width: 340)

        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.styleMask = [.titled, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        liveSaveWindow = window
    }
    
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
