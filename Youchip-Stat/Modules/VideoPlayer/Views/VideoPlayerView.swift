//
//  VideoPlayerView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import AppKit

// MARK: - Video Player View

struct VideoPlayerView: View {
    
    @ObservedObject var viewModel: VideoPlayerViewModel
    @ObservedObject var videoManager: VideoPlayerManager
    
    var body: some View {
        GeometryReader { geometry in
            Group {
                if viewModel.state.isEditorMode {
                    editorModeView
                } else {
                    normalModeView
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showScreenshotNameSheet },
            set: { viewModel.action.send(.showScreenshotNameSheet(show: $0)) }
        )) {
            ScreenshotNameSheet { name in
                viewModel.action.send(.saveScreenshot(name: name))
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showTagSelectionSheet },
            set: { viewModel.action.send(.showTagSelectionSheet(show: $0)) }
        )) {
            EditorTagSelectionSheet(
                videoTime: viewModel.state.editorScreenshotVideoTime,
                onSave: { selectedStamps in
                    viewModel.action.send(.saveEditorWithTags(selectedStamps))
                },
                onCancel: {
                    viewModel.action.send(.showTagSelectionSheet(show: false))
                }
            )
        }
        .frame(minWidth: 400, minHeight: 300)
        .onChange(of: viewModel.state.isEditorMode) { isEditor in
            handleEditorModeChange(isEditor: isEditor)
        }
    }
    
    private func handleEditorModeChange(isEditor: Bool) {
        if isEditor {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let window = WindowsManager.shared.videoWindow?.window else { return }
                
                viewModel.action.send(.saveWindowFrame(CGRect(origin: window.frame.origin, size: window.frame.size)))
                let targetFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
                window.setFrame(targetFrame, display: true, animate: true)
            }
        } else {
            viewModel.action.send(.restoreWindowFrame)
        }
    }
    
    // MARK: - Normal Mode View
    
    private var normalModeView: some View {
        VStack(spacing: 0) {
            customNormalToolbar
            
            Divider()
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let player = videoManager.player {
                    GeometryReader { geometry in
                        videoPlayerContent(geometry: geometry, player: player)
                    }
                } else {
                    noVideoContent
                }
            }
        }
    }
    
    // MARK: - Custom Normal Toolbar
    
    private var customNormalToolbar: some View {
        HStack(spacing: 12) {
            telestrationButton
            editorButton
            
            Spacer()
            
            zoomControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(NSColor.windowBackgroundColor)
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
    }
    
    // MARK: - Editor Mode View
    
    private var editorModeView: some View {
        VStack(spacing: 0) {
            customEditorToolbar
            
            Divider()
            
            HStack(spacing: 0) {
                EditorToolsPanel(
                    drawingState: viewModel.state.editorDrawingState,
                    onSelectTool: { tool in
                        viewModel.action.send(.selectEditorTool(tool))
                    }
                )
                
                Divider()
                
                editorVideoContent
                
                Divider()
                
                EditorSettingsPanel(drawingState: viewModel.state.editorDrawingState)
            }
        }
    }
    
    // MARK: - Custom Editor Toolbar
    
    private var customEditorToolbar: some View {
        HStack(spacing: 12) {
            TextField("Screenshot Name", text: Binding(
                get: { viewModel.state.editorScreenshotName },
                set: { viewModel.action.send(.updateEditorName($0)) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 250)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Duration:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Text("\(String(format: "%.1f", viewModel.state.editorDisplayDuration))s")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 45)
                    
                    Stepper("", value: Binding(
                        get: { viewModel.state.editorDisplayDuration },
                        set: { newValue in
                            viewModel.action.send(.updateEditorDisplayDuration(newValue))
                        }
                    ), in: 1.0...10.0, step: 0.5)
                    .labelsHidden()
                }
            }
            
            Spacer()
            
            Button("Cancel") {
                viewModel.action.send(.cancelEditor)
            }
            .keyboardShortcut(.escape, modifiers: [])
            
            // Show "Сохранить на тег" button only if there are intersecting stamps
            if !viewModel.getIntersectingStamps().isEmpty {
                Button("Сохранить на тег") {
                    viewModel.action.send(.showTagSelectionSheet(show: true))
                }
                .buttonStyle(.bordered)
            }
            
            Button("Save") {
                viewModel.action.send(.saveEditor)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(NSColor.windowBackgroundColor)
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
    }
    
    private var editorVideoContent: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let screenshotImage = viewModel.state.tempScreenshotImage {
                    let imageSize = screenshotImage.size
                    let displaySize = calculateDisplaySize(
                        imageSize: imageSize,
                        containerSize: geometry.size
                    )
                    
                    Image(nsImage: screenshotImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .overlay(
                            DrawingCanvasView(drawingState: viewModel.state.editorDrawingState)
                                .frame(width: displaySize.width, height: displaySize.height)
                        )
                        .onAppear {
                            viewModel.state.editorDrawingState.updateViewSize(displaySize)
                        }
                        .onChange(of: displaySize) { newSize in
                            viewModel.state.editorDrawingState.updateViewSize(newSize)
                        }
                }
            }
        }
    }
    
    private func calculateDisplaySize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        
        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }
    
    // MARK: - Video Player Content
    
    private func videoPlayerContent(geometry: GeometryProxy, player: AVPlayer) -> some View {
        ZStack {
            videoPlayerView(geometry: geometry, player: player)
            
            if viewModel.state.isShowingScreenshot, let screenshotImage = viewModel.state.displayedScreenshotImage {
                ZStack {
                    // Черный фон для заполнения пустого пространства
                    Color.black
                        .ignoresSafeArea()
                    
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: screenshotImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .transition(.opacity)
                            .onTapGesture {
                                // Клик по скриншоту закрывает его и продолжает воспроизведение
                                viewModel.action.send(.hideScreenshotAndResume)
                            }
                        
                        // Кнопка закрытия
                        Button(action: {
                            viewModel.action.send(.hideScreenshotAndResume)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(16)
                        .help("Закрыть скриншот и продолжить воспроизведение")
                    }
                }
                .zIndex(10)
            }
            
            if viewModel.state.videoScale > 1.0 {
                joystickView(geometry: geometry)
            }
        }
    }
    
    private func videoPlayerView(geometry: GeometryProxy, player: AVPlayer) -> some View {
        ZStack {
            if viewModel.state.videoScale == 1.0 {
                VideoPlayer(player: player)
                    .scaleEffect(viewModel.state.videoScale)
                    .offset(viewModel.state.videoOffset)
                    .gesture(videoGestures(geometry: geometry))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                CustomVideoPlayer(player: player)
                    .scaleEffect(viewModel.state.videoScale)
                    .offset(viewModel.state.videoOffset)
                    .gesture(videoGestures(geometry: geometry))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    // MARK: - Gestures
    
    private func videoGestures(geometry: GeometryProxy) -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    viewModel.action.send(.handleMagnificationChange(
                        value: value,
                        geometrySize: geometry.size
                    ))
                },
            DragGesture()
                .onChanged { value in
                    viewModel.action.send(.handleDragChange(
                        translation: value.translation,
                        geometrySize: geometry.size
                    ))
                }
                .onEnded { _ in
                    viewModel.action.send(.handleDragEnded)
                }
        )
    }
    
    // MARK: - Toolbar Buttons
    
    private var telestrationButton: some View {
        Button {
            viewModel.action.send(.takeScreenshotForPolygonEditor)
        } label: {
            Text("Telestration")
        }
        .help("Создать скриншот для телестрации")
    }
    
    private var editorButton: some View {
        Button {
            viewModel.action.send(.takeScreenshotForEditor)
        } label: {
            Text("Редактор")
        }
        .help("Открыть редактор")
    }
    
    // MARK: - Zoom Controls
    
    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.action.send(.zoomOut)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(viewModel.state.videoScale <= 1.0)
            .help("Уменьшить масштаб")
            
            Text(String(format: "%.0f%%", viewModel.state.videoScale * 100))
                .font(.system(size: 12, design: .monospaced))
                .frame(minWidth: 45)
            
            Button {
                viewModel.action.send(.zoomIn)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(viewModel.state.videoScale >= 4.0)
            .help("Увеличить масштаб")
            
            if viewModel.state.videoScale > 1.0 {
                Button {
                    viewModel.action.send(.resetZoom)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Сбросить масштаб")
            }
        }
    }
    
    // MARK: - Joystick View
    
    private func joystickView(geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()
            HStack {
                JoystickView(onMove: { direction in
                    viewModel.action.send(.handleJoystickMove(
                        direction: direction,
                        geometrySize: geometry.size
                    ))
                })
                .frame(width: 80, height: 200)
                .padding(.leading, 20)
                Spacer()
            }
            Spacer()
        }
        .transition(.asymmetric(
            insertion: .scale.combined(with: .opacity),
            removal: .scale.combined(with: .opacity)
        ))
        .animation(.easeInOut(duration: 0.3), value: viewModel.state.videoScale > 1.0)
    }
    
    // MARK: - No Video Content
    
    private var noVideoContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.gray.opacity(0.6))
            
            Text(^String.Titles.videoPlayerVideoNotLoaded)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - Joystick View Component

