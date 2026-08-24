//
//  ExportModeWindowController.swift
//  Youchip-Stat
//
//  Экспорт из разметки открывается ОТДЕЛЬНЫМ окном, а не листом (`.sheet`): в низком окне
//  таймлайнов лист «поднимал» окно и вылезал за края, плюс отдельным окном его удобнее двигать.
//  Переиспользует тот же `ExportModeSelectionSheet` (в режиме листа его показывает OrganizerView).
//

import SwiftUI
import AppKit

/// SwiftUI-обёртка: держит СВОЁ состояние тумблеров (посеянное текущими значениями разметки) и
/// отдаёт итог наружу. Позиция/масштаб экспорта берутся из тумблеров на момент нажатия «Фильм»/
/// «Плейлист».
struct ExportModeWindowView: View {

    @State private var withDrawings: Bool
    @State private var watermark: ExportWatermarkOptions
    private let onSelect: (ExportMode, Bool, ExportWatermarkOptions) -> Void
    private let onClose: () -> Void

    init(withDrawings: Bool,
         watermark: ExportWatermarkOptions,
         onSelect: @escaping (ExportMode, Bool, ExportWatermarkOptions) -> Void,
         onClose: @escaping () -> Void) {
        _withDrawings = State(initialValue: withDrawings)
        _watermark = State(initialValue: watermark)
        self.onSelect = onSelect
        self.onClose = onClose
    }

    var body: some View {
        ExportModeSelectionSheet(
            onSelect: { mode in onSelect(mode, withDrawings, watermark) },
            exportWithDrawings: $withDrawings,
            watermarkOptions: $watermark,
            onClose: onClose
        )
    }
}

/// Окно выбора режима экспорта разметки. Закрытие (кнопкой, крестиком или после выбора) единожды
/// зовёт `onClosed` — по нему `WindowsManager` чистит ссылку и сбрасывает флаг у `FullControlView`.
final class ExportModeWindowController: NSWindowController, NSWindowDelegate {

    /// Вызывается РОВНО один раз при закрытии окна любым способом.
    var onClosed: (() -> Void)?
    private var didHandleClose = false

    init(withDrawings: Bool,
         watermark: ExportWatermarkOptions,
         onSelect: @escaping (ExportMode, Bool, ExportWatermarkOptions) -> Void) {
        // Окно создаём первым и захватываем в колбэк ЕГО (а не self): захват self до `super.init`
        // запрещён. Закрытие идёт через `window.close()` → `windowWillClose` → `onClosed`.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let view = ExportModeWindowView(
            withDrawings: withDrawings,
            watermark: watermark,
            onSelect: onSelect,
            // Кнопки «Фильм»/«Плейлист»/«Отмена» закрывают именно это окно.
            onClose: { [weak window] in window?.close() }
        )
        window.contentViewController = FirstMouseHostingController(rootView: view)
        window.title = ^String.Titles.exportAs
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
