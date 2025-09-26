//
//  ViewerVideoView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import AVFoundation

struct ViewerVideoView: View {
    @ObservedObject var playlistManager: VideoPlaylistManager
    @ObservedObject var organizer: PlaylistManager
    @StateObject private var drawingState = DrawingState()
    @State private var player: AVPlayer?
    @State private var currentComposition: AVComposition?
    @State private var isPlayerReady = false
    @State private var timeObserver: Any?
    @State private var videoSize: CGSize = .zero
    
    private var videoAspectRatio: CGFloat {
        guard videoSize.width > 0 && videoSize.height > 0 else { return 16/9 }
        return videoSize.width / videoSize.height
    }
    
    private var videoRotation: Double {
        guard videoSize.width > 0 && videoSize.height > 0 else { return 0 }
        // Если высота больше ширины (портретная ориентация), поворачиваем на 90 градусов против часовой стрелки
        return videoSize.height > videoSize.width ? 90 : 0
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Видео")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Drawing controls
                HStack(spacing: 8) {
                    // Drawing mode toggle
                    Button(action: {
                        drawingState.isDrawingMode.toggle()
                        if drawingState.isDrawingMode {
                            // Pause video when entering drawing mode
                            player?.pause()
                            playlistManager.isPlaying = false
                        }
                    }) {
                        Image(systemName: drawingState.isDrawingMode ? "pencil.circle.fill" : "pencil.circle")
                            .font(.system(size: 16))
                            .foregroundColor(drawingState.isDrawingMode ? .red : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Режим рисования")
                    
                    // Clear drawing
                    if drawingState.hasDrawing {
                        Button(action: {
                            drawingState.clearDrawing()
                        }) {
                            Image(systemName: "trash.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Очистить рисунок")
                    }
                    
                    // Save screenshot
                    Button(action: {
                        saveScreenshot()
                    }) {
                        Image(systemName: "camera.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Сохранить скриншот")
                }
                
                // Play/Pause button
                if playlistManager.isPlaying {
                    Button(action: {
                        player?.pause()
                        playlistManager.isPlaying = false
                        // Clear drawing when playing
                        drawingState.clearDrawing()
                    }) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Button(action: {
                        if organizer.currentTags.isEmpty {
                            // Если органайзер пуст, показать сообщение
                        } else {
                            playlistManager.setPlaylist(organizer.currentTags)
                            playlistManager.playPlaylist()
                            playCurrentPlaylist()
                            // Clear drawing when playing
                            drawingState.clearDrawing()
                        }
                    }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            
            Divider()
            
            // Video player area
            ZStack {
                if let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(videoAspectRatio, contentMode: .fit)
                        .rotationEffect(.degrees(videoRotation))
                        .background(Color.black)
                        .overlay(
                            // Drawing overlay
                            DrawingOverlay(drawingState: drawingState)
                                .allowsHitTesting(drawingState.isDrawingMode)
                        )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("Нет видео для воспроизведения")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if organizer.currentTags.isEmpty {
                            Text("Добавьте теги в органайзер")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Нажмите кнопку воспроизведения")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            setupPlayer()
            setupNotifications()
        }
        .onDisappear {
            cleanupPlayer()
            removeNotifications()
        }
        .onChange(of: playlistManager.currentPlaylist) { _ in
            // Когда плейлист изменился, нужно пересоздать композицию
            if playlistManager.isPlaying {
                createCompositionFromPlaylist()
            }
        }
        .onChange(of: playlistManager.isPlaying) { isPlaying in
            if isPlaying && !playlistManager.currentPlaylist.isEmpty {
                createCompositionFromPlaylist()
            } else if !isPlaying {
                player?.pause()
            }
        }
    }
    
    private func setupPlayer() {
        // Инициализация плеера
        player = AVPlayer()
        isPlayerReady = true
    }
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        playlistManager.stopPlayback()
    }
    
    private func playCurrentPlaylist() {
        guard !playlistManager.currentPlaylist.isEmpty else { return }
        createCompositionFromPlaylist()
    }
    
    private func playSingleTag(_ tag: OrganizerTag) {
        playlistManager.setPlaylist([tag])
        createCompositionFromPlaylist()
    }
    
    private func createCompositionFromPlaylist() {
        guard let originalAsset = VideoPlayerManager.shared.player?.currentItem?.asset else {
            print("Original video asset not found")
            return
        }
        
        let composition = AVMutableComposition()
        
        guard let videoTrack = originalAsset.tracks(withMediaType: .video).first,
              let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("Failed to create video track")
            return
        }
        
        let audioTrack = originalAsset.tracks(withMediaType: .audio).first
        var compAudioTrack: AVMutableCompositionTrack? = nil
        if let audioTrack = audioTrack {
            compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        
        var currentTime = CMTime.zero
        
        for tag in playlistManager.currentPlaylist {
            let startTime = CMTime(seconds: tag.startTime, preferredTimescale: 600)
            let duration = CMTime(seconds: tag.duration, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, duration: duration)
            
            do {
                try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: currentTime)
                if let compAudio = compAudioTrack, let aTrack = audioTrack {
                    try compAudio.insertTimeRange(timeRange, of: aTrack, at: currentTime)
                }
                currentTime = currentTime + duration
            } catch {
                print("Failed to insert time range: \(error)")
                return
            }
        }
        
        currentComposition = composition
        let playerItem = AVPlayerItem(asset: composition)
        player?.replaceCurrentItem(with: playerItem)
        
        // Получаем размер видео
        updateVideoSize(from: originalAsset)
        
        // Воспроизводим
        player?.play()
        playlistManager.isPlaying = true
    }
    
    private func updateVideoSize(from asset: AVAsset) {
        let videoTracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { return }
        
        let size = videoTrack.naturalSize
        let transform = videoTrack.preferredTransform
        
        // Учитываем трансформацию для получения правильного размера
        let actualSize: CGSize
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            // Поворот на 90 градусов
            actualSize = CGSize(width: size.height, height: size.width)
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            // Поворот на -90 градусов
            actualSize = CGSize(width: size.height, height: size.width)
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            // Поворот на 180 градусов
            actualSize = size
        } else {
            // Без поворота
            actualSize = size
        }
        
        DispatchQueue.main.async {
            self.videoSize = actualSize
        }
    }
    
    // MARK: - Notifications
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .playSingleTag,
            object: nil,
            queue: .main
        ) { notification in
            if let tag = notification.object as? OrganizerTag {
                self.playSingleTag(tag)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .stopViewerPlayer,
            object: nil,
            queue: .main
        ) { _ in
            self.forceStopPlayer()
        }
    }
    
    private func removeNotifications() {
        NotificationCenter.default.removeObserver(self, name: .playSingleTag, object: nil)
        NotificationCenter.default.removeObserver(self, name: .stopViewerPlayer, object: nil)
    }
    
    // MARK: - Public Methods
    func forceStopPlayer() {
        cleanupPlayer()
    }
    
    // MARK: - Screenshot Functions
    private func saveScreenshot() {
        // Pause video when taking screenshot
        player?.pause()
        playlistManager.isPlaying = false
        
        guard let player = player else { return }
        
        // Get current time
        let currentTime = player.currentTime()
        
        // Create image generator
        let imageGenerator = AVAssetImageGenerator(asset: player.currentItem?.asset ?? AVAsset())
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: currentTime, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            // Create final image with drawing overlay if exists
            let finalImage = createImageWithDrawing(originalImage: nsImage)
            
            // Save image
            let panel = NSSavePanel()
            panel.allowedFileTypes = ["png"]
            panel.nameFieldStringValue = "screenshot_\(Int(currentTime.seconds)).png"
            
            if panel.runModal() == .OK, let url = panel.url {
                if let tiffData = finalImage.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    try pngData.write(to: url)
                    print("Скриншот сохранен: \(url)")
                }
            }
        } catch {
            print("Ошибка создания скриншота: \(error)")
        }
    }
    
    private func createImageWithDrawing(originalImage: NSImage) -> NSImage {
        let size = originalImage.size
        let finalImage = NSImage(size: size)
        
        finalImage.lockFocus()
        
        // Draw original image
        originalImage.draw(in: NSRect(origin: .zero, size: size))
        
        // Draw completed paths
        for path in drawingState.completedPaths {
            drawPath(path, in: NSRect(origin: .zero, size: size))
        }
        
        // Draw current path
        if !drawingState.currentPath.points.isEmpty {
            drawPath(drawingState.currentPath, in: NSRect(origin: .zero, size: size))
        }
        
        finalImage.unlockFocus()
        
        return finalImage
    }
    
    private func drawPath(_ path: DrawingPath, in rect: NSRect) {
        guard path.points.count > 1 else { return }
        
        let bezierPath = NSBezierPath()
        bezierPath.move(to: path.points[0])
        
        for i in 1..<path.points.count {
            bezierPath.line(to: path.points[i])
        }
        
        NSColor.red.setStroke()
        bezierPath.lineWidth = path.lineWidth
        bezierPath.lineCapStyle = .round
        bezierPath.lineJoinStyle = .round
        bezierPath.stroke()
    }
}

// MARK: - Drawing Overlay
struct DrawingOverlay: View {
    @ObservedObject var drawingState: DrawingState
    @State private var dragLocation: CGPoint = .zero
    
    var body: some View {
        Canvas { context, size in
            // Draw completed paths
            for path in drawingState.completedPaths {
                drawPath(path, in: context, size: size)
            }
            
            // Draw current path
            if !drawingState.currentPath.points.isEmpty {
                drawPath(drawingState.currentPath, in: context, size: size)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if drawingState.isDrawingMode {
                        let location = value.location
                        
                        if drawingState.currentPath.points.isEmpty {
                            drawingState.startNewPath(at: location)
                        } else {
                            drawingState.addPoint(location)
                        }
                    }
                }
                .onEnded { _ in
                    if drawingState.isDrawingMode {
                        drawingState.finishPath()
                    }
                }
        )
    }
    
    private func drawPath(_ drawingPath: DrawingPath, in context: GraphicsContext, size: CGSize) {
        guard drawingPath.points.count > 1 else { return }
        
        var path = Path()
        path.move(to: drawingPath.points[0])
        
        for i in 1..<drawingPath.points.count {
            path.addLine(to: drawingPath.points[i])
        }
        
        context.stroke(
            path,
            with: .color(.red),
            lineWidth: drawingPath.lineWidth
        )
    }
}
