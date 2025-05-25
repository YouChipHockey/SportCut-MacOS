//
//  AnalyticsWindowController.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers

class AnalyticsWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let view = AnalyticsView()
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Аналитика разметки"
        super.init(window: window)
        window.styleMask.insert(NSWindow.StyleMask.closable)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let windowSize = NSSize(width: 800, height: 600)
            let windowOrigin = NSPoint(
                x: screenFrame.midX - windowSize.width/2,
                y: screenFrame.midY - windowSize.height/2
            )
            window.setFrame(NSRect(origin: windowOrigin, size: windowSize), display: true)
        }
        
        setupToolbar()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowWillClose(_ notification: Notification) {
        self.window?.delegate = nil
        WindowsManager.shared.analyticsWindow = nil
    }
    
    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "AnalyticsToolbar")
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        window?.toolbar = toolbar
    }
    
    @objc func exportAsImage(_ sender: Any) {
        guard let window = self.window else { return }
        let savePanel = NSSavePanel()
        savePanel.title = "Экспорт аналитики в изображение"
        savePanel.nameFieldStringValue = "Аналитика_разметки.png"
        savePanel.allowedContentTypes = [UTType.jpeg]
        savePanel.canCreateDirectories = true
        
        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            self?.captureScrollViewAndExportAsImage(to: url)
        }
    }
    
    private func captureScrollViewAndExportAsImage(to url: URL) {
        guard let window = self.window else { return }
        
        let progressView = NSView(frame: NSRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height))
        progressView.wantsLayer = true
        progressView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        
        let progressIndicator = NSProgressIndicator(frame: NSRect(x: window.frame.width/2 - 30, y: window.frame.height/2 - 30, width: 60, height: 60))
        progressIndicator.style = .spinning
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        
        let label = NSTextField(frame: NSRect(x: window.frame.width/2 - 100, y: window.frame.height/2 + 40, width: 200, height: 30))
        label.stringValue = "Создание изображения..."
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.textColor = .white
        
        progressView.addSubview(progressIndicator)
        progressView.addSubview(label)
        window.contentView?.addSubview(progressView)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let scrollView = self.findScrollView(in: window.contentView) {
                if let documentView = scrollView.documentView {
                    // Сохраняем текущие позиции прокрутки
                    let savedOrigin = scrollView.contentView.bounds.origin
                    
                    // Получаем полные размеры контента
                    let fullBounds = documentView.bounds
                    let totalHeight = documentView.bounds.height
                    let viewportHeight = scrollView.contentView.bounds.height
                    let viewportWidth = scrollView.contentView.bounds.width
                    
                    var imageParts: [NSImage] = []
                    
                    // Начинаем с верхней части документа и идем вниз
                    // Создаем массив смещений для прокрутки в правильном порядке сверху вниз
                    let yOffsets = stride(from: 0.0, to: totalHeight, by: viewportHeight).map { $0 }
                    
                    for yOffset in yOffsets {
                        scrollView.contentView.scroll(to: NSPoint(x: 0, y: yOffset))
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                        
                        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
                        
                        let partHeight = min(viewportHeight, totalHeight - yOffset)
                        let partRect = NSRect(x: 0, y: yOffset, width: viewportWidth, height: partHeight)
                        let partImage = documentView.bitmapImageRepForCachingDisplay(in: partRect)
                        documentView.cacheDisplay(in: partRect, to: partImage!)
                        
                        let image = NSImage(size: NSSize(width: viewportWidth, height: partHeight))
                        image.addRepresentation(partImage!)
                        image.backgroundColor = NSColor.windowBackgroundColor
                        imageParts.insert(image, at: 0)
                        DispatchQueue.main.async {
                            let progress = min(1.0, (yOffset + viewportHeight) / totalHeight)
                            label.stringValue = "Создание изображения... \(Int(progress * 100))%"
                        }
                    }
                    scrollView.contentView.scroll(to: savedOrigin)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                    let finalImage = NSImage(size: NSSize(width: viewportWidth, height: totalHeight))
                    finalImage.lockFocus()
                    var currentY = 0.0
                    for part in imageParts {
                        part.draw(in: NSRect(x: 0, y: currentY, width: viewportWidth, height: part.size.height))
                        currentY += part.size.height
                    }
                    
                    finalImage.unlockFocus()
                    if let tiffData = finalImage.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffData),
                       let imageData = bitmapRep.representation(using: .png, properties: [:]) {
                        
                        do {
                            try imageData.write(to: url)
                            DispatchQueue.main.async {
                                progressView.removeFromSuperview()
                                self.showSuccessNotification(filePath: url.path)
                            }
                        } catch {
                            DispatchQueue.main.async {
                                progressView.removeFromSuperview()
                                self.showExportError(message: "Не удалось сохранить изображение: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            progressView.removeFromSuperview()
                            self.showExportError(message: "Не удалось создать изображение")
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        progressView.removeFromSuperview()
                        self.showExportError(message: "Не удалось найти содержимое ScrollView")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    progressView.removeFromSuperview()
                    self.showExportError(message: "Не удалось найти ScrollView в окне")
                }
            }
        }
    }
    
    private func showSuccessNotification(filePath: String) {
        let notification = NSUserNotification()
        notification.title = "Экспорт успешно завершен"
        notification.informativeText = "Изображение сохранено по пути: \(filePath)"
        NSUserNotificationCenter.default.deliver(notification)
        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
    }
    
    private func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view = view else { return nil }
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }
        
        return nil
    }
    
    private func showExportError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Ошибка экспорта PDF"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
}

extension AnalyticsWindowController: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier.rawValue == "ExportImage" {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Экспорт в изображение"
            item.paletteLabel = "Экспорт в изображение"
            item.toolTip = "Экспортировать аналитику как изображение"
            item.image = NSImage(systemSymbolName: "arrow.down.doc.fill", accessibilityDescription: "Export")
            item.target = self
            item.action = #selector(exportAsImage(_:))
            return item
        }
        return nil
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [NSToolbarItem.Identifier(rawValue: "ExportImage")]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [NSToolbarItem.Identifier(rawValue: "ExportImage")]
    }
}
