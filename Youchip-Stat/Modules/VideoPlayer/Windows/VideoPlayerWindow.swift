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

struct VideoPlayerWindow: View {
    
    let id: String
    
    @ObservedObject var videoManager = VideoPlayerManager.shared
    
    @State private var showScreenshotNameSheet = false
    @State private var tempScreenshotImage: NSImage?
    @State private var currentScreenshotName: String = ""
    @State private var screenshotImage: URL? = nil
    
    init(id: String) {
        self.id = id
    }
    
    var body: some View {
        VStack {
            if let player = videoManager.player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
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
            } else {
                Text(^String.Titles.videoPlayerVideoNotLoaded)
                    .foregroundColor(.gray)
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
            tempScreenshotImage = nsImage
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
