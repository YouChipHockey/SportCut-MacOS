//
//  FocusAwareTextField.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct FocusAwareTextField: View {
    
    @Binding var text: String
    var placeholder: String
    @ObservedObject private var focusManager = FocusStateManager.shared
    @State private var isFocused = false
    @State private var observer: Any? = nil
    
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .background(FocusTrackingView(isFocused: $isFocused, focusManager: focusManager))
            .onAppear {
                DispatchQueue.main.async {
                    focusManager.setFocused(false)
                }
            }
            .onDisappear {
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                }
                focusManager.setFocused(false)
            }
    }
    
}
