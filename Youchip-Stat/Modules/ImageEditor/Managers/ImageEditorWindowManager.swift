//
//  ImageEditorWindowManager.swift
//  Youchip-Stat
//
//  Открывает редактор картинок проекта в отдельном окне (не в главном).
//

import AppKit
import SwiftUI

final class ImageEditorWindowManager {
    static let shared = ImageEditorWindowManager()

    /// Удерживаем открытые окна, чтобы их не освобождало ARC.
    private var windows: [UUID: NSWindow] = [:]

    private init() {}

    func openProject(_ projectId: UUID, onClose: (() -> Void)? = nil) {
        // Если окно этого проекта уже открыто — просто выводим на передний план.
        if let existing = windows[projectId] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let editor = ImageEditorCanvasView(projectId: projectId, onClose: { [weak self] in
            self?.closeProject(projectId)
            onClose?()
        })

        let hosting = FirstMouseHostingController(rootView: editor)
        let window = NSWindow(contentViewController: hosting)
        window.title = ImageEditorProjectsManager.shared.meta(for: projectId)?.name ?? (^String.Titles.mainTabEditor)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        // Закрытие окна крестиком — убрать из словаря и обновить список.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.windows[projectId] = nil
            ImageEditorProjectsManager.shared.reload()
            onClose?()
        }

        windows[projectId] = window
    }

    private func closeProject(_ projectId: UUID) {
        guard let window = windows[projectId] else { return }
        windows[projectId] = nil
        window.close()
    }
}
