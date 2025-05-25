//
//  KeyCaptureView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI
import Foundation

struct KeyCaptureView: NSViewRepresentable {
    @Binding var keyString: String?
    var isCapturing: Binding<Bool>
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureNSView()
        view.keyString = $keyString
        view.isCapturing = isCapturing
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyCaptureNSView {
            view.keyString = $keyString
            view.isCapturing = isCapturing
            
            if isCapturing.wrappedValue {
                DispatchQueue.main.async {
                    view.window?.makeFirstResponder(view)
                }
            }
        }
    }
    
    class KeyCaptureNSView: NSView {
        var keyString: Binding<String?>?
        var isCapturing: Binding<Bool>?
        private var lastFlags: NSEvent.ModifierFlags = []
        
        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize {
            return NSSize(width: 0, height: 0)
        }
        override func draw(_ dirtyRect: NSRect) {}
        
        override func hitTest(_ point: NSPoint) -> NSView? {
            return isCapturing?.wrappedValue == true ? self : nil
        }
        
        override func keyDown(with event: NSEvent) {
            guard isCapturing?.wrappedValue == true else { return }
            lastFlags = event.modifierFlags
            let characters = event.charactersIgnoringModifiers ?? ""
            let modifiers = getModifierFlags(event.modifierFlags)
            var keyRepresentation = modifiers.joined(separator: "+")
            if !characters.isEmpty && !isOnlyModifier(characters) {
                if !keyRepresentation.isEmpty {
                    keyRepresentation += "+"
                }
                keyRepresentation += getKeyName(event)
                if !keyRepresentation.isEmpty {
                    let oldValue = keyString?.wrappedValue
                    keyString?.wrappedValue = keyRepresentation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if self.keyString?.wrappedValue != keyRepresentation && self.keyString?.wrappedValue != nil {
                            self.keyString?.wrappedValue = oldValue
                        }
                        self.isCapturing?.wrappedValue = false
                    }
                }
            }
        }
        
        override func flagsChanged(with event: NSEvent) {
            guard isCapturing?.wrappedValue == true else { return }
            let newFlags = event.modifierFlags
            let isKeyDown = newFlags.contains(lastFlags)
            lastFlags = newFlags
            let modifiers = getModifierFlags(newFlags)
            
            if !isKeyDown && !modifiers.isEmpty {
                let keyRepresentation = modifiers.joined(separator: "+")
                if !keyRepresentation.isEmpty {
                    keyString?.wrappedValue = keyRepresentation
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isCapturing?.wrappedValue = false
                    }
                }
            }
        }
        
        private func getModifierFlags(_ flags: NSEvent.ModifierFlags) -> [String] {
            var modifiers: [String] = []
            
            if flags.contains(.command) {
                modifiers.append("⌘")
            }
            if flags.contains(.option) {
                modifiers.append("⌥")
            }
            if flags.contains(.control) {
                modifiers.append("⌃")
            }
            if flags.contains(.shift) {
                modifiers.append("⇧")
            }
            if flags.contains(.function) {
                modifiers.append("Fn")
            }
            
            return modifiers
        }
        
        private func isOnlyModifier(_ character: String) -> Bool {
            let modifierCharacters = ["\u{F700}", "\u{F701}", "\u{F702}", "\u{F703}"]
            return modifierCharacters.contains(character)
        }
        
        private func getKeyName(_ event: NSEvent) -> String {
            let character = event.charactersIgnoringModifiers ?? ""
            if let specialKey = getSpecialKeyName(event.keyCode) {
                return specialKey
            }
            if event.keyCode >= 122 && event.keyCode <= 129 {
                return "F\(event.keyCode - 121)"
            }
            if !character.isEmpty {
                switch character {
                case " ": return "Space"
                default: return character.uppercased()
                }
            }
            return "Key(\(event.keyCode))"
        }
        private func getSpecialKeyNameForKeyUp(_ keyCode: UInt16) -> String? {
            if keyCode == 63 {
                return "Fn"
            }
            return nil
        }
        private func getSpecialKeyName(_ keyCode: UInt16) -> String? {
            let keyCodeMap: [UInt16: String] = [
                0x24: "Return",
                0x30: "Tab",
                0x31: "Space",
                0x33: "Delete",
                0x35: "Esc",
                0x7D: "↓",
                0x7E: "↑",
                0x7B: "←",
                0x7C: "→",
                0x73: "Home",
                0x77: "End",
                0x74: "Page Up",
                0x79: "Page Down",
                0x72: "Help",
                0x00: "A",
                0x0B: "B",
                0x08: "C",
                0x02: "D",
                0x0E: "E",
                0x03: "F",
                0x05: "G",
                0x04: "H",
                0x22: "I",
                0x26: "J",
                0x28: "K",
                0x25: "L",
                0x2E: "M",
                0x2D: "N",
                0x1F: "O",
                0x23: "P",
                0x0C: "Q",
                0x0F: "R",
                0x01: "S",
                0x11: "T",
                0x20: "U",
                0x09: "V",
                0x0D: "W",
                0x07: "X",
                0x10: "Y",
                0x06: "Z",
                0x12: "1",
                0x13: "2",
                0x14: "3",
                0x15: "4",
                0x17: "5",
                0x16: "6",
                0x1A: "7",
                0x1C: "8",
                0x19: "9",
                0x1D: "0",
                0x7A: "F1",
                0x78: "F2",
                0x63: "F3",
                0x76: "F4",
                0x60: "F5",
                0x61: "F6",
                0x62: "F7",
                0x64: "F8",
                0x65: "F9",
                0x6D: "F10",
                0x67: "F11",
                0x6F: "F12",
            ]
            
            return keyCodeMap[keyCode]
        }
    }
}
