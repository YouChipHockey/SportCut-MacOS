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
    static let stampCountsChanged = NSNotification.Name("stampCountsChanged")
    static let timelineStampHoverChanged = NSNotification.Name("timelineStampHoverChanged")
    static let editorModeChanged = NSNotification.Name("editorModeChanged")
    static let editorEnterKeyPressed = NSNotification.Name("editorEnterKeyPressed")
    static let editorCopyKeyPressed = NSNotification.Name("editorCopyKeyPressed")
    static let editorPasteKeyPressed = NSNotification.Name("editorPasteKeyPressed")
    static let editorUndoKeyPressed = NSNotification.Name("editorUndoKeyPressed")
    static let screenshotDisplayChanged = NSNotification.Name("screenshotDisplayChanged")
    static let textBoxEditingChanged = NSNotification.Name("textBoxEditingChanged")
}
