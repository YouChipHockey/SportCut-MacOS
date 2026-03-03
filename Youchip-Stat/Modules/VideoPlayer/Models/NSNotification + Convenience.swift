//
//  NSNotification + Convenience.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import Foundation

extension Notification {
    struct Key {
        static let collectionName = "collectionName"
    }
}

extension NSNotification.Name {
    static let collectionDataChanged = NSNotification.Name("collectionDataChanged")
    static let currentCollectionRefreshed = NSNotification.Name("currentCollectionRefreshed")
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
    /// Открыть редактор рисунка по скриншоту (перемотка на videoTime + восстановление состояния из метаданных). object = OpenEditorForScreenshotPayload.
    static let openEditorForScreenshot = NSNotification.Name("openEditorForScreenshot")
    /// Запрос редактора из окна пересмотра — захватывает кадр из reviewPlayer и открывает редактор в главном окне.
    static let takeReviewScreenshotForEditor = NSNotification.Name("takeReviewScreenshotForEditor")
    /// Запрос скриншота из окна пересмотра.
    static let takeReviewScreenshot = NSNotification.Name("takeReviewScreenshot")
}

/// Payload для открытия редактора из таймлайна (ПКМ по иконке рисунка → Редактировать).
struct OpenEditorForScreenshotPayload {
    let screenshot: ScreenshotMetadata
    let screenshotsFolder: URL
    let videoId: String
}
