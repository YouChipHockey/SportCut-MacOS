//
//  FocusTrackingView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct FocusTrackingView: NSViewRepresentable {
    
    @Binding var isFocused: Bool
    var focusManager: FocusStateManager
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let responder = nsView.window?.firstResponder,
               let textField = responder as? NSTextField {
                var currentView: NSView? = textField
                var isInOurHierarchy = false
                
                while let parent = currentView?.superview {
                    if parent == nsView.superview?.superview {
                        isInOurHierarchy = true
                        break
                    }
                    currentView = parent
                }
                
                if isInOurHierarchy {
                    self.isFocused = true
                    self.focusManager.setFocused(true)
                } else {
                    self.isFocused = false
                    self.focusManager.setFocused(false)
                }
            } else {
                self.isFocused = false
                self.focusManager.setFocused(false)
            }
        }
    }
    
    class Coordinator: NSObject {
        var parent: FocusTrackingView
        var timer: Timer?
        
        init(parent: FocusTrackingView) {
            self.parent = parent
            super.init()
            
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if FocusTrackingView.nsView?.window == nil {
                    if self.parent.isFocused {
                        self.parent.isFocused = false
                        self.parent.focusManager.setFocused(false)
                    }
                    return
                }
                
                if let window = FocusTrackingView.nsView?.window,
                   let responder = window.firstResponder {
                    
                    let isTextFieldFocused = responder is NSTextField || responder is NSTextView
                    
                    if !isTextFieldFocused && self.parent.isFocused {
                        self.parent.isFocused = false
                        self.parent.focusManager.setFocused(false)
                    }
                }
            }
        }
        
        deinit {
            timer?.invalidate()
            timer = nil
        }
    }
    
    static var nsView: NSView? = nil
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.timer?.invalidate()
        coordinator.timer = nil
        self.nsView = nil
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(parent: self)
        Self.nsView = nil
        return coordinator
    }
    
}
