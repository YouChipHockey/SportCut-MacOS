//
//  VideoPlayerViewModel.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Combine
import AVFoundation

// MARK: - Video Player Actions

enum VideoPlayerAction {
    case zoomIn
    case zoomOut
    case resetZoom
    case handleMagnificationChange(value: CGFloat, geometrySize: CGSize)
    case handleDragChange(translation: CGSize, geometrySize: CGSize)
    case handleDragEnded
    case handleJoystickMove(direction: JoystickDirection, geometrySize: CGSize)
    
    case takeScreenshot
    case takeScreenshotForPolygonEditor
    case takeScreenshotForEditor
    case showScreenshotNameSheet(show: Bool)
    case saveScreenshot(name: String)
    
    case openEditor
    case openEditorWindow(imageUrl: URL, screenshotsFolder: URL)
    case openPolygonEditorWindow(image: NSImage)
    
    // Editor Mode Actions
    case cancelEditor
    case saveEditor
    case saveEditorAsTag
    case selectEditorTool(EditorTool)
    case updateEditorName(String)
    case toggleEditorSaveAsTag
    case showTagSelectionSheet(show: Bool)
    case saveEditorWithTags([TimelineStamp])
    case updateEditorDisplayDuration(Double)
    
    // Window Management
    case saveWindowFrame(CGRect)
    case restoreWindowFrame

    // Screenshot Display Control
    case hideScreenshotAndResume
    
    // Telestration
    case addTelestrationObject(DrawableObject)
}

// MARK: - Video Player ViewModel

class VideoPlayerViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var state = VideoPlayerState()
    
    // MARK: - Actions
    
    let action = PassthroughSubject<VideoPlayerAction, Never>()
    private var observables: [AnyCancellable] = []
    
    // MARK: - Dependencies
    
    private var videoId: String
    
    // MARK: - Initialization
    
    init(videoId: String) {
        self.videoId = videoId
        setupActionHandling()
        setupNotificationHandling()
        setupScreenshotTimeObserver()
    }
    
    deinit {
        observables.removeAll()
        state.detectionTimer?.invalidate()
        state.screenshotDisplayTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    
    private func setupActionHandling() {
        action
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                self?.handleAction(action)
            }
            .store(in: &observables)
    }
    
    private func setupNotificationHandling() {
        NotificationCenter.default.addObserver(
            forName: .editorModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let isActive = notification.object as? Bool, !isActive {
                if self?.state.isEditorMode == true {
                    self?.handleCancelEditor()
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .openEditorForScreenshot,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let payload = notification.object as? OpenEditorForScreenshotPayload,
                  payload.videoId == self.videoId else { return }
            self.openEditorForScreenshot(payload: payload)
        }
        
        NotificationCenter.default.addObserver(
            forName: .takeReviewScreenshotForEditor,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.openEditorFromReviewPlayer()
        }
        
        NotificationCenter.default.addObserver(
            forName: .takeReviewScreenshot,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.performTakeScreenshotFromReview()
        }

        NotificationCenter.default.addObserver(
            forName: .videoIdDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let newId = notification.object as? String else { return }
            self.videoId = newId
        }
    }
    
    private func setupScreenshotTimeObserver() {
        Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkForScreenshotAtCurrentTime()
            }
            .store(in: &observables)
    }
    
    private func checkForScreenshotAtCurrentTime() {
        guard !state.isEditorMode else { return }

        // Don't show screenshots while user is resizing a tag
        guard !VideoPlayerManager.shared.isResizingTag else { return }

        let currentTime: Double
        if VideoPlayerManager.shared.isReviewMode {
            currentTime = VideoPlayerManager.shared.reviewCurrentTime
        } else {
            currentTime = VideoPlayerManager.shared.currentTime
        }
        let timeDifference = abs(currentTime - state.lastCheckedVideoTime)
        
        // Если скриншот показан и пользователь нажал play, скрываем скриншот и возобновляем воспроизведение
        if state.isShowingScreenshot {
            let isPlaying: Bool
            if VideoPlayerManager.shared.isReviewMode {
                isPlaying = VideoPlayerManager.shared.reviewPlayer?.timeControlStatus == .playing
            } else {
                isPlaying = (VideoPlayerManager.shared.player?.rate ?? 0) > 0
            }
            if isPlaying {
                hideScreenshotOverlay(resumePlayback: false)
                state.lastCheckedVideoTime = currentTime
            }
            return
        }
        
        state.lastCheckedVideoTime = currentTime
        
        guard !state.isShowingScreenshot else { return }
        
        let screenshots = ScreenshotsMetadataManager.shared.screenshots
        
        if let screenshot = screenshots.first(where: { abs($0.videoTime - currentTime) < 0.15 }) {
            if state.lastShownScreenshotName != screenshot.screenshotName {
                showScreenshotOverlay(metadata: screenshot)
            }
        } else {
            if let lastShown = state.lastShownScreenshotName,
               screenshots.contains(where: { $0.screenshotName == lastShown && abs($0.videoTime - currentTime) >= 0.5 }) {
                state.lastShownScreenshotName = nil
            }
        }
    }
    
    private func showScreenshotOverlay(metadata: ScreenshotMetadata) {
        guard let screenshotsFolder = screenshotsFolderForCurrentVideo() else {
            return
        }

        let imageFileName = metadata.screenshotName.hasSuffix(".png") ? metadata.screenshotName : "\(metadata.screenshotName).png"
        let imageURL = screenshotsFolder.appendingPathComponent(imageFileName)
        
        guard let image = NSImage(contentsOf: imageURL) else { return }
        
        if VideoPlayerManager.shared.isReviewMode {
            VideoPlayerManager.shared.reviewPlayer?.pause()
            VideoPlayerManager.shared.reviewScreenshotImage = image
            VideoPlayerManager.shared.isShowingReviewScreenshot = true
        } else {
            VideoPlayerManager.shared.player?.pause()
        }

        state.displayedScreenshotImage = image
        state.isShowingScreenshot = true
        state.lastShownScreenshotName = metadata.screenshotName

        NotificationCenter.default.post(name: .screenshotDisplayChanged, object: true)

        // Убираем автоматический таймер - пользователь сам должен продолжить воспроизведение
        state.screenshotDisplayTimer?.invalidate()
        state.screenshotDisplayTimer = nil
    }
    
    private func hideScreenshotOverlay(resumePlayback: Bool = false) {
        state.isShowingScreenshot = false
        state.displayedScreenshotImage = nil
        state.screenshotDisplayTimer?.invalidate()
        state.screenshotDisplayTimer = nil

        if VideoPlayerManager.shared.isReviewMode {
            VideoPlayerManager.shared.reviewScreenshotImage = nil
            VideoPlayerManager.shared.isShowingReviewScreenshot = false
        }

        NotificationCenter.default.post(name: .screenshotDisplayChanged, object: false)
        if resumePlayback {
            if VideoPlayerManager.shared.isReviewMode {
                VideoPlayerManager.shared.reviewPlayer?.play()
            } else {
                VideoPlayerManager.shared.player?.play()
            }
        }
    }
    
    // MARK: - Action Handler
    
    private func handleAction(_ action: VideoPlayerAction) {
        switch action {
        case .zoomIn:
            handleZoomIn()
            
        case .zoomOut:
            handleZoomOut()
            
        case .resetZoom:
            state.videoScale = 1.0
            state.videoOffset = .zero
            state.lastDragValue = .zero
            
        case let .handleMagnificationChange(value, geometrySize):
            handleMagnificationChange(value: value, geometrySize: geometrySize)
            
        case let .handleDragChange(translation, geometrySize):
            handleDragChange(translation: translation, geometrySize: geometrySize)
            
        case .handleDragEnded:
            state.lastDragValue = state.videoOffset
            
        case let .handleJoystickMove(direction, geometrySize):
            handleJoystickMove(direction: direction, geometrySize: geometrySize)
            
        case .takeScreenshot:
            performTakeScreenshot()
            
        case .takeScreenshotForPolygonEditor:
            performTakeScreenshotForPolygonEditor()
            
        case .takeScreenshotForEditor:
            performTakeScreenshotForEditor()
            
        case let .showScreenshotNameSheet(show):
            state.showScreenshotNameSheet = show
            
        case let .saveScreenshot(name):
            performSaveScreenshot(name: name)
            
        case .openEditor:
            break
            
        case let .openEditorWindow(imageUrl, screenshotsFolder):
            openEditorInNewWindow(with: imageUrl, screenshotsFolder: screenshotsFolder)
            
        case let .openPolygonEditorWindow(image):
            openPolygonEditorInNewWindow(with: image)
            
        case .cancelEditor:
            handleCancelEditor()
            
        case .saveEditor:
            handleSaveEditor()
            
        case .saveEditorAsTag:
            state.editorSaveAsTag = true
            handleSaveEditor()
            
        case let .selectEditorTool(tool):
            // Сбрасываем телестрацию при переключении инструмента
            if tool != .telestration && (state.editorDrawingState.isCreatingTelestrationObject || state.editorDrawingState.pendingTelestrationObject != nil) {
                state.editorDrawingState.cancelTelestrationObjectCreation()
            }
            // Сбрасываем создание фигуры при переключении инструмента
            if tool != .shapes && (state.editorDrawingState.isCreatingShape || state.editorDrawingState.pendingShape != nil) {
                state.editorDrawingState.cancelShapeCreation()
            }
            // Сбрасываем создание текстового бокса при переключении инструмента
            if tool != .textBox && (state.editorDrawingState.isCreatingTextBox || state.editorDrawingState.pendingTextBox != nil) {
                state.editorDrawingState.cancelTextBoxCreation()
            }
            // Сбрасываем выделение фигуры, текстового бокса и телестрации при переключении инструмента
            let previousTool = state.editorDrawingState.currentTool
            if tool != previousTool {
                state.editorDrawingState.selectedShapeId = nil
                state.editorDrawingState.selectedTextBoxId = nil
                state.editorDrawingState.selectedTelestrationObjectId = nil
                state.editorDrawingState.isAddingPointToTelestration = false
            }
            // Если переключаемся с pencil/arrow на другой инструмент, завершаем текущий путь
            if (previousTool == .pencil || previousTool == .arrow) && tool != .pencil && tool != .arrow {
                state.editorDrawingState.finishPath()
            }
            state.editorDrawingState.currentTool = tool
            
        case let .updateEditorName(name):
            state.editorScreenshotName = name
            
        case .toggleEditorSaveAsTag:
            state.editorSaveAsTag.toggle()
            
        case let .showTagSelectionSheet(show):
            state.showTagSelectionSheet = show
            
        case let .saveEditorWithTags(selectedStamps):
            handleSaveEditorWithTags(selectedStamps)
            
        case let .updateEditorDisplayDuration(duration):
            state.editorDisplayDuration = duration
            
        case let .saveWindowFrame(frame):
            state.savedWindowFrame = frame
            
        case .restoreWindowFrame:
            handleRestoreWindowFrame()
            
        case .hideScreenshotAndResume:
            hideScreenshotOverlay(resumePlayback: true)
            
        case let .addTelestrationObject(object):
            // Объект уже добавлен в массив telestrationObjects в confirmTelestrationObjectCreation
            // Здесь ничего не делаем, так как объект уже в состоянии
            break
        }
    }
    
    // MARK: - Zoom Logic
    
    private func handleZoomIn() {
        let newScale = min(4.0, state.videoScale + 0.1)
        state.videoScale = newScale
        updateVideoOffsetForScale(newScale)
    }
    
    private func handleZoomOut() {
        let newScale = max(1.0, state.videoScale - 0.1)
        state.videoScale = newScale
        updateVideoOffsetForScale(newScale)
    }
    
    private func updateVideoOffsetForScale(_ newScale: CGFloat) {
        if newScale == 1.0 {
            state.videoOffset = .zero
            state.lastDragValue = .zero
        }
    }
    
    // MARK: - Magnification Logic
    
    private func handleMagnificationChange(value: CGFloat, geometrySize: CGSize) {
        let newScale = min(max(1.0, value), 4.0)
        
        if newScale == 1.0 {
            state.videoOffset = .zero
            state.lastDragValue = .zero
        } else {
            let maxOffsetX = (geometrySize.width * (newScale - 1)) / 2
            let maxOffsetY = (geometrySize.height * (newScale - 1)) / 2
            
            state.videoOffset = CGSize(
                width: min(max(state.videoOffset.width, -maxOffsetX), maxOffsetX),
                height: min(max(state.videoOffset.height, -maxOffsetY), maxOffsetY)
            )
            state.lastDragValue = state.videoOffset
        }
        
        state.videoScale = newScale
    }
    
    // MARK: - Drag Logic
    
    private func handleDragChange(translation: CGSize, geometrySize: CGSize) {
        guard state.videoScale > 1.0 else { return }
        
        let newOffset = CGSize(
            width: state.lastDragValue.width + translation.width,
            height: state.lastDragValue.height + translation.height
        )
        
        let maxOffsetX = (geometrySize.width * (state.videoScale - 1)) / 2
        let maxOffsetY = (geometrySize.height * (state.videoScale - 1)) / 2
        
        state.videoOffset = CGSize(
            width: min(max(newOffset.width, -maxOffsetX), maxOffsetX),
            height: min(max(newOffset.height, -maxOffsetY), maxOffsetY)
        )
    }
    
    // MARK: - Joystick Logic
    
    private func handleJoystickMove(direction: JoystickDirection, geometrySize: CGSize) {
        let step: CGFloat = 30
        let maxOffsetX = (geometrySize.width * (state.videoScale - 1)) / 2
        let maxOffsetY = (geometrySize.height * (state.videoScale - 1)) / 2
        
        var newOffset = state.videoOffset
        
        switch direction {
        case .up:
            newOffset.height = min(newOffset.height + step, maxOffsetY)
        case .down:
            newOffset.height = max(newOffset.height - step, -maxOffsetY)
        case .left:
            newOffset.width = min(newOffset.width + step, maxOffsetX)
        case .right:
            newOffset.width = max(newOffset.width - step, -maxOffsetX)
        }
        
        state.videoOffset = newOffset
        state.lastDragValue = newOffset
    }
    
    // MARK: - Screenshot Logic
    
    private func performTakeScreenshot() {
        // In review mode, capture from the review player.
        if VideoPlayerManager.shared.isReviewMode {
            performTakeScreenshotFromReview()
            return
        }
        
        guard let player = VideoPlayerManager.shared.player,
              let asset = player.currentItem?.asset else {
            return
        }
        
        player.pause()
        let currentTime = player.currentTime()
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: currentTime, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            if state.videoScale > 1.0 {
                if let croppedImage = cropImageForZoom(cgImage: cgImage, nsImage: nsImage) {
                    state.tempScreenshotImage = croppedImage
                } else {
                    state.tempScreenshotImage = nsImage
                }
            } else {
                state.tempScreenshotImage = nsImage
            }
            
            state.showScreenshotNameSheet = true
        } catch {
            print(String(format: ^String.Titles.videoPlayerErrorScreenshot, error.localizedDescription))
        }
    }
    
    private func performTakeScreenshotForPolygonEditor() {
        guard let player = VideoPlayerManager.shared.player,
              let asset = player.currentItem?.asset else {
            return
        }
        
        player.pause()
        let currentTime = player.currentTime()
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: currentTime, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            var finalImage = nsImage
            
            if state.videoScale > 1.0 {
                if let croppedImage = cropImageForZoom(cgImage: cgImage, nsImage: nsImage) {
                    finalImage = croppedImage
                }
            }
            
            state.tempScreenshotImage = finalImage
            openPolygonEditorInNewWindow(with: finalImage)
            
        } catch {
            print(String(format: ^String.Titles.videoPlayerErrorScreenshot, error.localizedDescription))
        }
    }
    
    private func cropImageForZoom(cgImage: CGImage, nsImage: NSImage) -> NSImage? {
        let imgWidth = CGFloat(cgImage.width)
        let imgHeight = CGFloat(cgImage.height)
        let viewSize = NSScreen.main?.frame.size ?? NSSize(width: imgWidth, height: imgHeight)
        
        let scaleX = imgWidth / viewSize.width
        let scaleY = imgHeight / viewSize.height
        
        let visibleWidth = viewSize.width / state.videoScale
        let visibleHeight = viewSize.height / state.videoScale
        
        let centerX = imgWidth / 2.0 - state.videoOffset.width * scaleX
        let centerY = imgHeight / 2.0 - state.videoOffset.height * scaleY
        
        let cropRect = CGRect(
            x: centerX - visibleWidth * scaleX / 2.0,
            y: centerY - visibleHeight * scaleY / 2.0,
            width: visibleWidth * scaleX,
            height: visibleHeight * scaleY
        ).integral
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }
        
        let finalSize = NSSize(width: viewSize.width, height: viewSize.height)
        let croppedNSImage = NSImage(size: finalSize)
        croppedNSImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: croppedCGImage, size: cropRect.size)
            .draw(in: NSRect(origin: .zero, size: finalSize),
                  from: NSRect(origin: .zero, size: cropRect.size),
                  operation: .copy, fraction: 1.0)
        croppedNSImage.unlockFocus()
        
        return croppedNSImage
    }
    
    private func performSaveScreenshot(name: String) {
        guard let nsImage = state.tempScreenshotImage,
              let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == videoId }) else {
            return
        }
        
        let screenshotsFolder = filesFile.screenshotsFolder
        let fileName = name.hasSuffix(".png") ? name : "\(name).png"
        let fileURL = screenshotsFolder.appendingPathComponent(fileName)
        
        if let imageData = nsImage.pngData() {
            try? imageData.write(to: fileURL)
            state.screenshotImage = fileURL
            openEditorInNewWindow(with: fileURL, screenshotsFolder: screenshotsFolder)
        }
    }
    
    private func performTakeScreenshotForEditor() {
        // Источник кадра и времени определяет ОКНО, из которого открыли редактор, а не то, каким
        // плейхедом сейчас ведут разметку. Это действие приходит только из окна разметки (кнопка
        // «Редактор»), поэтому в лайве берём ЖИВОЙ кадр и время лайва — даже когда открыт
        // пересмотр и включена «Разметка пересмотра». У окна пересмотра свой вход:
        // `.takeReviewScreenshotForEditor` → `openEditorFromReviewPlayer` (кадр и время пересмотра).
        if VideoPlayerManager.shared.isLiveMode {
            openEditorFromLiveFrame()
            return
        }
        
        guard let player = VideoPlayerManager.shared.player,
              let asset = player.currentItem?.asset else {
            return
        }
        
        player.pause()
        let currentTime = player.currentTime()
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: currentTime, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            state.tempScreenshotImage = nsImage
            state.isEditorMode = true
            state.editorScreenshotName = "Screenshot_\(Date().timeIntervalSince1970)"
            state.editorDrawingState.clearDrawing()
            state.editorDrawingState.currentTool = .pencil // Всегда выбираем карандаш при открытии редактора
            
            state.editorScreenshotVideoTime = CMTimeGetSeconds(currentTime)
            NotificationCenter.default.post(name: .editorModeChanged, object: true)
            
        } catch {
            print("Error taking screenshot for editor: \(error.localizedDescription)")
        }
    }
    
    /// Захватывает кадр из reviewPlayer и открывает редактор в главном видео-окне.
    private func openEditorFromReviewPlayer() {
        guard let reviewPlayer = VideoPlayerManager.shared.reviewPlayer,
              let asset = reviewPlayer.currentItem?.asset else { return }
        
        let currentTime = reviewPlayer.currentTime()
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: currentTime, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            state.tempScreenshotImage = nsImage
            state.isEditorMode = true
            state.editorScreenshotName = "Screenshot_\(Date().timeIntervalSince1970)"
            state.editorDrawingState.clearDrawing()
            state.editorDrawingState.currentTool = .pencil
            state.editorScreenshotVideoTime = VideoPlayerManager.shared.reviewCurrentTime
            NotificationCenter.default.post(name: .editorModeChanged, object: true)
        } catch {
            print("Error capturing review player frame: \(error.localizedDescription)")
        }
    }
    
    /// Делает скриншот из текущего кадра reviewPlayer (аналог takeScreenshot для режима пересмотра).
    private func performTakeScreenshotFromReview() {
        guard let reviewPlayer = VideoPlayerManager.shared.reviewPlayer,
              let asset = reviewPlayer.currentItem?.asset else { return }
        
        let currentTime = reviewPlayer.currentTime()
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: currentTime, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            state.tempScreenshotImage = nsImage
            state.showScreenshotNameSheet = true
        } catch {
            print("Error capturing review player frame for screenshot: \(error.localizedDescription)")
        }
    }
    
    /// Открыть редактор из текущего кадра real-time трансляции (пауза трансляции выполняется в VideoPlayerView при смене isEditorMode).
    private func openEditorFromLiveFrame() {
        guard let nsImage = LiveStreamManager.shared.captureCurrentFrame() else {
            print("Error capturing live frame for editor")
            return
        }
        state.tempScreenshotImage = nsImage
        state.isEditorMode = true
        state.editorScreenshotName = "Screenshot_\(Date().timeIntervalSince1970)"
        state.editorDrawingState.clearDrawing()
        state.editorDrawingState.currentTool = .pencil
        // Фиксируем время открытия редактора — при сохранении тег и метаданные привяжутся к этому моменту, а не к текущему времени трансляции
        state.editorScreenshotVideoTime = VideoPlayerManager.shared.currentTime
        NotificationCenter.default.post(name: .editorModeChanged, object: true)
    }
    
    /// Открыть редактор для ранее сохранённого скриншота: в обычном режиме — кадр с видео + метаданные; в live — загружаем сохранённую картинку из папки.
    private func openEditorForScreenshot(payload: OpenEditorForScreenshotPayload) {
        let screenshot = payload.screenshot
        let name = screenshot.screenshotName.hasSuffix(".png") ? String(screenshot.screenshotName.dropLast(4)) : screenshot.screenshotName
        
        if VideoPlayerManager.shared.isLiveMode {
            openEditorForScreenshotInLiveMode(screenshot: screenshot, name: name, screenshotsFolder: payload.screenshotsFolder)
            return
        }
        
        guard let player = VideoPlayerManager.shared.player,
              let asset = player.currentItem?.asset else {
            print("❌ Нет воспроизведения видео для кадра при повторном редактировании")
            return
        }
        
        VideoPlayerManager.shared.seek(to: screenshot.videoTime)
        VideoPlayerManager.shared.player?.pause()
        
        // База — кадр с видео в момент времени рисунка, не сохранённая картинка (без наложенных объектов)
        let time = CMTime(seconds: screenshot.videoTime, preferredTimescale: 600)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        guard let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil) else {
            print("❌ Не удалось получить кадр видео для редактирования")
            return
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        state.tempScreenshotImage = image
        state.editorScreenshotName = name
        state.editorScreenshotVideoTime = screenshot.videoTime
        state.editorDisplayDuration = screenshot.displayDuration
        state.isEditingExistingScreenshot = true
        state.editorDrawingState.clearDrawing()
        
        if let editorState = screenshot.editorState {
            editorState.apply(to: state.editorDrawingState)
        } else {
            state.editorDrawingState.currentTool = .pencil
        }
        
        state.isEditorMode = true
        NotificationCenter.default.post(name: .editorModeChanged, object: true)
    }
    
    /// В live нет видео-файла — открываем редактор: база всегда «чистый» кадр (_base.png), поверх накладываются метаданные.
    private func openEditorForScreenshotInLiveMode(screenshot: ScreenshotMetadata, name: String, screenshotsFolder: URL) {
        let nameNorm = name.replacingOccurrences(of: ".png", with: "")
        let baseFileName = "\(nameNorm)_base.png"
        let baseURL = screenshotsFolder.appendingPathComponent(baseFileName)
        let imageURL = screenshotsFolder.appendingPathComponent(screenshot.screenshotName.hasSuffix(".png") ? screenshot.screenshotName : "\(screenshot.screenshotName).png")
        // Сначала пробуем загрузить исходный кадр без рисунков — на него накладываются метаданные
        let image: NSImage?
        if FileManager.default.fileExists(atPath: baseURL.path), let baseImage = NSImage(contentsOf: baseURL) {
            image = baseImage
        } else if let fallback = NSImage(contentsOf: imageURL) {
            image = fallback
        } else {
            image = nil
        }
        guard let image = image else {
            print("❌ Не удалось загрузить изображение для редактирования в live: \(imageURL.path)")
            return
        }
        state.tempScreenshotImage = image
        state.editorScreenshotName = name
        state.editorScreenshotVideoTime = screenshot.videoTime
        state.editorDisplayDuration = screenshot.displayDuration
        state.isEditingExistingScreenshot = true
        state.editorDrawingState.clearDrawing()
        if let editorState = screenshot.editorState {
            editorState.apply(to: state.editorDrawingState)
        } else {
            state.editorDrawingState.currentTool = .pencil
        }
        state.isEditorMode = true
        NotificationCenter.default.post(name: .editorModeChanged, object: true)
    }
    
    // MARK: - Editor Mode
    
    private func handleCancelEditor() {
        // Сбрасываем все pending объекты перед выходом
        if state.editorDrawingState.pendingShape != nil {
            state.editorDrawingState.cancelShapeCreation()
        }
        if state.editorDrawingState.pendingTelestrationObject != nil {
            state.editorDrawingState.cancelTelestrationObjectCreation()
        }
        if state.editorDrawingState.pendingTextBox != nil {
            state.editorDrawingState.cancelTextBoxCreation()
        }
        if state.editorDrawingState.isCreatingTelestrationObject {
            state.editorDrawingState.cancelTelestrationObjectCreation()
        }
        if state.editorDrawingState.isCreatingShape {
            state.editorDrawingState.cancelShapeCreation()
        }
        if state.editorDrawingState.isCreatingTextBox {
            state.editorDrawingState.cancelTextBoxCreation()
        }
        
        state.isEditorMode = false
        state.isEditingExistingScreenshot = false
        state.editorScreenshotName = ""
        state.editorSaveAsTag = false
        state.tempScreenshotImage = nil
        state.editorDrawingState.clearDrawing()
        state.editorScreenshotVideoTime = 0.0
        state.showTagSelectionSheet = false
        // Сбрасываем инструмент на карандаш при выходе из режима редактирования
        state.editorDrawingState.currentTool = .pencil
        
        NotificationCenter.default.post(name: .editorModeChanged, object: false)
    }
    
    /// Папка скриншотов для текущего видео: для live — Documents/Screenshots/videoId, иначе из VideoFilesManager.
    private func screenshotsFolderForCurrentVideo() -> URL? {
        if VideoPlayerManager.shared.isLiveMode {
            guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
            let folder = documentsDir.appendingPathComponent("Screenshots").appendingPathComponent(videoId)
            if !FileManager.default.fileExists(atPath: folder.path) {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            return folder
        }
        return VideoFilesManager.shared.files.first(where: { $0.videoData.id == videoId })?.screenshotsFolder
    }
    
    private func handleSaveEditor() {
        guard let nsImage = state.tempScreenshotImage,
              let screenshotsFolder = screenshotsFolderForCurrentVideo() else {
            handleCancelEditor()
            return
        }
        
        let currentVideoTime = state.editorScreenshotVideoTime
        let nameNorm = state.editorScreenshotName.replacingOccurrences(of: ".png", with: "")
        let fileName = state.editorScreenshotName.hasSuffix(".png") ? state.editorScreenshotName : "\(state.editorScreenshotName).png"
        let fileURL = screenshotsFolder.appendingPathComponent(fileName)
        
        let finalImage = mergeDrawingWithImage(baseImage: nsImage, drawingState: state.editorDrawingState)
        let editorSnapshot = EditorStateSnapshot.from(drawingState: state.editorDrawingState)
        
        if state.isEditingExistingScreenshot {
            // Обновление существующего рисунка: перезапись файла, метаданные с сохранением привязок, без нового тега
            if let imageData = finalImage.pngData() {
                try? imageData.write(to: fileURL)
            }
            updateExistingScreenshotMetadata(
                screenshotName: nameNorm,
                displayDuration: state.editorDisplayDuration,
                editorState: editorSnapshot,
                screenshotsFolder: screenshotsFolder
            )
            ScreenshotsMetadataManager.shared.loadScreenshots(from: screenshotsFolder)
        } else {
            // Новый рисунок: сохраняем картинку, создаём тег, пишем метаданные
            if let imageData = finalImage.pngData() {
                try? imageData.write(to: fileURL)
                state.screenshotImage = fileURL
            }
            // В live сохраняем ещё «чистый» кадр без рисунков — база для повторного редактирования (метаданные накладываются на неё)
            if VideoPlayerManager.shared.isLiveMode, let baseData = nsImage.pngData() {
                let baseURL = screenshotsFolder.appendingPathComponent("\(nameNorm)_base.png")
                try? baseData.write(to: baseURL)
            }
            let createdStampId = addScreenshotAsTag(
                screenshotName: state.editorScreenshotName,
                videoTime: currentVideoTime
            )
            let relatedStampIds = createdStampId != nil ? [createdStampId!] : []
            saveScreenshotMetadata(
                screenshotName: state.editorScreenshotName,
                videoTime: currentVideoTime,
                displayDuration: state.editorDisplayDuration,
                relatedStampIds: relatedStampIds,
                screenshotsFolder: screenshotsFolder,
                editorState: editorSnapshot
            )
            ScreenshotsMetadataManager.shared.loadScreenshots(from: screenshotsFolder)
        }
        
        // Сбрасываем все pending объекты перед выходом
        if state.editorDrawingState.pendingShape != nil {
            state.editorDrawingState.cancelShapeCreation()
        }
        if state.editorDrawingState.pendingTelestrationObject != nil {
            state.editorDrawingState.cancelTelestrationObjectCreation()
        }
        if state.editorDrawingState.pendingTextBox != nil {
            state.editorDrawingState.cancelTextBoxCreation()
        }
        if state.editorDrawingState.isCreatingTelestrationObject {
            state.editorDrawingState.cancelTelestrationObjectCreation()
        }
        if state.editorDrawingState.isCreatingShape {
            state.editorDrawingState.cancelShapeCreation()
        }
        if state.editorDrawingState.isCreatingTextBox {
            state.editorDrawingState.cancelTextBoxCreation()
        }
        
        handleCancelEditor()
    }
    
    private func handleSaveEditorWithTags(_ selectedStamps: [TimelineStamp]) {
        if state.isEditingExistingScreenshot {
            state.showTagSelectionSheet = false
            handleSaveEditor()
            return
        }
        guard let nsImage = state.tempScreenshotImage,
              let screenshotsFolder = screenshotsFolderForCurrentVideo() else {
            handleCancelEditor()
            return
        }
        
        let currentVideoTime = state.editorScreenshotVideoTime
        let fileName = state.editorScreenshotName.hasSuffix(".png") ? state.editorScreenshotName : "\(state.editorScreenshotName).png"
        let fileURL = screenshotsFolder.appendingPathComponent(fileName)
        
        let finalImage = mergeDrawingWithImage(baseImage: nsImage, drawingState: state.editorDrawingState)
        
        if let imageData = finalImage.pngData() {
            try? imageData.write(to: fileURL)
            state.screenshotImage = fileURL
            
            let nameNorm = state.editorScreenshotName.replacingOccurrences(of: ".png", with: "")
            if VideoPlayerManager.shared.isLiveMode, let baseData = nsImage.pngData() {
                let baseURL = screenshotsFolder.appendingPathComponent("\(nameNorm)_base.png")
                try? baseData.write(to: baseURL)
            }
            
            // Always create a tag on Screenshots timeline and get its stamp ID
            let createdStampId = addScreenshotAsTag(
                screenshotName: state.editorScreenshotName,
                videoTime: currentVideoTime
            )
            
            // Save with selected stamps PLUS the created screenshot tag
            var stampIds = selectedStamps.map { $0.id }
            if let createdId = createdStampId {
                // Add the created tag to the beginning of the list
                stampIds.insert(createdId, at: 0)
            }
            
            let editorSnapshot = EditorStateSnapshot.from(drawingState: state.editorDrawingState)
            saveScreenshotMetadata(
                screenshotName: state.editorScreenshotName,
                videoTime: currentVideoTime,
                displayDuration: state.editorDisplayDuration,
                relatedStampIds: stampIds,
                screenshotsFolder: screenshotsFolder,
                editorState: editorSnapshot
            )
            
            ScreenshotsMetadataManager.shared.loadScreenshots(from: screenshotsFolder)
        }
        
        // Close the tag selection sheet
        state.showTagSelectionSheet = false
        
        // Сбрасываем все pending объекты перед выходом
        if state.editorDrawingState.pendingShape != nil {
            state.editorDrawingState.cancelShapeCreation()
        }
        if state.editorDrawingState.pendingTelestrationObject != nil {
            state.editorDrawingState.cancelTelestrationObjectCreation()
        }
        if state.editorDrawingState.pendingTextBox != nil {
            state.editorDrawingState.cancelTextBoxCreation()
        }
        if state.editorDrawingState.isCreatingTelestrationObject {
            state.editorDrawingState.cancelTelestrationObjectCreation()
        }
        if state.editorDrawingState.isCreatingShape {
            state.editorDrawingState.cancelShapeCreation()
        }
        if state.editorDrawingState.isCreatingTextBox {
            state.editorDrawingState.cancelTextBoxCreation()
        }
        
        handleCancelEditor()
    }
    
    // Helper method to get intersecting stamps at current video time (для кнопки «Сохранить на тег»).
    // Не учитываем теги с таймлайна «Рисунки» и теги, у которых название совпадает с именем текущего рисунка.
    func getIntersectingStamps() -> [TimelineStamp] {
        let videoTime = state.editorScreenshotVideoTime
        let screenshotName = state.editorScreenshotName.replacingOccurrences(of: ".png", with: "")
        var stamps: [TimelineStamp] = []
        
        let timelineData = TimelineDataManager.shared
        for line in timelineData.lines {
            // Исключаем служебные таймлайны («Рисунки», счётчики)
            if line.isServiceTimeline { continue }
            for stamp in line.stamps {
                if videoTime >= stamp.timeStartSeconds && videoTime <= stamp.timeFinishSeconds {
                    // Исключаем тег, если его название совпадает с именем рисунка
                    let stampLabelNorm = stamp.label.replacingOccurrences(of: ".png", with: "")
                    if stampLabelNorm == screenshotName { continue }
                    stamps.append(stamp)
                }
            }
        }
        
        return stamps
    }
    
    private func saveScreenshotMetadata(screenshotName: String, videoTime: Double, displayDuration: Double, relatedStampIds: [UUID], screenshotsFolder: URL, editorState: EditorStateSnapshot? = nil) {
        print("💾 Сохранение метаданных скриншота '\(screenshotName)' с displayDuration = \(displayDuration) секунд")
        
        let metadata = ScreenshotMetadata(
            screenshotName: screenshotName,
            videoTime: videoTime,
            createdAt: Date(),
            saveAsTag: false, // No longer used but kept for backward compatibility
            displayDuration: displayDuration,
            relatedStampIds: relatedStampIds,
            editorState: editorState
        )
        
        let metadataFileName = "\(screenshotName).json"
        let metadataURL = screenshotsFolder.appendingPathComponent(metadataFileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(metadata)
            try data.write(to: metadataURL)
            print("✅ Метаданные успешно сохранены: \(metadataURL.path)")
        } catch {
            print("❌ Error saving screenshot metadata: \(error.localizedDescription)")
        }
    }
    
    /// Обновление метаданных существующего рисунка: сохраняем привязки и время, обновляем displayDuration и editorState.
    private func updateExistingScreenshotMetadata(screenshotName: String, displayDuration: Double, editorState: EditorStateSnapshot?, screenshotsFolder: URL) {
        let nameNorm = screenshotName.replacingOccurrences(of: ".png", with: "")
        let metadataURL = screenshotsFolder.appendingPathComponent("\(nameNorm).json")
        
        let existing: ScreenshotMetadata?
        if let data = try? Data(contentsOf: metadataURL),
           let decoded = try? JSONDecoder().decode(ScreenshotMetadata.self, from: data) {
            existing = decoded
        } else {
            existing = ScreenshotsMetadataManager.shared.screenshots.first { $0.screenshotName.replacingOccurrences(of: ".png", with: "") == nameNorm }
        }
        
        let metadata: ScreenshotMetadata
        if let prev = existing {
            metadata = ScreenshotMetadata(
                screenshotName: prev.screenshotName,
                videoTime: prev.videoTime,
                createdAt: prev.createdAt,
                saveAsTag: prev.saveAsTag,
                displayDuration: displayDuration,
                relatedStampIds: prev.relatedStampIds,
                editorState: editorState
            )
        } else {
            metadata = ScreenshotMetadata(
                screenshotName: nameNorm,
                videoTime: state.editorScreenshotVideoTime,
                createdAt: Date(),
                saveAsTag: false,
                displayDuration: displayDuration,
                relatedStampIds: [],
                editorState: editorState
            )
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(metadata)
            try data.write(to: metadataURL)
            print("✅ Метаданные рисунка обновлены: \(nameNorm)")
        } catch {
            print("❌ Ошибка обновления метаданных: \(error.localizedDescription)")
        }
    }
    
    @discardableResult
    private func addScreenshotAsTag(screenshotName: String, videoTime: Double) -> UUID? {
        let timelineData = TimelineDataManager.shared
        let tagLibrary = TagLibraryManager.shared
        
        let screenshotsLineID = ensureScreenshotsTimelineExists()
        ensureScreenshotsTagGroupExists()
        
        let videoDuration = max(1.0, VideoPlayerManager.shared.timelineDuration)
        let startTime = max(0, videoTime - 3.0)
        let endTime = min(videoDuration, videoTime + 3.0)
        
        let tagID = "screenshot_\(screenshotName)_\(UUID().uuidString)"
        addTagToScreenshotsGroup(tagID: tagID)
        guard let lineIndex = timelineData.lines.firstIndex(where: { $0.id == screenshotsLineID }) else {
            return nil
        }
        
        let stamp = TimelineStamp(
            tagRefs: [StampTagRef(id: tagID, tagGroupId: "")],
            primaryID: nil,
            timeStartSeconds: startTime,
            timeFinishSeconds: endTime,
            colorHex: "808080",
            label: screenshotName,
            labels: [],
            timeEvents: []
        )
        
        timelineData.lines[lineIndex].stamps.append(stamp)
        timelineData.updateTimelines()
        NotificationCenter.default.post(name: .stampCountsChanged, object: nil)
        
        return stamp.id
    }
    
    private func ensureScreenshotsTagGroupExists() {
        let tagLibrary = TagLibraryManager.shared
        
        if !tagLibrary.allTagGroups.contains(where: { $0.id == ScreenshotConstants.screenshotsGroupID }) {
            let screenshotsGroup = TagGroup(
                id: ScreenshotConstants.screenshotsGroupID,
                name: ScreenshotConstants.screenshotsGroupName,
                tags: []
            )
            tagLibrary.allTagGroups.append(screenshotsGroup)
        }
    }
    
    private func addTagToScreenshotsGroup(tagID: String) {
        let tagLibrary = TagLibraryManager.shared
        
        if let groupIndex = tagLibrary.allTagGroups.firstIndex(where: { $0.id == ScreenshotConstants.screenshotsGroupID }) {
            var group = tagLibrary.allTagGroups[groupIndex]
            
            if !group.tags.contains(tagID) {
                group.tags.append(tagID)
                tagLibrary.allTagGroups[groupIndex] = group
            }
        }
    }
    
    @discardableResult
    private func ensureScreenshotsTimelineExists() -> UUID {
        let timelineData = TimelineDataManager.shared
        let screenshotsID = ScreenshotConstants.screenshotsTimelineID
        
        if let existingLine = timelineData.lines.first(where: { $0.id == screenshotsID }) {
            if let index = timelineData.lines.firstIndex(where: { $0.id == screenshotsID }), index != 0 {
                let line = timelineData.lines.remove(at: index)
                timelineData.lines.insert(line, at: 0)
                timelineData.updateTimelines()
            }
            return existingLine.id
        }
        
        let screenshotsLine = TimelineLine(id: screenshotsID, name: ScreenshotConstants.screenshotsGroupName, stamps: [], tagIdForMode: "")
        timelineData.lines.insert(screenshotsLine, at: 0)
        timelineData.updateTimelines()
        
        return screenshotsID
    }
    
    private func mergeDrawingWithImage(baseImage: NSImage, drawingState: EditorDrawingState) -> NSImage {
        let size = baseImage.size
        let finalImage = NSImage(size: size)
        
        finalImage.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: size))
        
        // Рисуем пути
        for path in drawingState.completedPaths {
            drawPathOnImage(path, in: NSRect(origin: .zero, size: size), viewSize: drawingState.viewSize)
        }
        if !drawingState.currentPath.points.isEmpty {
            drawPathOnImage(drawingState.currentPath, in: NSRect(origin: .zero, size: size), viewSize: drawingState.viewSize)
        }
        
        // Рисуем объекты телестрации
        for object in drawingState.telestrationObjects {
            drawTelestrationObjectOnImage(object, in: NSRect(origin: .zero, size: size), viewSize: drawingState.viewSize)
        }
        
        // Рисуем фигуры
        for shape in drawingState.shapes {
            drawShapeOnImage(shape, in: NSRect(origin: .zero, size: size), viewSize: drawingState.viewSize)
        }
        
        // Рисуем текстовые боксы
        for textBox in drawingState.textBoxes {
            drawTextBoxOnImage(textBox, in: NSRect(origin: .zero, size: size), viewSize: drawingState.viewSize)
        }
        
        finalImage.unlockFocus()
        return finalImage
    }
    
    private func drawPathOnImage(_ path: EditorDrawingPath, in rect: NSRect, viewSize: CGSize) {
        guard path.points.count > 1 else { return }
        
        let bezierPath = NSBezierPath()
        
        let scaleX = viewSize.width > 0 ? rect.width / viewSize.width : 1.0
        let scaleY = viewSize.height > 0 ? rect.height / viewSize.height : 1.0
        let scale = max(scaleX, scaleY)
        
        let scaledX = path.points[0].x * scaleX
        let scaledY = path.points[0].y * scaleY
        let flippedFirstPoint = CGPoint(x: scaledX, y: rect.height - scaledY)
        bezierPath.move(to: flippedFirstPoint)
        
        var scaledPoints: [CGPoint] = [flippedFirstPoint]
        for point in path.points.dropFirst() {
            let scaledX = point.x * scaleX
            let scaledY = point.y * scaleY
            let flippedPoint = CGPoint(x: scaledX, y: rect.height - scaledY)
            bezierPath.line(to: flippedPoint)
            scaledPoints.append(flippedPoint)
        }
        
        NSColor(path.color).setStroke()
        bezierPath.lineWidth = path.lineWidth * scale
        bezierPath.lineCapStyle = .round
        bezierPath.lineJoinStyle = .round
        
        if let dashPattern = path.lineStyle.dashPattern {
            let baseLineWidth: CGFloat = 3
            let widthScale = max(1, path.lineWidth / baseLineWidth)
            let scaledDashPattern = dashPattern.map { $0 * scale * widthScale }
            bezierPath.setLineDash(scaledDashPattern, count: scaledDashPattern.count, phase: 0)
        }
        
        bezierPath.stroke()
        
        // Рисуем стрелочку на конце пути, если нужно
        if path.hasArrow && scaledPoints.count >= 2 {
            drawArrowHeadOnImage(path: path, scaledPoints: scaledPoints, scale: scale, in: rect)
        }
    }
    
    private func drawArrowHeadOnImage(path: EditorDrawingPath, scaledPoints: [CGPoint], scale: CGFloat, in rect: NSRect) {
        guard scaledPoints.count >= 2 else { return }
        
        let lastPoint = scaledPoints[scaledPoints.count - 1]
        
        // Используем несколько последних точек для более стабильного направления
        // Берем больше точек для более плавного направления (15-20 точек или минимум 10)
        let pointsToUse = min(20, max(10, scaledPoints.count))
        let startIndex = max(0, scaledPoints.count - pointsToUse)
        let referencePoint = scaledPoints[startIndex]
        
        // Вычисляем направление стрелки на основе более длинного сегмента
        let dx = lastPoint.x - referencePoint.x
        let dy = lastPoint.y - referencePoint.y
        
        // Если сегмент слишком короткий, используем среднее направление по нескольким последним точкам
        let distance = sqrt(dx * dx + dy * dy)
        let angle: CGFloat
        if distance < 30 * scale {
            // Для коротких сегментов усредняем направление по последним 5-7 точкам
            let avgPoints = min(7, max(3, scaledPoints.count))
            var sumDx: CGFloat = 0
            var sumDy: CGFloat = 0
            for i in max(1, scaledPoints.count - avgPoints)..<scaledPoints.count {
                let prevPoint = scaledPoints[i - 1]
                let currPoint = scaledPoints[i]
                sumDx += currPoint.x - prevPoint.x
                sumDy += currPoint.y - prevPoint.y
            }
            angle = atan2(sumDy, sumDx)
        } else {
            angle = atan2(dy, dx)
        }
        
        // Размер стрелки зависит от ширины линии
        let arrowLength = path.lineWidth * scale * 3
        let arrowWidth = path.lineWidth * scale * 2
        
        // Создаем путь стрелки
        let arrowPath = NSBezierPath()
        let arrowTip = lastPoint
        
        // Вычисляем точки стрелки
        let arrowPoint1 = CGPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle + .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle + .pi / 2)
        )
        let arrowPoint2 = CGPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle - .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle - .pi / 2)
        )
        
        arrowPath.move(to: arrowTip)
        arrowPath.line(to: arrowPoint1)
        arrowPath.line(to: arrowPoint2)
        arrowPath.close()
        
        // Рисуем стрелку
        NSColor(path.color).setFill()
        arrowPath.fill()
        NSColor(path.color).setStroke()
        arrowPath.lineWidth = path.lineWidth * scale
        arrowPath.stroke()
    }
    
    // MARK: - Window Management
    
    private func handleRestoreWindowFrame() {
        guard let savedFrame = state.savedWindowFrame else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let window = WindowsManager.shared.videoWindow?.window else { return }
            
            window.setFrame(NSRect(x: savedFrame.origin.x, y: savedFrame.origin.y, width: savedFrame.width, height: savedFrame.height), display: true, animate: false)
            self?.state.savedWindowFrame = nil
        }
    }
    
    private func openEditorInNewWindow(with imageUrl: URL, screenshotsFolder: URL) {
        let editorViewModel = EditorViewModel(file: imageUrl, screenshotsFolder: screenshotsFolder)
        
        let editorView = EditorView()
            .environmentObject(editorViewModel)
        
        let hostingController = FirstMouseHostingController(rootView: editorView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = ^String.Titles.editScreenshot
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    
    private func openPolygonEditorInNewWindow(with nsImage: NSImage) {
        let polygonEditorViewModel = PolygonEditorViewModel(image: nsImage)
        let polygonEditorView = PolygonEditorView()
            .environmentObject(polygonEditorViewModel)
        
        let hostingController = FirstMouseHostingController(rootView: polygonEditorView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "polygonEditorTitle"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSScreen.main?.frame.size ?? NSSize(width: 1200, height: 800))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    
    // MARK: - Telestration
    
    private func drawTelestrationObjectOnImage(_ object: DrawableObject, in rect: NSRect, viewSize: CGSize) {
        // Convert view coordinates to image coordinates
        let scaleX = rect.width / viewSize.width
        let scaleY = rect.height / viewSize.height
        let scale = max(scaleX, scaleY) // Используем максимальный масштаб для сохранения пропорций
        
        var scaledObject = object
        scaledObject.positions = object.positions.map { point in
            // Инвертируем Y координату для правильной конвертации (SwiftUI -> Core Graphics)
            // В SwiftUI Y идет сверху вниз, в Core Graphics - снизу вверх
            // Инвертируем относительно rect.height, а не viewSize.height
            CGPoint(x: point.x * scaleX, y: rect.height - (point.y * scaleY))
        }
        // Контрольная точка закруглённой стрелки тоже в координатах вида — переводим в пространство изображения
        if let cp = object.controlPoint {
            scaledObject.controlPoint = CGPoint(x: cp.x * scaleX, y: rect.height - (cp.y * scaleY))
        }
        
        // Масштабируем радиус для objectHighlight
        if object.type == .objectHighlight {
            scaledObject.radius = object.radius * scale
        }
        
        switch scaledObject.type {
        case .zoneBetweenObjects:
            drawZoneBetweenObjectsOnImage(scaledObject, scale: scale)
        case .lineBetweenObjects:
            drawLineBetweenObjectsOnImage(scaledObject, scale: scale)
        case .lineWithArrow:
            drawLineWithArrowOnImage(scaledObject, scale: scale)
        case .curvedArrow:
            drawCurvedArrowOnImage(scaledObject, scale: scale, scaleX: scaleX, scaleY: scaleY)
        case .objectHighlight:
            drawObjectHighlightOnImage(scaledObject)
        case .simpleZone:
            drawSimpleZoneOnImage(scaledObject, scale: scale)
        }
    }
    
    private func drawZoneBetweenObjectsOnImage(_ object: DrawableObject, scale: CGFloat) {
        guard object.positions.count >= 3 else { return }
        
        let path = NSBezierPath()
        path.move(to: NSPoint(x: object.positions[0].x, y: object.positions[0].y))
        for position in object.positions.dropFirst() {
            path.line(to: NSPoint(x: position.x, y: position.y))
        }
        path.close()
        
        NSColor(object.fillColor).withAlphaComponent(0.3).setFill()
        path.fill()
        
        NSColor(object.edgeColor).withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2 * scale
        
        if object.lineStyle == .dashed {
            path.setLineDash([5 * scale, 5 * scale], count: 2, phase: 0)
        }
        path.stroke()
        
        // Вершины (масштабируем размер вершин)
        let vertexSize: CGFloat = 10 * scale // В SwiftUI используется 10, масштабируем
        for position in object.positions {
            let rect = NSRect(x: position.x - vertexSize/2, y: position.y - vertexSize/2, width: vertexSize, height: vertexSize)
            NSColor(object.vertexColor).setFill()
            NSBezierPath(ovalIn: rect).fill()
            
            NSColor.white.setStroke()
            let b = NSBezierPath(ovalIn: rect)
            b.lineWidth = 1 * scale
            b.stroke()
        }
    }
    
    private func drawLineBetweenObjectsOnImage(_ object: DrawableObject, scale: CGFloat) {
        guard object.positions.count >= 2 else { return }
        
        let path = NSBezierPath()
        
        for i in 0..<(object.positions.count - 1) {
            let current = object.positions[i]
            let next = object.positions[i + 1]
            
            path.move(to: NSPoint(x: current.x, y: current.y))
            path.line(to: NSPoint(x: next.x, y: next.y))
        }
        
        let lineW = object.strokeWidth * scale
        NSColor(object.edgeColor).withAlphaComponent(0.8).setStroke()
        path.lineWidth = lineW
        
        if object.lineStyle == .dashed {
            let baseLineWidth: CGFloat = 3.0
            let dashScale = max(1, object.strokeWidth / baseLineWidth)
            path.setLineDash([5 * scale * dashScale, 5 * scale * dashScale], count: 2, phase: 0)
        }
        path.stroke()
        
        // Вершины (масштабируем размер вершин)
        let vertexSize: CGFloat = 10 * scale // В SwiftUI используется 10, масштабируем
        for position in object.positions {
            let rect = NSRect(x: position.x - vertexSize/2, y: position.y - vertexSize/2, width: vertexSize, height: vertexSize)
            NSColor(object.vertexColor).setFill()
            NSBezierPath(ovalIn: rect).fill()
            
            NSColor.white.setStroke()
            let b = NSBezierPath(ovalIn: rect)
            b.lineWidth = 1 * scale
            b.stroke()
        }
    }
    
    private func drawLineWithArrowOnImage(_ object: DrawableObject, scale: CGFloat) {
        guard object.positions.count >= 2 else { return }
        
        let lineW = object.strokeWidth * scale
        let path = NSBezierPath()
        
        // Рисуем линию до последней точки
        for i in 0..<(object.positions.count - 1) {
            let current = object.positions[i]
            let next = object.positions[i + 1]
            
            path.move(to: NSPoint(x: current.x, y: current.y))
            path.line(to: NSPoint(x: next.x, y: next.y))
        }
        
        NSColor(object.edgeColor).withAlphaComponent(0.8).setStroke()
        path.lineWidth = lineW
        
        if object.lineStyle == .dashed {
            let baseLineWidth: CGFloat = 3.0
            let dashScale = max(1, object.strokeWidth / baseLineWidth)
            path.setLineDash([5 * scale * dashScale, 5 * scale * dashScale], count: 2, phase: 0)
        }
        path.stroke()
        
        // Рисуем стрелку на последней точке (размер стрелки фиксированный при масштабе)
        let lastPoint = object.positions[object.positions.count - 1]
        let secondLastPoint = object.positions[object.positions.count - 2]
        
        // Вычисляем направление стрелки
        let dx = lastPoint.x - secondLastPoint.x
        let dy = lastPoint.y - secondLastPoint.y
        let angle = atan2(dy, dx)
        
        // Размер стрелки (фиксированный при масштабе, как в редакторе)
        let arrowLength: CGFloat = 15 * scale
        let arrowWidth: CGFloat = 10 * scale
        
        // Создаем путь стрелки
        let arrowPath = NSBezierPath()
        let arrowTip = NSPoint(x: lastPoint.x, y: lastPoint.y)
        let arrowPoint1 = NSPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle + .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle + .pi / 2)
        )
        let arrowPoint2 = NSPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle - .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle - .pi / 2)
        )
        
        arrowPath.move(to: arrowTip)
        arrowPath.line(to: arrowPoint1)
        arrowPath.line(to: arrowPoint2)
        arrowPath.close()
        
        NSColor(object.edgeColor).setFill()
        arrowPath.fill()
        NSColor(object.edgeColor).setStroke()
        arrowPath.lineWidth = lineW
        arrowPath.stroke()
        
        // Вершины (кроме последней, так как там стрелка)
        let vertexSize: CGFloat = 10 * scale
        for position in object.positions.dropLast() {
            let rect = NSRect(x: position.x - vertexSize/2, y: position.y - vertexSize/2, width: vertexSize, height: vertexSize)
            NSColor(object.vertexColor).setFill()
            NSBezierPath(ovalIn: rect).fill()
            
            NSColor.white.setStroke()
            let b = NSBezierPath(ovalIn: rect)
            b.lineWidth = 1 * scale
            b.stroke()
        }
    }
    
    // Вычисляем контрольную точку на основе curveHeight
    private func computeControlPointForCurvedArrow(start: CGPoint, end: CGPoint, curveHeight: CGFloat) -> CGPoint {
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        
        // Вычисляем перпендикулярный вектор к линии
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        
        if length == 0 {
            return CGPoint(x: midX, y: midY)
        }
        
        // Перпендикулярный вектор (повернутый на 90 градусов)
        let perpX = -dy / length
        let perpY = dx / length
        
        // Контрольная точка смещена перпендикулярно на curveHeight
        return CGPoint(
            x: midX + perpX * curveHeight,
            y: midY + perpY * curveHeight
        )
    }
    
    private func drawCurvedArrowOnImage(_ object: DrawableObject, scale: CGFloat, scaleX: CGFloat, scaleY: CGFloat) {
        guard object.positions.count >= 2 else { return }
        
        let startPoint = object.positions[0]
        let endPoint = object.positions[1]
        let controlPoint: CGPoint
        if let cp = object.controlPoint {
            controlPoint = cp
        } else {
            // Сохраняем отношение (смещение/длина отрезка) как в редакторе: L_im и L_view могут отличаться при scaleX != scaleY
            let dxIm = endPoint.x - startPoint.x
            let dyIm = endPoint.y - startPoint.y
            let L_im = sqrt(dxIm * dxIm + dyIm * dyIm)
            let L_view = L_im > 0 ? sqrt((dxIm * dxIm) / (scaleX * scaleX) + (dyIm * dyIm) / (scaleY * scaleY)) : 0
            let segmentScale = L_view > 0 ? (L_im / L_view) : 1
            controlPoint = computeControlPointForCurvedArrow(
                start: startPoint,
                end: endPoint,
                curveHeight: -object.curveHeight * segmentScale
            )
        }
        
        // Рисуем квадратичную кривую Bezier
        let path = NSBezierPath()
        path.move(to: NSPoint(x: startPoint.x, y: startPoint.y))
        path.curve(to: NSPoint(x: endPoint.x, y: endPoint.y),
                   controlPoint1: NSPoint(x: controlPoint.x, y: controlPoint.y),
                   controlPoint2: NSPoint(x: controlPoint.x, y: controlPoint.y))
        
        let lineW = object.strokeWidth * scale
        NSColor(object.edgeColor).withAlphaComponent(0.8).setStroke()
        path.lineWidth = lineW
        
        if object.lineStyle == .dashed {
            path.setLineDash([5 * scale, 5 * scale], count: 2, phase: 0)
        }
        path.stroke()
        
        // Вычисляем направление стрелки в конечной точке кривой
        let t: CGFloat = 0.95
        let curvePoint = CGPoint(
            x: pow(1-t, 2) * startPoint.x + 2 * (1-t) * t * controlPoint.x + pow(t, 2) * endPoint.x,
            y: pow(1-t, 2) * startPoint.y + 2 * (1-t) * t * controlPoint.y + pow(t, 2) * endPoint.y
        )
        
        // Вычисляем направление стрелки
        let dx = endPoint.x - curvePoint.x
        let dy = endPoint.y - curvePoint.y
        let angle = atan2(dy, dx)
        
        // Размер стрелки фиксированный (не зависит от толщины линии)
        let arrowLength: CGFloat = 15 * scale
        let arrowWidth: CGFloat = 10 * scale
        
        // Создаем путь стрелки
        let arrowPath = NSBezierPath()
        let arrowTip = NSPoint(x: endPoint.x, y: endPoint.y)
        let arrowPoint1 = NSPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle + .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle + .pi / 2)
        )
        let arrowPoint2 = NSPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle - .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle - .pi / 2)
        )
        
        arrowPath.move(to: arrowTip)
        arrowPath.line(to: arrowPoint1)
        arrowPath.line(to: arrowPoint2)
        arrowPath.close()
        
        NSColor(object.edgeColor).setFill()
        arrowPath.fill()
        NSColor(object.edgeColor).setStroke()
        arrowPath.lineWidth = lineW
        arrowPath.stroke()
        
        // Показываем только начальную точку (конечная точка скрыта, так как там стрелка)
        let vertexSize: CGFloat = 10 * scale
        let rect = NSRect(x: startPoint.x - vertexSize/2, y: startPoint.y - vertexSize/2, width: vertexSize, height: vertexSize)
        NSColor(object.vertexColor).setFill()
        NSBezierPath(ovalIn: rect).fill()
        
        NSColor.white.setStroke()
        let b = NSBezierPath(ovalIn: rect)
        b.lineWidth = 1 * scale
        b.stroke()
    }
    
    private func drawObjectHighlightOnImage(_ object: DrawableObject) {
        guard let position = object.positions.first else { return }
        
        // Применяем отражение по вертикали относительно низа объекта (position.y)
        // position.y - это низ объекта, нужно отразить относительно этой точки
        var reflectionTransform = AffineTransform()
        reflectionTransform.translate(x: position.x, y: position.y)
        reflectionTransform.scale(x: 1.0, y: -1.0) // Отражение по вертикали
        reflectionTransform.translate(x: -position.x, y: -position.y)
        
        // Прямоугольник снизу вверх (y начинается снизу)
        let columnRect = NSRect(
            x: position.x - object.radius / 2,
            y: position.y - object.radius * 2,
            width: object.radius,
            height: object.radius * 2
        )
        
        var columnPath = NSBezierPath(rect: columnRect)
        columnPath.transform(using: reflectionTransform)
        
        let o = CGFloat(object.glowOpacity)
        let columnGradient = NSGradient(colors: [
            NSColor(object.glowColor).withAlphaComponent(0.9 * o),
            NSColor(object.glowColor).withAlphaComponent(0.6 * o),
            NSColor(object.glowColor).withAlphaComponent(0.3 * o),
            NSColor.clear
        ])
        
        // Градиент снизу вверх (angle: 90)
        columnGradient?.draw(in: columnPath, angle: 90)
        
        for i in 1...3 {
            let blurRect = columnRect.insetBy(dx: -CGFloat(i), dy: 0)
            var blurPath = NSBezierPath(rect: blurRect)
            blurPath.transform(using: reflectionTransform)
            NSColor(object.glowColor).withAlphaComponent(0.1 / CGFloat(i) * o).setFill()
            blurPath.fill()
        }
        
        // Овал (центр в позиции клика)
        let ovalRect = NSRect(
            x: position.x - object.radius/2,
            y: position.y - (object.radius * 0.6)/2,
            width: object.radius,
            height: object.radius * 0.6
        )
        
        var ovalPath = NSBezierPath(ovalIn: ovalRect)
        ovalPath.transform(using: reflectionTransform)
        
        // Создаем путь для нижней половины эллипса
        var bottomHalfPath = NSBezierPath()
        let centerX = ovalRect.midX
        let centerY = ovalRect.midY
        let radiusX = ovalRect.width / 2
        let radiusY = ovalRect.height / 2
        
        // Создаем нижнюю половину эллипса через точки
        let steps = 20
        var firstPoint = true
        for i in 0...steps {
            let angle = CGFloat.pi * CGFloat(i) / CGFloat(steps) // от π до 0
            let x = centerX + radiusX * cos(angle)
            let y = centerY + radiusY * sin(angle)
            if firstPoint {
                bottomHalfPath.move(to: NSPoint(x: x, y: y))
                firstPoint = false
            } else {
                bottomHalfPath.line(to: NSPoint(x: x, y: y))
            }
        }
        // Закрываем путь прямой линией
        bottomHalfPath.line(to: NSPoint(x: centerX + radiusX, y: centerY))
        bottomHalfPath.close()
        bottomHalfPath.transform(using: reflectionTransform)
        
        // Заливаем только нижнюю половину овала
        NSColor(object.glowColor).withAlphaComponent(0.8 * o).setFill()
        bottomHalfPath.fill()
        
        // Рисуем обводку всего овала
        NSColor(object.glowColor).withAlphaComponent(0.8 * o).setStroke()
        ovalPath.lineWidth = 1
        ovalPath.stroke()
    }
    
    private func drawSimpleZoneOnImage(_ object: DrawableObject, scale: CGFloat) {
        guard object.positions.count >= 3 else { return }
        
        let path = NSBezierPath()
        path.move(to: NSPoint(x: object.positions[0].x, y: object.positions[0].y))
        for position in object.positions.dropFirst() {
            path.line(to: NSPoint(x: position.x, y: position.y))
        }
        path.close()
        
        NSColor(object.fillColor).withAlphaComponent(0.3).setFill()
        path.fill()
        
        NSColor(object.edgeColor).withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2 * scale
        
        if object.lineStyle == .dashed {
            path.setLineDash([5 * scale, 5 * scale], count: 2, phase: 0)
        }
        path.stroke()
        
        // В простой зоне нет вершин после нажатия done
    }
    
    // MARK: - Shapes Drawing on Image
    
    private func drawShapeOnImage(_ shape: EditorShape, in rect: NSRect, viewSize: CGSize) {
        // Convert view coordinates to image coordinates
        let scaleX = rect.width / viewSize.width
        let scaleY = rect.height / viewSize.height
        
        // Инвертируем Y координату для правильной конвертации (SwiftUI -> Core Graphics)
        // В SwiftUI Y идет сверху вниз, в Core Graphics - снизу вверх
        let flippedY = rect.height - (shape.position.y * scaleY)
        let scaledX = shape.position.x * scaleX
        
        // Масштабируем размер
        let scaledSize = CGSize(
            width: shape.size.width * scaleX,
            height: shape.size.height * scaleY
        )
        
        // Создаем путь фигуры относительно центра (0, 0)
        var path = createShapePathOnImage(type: shape.type, size: scaledSize)
        
        // Применяем трансформации: поворот вокруг центра фигуры, затем перемещение
        let rotationRadians = shape.rotation * .pi / 180
        let transform = CGAffineTransform(translationX: scaledX, y: flippedY)
            .rotated(by: rotationRadians)
        
        // Применяем трансформацию к пути
        let affineTransform = AffineTransform(
            m11: transform.a, m12: transform.b,
            m21: transform.c, m22: transform.d,
            tX: transform.tx, tY: transform.ty
        )
        path.transform(using: affineTransform)
        
        // Применяем отражение по обеим осям относительно центра фигуры в её финальной позиции
        // Это компенсирует зеркалирование при сохранении
        var finalReflection = AffineTransform()
        finalReflection.translate(x: scaledX, y: flippedY)
        finalReflection.scale(x: 1.0, y: -1.0) // Отражение по обеим осям
        finalReflection.translate(x: -scaledX, y: -flippedY)
        path.transform(using: finalReflection)
        
        // Заливка
        NSColor(shape.fillColor).withAlphaComponent(CGFloat(shape.fillOpacity)).setFill()
        path.fill()
        
        // Обводка
        NSColor(shape.strokeColor).setStroke()
        path.lineWidth = shape.strokeWidth * scaleX
        if shape.lineStyle == .dashed {
            path.setLineDash([5 * scaleX, 5 * scaleX], count: 2, phase: 0)
        }
        path.stroke()
    }
    
    private func createShapePathOnImage(type: ShapeType, size: CGSize) -> NSBezierPath {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let path = NSBezierPath()
        
        switch type {
        case .triangle:
            path.move(to: NSPoint(x: 0, y: -halfHeight))
            path.line(to: NSPoint(x: -halfWidth, y: halfHeight))
            path.line(to: NSPoint(x: halfWidth, y: halfHeight))
            path.close()
            
        case .square:
            path.appendRect(NSRect(x: -halfWidth, y: -halfHeight, width: size.width, height: size.height))
            
        case .rectangle:
            path.appendRect(NSRect(x: -halfWidth, y: -halfHeight, width: size.width, height: size.height))
            
        case .circle:
            path.appendOval(in: NSRect(x: -halfWidth, y: -halfHeight, width: size.width, height: size.height))
            
        case .star:
            let points = 5
            let outerRadius = min(halfWidth, halfHeight)
            let innerRadius = outerRadius * 0.4
            for i in 0..<points * 2 {
                let angle = Double(i) * .pi / Double(points)
                let radius = i % 2 == 0 ? outerRadius : innerRadius
                let x = CGFloat(cos(angle)) * radius
                let y = CGFloat(sin(angle)) * radius
                if i == 0 {
                    path.move(to: NSPoint(x: x, y: y))
                } else {
                    path.line(to: NSPoint(x: x, y: y))
                }
            }
            path.close()
            
        case .hexagon:
            let radius = min(halfWidth, halfHeight)
            for i in 0..<6 {
                let angle = Double(i) * .pi / 3.0
                let x = CGFloat(cos(angle)) * radius
                let y = CGFloat(sin(angle)) * radius
                if i == 0 {
                    path.move(to: NSPoint(x: x, y: y))
                } else {
                    path.line(to: NSPoint(x: x, y: y))
                }
            }
            path.close()
        }
        
        return path
    }
    
    // MARK: - TextBox Drawing on Image
    
    private func drawTextBoxOnImage(_ textBox: EditorTextBox, in rect: NSRect, viewSize: CGSize) {
        // Convert view coordinates to image coordinates
        let scaleX = rect.width / viewSize.width
        let scaleY = rect.height / viewSize.height
        
        // Инвертируем Y координату для правильной конвертации (SwiftUI -> Core Graphics)
        // В SwiftUI Y идет сверху вниз, в Core Graphics - снизу вверх
        let flippedY = rect.height - (textBox.position.y * scaleY)
        let scaledX = textBox.position.x * scaleX
        
        // Масштабируем размер
        let scaledSize = CGSize(
            width: textBox.size.width * scaleX,
            height: textBox.size.height * scaleY
        )
        
        // Создаем прямоугольник относительно центра (0, 0)
        let textBoxRect = NSRect(
            x: -scaledSize.width / 2,
            y: -scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
        
        // Создаем путь прямоугольника
        var path = NSBezierPath(rect: textBoxRect)
        
        // Применяем трансформации: поворот вокруг центра фигуры, затем перемещение
        let rotationRadians = textBox.rotation * .pi / 180
        let transform = CGAffineTransform(translationX: scaledX, y: flippedY)
            .rotated(by: rotationRadians)
        
        // Применяем трансформацию к пути
        let affineTransform = AffineTransform(
            m11: transform.a, m12: transform.b,
            m21: transform.c, m22: transform.d,
            tX: transform.tx, tY: transform.ty
        )
        path.transform(using: affineTransform)
        
        // Применяем отражение по вертикали относительно центра текстового бокса в его финальной позиции
        // Это компенсирует зеркалирование при сохранении (1 в 1 как в drawShapeOnImage)
        var finalReflection = AffineTransform()
        finalReflection.translate(x: scaledX, y: flippedY)
        finalReflection.scale(x: 1.0, y: -1.0) // Отражение по вертикали
        finalReflection.translate(x: -scaledX, y: -flippedY)
        path.transform(using: finalReflection)
        
        // Рисуем фон
        if textBox.backgroundColor != .clear {
            NSColor(textBox.backgroundColor).setFill()
            path.fill()
        }
        
        // Рисуем границу
        NSColor(textBox.borderColor).setStroke()
        path.lineWidth = textBox.borderWidth * max(scaleX, scaleY)
        path.stroke()
        
        // Рисуем текст в том же контексте, с теми же трансформациями, что и прямоугольник
        guard !textBox.text.isEmpty else { return }
        
        let textRect = textBoxRect.insetBy(dx: 5 * max(scaleX, scaleY), dy: 5 * max(scaleX, scaleY))
        let font = NSFont(name: textBox.fontName, size: textBox.fontSize * max(scaleX, scaleY)) ?? NSFont.systemFont(ofSize: textBox.fontSize * max(scaleX, scaleY))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(textBox.textColor),
            .paragraphStyle: paragraphStyle
        ]
        let attributedString = NSAttributedString(string: textBox.text, attributes: textAttributes)
        
        NSGraphicsContext.current?.saveGraphicsState()
        
        // Применяем те же трансформации, что и для пути: сначала отражение, затем перемещение+поворот
        // (порядок concat: Ref * (T*R), чтобы точка в локальных координатах попала в Reflect*(T*R)*p)
        let finalReflectionNS = NSAffineTransform()
        finalReflectionNS.translateX(by: scaledX, yBy: flippedY)
        finalReflectionNS.scaleX(by: 1.0, yBy: 1.0)
        finalReflectionNS.translateX(by: -scaledX, yBy: -flippedY)
        finalReflectionNS.concat()
        
        let textTransform = NSAffineTransform()
        textTransform.translateX(by: scaledX, yBy: flippedY)
        textTransform.rotate(byRadians: rotationRadians)
        textTransform.concat()
        
        // Рисуем текст прямо в контексте (без промежуточного NSImage)
        attributedString.draw(in: textRect)
        
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}

