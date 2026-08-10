//
//  ImageEditorCanvasView.swift
//  Youchip-Stat
//
//  Самостоятельный редактор картинок: загруженное фото + рисовалка (переиспользуем
//  общие панели/канвас) + инструмент «Картинки». Сохранение проекта и скачивание.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageEditorCanvasView: View {
    let projectId: UUID
    var onClose: () -> Void

    @StateObject private var drawingState = EditorDrawingState()
    @State private var baseImage: NSImage = NSImage()
    @State private var displaySize: CGSize = .zero
    @State private var loaded = false
    @State private var infoMessage: String?

    private var manager: ImageEditorProjectsManager { .shared }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                EditorToolsPanel(
                    drawingState: drawingState,
                    onSelectTool: { tool in selectTool(tool) },
                    showImagesTool: true,
                    onAddImage: { pickAndAddImage() }
                )
                .frame(minWidth: 200)

                Divider()

                canvasArea

                Divider()

                EditorSettingsPanel(drawingState: drawingState)
            }
        }
        .onAppear { loadIfNeeded() }
        .onDisappear {
            // Страховка от потери правок при закрытии окна крестиком: сохраняем
            // состояние без ре-рендера превью (вью уже разбирается).
            if loaded {
                manager.saveProject(projectId, drawingState: drawingState, thumbnail: nil)
            }
        }
        .alert(^String.Titles.fieldMapMenuInfo, isPresented: Binding(
            get: { infoMessage != nil }, set: { if !$0 { infoMessage = nil } }
        )) {
            Button(^String.Titles.fieldMapButtonOK) { infoMessage = nil }
        } message: { Text(infoMessage ?? "") }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: { saveProject(); onClose() }) {
                HStack(spacing: 4) { Image(systemName: "chevron.left"); Text(^String.Titles.back) }
            }
            .buttonStyle(.plain)

            Spacer()

            Text(manager.meta(for: projectId)?.name ?? ^String.Titles.editorImages)
                .font(.headline)

            Spacer()

            Button(action: { downloadImage() }) {
                HStack(spacing: 4) { Image(systemName: "arrow.down.doc"); Text(^String.Titles.download) }
            }
            Button(action: { saveProject(); infoMessage = ^String.Titles.fileSavedSuccessfully }) {
                Text(^String.Titles.saveButtonTitle)
            }
            .keyboardShortcut("s", modifiers: [.command])
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    private var canvasArea: some View {
        GeometryReader { geometry in
            ZStack {
                Color(NSColor.darkGray).opacity(0.35).ignoresSafeArea()

                if loaded {
                    let size = calculateDisplaySize(imageSize: baseImage.size, containerSize: geometry.size)
                    Image(nsImage: baseImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                        .overlay(
                            ZStack {
                                DrawingCanvasView(drawingState: drawingState)
                                EditorImagesOverlay(drawingState: drawingState)
                            }
                            .frame(width: size.width, height: size.height)
                        )
                        .onAppear {
                            displaySize = size
                            drawingState.updateViewSize(size)
                        }
                        .onChange(of: size) { newSize in
                            displaySize = newSize
                            drawingState.updateViewSize(newSize)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Логика

    private func selectTool(_ tool: EditorTool) {
        // Сброс выделений при смене инструмента (как в общем редакторе).
        drawingState.selectedShapeId = nil
        drawingState.selectedTextBoxId = nil
        drawingState.selectedTelestrationObjectId = nil
        if tool != .image { drawingState.selectedImageId = nil }
        drawingState.currentTool = tool
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        if let img = manager.loadBaseImage(projectId) { baseImage = img }
        let state = manager.loadDrawingState(projectId)
        // Переносим восстановленное состояние в наш drawingState.
        drawingState.completedPaths = state.completedPaths
        drawingState.telestrationObjects = state.telestrationObjects
        drawingState.shapes = state.shapes
        drawingState.textBoxes = state.textBoxes
        drawingState.images = state.images
        drawingState.viewSize = state.viewSize
        drawingState.initialViewSize = state.viewSize
        loaded = true
    }

    private func pickAndAddImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .image]
        panel.prompt = ^String.Titles.editorAddImage
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }

        // Копируем файл в папку проекта под уникальным именем.
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let folder = manager.addedImagesFolder(projectId)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(fileName))

        drawingState.currentTool = .image
        drawingState.addImageObject(fileName: fileName, image: image)
    }

    private func clearSelectionsForRender() {
        drawingState.selectedShapeId = nil
        drawingState.selectedTextBoxId = nil
        drawingState.selectedTelestrationObjectId = nil
        drawingState.selectedImageId = nil
    }

    /// Сплющивает базовую картинку + рисунок + картинки в одно изображение полного разрешения.
    private func flattenedImage() -> NSImage? {
        guard displaySize.width > 0, baseImage.size.width > 0 else { return baseImage }
        clearSelectionsForRender()

        let size = displaySize
        let content = ZStack {
            Image(nsImage: baseImage).resizable().frame(width: size.width, height: size.height)
            DrawingCanvasView(drawingState: drawingState)
            EditorImagesOverlay(drawingState: drawingState, renderMode: true)
        }
        .frame(width: size.width, height: size.height)

        if #available(macOS 13.0, *) {
            let renderer = ImageRenderer(content: content)
            // Рендерим в разрешении оригинала: scale = ширина_оригинала / ширина_на_экране.
            renderer.scale = baseImage.size.width / size.width
            return renderer.nsImage ?? baseImage
        } else {
            let hosting = NSHostingView(rootView: content)
            hosting.frame = CGRect(origin: .zero, size: size)
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return baseImage }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let img = NSImage(size: size)
            img.addRepresentation(rep)
            return img
        }
    }

    private func saveProject() {
        let thumb = flattenedImage()
        manager.saveProject(projectId, drawingState: drawingState, thumbnail: thumb)
    }

    private func downloadImage() {
        saveProject()
        guard let image = flattenedImage(), let png = ImageEditorProjectsManager.pngData(from: image) else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(manager.meta(for: projectId)?.name ?? "image").png"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? png.write(to: url)
            }
        }
    }

    private func calculateDisplaySize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect > containerAspect {
            let width = containerSize.width
            return CGSize(width: width, height: width / imageAspect)
        } else {
            let height = containerSize.height
            return CGSize(width: height * imageAspect, height: height)
        }
    }
}
