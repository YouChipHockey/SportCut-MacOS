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

struct VideoPlayerWindow: View { // скрин с зумом
    
    let id: String
    
    @ObservedObject var videoManager = VideoPlayerManager.shared
    
    @State private var showScreenshotNameSheet = false
    @State private var tempScreenshotImage: NSImage?
    @State private var currentScreenshotName: String = ""
    @State private var screenshotImage: URL? = nil
    
    @State private var videoScale: CGFloat = 1.0
    @State private var videoOffset: CGSize = .zero
    @State private var lastDragValue: CGSize = .zero
    
    init(id: String) {
        self.id = id
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                if let player = videoManager.player {
                    ZStack {
                        VideoPlayer(player: player)
                            .scaleEffect(videoScale)
                            .offset(videoOffset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
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
                                        },
                                    DragGesture()
                                        .onChanged { value in
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
                                        .onEnded { value in
                                            lastDragValue = videoOffset
                                        }
                                )
                            )
                            .overlay(
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Button(action: takeScreenshot) {
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 18))
                                                .padding(10)
                                                .background(Color.black.opacity(0.6))
                                                .foregroundColor(.white)
                                                .clipShape(Circle())
                                                .shadow(radius: 3)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                        .padding()
                                        .padding(.bottom, 40)
                                        .help(^String.Titles.createScreenshotAndOpenEditor)
                                    }
                                }
                            )
                        if videoScale > 1.0 {
                            VStack {
                                Spacer()
                                HStack {
                                    JoystickView(
                                        onMove: { direction in
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
                                                newOffset.width = max(newOffset.width - step, -maxOffsetX)
                                            case .right:
                                                newOffset.width = min(newOffset.width + step, maxOffsetX)
                                            }
                                            videoOffset = newOffset
                                            lastDragValue = newOffset
                                        }
                                    )
                                    .frame(width: 60, height: 180)
                                    .padding(.leading, 30)
                                    Spacer()
                                }
                                Spacer()
                            }
                            .transition(.opacity)
                        }
                    }
                } else {
                    Text(^String.Titles.videoPlayerVideoNotLoaded)
                        .foregroundColor(.gray)
                }
                HStack {
                    Button(action: {
                        let newScale = max(1.0, videoScale - 0.1)
                        videoScale = newScale
                        let maxOffsetX = (geometry.size.width * (newScale - 1)) / 2
                        let maxOffsetY = (geometry.size.height * (newScale - 1)) / 2
                        videoOffset = CGSize(
                            width: min(max(videoOffset.width, -maxOffsetX), maxOffsetX),
                            height: min(max(videoOffset.height, -maxOffsetY), maxOffsetY)
                        )
                        lastDragValue = videoOffset
                    }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Button(action: {
                        let newScale = min(4.0, videoScale + 0.1)
                        videoScale = newScale
                        let maxOffsetX = (geometry.size.width * (newScale - 1)) / 2
                        let maxOffsetY = (geometry.size.height * (newScale - 1)) / 2
                        videoOffset = CGSize(
                            width: min(max(videoOffset.width, -maxOffsetX), maxOffsetX),
                            height: min(max(videoOffset.height, -maxOffsetY), maxOffsetY)
                        )
                        lastDragValue = videoOffset
                    }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    Text(String(format: "%.1fx", videoScale))
                        .font(.caption)
                }
                .padding(.bottom, 8)
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
    
    enum JoystickDirection {
        case up, down, left, right
    }

    struct JoystickView: View {
        let onMove: (JoystickDirection) -> Void
        
        var body: some View {
            VStack(spacing: 8) {
                Button(action: { onMove(.up) }) {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.system(size: 28))
                }
                HStack(spacing: 8) {
                    Button(action: { onMove(.right) }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 28))
                    }
                    Spacer().frame(width: 8)
                    Button(action: { onMove(.left) }) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 28))
                    }
                }
                Button(action: { onMove(.down) }) {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 28))
                }
            }
            .foregroundColor(.white)
            .background(Color.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 3)
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
            // --- Зум: если videoScale > 1.0, делаем crop и scale ---
            if videoScale > 1.0 {
                // Получаем размеры исходного изображения
                let imgWidth = CGFloat(cgImage.width)
                let imgHeight = CGFloat(cgImage.height)
                // Размер viewport'а (окна просмотра)
                let viewSize = NSScreen.main?.frame.size ?? NSSize(width: imgWidth, height: imgHeight)
                // Масштабируем размеры окна под изображение
                let scaleX = imgWidth / viewSize.width
                let scaleY = imgHeight / viewSize.height
                // Размер видимой области в пикселях изображения
                let visibleWidth = viewSize.width / videoScale
                let visibleHeight = viewSize.height / videoScale
                // Центр изображения
                let centerX = imgWidth / 2.0 - videoOffset.width * scaleX
                let centerY = imgHeight / 2.0 - videoOffset.height * scaleY
                // Координаты crop rect
                let cropRect = CGRect(
                    x: centerX - visibleWidth * scaleX / 2.0,
                    y: centerY - visibleHeight * scaleY / 2.0,
                    width: visibleWidth * scaleX,
                    height: visibleHeight * scaleY
                ).integral
                if let croppedCGImage = cgImage.cropping(to: cropRect) {
                    // Масштабируем обратно до исходного размера окна
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
