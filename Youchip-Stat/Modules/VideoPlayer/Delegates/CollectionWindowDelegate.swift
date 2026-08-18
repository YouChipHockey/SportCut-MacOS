//
//  CollectionWindowDelegate.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import AppKit

/// Делегат окна редактора коллекций. О закрытии сообщает не сам (иначе закрытие одного
/// редактора возвращало бы горячие клавиши при втором открытом), а через `onClose` —
/// `WindowsManager` шлёт `.collectionEditorClosed`, когда закрылся последний редактор.
class CollectionWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
