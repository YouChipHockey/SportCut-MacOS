//
//  VideoPlayerWindow.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers
import Vision

struct VideoPlayerWindow: View {
    
    let id: String
    
    @ObservedObject var videoManager = VideoPlayerManager.shared
    
    @State private var showScreenshotNameSheet = false
    @State private var tempScreenshotImage: NSImage?
    @State private var currentScreenshotName: String = ""
    @State private var screenshotImage: URL? = nil
    
    @State private var detectionTimer: Timer?
    @State private var isDetectionEnabled = false
    
    @State private var videoScale: CGFloat = 1.0
    @State private var videoOffset: CGSize = .zero
    @State private var lastDragValue: CGSize = .zero
    
    init(id: String) {
        self.id = id
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let player = videoManager.player {
                    videoPlayerContent(geometry: geometry, player: player)
                } else {
                    noVideoContent
                }
            }
        }
        .sheet(isPresented: $showScreenshotNameSheet) {
            ScreenshotNameSheet { name in
                currentScreenshotName = name
                saveScreenshot(with: name)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func videoPlayerContent(geometry: GeometryProxy, player: AVPlayer) -> some View {
        ZStack {
            videoPlayerView(geometry: geometry, player: player)
            
            if videoScale > 1.0 {
                joystickView(geometry: geometry)
            }
        }
    }
    
    private func videoPlayerView(geometry: GeometryProxy, player: AVPlayer) -> some View {
        ZStack {
            if videoScale == 1.0 {
                VideoPlayer(player: player)
                    .scaleEffect(videoScale)
                    .offset(videoOffset)
                    .gesture(videoGestures(geometry: geometry))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                CustomVideoPlayer(player: player)
                    .scaleEffect(videoScale)
                    .offset(videoOffset)
                    .gesture(videoGestures(geometry: geometry))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .overlay(overlayControls)
    }
    
    private func videoGestures(geometry: GeometryProxy) -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    handleMagnificationChange(value: value, geometry: geometry)
                },
            DragGesture()
                .onChanged { value in
                    handleDragChange(value: value, geometry: geometry)
                }
                .onEnded { value in
                    lastDragValue = videoOffset
                }
        )
    }
    
    private func handleMagnificationChange(value: CGFloat, geometry: GeometryProxy) {
        let newScale = min(max(1.0, value), 4.0)
        if newScale == 1.0 {
            videoOffset = .zero
            lastDragValue = .zero
        } else {
            let maxOffsetX = (geometry.size.width * (newScale - 1)) / 2
            let maxOffsetY = (geometry.size.height * (newScale - 1)) / 2
            videoOffset = CGSize(
                width: min(max(videoOffset.width, -maxOffsetX), maxOffsetX),
                height: min(max(videoOffset.height, -maxOffsetY), maxOffsetY)
            )
            lastDragValue = videoOffset
        }
        videoScale = newScale
    }
    
    private func handleDragChange(value: DragGesture.Value, geometry: GeometryProxy) {
        guard videoScale > 1.0 else { return }
        let newOffset = CGSize(
            width: lastDragValue.width + value.translation.width,
            height: lastDragValue.height + value.translation.height
        )
        let maxOffsetX = (geometry.size.width * (videoScale - 1)) / 2
        let maxOffsetY = (geometry.size.height * (videoScale - 1)) / 2
        videoOffset = CGSize(
            width: min(max(newOffset.width, -maxOffsetX), maxOffsetX),
            height: min(max(newOffset.height, -maxOffsetY), maxOffsetY)
        )
    }
    
    private var overlayControls: some View {
        VStack {
            topControls
            Spacer()
            bottomZoomControls
        }
    }
    
    private var topControls: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                polygonButton
                screenshotButton
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
    }
    
    private var polygonButton: some View {
        Button(action: takeScreenshotForPolygonEditor) {
            HStack(spacing: 6) {
                Image(systemName: "hexagon.grid.3x3")
                    .font(.system(size: 14, weight: .medium))
                Text("Telestration")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(controlButtonBackground)
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .help("createPolygonScreenshot")
    }
    
    private var screenshotButton: some View {
        Button(action: takeScreenshot) {
            HStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 14, weight: .medium))
                Text("Screenshots")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(controlButtonBackground)
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .help(^String.Titles.createScreenshotAndOpenEditor)
    }
    
    private var controlButtonBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
    }
    
    private var bottomZoomControls: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                zoomLevelIndicator
                zoomButtons
            }
            .padding(.bottom, 20)
            .padding(.trailing, 20)
        }
    }
    
    private var zoomLevelIndicator: some View {
        Text(String(format: "%.1fx", videoScale))
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
    
    private var zoomButtons: some View {
        HStack(spacing: 8) {
            zoomOutButton
            zoomInButton
        }
    }
    
    private var zoomOutButton: some View {
        Button(action: zoomOut) {
            Image(systemName: "minus.magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .background(zoomButtonBackground)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(videoScale <= 1.0)
        .opacity(videoScale <= 1.0 ? 0.5 : 1.0)
    }
    
    private var zoomInButton: some View {
        Button(action: zoomIn) {
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .background(zoomButtonBackground)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(videoScale >= 4.0)
        .opacity(videoScale >= 4.0 ? 0.5 : 1.0)
    }
    
    private var zoomButtonBackground: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
    }
    
    private func joystickView(geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()
            HStack {
                JoystickView(onMove: { direction in
                    handleJoystickMove(direction: direction, geometry: geometry)
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
        .animation(.easeInOut(duration: 0.3), value: videoScale > 1.0)
    }
    
    private func handleJoystickMove(direction: JoystickDirection, geometry: GeometryProxy) {
        let step: CGFloat = 30
        let maxOffsetX = (geometry.size.width * (videoScale - 1)) / 2
        let maxOffsetY = (geometry.size.height * (videoScale - 1)) / 2
        var newOffset = videoOffset
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
        videoOffset = newOffset
        lastDragValue = newOffset
    }
    
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
    
    private func zoomOut() {
        let newScale = max(1.0, videoScale - 0.1)
        videoScale = newScale
        updateVideoOffsetForScale(newScale)
    }
    
    private func zoomIn() {
        let newScale = min(4.0, videoScale + 0.1)
        videoScale = newScale
        updateVideoOffsetForScale(newScale)
    }
    
    private func updateVideoOffsetForScale(_ newScale: CGFloat) {
        // This is a simplified version - in a real implementation,
        // you'd need to pass geometry to calculate proper bounds
        if newScale == 1.0 {
            videoOffset = .zero
            lastDragValue = .zero
        }
    }
    
    enum JoystickDirection {
        case up, down, left, right
    }

    struct JoystickView: View {
        let onMove: (JoystickDirection) -> Void
        
        var body: some View {
            VStack(spacing: 12) {
                // Up button
                Button(action: { onMove(.up) }) {
                    Image(systemName: "chevron.up")
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
                }
                .buttonStyle(PlainButtonStyle())
                
                // Left and Right buttons
                HStack(spacing: 12) {
                    Button(action: { onMove(.left) }) {
                        Image(systemName: "chevron.left")
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
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer().frame(width: 8)
                    
                    Button(action: { onMove(.right) }) {
                        Image(systemName: "chevron.right")
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
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Down button
                Button(action: { onMove(.down) }) {
                    Image(systemName: "chevron.down")
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
                }
                .buttonStyle(PlainButtonStyle())
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
    
    private func takeScreenshotForPolygonEditor() {
            guard let player = videoManager.player,
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
                
                // Обработка масштабирования и смещения
                var finalImage = nsImage
                if videoScale > 1.0 {
                    let imgWidth = CGFloat(cgImage.width)
                    let imgHeight = CGFloat(cgImage.height)
                    let viewSize = NSScreen.main?.frame.size ?? NSSize(width: imgWidth, height: imgHeight)
                    let scaleX = imgWidth / viewSize.width
                    let scaleY = imgHeight / viewSize.height
                    let visibleWidth = viewSize.width / videoScale
                    let visibleHeight = viewSize.height / videoScale
                    let centerX = imgWidth / 2.0 - videoOffset.width * scaleX
                    let centerY = imgHeight / 2.0 - videoOffset.height * scaleY
                    let cropRect = CGRect(
                        x: centerX - visibleWidth * scaleX / 2.0,
                        y: centerY - visibleHeight * scaleY / 2.0,
                        width: visibleWidth * scaleX,
                        height: visibleHeight * scaleY
                    ).integral
                    
                    if let croppedCGImage = cgImage.cropping(to: cropRect) {
                        let finalSize = NSSize(width: viewSize.width, height: viewSize.height)
                        let croppedNSImage = NSImage(size: finalSize)
                        croppedNSImage.lockFocus()
                        NSGraphicsContext.current?.imageInterpolation = .high
                        NSImage(cgImage: croppedCGImage, size: cropRect.size)
                            .draw(in: NSRect(origin: .zero, size: finalSize),
                                  from: NSRect(origin: .zero, size: cropRect.size),
                                  operation: .copy, fraction: 1.0)
                        croppedNSImage.unlockFocus()
                        finalImage = croppedNSImage
                    }
                }
                
                tempScreenshotImage = finalImage
                openPolygonEditorInNewWindow(with: finalImage)
                
            } catch {
                print(String(format: ^String.Titles.videoPlayerErrorScreenshot, error.localizedDescription))
            }
        }
        
    private func takeScreenshot() {
        guard let player = videoManager.player,
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
            if videoScale > 1.0 {
                let imgWidth = CGFloat(cgImage.width)
                let imgHeight = CGFloat(cgImage.height)
                let viewSize = NSScreen.main?.frame.size ?? NSSize(width: imgWidth, height: imgHeight)
                let scaleX = imgWidth / viewSize.width
                let scaleY = imgHeight / viewSize.height
                let visibleWidth = viewSize.width / videoScale
                let visibleHeight = viewSize.height / videoScale
                let centerX = imgWidth / 2.0 - videoOffset.width * scaleX
                let centerY = imgHeight / 2.0 - videoOffset.height * scaleY
                let cropRect = CGRect(
                    x: centerX - visibleWidth * scaleX / 2.0,
                    y: centerY - visibleHeight * scaleY / 2.0,
                    width: visibleWidth * scaleX,
                    height: visibleHeight * scaleY
                ).integral
                if let croppedCGImage = cgImage.cropping(to: cropRect) {
                    let finalSize = NSSize(width: viewSize.width, height: viewSize.height)
                    let croppedNSImage = NSImage(size: finalSize)
                    croppedNSImage.lockFocus()
                    NSGraphicsContext.current?.imageInterpolation = .high
                    NSImage(cgImage: croppedCGImage, size: cropRect.size)
                        .draw(in: NSRect(origin: .zero, size: finalSize),
                              from: NSRect(origin: .zero, size: cropRect.size),
                              operation: .copy, fraction: 1.0)
                    croppedNSImage.unlockFocus()
                    tempScreenshotImage = croppedNSImage
                } else {
                    tempScreenshotImage = nsImage
                }
            } else {
                tempScreenshotImage = nsImage
            }
            showScreenshotNameSheet = true
        } catch {
            print(String(format: ^String.Titles.videoPlayerErrorScreenshot, error.localizedDescription))
        }
    }
    
    private func saveScreenshot(with name: String) {
        guard let nsImage = tempScreenshotImage,
              let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == id }) else {
            return
        }
        
        let screenshotsFolder = filesFile.screenshotsFolder
        let fileName = name.hasSuffix(".png") ? name : "\(name).png"
        let fileURL = screenshotsFolder.appendingPathComponent(fileName)
        
        if let imageData = nsImage.pngData() {
            try? imageData.write(to: fileURL)
            screenshotImage = fileURL
            openEditorInNewWindow(with: fileURL, screenshotsFolder: screenshotsFolder)
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
    
}

// MARK: - CustomVideoPlayer
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
