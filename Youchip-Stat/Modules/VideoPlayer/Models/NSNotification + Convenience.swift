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
    /// Пробел play/pause в окне режима просмотра (SportCut). Обрабатывается в `SportCutMainView`.
    static let sportCutTogglePlayPause = NSNotification.Name("sportCutTogglePlayPause")
    static let sportCutSeekBackward = NSNotification.Name("sportCutSeekBackward")
    static let sportCutSeekForward = NSNotification.Name("sportCutSeekForward")
    static let sportCutStepFrameBackward = NSNotification.Name("sportCutStepFrameBackward")
    static let sportCutStepFrameForward = NSNotification.Name("sportCutStepFrameForward")
    /// Открыть редактор рисунка по скриншоту (перемотка на videoTime + восстановление состояния из метаданных). object = OpenEditorForScreenshotPayload.
    static let openEditorForScreenshot = NSNotification.Name("openEditorForScreenshot")
    /// Запрос редактора из окна пересмотра — захватывает кадр из reviewPlayer и открывает редактор в главном окне.
    static let takeReviewScreenshotForEditor = NSNotification.Name("takeReviewScreenshotForEditor")
    /// Запрос скриншота из окна пересмотра.
    static let takeReviewScreenshot = NSNotification.Name("takeReviewScreenshot")
    /// Обновление videoId в VideoPlayerViewModel после перехода из лайв-режима в обычный.
    static let videoIdDidChange = NSNotification.Name("videoIdDidChange")
    
    // MARK: - Tools Menu Commands (macOS menu bar)
    static let toolsExportMarkupJSONFull = NSNotification.Name("toolsExportMarkupJSONFull")
    static let toolsExportMarkupJSONSimple = NSNotification.Name("toolsExportMarkupJSONSimple")
    static let toolsExportMarkupXML = NSNotification.Name("toolsExportMarkupXML")
    static let toolsExportMarkupExcel = NSNotification.Name("toolsExportMarkupExcel")
    static let toolsExportMarkupCSV = NSNotification.Name("toolsExportMarkupCSV")
    static let toolsExportCutsCurrentTimeline = NSNotification.Name("toolsExportCutsCurrentTimeline")
    static let toolsExportCutsAllTimelines = NSNotification.Name("toolsExportCutsAllTimelines")
    static let toolsExportCutsDrawings = NSNotification.Name("toolsExportCutsDrawings")
    static let toolsExportCutsByTags = NSNotification.Name("toolsExportCutsByTags")
    static let toolsExportCutsByLabels = NSNotification.Name("toolsExportCutsByLabels")
    static let toolsExportCutsByEvents = NSNotification.Name("toolsExportCutsByEvents")
    static let toolsReportSimple = NSNotification.Name("toolsReportSimple")
    static let toolsReportAdvanced = NSNotification.Name("toolsReportAdvanced")

    // MARK: - Key Bindings Runtime
    /// Сброс режима подсветки по клавише Esc (object = nil).
    static let keyBindingEscPressed = NSNotification.Name("keyBindingEscPressed")
    /// Нажатие горячей клавиши подсветки (object = highlightHotkey String).
    static let keyBindingHighlightHotkey = NSNotification.Name("keyBindingHighlightHotkey")
}

/// Payload для открытия редактора из таймлайна (ПКМ по иконке рисунка → Редактировать).
struct OpenEditorForScreenshotPayload {
    let screenshot: ScreenshotMetadata
    let screenshotsFolder: URL
    let videoId: String
}
