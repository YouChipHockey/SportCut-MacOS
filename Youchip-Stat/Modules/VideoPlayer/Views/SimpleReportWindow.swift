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
        // Создаем NSTextView для отображения HTML
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
        
        // Конвертируем HTML в NSAttributedString
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
                // Если не удалось распарсить HTML, показываем как обычный текст
                textView?.string = htmlString
            }
        } else {
            textView?.string = htmlString
        }
        
        scrollView.documentView = textView
        self.contentView = scrollView
    }
    
    private func setupWindow() {
        // Показываем окно
        self.makeKeyAndOrderFront(nil)
        
        // Устанавливаем размер окна на весь экран
        if let screen = NSScreen.main {
            self.setFrame(screen.visibleFrame, display: true)
        }
    }
    
    deinit {
        print("🧹 SimpleReportWindow deinit - cleaning up resources")
        cleanupResources()
    }
    
    private func cleanupResources() {
        // Очищаем textView
        textView?.string = ""
        textView = nil
        
        // Очищаем contentView
        self.contentView = nil
    }
}

// MARK: - NSWindowDelegate
extension SimpleReportWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        print("🧹 SimpleReportWindow will close - cleaning up")
        cleanupResources()
        self.delegate = nil
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        print("🧹 SimpleReportWindow should close - cleaning up")
        cleanupResources()
        return true
    }
}

// MARK: - Factory
class SimpleReportWindowFactory {
    static func createReportWindow(htmlString: String, teamName: String, opponentName: String) -> SimpleReportWindow {
        let title = "ИИ Отчет: \(teamName) vs \(opponentName)"
        return SimpleReportWindow(htmlString: htmlString, title: title)
    }
}



