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
    /// Автофокус на поле при появлении.
    var autoFocus: Bool = false
    /// Вызывается по Enter (submit) внутри поля.
    var onSubmit: (() -> Void)? = nil
    @ObservedObject private var focusManager = FocusStateManager.shared
    @State private var isFocused = false
    @State private var observer: Any? = nil
    @FocusState private var fieldFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .focused($fieldFocused)
            .onSubmit { onSubmit?() }
            .background(FocusTrackingView(isFocused: $isFocused, focusManager: focusManager))
            .onAppear {
                DispatchQueue.main.async {
                    focusManager.setFocused(false)
                    if autoFocus {
                        fieldFocused = true
                    }
                }
            }
            .onDisappear {
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                }
                if isFocused {
                    focusManager.setFocused(false)
                }
            }
            .onChange(of: isFocused) { focused in
                focusManager.setFocused(focused)
            }
    }
    
}
