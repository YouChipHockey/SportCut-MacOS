//
//  ToolbarContent+DisableGlassEffect.swift
//  Youchip-Stat
//
//  Created by Cursor on 2026-03-25.
//

import SwiftUI

public extension ToolbarContent {
    func disableGlassEffect() -> some ToolbarContent {
        // New API for hiding the shared toolbar background (glass/blur) when available.
        // On unsupported OS versions, keep default behavior.
        if #available(iOS 26.0, macOS 15.0, *) {
            return sharedBackgroundVisibility(.hidden)
        } else {
            return self
        }
    }
}

