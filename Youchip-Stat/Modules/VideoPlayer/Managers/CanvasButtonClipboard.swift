//
//  CanvasButtonClipboard.swift
//  Youchip-Stat
//
//  Буфер копирования кнопок свободной раскладки (теги/лейблы/события).
//  Хранит только визуал самих кнопок — связки клавиш не копируются.
//  При вставке дублируются и сами сущности в коллекции.
//

import Foundation
import Combine

/// ObservableObject, а не простой синглтон: меню и кнопки «Вставить» строятся при отрисовке вью,
/// и без публикации изменений после копирования редактор не перерисовывался — пункт «Вставить»
/// оставался скрытым/выключенным, из-за чего копирование выглядело неработающим.
final class CanvasButtonClipboard: ObservableObject {

    static let shared = CanvasButtonClipboard()

    @Published private(set) var items: [TagFreeLayoutItem] = []

    var hasContent: Bool { !items.isEmpty }

    private init() {}

    func copy(_ items: [TagFreeLayoutItem]) {
        self.items = items
    }

    func clear() {
        items = []
    }
}
