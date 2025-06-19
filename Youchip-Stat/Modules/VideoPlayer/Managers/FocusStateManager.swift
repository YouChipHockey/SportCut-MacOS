//
//  FocusStateManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

class FocusStateManager: ObservableObject {
    
    static let shared = FocusStateManager()
    @Published var isAnyTextFieldFocused = false
    
    func setFocused(_ focused: Bool) {
        isAnyTextFieldFocused = false
    }
    
}
