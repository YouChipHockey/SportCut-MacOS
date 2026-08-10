//
//  FieldMapMultiSelectionWindowController.swift
//  Youchip-Stat
//
//  Окно разметки тега на нескольких картах (стопкой). См. FieldMapMultiSelectionView.
//

import SwiftUI
import Cocoa

class FieldMapMultiSelectionWindowController: NSWindowController, NSWindowDelegate {

    init(tag: Tag, items: [FieldMapSelectionItem], onSave: @escaping ([String: CGPoint]) -> Void) {
        let view = FieldMapMultiSelectionView(tag: tag, items: items, onSave: onSave)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "\(^String.Titles.selectMapPositionForTag) \(tag.name)"
        super.init(window: window)
        window.tabbingMode = .disallowed
        window.styleMask = [.titled, .closable, .resizable]
        window.delegate = self

        // Окно открываем сразу во всю высоту экрана (сколько бы карт ни было); ширина — под число
        // колонок (в столбце максимум 2 карты). Карты вписываются по высоте, при нехватке — прокрутка.
        let count = max(1, items.count)
        let columns = FieldMapMultiSelectionView.columnCount(for: count)
        let cellWidth: CGFloat = 360      // ширина карты + поля
        let horizontalChrome: CGFloat = 48
        if let visible = NSScreen.main?.visibleFrame {
            var width = CGFloat(columns) * cellWidth + horizontalChrome
            width = min(width, visible.width * 0.95)
            width = max(width, 560)
            let x = visible.minX + (visible.width - width) / 2
            // setFrame задаёт весь фрейм окна (с заголовком) → высота ровно во весь visibleFrame.
            window.setFrame(NSRect(x: x, y: visible.minY, width: width, height: visible.height), display: true)
        } else {
            window.setContentSize(NSSize(width: max(560, CGFloat(columns) * cellWidth + horizontalChrome), height: 800))
            window.center()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        WindowsManager.shared.fieldMapWindowDidClose()
    }
}
