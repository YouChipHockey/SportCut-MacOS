//
//  ExportSelectionWindowController.swift
//  Youchip-Stat
//
//  Шаги выбора для экспорта из разметки (по тегам / по лейблам / по событиям и их под-выборы)
//  открываются ОТДЕЛЬНЫМ окном, а не листом (`.sheet`). Раньше в низком окне таймлайнов лист
//  «поднимал» окно-хозяина и вылезал за края; окном шаг удобнее двигать, и вся цепочка экспорта
//  (выбор тега → выбор лейблов → режим экспорта) идёт единообразно окнами.
//
//  Контроллер универсальный: держит произвольный SwiftUI-контент (конкретный шаг выбора строит
//  `WindowsManager`). Одно окно шагов на сессию — переход к следующему шагу заменяет содержимое
//  через `WindowsManager` (см. `openExportSelectionWindow`).
//

import SwiftUI
import AppKit

/// Окно одного шага выбора для экспорта. Закрытие крестиком единожды зовёт `onClosed` — по нему
/// `WindowsManager` чистит ссылку, а вызывающий сбрасывает свой флаг-триггер. При программной
/// замене окна следующим шагом delegate обнуляется, поэтому `onClosed` НЕ срабатывает (переход —
/// не «отмена пользователем»).
final class ExportSelectionWindowController: NSWindowController, NSWindowDelegate {

    /// Вызывается РОВНО один раз при закрытии окна пользователем (крестик).
    var onClosed: (() -> Void)?
    private var didHandleClose = false

    init<Content: View>(title: String,
                        width: CGFloat,
                        height: CGFloat,
                        @ViewBuilder content: () -> Content) {
        // Как окно выбора режима экспорта: размер задаёт сам контент (фиксированный `.frame` в
        // `openExportSelectionWindow`), окно подгоняется под него. Без этого `List` без «родной»
        // высоты схлопывал окно в крошечное.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = FirstMouseHostingController(rootView: AnyView(content()))
        window.title = title
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        guard !didHandleClose else { return }
        didHandleClose = true
        onClosed?()
    }
}