struct JoystickView: View {
    let onMove: (JoystickDirection) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: { onMove(.up) }) {
                joystickButton(systemName: "chevron.up")
            }
            
            HStack(spacing: 12) {
                Button(action: { onMove(.left) }) {
                    joystickButton(systemName: "chevron.left")
                }
                
                Spacer().frame(width: 8)
                
                Button(action: { onMove(.right) }) {
                    joystickButton(systemName: "chevron.right")
                }
            }
            
            Button(action: { onMove(.down) }) {
                joystickButton(systemName: "chevron.down")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
    }
    
    private func joystickButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
            )
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
            .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Custom Video Player

struct CustomVideoPlayer: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        view.layer = playerLayer
        view.wantsLayer = true
        context.coordinator.playerLayer = playerLayer
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let playerLayer = context.coordinator.playerLayer {
            playerLayer.frame = nsView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var playerLayer: AVPlayerLayer?
    }
}

// MARK: - Editor Tag Selection Sheet

struct EditorTagSelectionSheet: View {
    let videoTime: Double
    let onSave: ([TimelineStamp]) -> Void
    let onCancel: () -> Void
    
    @ObservedObject var timelineData = TimelineDataManager.shared
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @State private var selectedStamps: Set<UUID> = []
    
    private var intersectingStamps: [TimelineStamp] {
        var stamps: [TimelineStamp] = []
        
        for line in timelineData.lines {
            for stamp in line.stamps {
                if videoTime >= stamp.timeStartSeconds && videoTime <= stamp.timeFinishSeconds {
                    stamps.append(stamp)
                }
            }
        }
        
        return stamps
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Выберите теги для скриншота")
                .font(.headline)
                .padding(.top)
            
            Text("Время: \(formatTime(videoTime))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if intersectingStamps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tag.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    Text("Нет тегов в этом моменте времени")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(intersectingStamps, id: \.id) { stamp in
                    HStack {
                        Image(systemName: selectedStamps.contains(stamp.id) ? "checkmark.square.fill" : "square")
                            .foregroundColor(selectedStamps.contains(stamp.id) ? .blue : .secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if let tag = tagLibrary.findTagById(stamp.idTag) {
                                Text(tag.name)
                                    .font(.system(size: 14, weight: .medium))
                            } else {
                                Text(stamp.label)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            
                            HStack(spacing: 8) {
                                if let line = timelineData.lines.first(where: { line in
                                    line.stamps.contains(where: { $0.id == stamp.id })
                                }) {
                                    Text(line.name)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                
                                Text("\(formatTime(stamp.timeStartSeconds)) - \(formatTime(stamp.timeFinishSeconds))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedStamps.contains(stamp.id) {
                            selectedStamps.remove(stamp.id)
                        } else {
                            selectedStamps.insert(stamp.id)
                        }
                    }
                }
            }
            
            HStack {
                Button("Отмена", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("Сохранить") {
                    let selected = intersectingStamps.filter { selectedStamps.contains($0.id) }
                    onSave(selected)
                }
                .disabled(selectedStamps.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .onAppear {
            // По умолчанию выбираем все теги
            selectedStamps = Set(intersectingStamps.map { $0.id })
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

