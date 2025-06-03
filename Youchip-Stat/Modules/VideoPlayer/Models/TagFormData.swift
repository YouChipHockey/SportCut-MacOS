//
//  TagFormData.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI
import Foundation

struct TagFormData {
    var name: String = ""
    var description: String = ""
    var color: Color = .blue
    var hexColor: String = "0000FF"
    var defaultTimeBefore: Double = 5.0
    var defaultTimeAfter: Double = 3.0
    var selectedLabelGroups: [String] = []
    var hotkey: String? = nil
    var labelHotkeys: [String: String] = [:]
    var mapEnabled: Bool = false
    
    init() {}
    
    init(from tag: Tag) {
        self.name = tag.name
        self.description = tag.description
        self.hexColor = tag.color
        self.color = Color(hex: tag.color)
        self.defaultTimeBefore = tag.defaultTimeBefore
        self.defaultTimeAfter = tag.defaultTimeAfter
        self.selectedLabelGroups = tag.lablesGroup
        self.hotkey = tag.hotkey
        self.mapEnabled = tag.mapEnabled ?? false
        self.labelHotkeys = tag.labelHotkeys ?? [:]
    }
    
    func hexStringFromColor(_ color: Color) -> String {
        let components = color.cgColor?.components
        let r: CGFloat = components?[0] ?? 0.0
        let g: CGFloat = components?[1] ?? 0.0
        let b: CGFloat = components?[2] ?? 0.0
        
        let hexString = String.init(
            format: "%02lX%02lX%02lX",
            lround(Double(r * 255)),
            lround(Double(g * 255)),
            lround(Double(b * 255))
        )
        return hexString
    }
    
    func isLabelHotkeyUsed(_ hotkey: String?, exceptLabel labelID: String) -> Bool {
        guard let hotkey = hotkey, !hotkey.isEmpty else { return false }
        return labelHotkeys.contains { (key, value) in
            value == hotkey && key != labelID
        }
    }
    
    mutating func assignLabelHotkey(labelID: String, hotkey: String?) -> Bool {
        if hotkey == nil || hotkey?.isEmpty == true {
            labelHotkeys[labelID] = nil
            return true
        }
        
        if isLabelHotkeyUsed(hotkey, exceptLabel: labelID) {
            return false
        }
        
        labelHotkeys[labelID] = hotkey
        return true
    }
}
