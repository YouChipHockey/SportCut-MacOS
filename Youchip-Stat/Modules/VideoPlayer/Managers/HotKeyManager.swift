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
    private var globalMonitorForKeyEvents: Any?
    private var registeredHotkeys: [String: Tag] = [:]
    private var registeredLabelHotkeys: [String: (labelId: String, tagId: String)] = [:]
    
    @Published var isEnabled = true
    @Published var hotKeySelectedTag: Tag? = nil
    @Published var hotKeySelectedLabelId: String? = nil
    @Published var isLabelHotkeyMode = false
    @Published var blockedSheetActive = false
    private var activeCollection: TagCollection = .standard
    
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
    }
    
    @objc private func collectionEditorOpened() {
        isEnabled = false
        print("HotKey manager disabled: Collection editor opened")
    }
    
    @objc private func collectionEditorClosed() {
        isEnabled = true
        print("HotKey manager enabled: Collection editor closed")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func sheetWillAppear(_ notification: Notification) {}
    
    @objc private func sheetDidDisappear(_ notification: Notification) {}
    
    @objc private func addLineSheetAppeared() {
        blockedSheetActive = true
    }
    
    @objc private func editTimelineSheetAppeared() {
        blockedSheetActive = true
    }
    
    @objc private func sheetDismissed() {
        blockedSheetActive = false
    }
    
    func setupKeyboardMonitoring() {
        removeMonitors()
        
        localMonitorForKeyEvents = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  self.isEnabled,
                  !self.blockedSheetActive,
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
        
        print("Registered tag hotkeys for \(collection): \(registeredHotkeys.keys.joined(separator: ", "))")
        print("Registered label hotkeys for \(collection): \(registeredLabelHotkeys.keys.joined(separator: ", "))")
    }
    
    func clearHotkeys() {
        registeredHotkeys.removeAll()
        registeredLabelHotkeys.removeAll()
    }
    
    private func hotkeyStringFromEvent(_ event: NSEvent) -> String {
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
        print("Hotkey activated for tag: \(tag.name)")
        VideoPlayerManager.shared.player?.pause()
        NotificationCenter.default.post(name: .showLabelSheet, object: tag)
    }
    
    func enableLabelHotkeyMode() {
        isLabelHotkeyMode = true
        print("Switched to label hotkey mode")
    }
    
    func disableLabelHotkeyMode() {
        isLabelHotkeyMode = false
        hotKeySelectedLabelId = nil
        print("Switched back to tag hotkey mode")
    }
}
