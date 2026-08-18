//
//  HotKeyManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    
    private var localMonitorForKeyEvents: Any?
    var registeredHotkeys: [String: Tag] = [:]
    var registeredLabelHotkeys: [String: (labelId: String, tagId: String)] = [:]
    
    @Published var isEnabled = true
    @Published var hotKeySelectedTag: Tag? = nil
    @Published var hotKeySelectedLabelId: String? = nil
    @Published var isLabelHotkeyMode = false
    @Published var blockedSheetActive = false
    private var activeCollection: TagCollection = .standard
    private var isEditorModeActive = false
    private var isEditingTextBox = false
    
    private init() {
        setupKeyboardMonitoring()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sheetWillAppear),
            name: NSWindow.willBeginSheetNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sheetDidDisappear),
            name: NSWindow.didEndSheetNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(addLineSheetAppeared),
            name: NSNotification.Name("AddLineSheetAppeared"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(editTimelineSheetAppeared),
            name: NSNotification.Name("EditTimelineSheetAppeared"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sheetDismissed),
            name: NSNotification.Name("SheetDismissed"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(collectionEditorOpened),
            name: .collectionEditorOpened,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(collectionEditorClosed),
            name: .collectionEditorClosed,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(editorModeChanged),
            name: .editorModeChanged,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textBoxEditingChanged),
            name: .textBoxEditingChanged,
            object: nil
        )
    }
    
    @objc private func collectionEditorOpened() {
        isEnabled = false
    }
    
    @objc private func collectionEditorClosed() {
        isEnabled = true
    }
    
    @objc private func editorModeChanged(_ notification: Notification) {
        if let isActive = notification.object as? Bool {
            isEditorModeActive = isActive
        }
    }
    
    @objc private func textBoxEditingChanged(_ notification: Notification) {
        if let isEditing = notification.object as? Bool {
            isEditingTextBox = isEditing
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func sheetWillAppear(_ notification: Notification) {
        blockedSheetActive = true
    }
    
    @objc private func sheetDidDisappear(_ notification: Notification) {
        blockedSheetActive = false
    }
    
    @objc private func addLineSheetAppeared() {
        blockedSheetActive = true
    }
    
    @objc private func editTimelineSheetAppeared() {
        blockedSheetActive = true
    }
    
    @objc private func sheetDismissed() {
        blockedSheetActive = false
    }

    /// Не перехватывать пробел (play/pause), пока пользователь вводит текст в поле или телестрацию.
    private func shouldPassThroughSpaceForTextInput() -> Bool {
        if isEditingTextBox { return true }
        if FocusStateManager.shared.isAnyTextFieldFocused { return true }
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextField { return true }
        if let textView = responder as? NSTextView {
            // AVPlayerView and SwiftUI hosting views contain internal NSTextView
            // that is not a real user text input. Only block for genuine field editors
            // (e.g. comment fields, rename fields) that the user is actively typing into.
            return textView.isFieldEditor
        }
        return false
    }
    
    func setupKeyboardMonitoring() {
        removeMonitors()
        
        localMonitorForKeyEvents = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            // В режиме редактирования Enter = Done/Apply для телестрации, фигур и текстбоксов
            if self.isEditorModeActive, event.keyCode == 36, !self.isEditingTextBox {
                NotificationCenter.default.post(name: .editorEnterKeyPressed, object: nil)
                return nil
            }
            // В режиме редактирования Cmd+C = копировать выбранный объект, Cmd+V = вставить (при инструменте «Курсор»)
            if self.isEditorModeActive, !self.isEditingTextBox, event.modifierFlags.contains(.command) {
                if event.keyCode == 8 {
                    NotificationCenter.default.post(name: .editorCopyKeyPressed, object: nil)
                    return nil
                }
                if event.keyCode == 9 {
                    NotificationCenter.default.post(name: .editorPasteKeyPressed, object: nil)
                    return nil
                }
                if event.keyCode == 6 {
                    NotificationCenter.default.post(name: .editorUndoKeyPressed, object: nil)
                    return nil
                }
            }
            // Пробел в окне режима просмотра (SportCut) — play/pause плеера сессии.
            if event.keyCode == 49,
               WindowsManager.shared.isSportCutKeyWindow(),
               self.isEnabled,
               !self.blockedSheetActive,
               !self.shouldPassThroughSpaceForTextInput() {
                NotificationCenter.default.post(name: .sportCutTogglePlayPause, object: nil)
                return nil
            }
            // Shift+стрелки в окне режима просмотра (SportCut) — перемотка ±3 сек.
            if event.modifierFlags.contains(.shift),
               WindowsManager.shared.isSportCutKeyWindow(),
               self.isEnabled,
               !self.blockedSheetActive {
                if event.keyCode == 123 {
                    NotificationCenter.default.post(name: .sportCutSeekBackward, object: nil)
                    return nil
                }
                if event.keyCode == 124 {
                    NotificationCenter.default.post(name: .sportCutSeekForward, object: nil)
                    return nil
                }
            }
            // Стрелки без модификаторов в SportCut — покадровая перемотка.
            if !event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control),
               (event.keyCode == 123 || event.keyCode == 124),
               WindowsManager.shared.isSportCutKeyWindow(),
               self.isEnabled,
               !self.blockedSheetActive {
                NotificationCenter.default.post(
                    name: event.keyCode == 123 ? .sportCutStepFrameBackward : .sportCutStepFrameForward,
                    object: nil
                )
                return nil
            }
            // Shift+стрелки в окне разметки — перемотка ±3 сек (также в режиме редактирования рисунка).
            if event.modifierFlags.contains(.shift),
               (event.keyCode == 123 || event.keyCode == 124),
               self.isEnabled,
               !self.blockedSheetActive,
               ActiveWindowManager.shared.isMarkerWindowActive() || ActiveWindowManager.shared.isViewerWindowActive() {
                let isViewer = WindowsManager.shared.viewerWindow != nil && ActiveWindowManager.shared.isViewerWindowActive()
                let seekBy: Double = event.keyCode == 123 ? -3 : 3
                if isViewer {
                    NotificationCenter.default.post(name: event.keyCode == 123 ? .seekViewerPlayerBackward : .seekViewerPlayerForward, object: nil)
                } else if self.isEditorModeActive {
                    NotificationCenter.default.post(name: .editorModeChanged, object: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        VideoPlayerManager.shared.seek(by: seekBy)
                    }
                } else {
                    VideoPlayerManager.shared.seek(by: seekBy)
                }
                return nil
            }
            // ⌘⌃0 в окне разметки — показать/скрыть служебный таймлайн счётчиков.
            if event.keyCode == 29 /* 0 */,
               event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.control),
               !event.modifierFlags.contains(.option),
               ActiveWindowManager.shared.isMarkerWindowActive(),
               self.isEnabled,
               !self.blockedSheetActive,
               !self.isEditingTextBox,
               !FocusStateManager.shared.isAnyTextFieldFocused {
                TimelineDataManager.shared.toggleClocksTimelineVisibility()
                return nil
            }
            // Opt+Cmd+S в окне разметки — сохранение выделенных клипов одним склеенным фильмом.
            if event.keyCode == 1 /* S */,
               event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control),
               ActiveWindowManager.shared.isMarkerWindowActive(),
               self.isEnabled,
               !self.blockedSheetActive,
               !self.isEditingTextBox,
               !FocusStateManager.shared.isAnyTextFieldFocused {
                ClipAutoSaveManager.shared.saveMergedSelectedClips()
                return nil
            }
            // Cmd+S в окне разметки — быстрое сохранение клипа выбранного тега в папку автосохранения.
            if event.keyCode == 1 /* S */,
               event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control),
               ActiveWindowManager.shared.isMarkerWindowActive(),
               self.isEnabled,
               !self.blockedSheetActive,
               !self.isEditingTextBox,
               !FocusStateManager.shared.isAnyTextFieldFocused {
                ClipAutoSaveManager.shared.saveSelectedStampClip()
                return nil
            }
            // Пробел = play/pause: окно видео / таймлайна / библиотеки тегов или окно «Пересмотр» (key window, не кэш уведомлений).
            if event.keyCode == 49,
               ActiveWindowManager.shared.isMarkerWindowActive() || WindowsManager.shared.isReviewWindowKey(),
               self.isEnabled,
               !self.blockedSheetActive,
               !self.shouldPassThroughSpaceForTextInput() {
                if VideoPlayerManager.shared.isReviewMode {
                    VideoPlayerManager.shared.toggleReviewPlayPause()
                } else {
                    VideoPlayerManager.shared.togglePlayPause()
                }
                return nil
            }
            // Esc — сброс режима подсветки связок клавиш
            if event.keyCode == 53 /* Escape */,
               KeyBindingRuntimeManager.shared.highlightModeActive {
                KeyBindingRuntimeManager.shared.resetHighlight()
                return nil
            }

            // Горячие клавиши подсветки связок
            if KeyBindingRuntimeManager.shared.highlightModeActive,
               !FocusStateManager.shared.isAnyTextFieldFocused {
                let hotkeyStr = self.hotkeyStringFromEvent(event)
                if KeyBindingRuntimeManager.shared.handleHighlightHotkey(hotkeyStr) {
                    return nil
                }
            }

            guard self.isEnabled,
                  (!self.blockedSheetActive || self.isLabelHotkeyMode),
                  !self.isEditorModeActive,
                  !FocusStateManager.shared.isAnyTextFieldFocused else {
                return event
            }
            return self.handleHotkey(event) ? nil : event
        }
    }
    
    private func removeMonitors() {
        if let localMonitor = localMonitorForKeyEvents {
            NSEvent.removeMonitor(localMonitor)
            localMonitorForKeyEvents = nil
        }
    }
    
    private func handleHotkey(_ event: NSEvent) -> Bool {
        let isMarkerWindowActive = ActiveWindowManager.shared.isMarkerWindowActive()
        let isViewerWindowActive = ActiveWindowManager.shared.isViewerWindowActive()
        guard isMarkerWindowActive || isViewerWindowActive  else {
            return false
        }
        
        let isViewerMode = WindowsManager.shared.viewerWindow != nil && isViewerWindowActive
        
        if event.keyCode == 49 {
            if shouldPassThroughSpaceForTextInput() { return false }
            
            if isViewerMode {
                NotificationCenter.default.post(name: .toggleViewerPlayer, object: nil)
            } else if VideoPlayerManager.shared.isReviewMode {
                VideoPlayerManager.shared.toggleReviewPlayPause()
            } else if isEditorModeActive {
                NotificationCenter.default.post(name: .editorModeChanged, object: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    VideoPlayerManager.shared.togglePlayPause()
                }
            } else {
                VideoPlayerManager.shared.togglePlayPause()
            }
            return true
        }
        
        // Shift+arrows теперь обрабатываются до guard isEditorModeActive в keyDown мониторе.
        
        let hotkeyString = hotkeyStringFromEvent(event)
        
        if isLabelHotkeyMode {
            if let labelInfo = registeredLabelHotkeys[hotkeyString] {
                hotKeySelectedLabelId = labelInfo.labelId
                NotificationCenter.default.post(name: .labelHotkeyPressed, object: labelInfo)
                return true
            }
        } else {
            if let tag = registeredHotkeys[hotkeyString] {
                DispatchQueue.main.async {
                    self.selectTag(tag)
                }
                return true
            }
        }
        return false
    }
    
    func registerHotkeys(from tags: [Tag], for collection: TagCollection) {
        registeredHotkeys.removeAll()
        registeredLabelHotkeys.removeAll()
        activeCollection = collection
        for tag in tags {
            if let hotkey = tag.hotkey, !hotkey.isEmpty {
                registeredHotkeys[hotkey.lowercased()] = tag
            }
            if let labelHotkeys = tag.labelHotkeys {
                for (labelId, hotkey) in labelHotkeys {
                    if !hotkey.isEmpty {
                        registeredLabelHotkeys[hotkey.lowercased()] = (labelId: labelId, tagId: tag.id)
                    }
                }
            }
        }
    }
    
    func clearHotkeys() {
        registeredHotkeys.removeAll()
        registeredLabelHotkeys.removeAll()
    }
    
    func suspendKeyboardMonitoring() {
        removeMonitors()
    }
    
    func resumeKeyboardMonitoring() {
        setupKeyboardMonitoring()
    }
    
    /// Комбинации, зарезервированные под системные хоткеи приложения (редактор). Их нельзя назначать тегам.
    /// Стрелки/пробел/Enter/Esc отсекаются отдельно (они превращаются в "key-<code>").
    static let reservedHotkeys: Set<String> = ["cmd+c", "cmd+v", "cmd+z", "cmd+a", "cmd+x", "cmd+s"]

    /// true, если строка хоткея конфликтует с системными сочетаниями приложения и не должна назначаться тегу/лейблу.
    static func isReservedHotkey(_ hotkey: String) -> Bool {
        let normalized = hotkey.lowercased()
        if normalized.contains("key-") { return true }   // пробел, стрелки, Enter, Esc и прочие спец-клавиши
        return reservedHotkeys.contains(normalized)
    }

    func hotkeyStringFromEvent(_ event: NSEvent) -> String {
        var components: [String] = []
        if event.modifierFlags.contains(.control) { components.append("ctrl") }
        if event.modifierFlags.contains(.option) { components.append("alt") }
        if event.modifierFlags.contains(.shift) { components.append("shift") }
        if event.modifierFlags.contains(.command) { components.append("cmd") }
        let keyCode = event.keyCode
        let keyChar: String
        switch keyCode {
        case 0: keyChar = "a"
        case 1: keyChar = "s"
        case 2: keyChar = "d"
        case 3: keyChar = "f"
        case 4: keyChar = "h"
        case 5: keyChar = "g"
        case 6: keyChar = "z"
        case 7: keyChar = "x"
        case 8: keyChar = "c"
        case 9: keyChar = "v"
        case 11: keyChar = "b"
        case 12: keyChar = "q"
        case 13: keyChar = "w"
        case 14: keyChar = "e"
        case 15: keyChar = "r"
        case 16: keyChar = "y"
        case 17: keyChar = "t"
        case 18: keyChar = "1"
        case 19: keyChar = "2"
        case 20: keyChar = "3"
        case 21: keyChar = "4"
        case 22: keyChar = "6"
        case 23: keyChar = "5"
        case 24: keyChar = "="
        case 25: keyChar = "9"
        case 26: keyChar = "7"
        case 27: keyChar = "-"
        case 28: keyChar = "8"
        case 29: keyChar = "0"
        case 30: keyChar = "]"
        case 31: keyChar = "o"
        case 32: keyChar = "u"
        case 33: keyChar = "["
        case 34: keyChar = "i"
        case 35: keyChar = "p"
        case 37: keyChar = "l"
        case 38: keyChar = "j"
        case 39: keyChar = "'"
        case 40: keyChar = "k"
        case 41: keyChar = ";"
        case 42: keyChar = "\\"
        case 43: keyChar = ","
        case 44: keyChar = "/"
        case 45: keyChar = "n"
        case 46: keyChar = "m"
        case 47: keyChar = "."
        case 50: keyChar = "`"
        default:
            keyChar = "key-\(keyCode)"
        }
        
        components.append(keyChar)
        return components.joined(separator: "+")
    }
    
    private func selectTag(_ tag: Tag) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .showLabelSheet, object: tag)
        }
    }
    
    func enableLabelHotkeyMode() {
        isLabelHotkeyMode = true
    }
    
    func disableLabelHotkeyMode() {
        isLabelHotkeyMode = false
        hotKeySelectedLabelId = nil
    }
    
}
