//
//  CollectionWindowDelegate.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import AppKit

class CollectionWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .collectionEditorClosed, object: nil)
    }
}
