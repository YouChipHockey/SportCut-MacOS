//
//  NSNotification + Convenience.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import Foundation

extension NSNotification.Name {
    static let collectionDataChanged = NSNotification.Name("collectionDataChanged")
    static let collectionEditorOpened = NSNotification.Name("collectionEditorOpened")
    static let collectionEditorClosed = NSNotification.Name("collectionEditorClosed")
    static let markupModeChanged = NSNotification.Name("markupModeChanged")
}
