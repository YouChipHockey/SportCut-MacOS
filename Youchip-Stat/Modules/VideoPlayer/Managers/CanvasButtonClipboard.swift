//
//  CanvasButtonClipboard.swift
//  Youchip-Stat
//
//  Буфер копирования кнопок свободной раскладки (теги/лейблы/события).
//  Хранит только визуал самих кнопок — связки клавиш не копируются.
//  При вставке дублируются и сами сущности в коллекции.
//

import Foundation

final class CanvasButtonClipboard {

    static let shared = CanvasButtonClipboard()

    private(set) var items: [TagFreeLayoutItem] = []

    var hasContent: Bool { !items.isEmpty }

    private init() {}

    func copy(_ items: [TagFreeLayoutItem]) {
        self.items = items
    }

    func clear() {
        items = []
    }
}
