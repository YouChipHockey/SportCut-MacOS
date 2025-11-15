//
//  SimpleReportWindow.swift
//  Youchip-Stat
//
//  Created by AI Assistant on 22/09/25.
//

import Cocoa
import AppKit

class SimpleReportWindow: NSWindow {
    private var textView: NSTextView?
    
    init(htmlString: String, title: String) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.title = title
        self.center()
        self.delegate = self
        
        setupTextView(with: htmlString)
        setupWindow()
    }
    
    private func setupTextView(with htmlString: String) {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        textView = NSTextView()
        textView?.isEditable = false
        textView?.isSelectable = true
        textView?.isVerticallyResizable = true
        textView?.isHorizontallyResizable = true
        textView?.autoresizingMask = [.width, .height]
        
        if let data = htmlString.data(using: .utf8) {
            do {
                let attributedString = try NSAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue
                    ],
                    documentAttributes: nil
                )
                textView?.textStorage?.setAttributedString(attributedString)
            } catch {
                textView?.string = htmlString
            }
        } else {
            textView?.string = htmlString
        }
        
        scrollView.documentView = textView
        self.contentView = scrollView
    }
    
    private func setupWindow() {
        self.makeKeyAndOrderFront(nil)
        
        if let screen = NSScreen.main {
            self.setFrame(screen.visibleFrame, display: true)
        }
    }
    
    deinit {
        cleanupResources()
    }
    
    private func cleanupResources() {
        textView?.string = ""
        textView = nil
        
        self.contentView = nil
    }
}

extension SimpleReportWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        cleanupResources()
        self.delegate = nil
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cleanupResources()
        return true
    }
}

class SimpleReportWindowFactory {
    static func createReportWindow(htmlString: String, teamName: String, opponentName: String) -> SimpleReportWindow {
        let title = "ИИ Отчет: \(teamName) vs \(opponentName)"
        return SimpleReportWindow(htmlString: htmlString, title: title)
    }
}












