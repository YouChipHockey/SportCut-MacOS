//
//  MarkupPlaylistClipEditorView.swift
//  Youchip-Stat
//
//  Редактор рисунка поверх клипа плейлиста внутри окна разметки.
//
//  Когда в главном видео-окне разметки играют клипы панели плейлистов, кнопка «Редактор»
//  открывает не редактор разметки, а ЭТОТ редактор — точную копию редактора из режима
//  просмотра (`SportCutVideoPlayerView.editorModeView`), привязанную к плееру панели
//  (`SportCutPlayerManager`). Благодаря этому рисунок сохраняется на клип
//  (`SportCutEventDrawing`), а не в скриншоты разметки.
//

import SwiftUI
import AppKit

struct MarkupPlaylistClipEditorView: View {
    @ObservedObject var playerManager: SportCutPlayerManager

    /// Кадр окна разметки до открытия редактора — редактор рисуется на весь экран (как в
    /// просмотре и в редакторе разметки), по выходу окно возвращается на место.
    @State private var savedWindowFrame: NSRect?

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    EditorToolsPanel(drawingState: playerManager.editorDrawingState) { tool in
                        playerManager.editorDrawingState.currentTool = tool
                    }
                }
                .frame(minWidth: 180)
                Divider()
                editorCanvasView
                Divider()
                EditorSettingsPanel(drawingState: playerManager.editorDrawingState)
                    .frame(width: 180)
            }
        }
        .onAppear { enterFullscreen() }
        .onDisappear { restoreWindowFrame() }
        // Те же горячие клавиши редактора, что и в окне просмотра (в окне разметки нет
        // SportCutVideoPlayerView, поэтому обработчики ставим здесь).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) { notification in
            guard let resized = notification.object as? NSWindow,
                  resized === NSApp.keyWindow else { return }
            playerManager.editorDrawingState.commitViewSizeScalingNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorCopyKeyPressed)) { _ in
            let state = playerManager.editorDrawingState
            guard state.currentTool == .cursor else { return }
            if let id = state.selectedTelestrationObjectId,
               let obj = state.telestrationObjects.first(where: { $0.id == id }) {
                state.addToCopyBuffer(.telestration(obj))
            } else if let id = state.selectedShapeId,
                      let s = state.shapes.first(where: { $0.id == id }) {
                state.addToCopyBuffer(.shape(s))
            } else if let id = state.selectedTextBoxId,
                      let t = state.textBoxes.first(where: { $0.id == id }) {
                state.addToCopyBuffer(.textBox(t))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorPasteKeyPressed)) { _ in
            let state = playerManager.editorDrawingState
            guard state.currentTool == .cursor, !state.copyBuffer.isEmpty else { return }
            let center = CGPoint(x: state.viewSize.width / 2, y: state.viewSize.height / 2)
            state.pasteFromBuffer(at: center, bufferIndex: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorUndoKeyPressed)) { _ in
            playerManager.editorDrawingState.undo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorEnterKeyPressed)) { _ in
            playerManager.editorDrawingState.handleEditorEnterKey()
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 12) {
            Text(^String.Titles.sportCutDrawing)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(^String.Titles.editorExportDurationLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Text("\(String(format: "%.1f", playerManager.editorDisplayDuration))s")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 40)
                    Stepper("", value: $playerManager.editorDisplayDuration, in: 1.0...10.0, step: 0.5)
                        .labelsHidden()
                }
            }

            Spacer()

            Button(^String.Titles.cancelButtonTitle) {
                playerManager.cancelEditor()
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.secondary)
            .keyboardShortcut(.escape, modifiers: [])

            Button(^String.Titles.saveButtonTitle) {
                playerManager.saveDrawing()
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.blue)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
    }

    private var editorCanvasView: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if let screenshot = playerManager.tempScreenshotImage {
                    let imgSize = screenshot.size
                    let displaySize = calculateDisplaySize(imageSize: imgSize, containerSize: geo.size)

                    Image(nsImage: screenshot)
                        .resizable()
                        .scaledToFit()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .overlay(
                            DrawingCanvasView(drawingState: playerManager.editorDrawingState)
                                .frame(width: displaySize.width, height: displaySize.height)
                        )
                        .onAppear {
                            playerManager.editorDrawingState.updateViewSize(displaySize)
                        }
                        .onChange(of: displaySize) { newSize in
                            playerManager.editorDrawingState.updateViewSize(newSize)
                        }
                }
            }
        }
    }

    private func enterFullscreen() {
        guard let window = WindowsManager.shared.videoWindow?.window else { return }
        savedWindowFrame = window.frame
        window.makeKeyAndOrderFront(nil)
        let target = NSScreen.main?.visibleFrame ?? window.frame
        window.setFrame(target, display: true, animate: true)
    }

    private func restoreWindowFrame() {
        guard let window = WindowsManager.shared.videoWindow?.window,
              let frame = savedWindowFrame else { return }
        window.setFrame(frame, display: true, animate: true)
        savedWindowFrame = nil
    }

    private func calculateDisplaySize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0 && imageSize.height > 0 else { return containerSize }
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let ratio = min(widthRatio, heightRatio)
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    }
}
