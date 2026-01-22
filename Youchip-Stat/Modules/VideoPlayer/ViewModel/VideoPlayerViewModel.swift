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
    case saveWindowHeight(CGFloat)
    case restoreWindowHeight
    
    // Screenshot Display Control
    case hideScreenshotAndResume
}

// MARK: - Video Player ViewModel

class VideoPlayerViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var state = VideoPlayerState()
    
    // MARK: - Actions
    
    let action = PassthroughSubject<VideoPlayerAction, Never>()
    private var observables: [AnyCancellable] = []
    
    // MARK: - Dependencies
    
    private let videoId: String
    
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
        
        let currentTime = VideoPlayerManager.shared.currentTime
        let timeDifference = abs(currentTime - state.lastCheckedVideoTime)
        
        // Если скриншот показан и пользователь нажал play, скрываем скриншот и возобновляем воспроизведение
        if state.isShowingScreenshot {
            if let player = VideoPlayerManager.shared.player, player.rate > 0 {
                hideScreenshotOverlay(resumePlayback: true)
                state.lastCheckedVideoTime = currentTime
                return
            }
            // Если скриншот показан, но видео на паузе - не делаем ничего, ждем действий пользователя
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
        guard let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == videoId }) else {
            return
        }
        
        let screenshotsFolder = filesFile.screenshotsFolder
        let imageFileName = metadata.screenshotName.hasSuffix(".png") ? metadata.screenshotName : "\(metadata.screenshotName).png"
        let imageURL = screenshotsFolder.appendingPathComponent(imageFileName)
        
        guard let image = NSImage(contentsOf: imageURL) else { return }
        
        VideoPlayerManager.shared.player?.pause()
        
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
        
        NotificationCenter.default.post(name: .screenshotDisplayChanged, object: false)
        if resumePlayback {
            VideoPlayerManager.shared.player?.play()
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
            
        case let .saveWindowHeight(height):
            state.savedWindowHeight = height
            
        case .restoreWindowHeight:
            handleRestoreWindowHeight()
            
        case .hideScreenshotAndResume:
            hideScreenshotOverlay(resumePlayback: true)
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
            
            state.editorScreenshotVideoTime = CMTimeGetSeconds(currentTime)
            NotificationCenter.default.post(name: .editorModeChanged, object: true)
            
        } catch {
            print("Error taking screenshot for editor: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Editor Mode
    
    private func handleCancelEditor() {
        state.isEditorMode = false
        state.editorScreenshotName = ""
        state.editorSaveAsTag = false
        state.tempScreenshotImage = nil
        state.editorDrawingState.clearDrawing()
        state.editorScreenshotVideoTime = 0.0
        state.showTagSelectionSheet = false
        
        NotificationCenter.default.post(name: .editorModeChanged, object: false)
    }
    
    private func handleSaveEditor() {
        guard let nsImage = state.tempScreenshotImage,
              let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == videoId }) else {
            handleCancelEditor()
            return
        }
        
        let currentVideoTime = state.editorScreenshotVideoTime
        let screenshotsFolder = filesFile.screenshotsFolder
        let fileName = state.editorScreenshotName.hasSuffix(".png") ? state.editorScreenshotName : "\(state.editorScreenshotName).png"
        let fileURL = screenshotsFolder.appendingPathComponent(fileName)
        
        let finalImage = mergeDrawingWithImage(baseImage: nsImage, drawingState: state.editorDrawingState)
        
        if let imageData = finalImage.pngData() {
            try? imageData.write(to: fileURL)
            state.screenshotImage = fileURL
            
            // Create a tag on Screenshots timeline and get its stamp ID
            let createdStampId = addScreenshotAsTag(
                screenshotName: state.editorScreenshotName,
                videoTime: currentVideoTime
            )
            
            // Save metadata with the created tag automatically linked
            let relatedStampIds = createdStampId != nil ? [createdStampId!] : []
            saveScreenshotMetadata(
                screenshotName: state.editorScreenshotName,
                videoTime: currentVideoTime,
                displayDuration: state.editorDisplayDuration,
                relatedStampIds: relatedStampIds,
                screenshotsFolder: screenshotsFolder
            )
            
            ScreenshotsMetadataManager.shared.loadScreenshots(from: screenshotsFolder)
        }
        
        handleCancelEditor()
    }
    
    private func handleSaveEditorWithTags(_ selectedStamps: [TimelineStamp]) {
        guard let nsImage = state.tempScreenshotImage,
              let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == videoId }) else {
            handleCancelEditor()
            return
        }
        
        let currentVideoTime = state.editorScreenshotVideoTime
        let screenshotsFolder = filesFile.screenshotsFolder
        let fileName = state.editorScreenshotName.hasSuffix(".png") ? state.editorScreenshotName : "\(state.editorScreenshotName).png"
        let fileURL = screenshotsFolder.appendingPathComponent(fileName)
        
        let finalImage = mergeDrawingWithImage(baseImage: nsImage, drawingState: state.editorDrawingState)
        
        if let imageData = finalImage.pngData() {
            try? imageData.write(to: fileURL)
            state.screenshotImage = fileURL
            
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
            
            saveScreenshotMetadata(
                screenshotName: state.editorScreenshotName,
                videoTime: currentVideoTime,
                displayDuration: state.editorDisplayDuration,
                relatedStampIds: stampIds,
                screenshotsFolder: screenshotsFolder
            )
            
            ScreenshotsMetadataManager.shared.loadScreenshots(from: screenshotsFolder)
        }
        
        // Close the tag selection sheet
        state.showTagSelectionSheet = false
        
        handleCancelEditor()
    }
    
    // Helper method to get intersecting stamps at current video time
    func getIntersectingStamps() -> [TimelineStamp] {
        let videoTime = state.editorScreenshotVideoTime
        var stamps: [TimelineStamp] = []
        
        let timelineData = TimelineDataManager.shared
        for line in timelineData.lines {
            for stamp in line.stamps {
                if videoTime >= stamp.timeStartSeconds && videoTime <= stamp.timeFinishSeconds {
                    stamps.append(stamp)
                }
            }
        }
        
        return stamps
    }
    
    private func saveScreenshotMetadata(screenshotName: String, videoTime: Double, displayDuration: Double, relatedStampIds: [UUID], screenshotsFolder: URL) {
        print("💾 Сохранение метаданных скриншота '\(screenshotName)' с displayDuration = \(displayDuration) секунд")
        
        let metadata = ScreenshotMetadata(
            screenshotName: screenshotName,
            videoTime: videoTime,
            createdAt: Date(),
            saveAsTag: false, // No longer used but kept for backward compatibility
            displayDuration: displayDuration,
            relatedStampIds: relatedStampIds
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
    
    @discardableResult
    private func addScreenshotAsTag(screenshotName: String, videoTime: Double) -> UUID? {
        let timelineData = TimelineDataManager.shared
        let tagLibrary = TagLibraryManager.shared
        
        let screenshotsLineID = ensureScreenshotsTimelineExists()
        ensureScreenshotsTagGroupExists()
        
        let videoDuration = max(1.0, VideoPlayerManager.shared.videoDuration)
        let startTime = max(0, videoTime - 3.0)
        let endTime = min(videoDuration, videoTime + 3.0)
        
        let tagID = "screenshot_\(screenshotName)_\(UUID().uuidString)"
        addTagToScreenshotsGroup(tagID: tagID)
        guard let lineIndex = timelineData.lines.firstIndex(where: { $0.id == screenshotsLineID }) else {
            return nil
        }
        
        let stamp = TimelineStamp(
            idTag: tagID,
            primaryID: nil,
            timeStartSeconds: startTime,
            timeFinishSeconds: endTime,
            colorHex: "808080",
            label: screenshotName,
            labels: [],
            timeEvents: [],
            position: nil
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
        
        let screenshotsLine = TimelineLine(id: screenshotsID, name: "Рисунки", stamps: [], tagIdForMode: "")
        timelineData.lines.insert(screenshotsLine, at: 0)
        timelineData.updateTimelines()
        
        return screenshotsID
    }
    
    private func mergeDrawingWithImage(baseImage: NSImage, drawingState: EditorDrawingState) -> NSImage {
        let size = baseImage.size
        let finalImage = NSImage(size: size)
        
        finalImage.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: size))
        for path in drawingState.completedPaths {
            drawPathOnImage(path, in: NSRect(origin: .zero, size: size), viewSize: drawingState.viewSize)
        }
        if !drawingState.currentPath.points.isEmpty {
            drawPathOnImage(drawingState.currentPath, in: NSRect(origin: .zero, size: size), viewSize: drawingState.viewSize)
        }
        
        finalImage.unlockFocus()
        return finalImage
    }
    
    private func drawPathOnImage(_ path: EditorDrawingPath, in rect: NSRect, viewSize: CGSize) {
        guard path.points.count > 1 else { return }
        
        let bezierPath = NSBezierPath()
        
        let scaleX = viewSize.width > 0 ? rect.width / viewSize.width : 1.0
        let scaleY = viewSize.height > 0 ? rect.height / viewSize.height : 1.0
        
        let scaledX = path.points[0].x * scaleX
        let scaledY = path.points[0].y * scaleY
        let flippedFirstPoint = CGPoint(x: scaledX, y: rect.height - scaledY)
        bezierPath.move(to: flippedFirstPoint)
        
        for point in path.points.dropFirst() {
            let scaledX = point.x * scaleX
            let scaledY = point.y * scaleY
            let flippedPoint = CGPoint(x: scaledX, y: rect.height - scaledY)
            bezierPath.line(to: flippedPoint)
        }
        
        NSColor(path.color).setStroke()
        let scale = max(scaleX, scaleY)
        bezierPath.lineWidth = path.lineWidth * scale
        bezierPath.lineCapStyle = .round
        bezierPath.lineJoinStyle = .round
        
        if let dashPattern = path.lineStyle.dashPattern {
            let scaledDashPattern = dashPattern.map { $0 * scale }
            bezierPath.setLineDash(scaledDashPattern, count: scaledDashPattern.count, phase: 0)
        }
        
        bezierPath.stroke()
    }
    
    // MARK: - Window Management
    
    private func handleRestoreWindowHeight() {
        guard let savedHeight = state.savedWindowHeight else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let window = NSApplication.shared.windows.first(where: { 
                $0.contentViewController?.view.window == $0 && 
                $0.title == ^String.Titles.video
            }) else { return }
            
            let currentFrame = window.frame
            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y + (currentFrame.height - savedHeight),
                width: currentFrame.width,
                height: savedHeight
            )
            window.setFrame(newFrame, display: true, animate: false)
            self?.state.savedWindowHeight = nil
        }
    }
    
    private func openEditorInNewWindow(with imageUrl: URL, screenshotsFolder: URL) {
        let editorViewModel = EditorViewModel(file: imageUrl, screenshotsFolder: screenshotsFolder)
        
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
    
    private func openPolygonEditorInNewWindow(with nsImage: NSImage) {
        let polygonEditorViewModel = PolygonEditorViewModel(image: nsImage)
        let polygonEditorView = PolygonEditorView()
            .environmentObject(polygonEditorViewModel)
        
        let hostingController = NSHostingController(rootView: polygonEditorView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "polygonEditorTitle"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSScreen.main?.frame.size ?? NSSize(width: 1200, height: 800))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

