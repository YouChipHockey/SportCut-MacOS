//
//  ScreenshotsWindowController.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 5/27/25.
//

import SwiftUI
import AppKit

class ScreenshotsWindowController: NSWindowController, NSWindowDelegate {
    
    let screenshotsFolder: URL
    
    init(screenshotsFolder: URL) {
        self.screenshotsFolder = screenshotsFolder
        let view = ScreenshotsGalleryView(screenshotsFolder: screenshotsFolder)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = ^String.Titles.fullControlButtonScreenshots
        window.tabbingMode = .disallowed
        
        super.init(window: window)
        window.delegate = self
        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowsManager.shared.screenshotsWindow = nil
    }
}

struct ScreenshotsGalleryView: View {
    let screenshotsFolder: URL
    @State private var screenshots: [ScreenshotItem] = []
    @State private var isLoading: Bool = true
    @State private var gridColumns = 3
    @State private var selectedScreenshots: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    @State private var screenshotsToDelete: [ScreenshotItem] = []
    
    struct ScreenshotItem: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
        let image: NSImage?
        
        init(url: URL) {
            self.url = url
            self.name = url.deletingPathExtension().lastPathComponent
            self.image = NSImage(contentsOf: url)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !screenshots.isEmpty {
                HStack {
                    Text("\(screenshots.count) \(^String.Titles.screenshotsCount)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !selectedScreenshots.isEmpty {
                        Button(action: {
                            screenshotsToDelete = screenshots.filter { selectedScreenshots.contains($0.id) }
                            showDeleteConfirmation = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .medium))
                                Text("\(^String.Titles.deleteSelected) (\(selectedScreenshots.count))")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(^String.Titles.cancelSelection) {
                            selectedScreenshots.removeAll()
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.05))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.gray.opacity(0.2)),
                    alignment: .bottom
                )
            }
            
            if isLoading {
                ProgressView(^String.Titles.loadingScreenshots)
            } else if screenshots.isEmpty {
                VStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 50))
                        .padding()
                    Text(^String.Titles.videoPlayerScreenshotMissing)
                        .font(.headline)
                    Text(^String.Titles.videoPlayerScreenshotHelp)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .foregroundColor(.gray)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: calculateColumnCount(width: geometry.size.width)),
                            spacing: 16
                        ) {
                            ForEach(screenshots) { item in
                                ScreenshotItemView(
                                    item: item,
                                    isSelected: selectedScreenshots.contains(item.id),
                                    onSelectionChanged: { isSelected in
                                        if isSelected {
                                            selectedScreenshots.insert(item.id)
                                        } else {
                                            selectedScreenshots.remove(item.id)
                                        }
                                    }
                                )
                                .frame(height: 200)
                            }
                        }
                        .padding()
                    }
                    .onAppear {
                        gridColumns = calculateColumnCount(width: geometry.size.width)
                    }
                    .onChange(of: geometry.size.width) { newWidth in
                        gridColumns = calculateColumnCount(width: newWidth)
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            loadScreenshots()
        }
        .alert(^String.Titles.deleteScreenshots, isPresented: $showDeleteConfirmation) {
            Button(^String.Titles.cancel, role: .cancel) { }
            Button(^String.Titles.delete, role: .destructive) {
                deleteSelectedScreenshots()
            }
        } message: {
            Text(^String.Titles.confirmDeleteScreenshots)
        }
    }
    
    private func calculateColumnCount(width: CGFloat) -> Int {
        let targetItemWidth: CGFloat = 200
        let availableWidth = width - 40
        let columns = max(1, Int(availableWidth / targetItemWidth))
        
        return columns
    }
    
    private func loadScreenshots() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: screenshotsFolder,
                                                                       includingPropertiesForKeys: nil)
                
                let imageURLs = fileURLs.filter { url in
                    let fileExtension = url.pathExtension.lowercased()
                    return ["png", "jpg", "jpeg"].contains(fileExtension)
                }
                
                let items = imageURLs.map { ScreenshotItem(url: $0) }
                
                DispatchQueue.main.async {
                    self.screenshots = items
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.screenshots = []
                    self.isLoading = false
                }
            }
        }
    }
    
    private func deleteSelectedScreenshots() {
        DispatchQueue.global(qos: .userInitiated).async {
            var deletedCount = 0
            var errors: [String] = []
            
            for screenshot in self.screenshotsToDelete {
                do {
                    try FileManager.default.removeItem(at: screenshot.url)
                    deletedCount += 1
                } catch {
                    errors.append("Ошибка удаления \(screenshot.name): \(error.localizedDescription)")
                }
            }
            
            DispatchQueue.main.async {
                self.screenshots.removeAll { screenshot in
                    self.screenshotsToDelete.contains { $0.id == screenshot.id }
                }
                
                self.selectedScreenshots.removeAll()
                self.screenshotsToDelete.removeAll()                
            }
        }
    }
}

struct ScreenshotItemView: View {
    let item: ScreenshotsGalleryView.ScreenshotItem
    let isSelected: Bool
    let onSelectionChanged: (Bool) -> Void
    @State private var isHovered = false
    
    var body: some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                if let image = item.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 160)
                        .padding(.top, 8)
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 160)
                        .padding(.top, 8)
                        .foregroundColor(.gray)
                }
                
                // Selection checkbox
                Button(action: {
                    onSelectionChanged(!isSelected)
                }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isSelected ? .blue : .gray)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .frame(width: 24, height: 24)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(8)
            }
            
            Text(item.name)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.2) : (isHovered ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : (isHovered ? Color.blue : Color.gray.opacity(0.3)), lineWidth: isSelected ? 2 : 1)
        )
        .onHover { hovering in
            withAnimation {
                isHovered = hovering
            }
            
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            if !isSelected {
                openInEditor()
            }
        }
    }
    
    private func openInEditor() {
        let editorViewModel = EditorViewModel(file: item.url, screenshotsFolder: item.url.deletingLastPathComponent())
        
        let editorView = EditorView()
            .environmentObject(editorViewModel)
            
        let hostingController = NSHostingController(rootView: editorView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = ^String.Titles.editScreenshot
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    
}
