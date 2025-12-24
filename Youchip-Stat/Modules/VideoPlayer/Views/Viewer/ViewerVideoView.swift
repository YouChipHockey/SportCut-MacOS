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
        return videoSize.height > videoSize.width ? 90 : 0
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(^String.Titles.video)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Button(action: {
                        if playlistManager.isPlaying {
                            player?.pause()
                            playlistManager.isPlaying = false
                        }
                        
                        drawingState.showDrawingMenu.toggle()
                    }) {
                        Image(systemName: drawingState.showDrawingMenu ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                            .font(.system(size: 16))
                            .foregroundColor(drawingState.showDrawingMenu ? .blue : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(^String.Titles.drawingTools)
                    .popover(isPresented: $drawingState.showDrawingMenu, arrowEdge: .bottom) {
                        DrawingToolsMenu(
                            drawingState: drawingState,
                            onReset: {
                                drawingState.clearDrawing()
                                drawingState.isDrawingMode = false
                                drawingState.showDrawingMenu = false
                                
                                if !organizer.currentTags.isEmpty && !playlistManager.isPlaying {
                                    playlistManager.setPlaylist(organizer.currentTags)
                                    playlistManager.playPlaylist()
                                    playCurrentPlaylist()
                                }
                            }
                        )
                    }
                    
                    if drawingState.hasDrawing {
                        Button(action: {
                            drawingState.clearDrawing()
                        }) {
                            Image(systemName: "trash.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(^String.Titles.clearDrawing)
                    }
                    
                    Button(action: {
                        saveScreenshot()
                    }) {
                        Image(systemName: "camera.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(^String.Titles.saveScreenshot)
                }
                
                if playlistManager.isPlaying {
                    Button(action: {
                        player?.pause()
                        playlistManager.isPlaying = false
                    }) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Button(action: {
                        if organizer.currentTags.isEmpty {
                        } else {
                            drawingState.clearDrawing()
                            drawingState.isDrawingMode = false
                            drawingState.showDrawingMenu = false
                            
                            playlistManager.setPlaylist(organizer.currentTags)
                            playlistManager.playPlaylist()
                            playCurrentPlaylist()
                        }
                    }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            
            Divider()
            
            ZStack {
                if let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(videoAspectRatio, contentMode: .fit)
                        .rotationEffect(.degrees(videoRotation))
                        .background(Color.black)
                        .overlay(
                            DrawingOverlay(drawingState: drawingState)
                                .allowsHitTesting(drawingState.isDrawingMode)
                        )
                        .overlay(alignment: .bottom) {
                            videoOverlayText()
                                .padding(.bottom, 45)
                        }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text(^String.Titles.noVideoToPlay)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if organizer.currentTags.isEmpty {
                            Text(^String.Titles.addTagsToOrganizer)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        } else {
                            Text(^String.Titles.pressPlayButton)
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
            if playlistManager.isPlaying {
                createCompositionFromPlaylist()
            }
        }
        .onChange(of: playlistManager.isPlaying) { isPlaying in
            if isPlaying {
                player?.play()
            } else {
                player?.pause()
            }
//            if isPlaying && !playlistManager.currentPlaylist.isEmpty {
//                createCompositionFromPlaylist()
//            } else if !isPlaying {
//                player?.pause()
//            }
        }
    }
    
    private func setupPlayer() {
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
            return
        }
        
        let composition = AVMutableComposition()
        
        guard let videoTrack = originalAsset.tracks(withMediaType: .video).first,
              let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
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
                return
            }
        }
        
        currentComposition = composition
        let playerItem = AVPlayerItem(asset: composition)
        player?.replaceCurrentItem(with: playerItem)
        updateVideoSize(from: originalAsset)
        player?.play()
        playlistManager.isPlaying = true
    }
    
    private func updateVideoSize(from asset: AVAsset) {
        let videoTracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { return }
        
        let size = videoTrack.naturalSize
        let transform = videoTrack.preferredTransform
        
        let actualSize: CGSize
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            actualSize = CGSize(width: size.height, height: size.width)
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            actualSize = CGSize(width: size.height, height: size.width)
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            actualSize = size
        } else {
            actualSize = size
        }
        
        DispatchQueue.main.async {
            self.videoSize = actualSize
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .playSingleTag,
            object: nil,
            queue: .main
        ) { notification in
            if let tag = notification.object as? OrganizerTag {
                self.drawingState.clearDrawing()
                self.drawingState.isDrawingMode = false
                self.drawingState.showDrawingMenu = false
                
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
    
    func forceStopPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playlistManager.stopPlayback()
    }
    
    private func saveScreenshot() {
        player?.pause()
        playlistManager.isPlaying = false
        
        guard let player = player else { return }
        
        let currentTime = player.currentTime()
        let imageGenerator = AVAssetImageGenerator(asset: player.currentItem?.asset ?? AVAsset())
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: currentTime, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            let finalImage = createImageWithDrawing(originalImage: nsImage)
            let panel = NSSavePanel()
            panel.allowedFileTypes = ["png"]
            panel.nameFieldStringValue = "screenshot_\(Int(currentTime.seconds)).png"
            
            if panel.runModal() == .OK, let url = panel.url {
                if let tiffData = finalImage.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    try pngData.write(to: url)
                    print(String(format: ^String.Titles.screenshotSaved, url.path))
                }
            }
        } catch {
            print(String(format: ^String.Titles.errorCreatingScreenshot, error.localizedDescription))
        }
    }
    
    private func createImageWithDrawing(originalImage: NSImage) -> NSImage {
        let size = originalImage.size
        let finalImage = NSImage(size: size)
        
        finalImage.lockFocus()
        originalImage.draw(in: NSRect(origin: .zero, size: size))
        for path in drawingState.completedPaths {
            drawPath(path, in: NSRect(origin: .zero, size: size))
        }
        if !drawingState.currentPath.points.isEmpty {
            drawPath(drawingState.currentPath, in: NSRect(origin: .zero, size: size))
        }
        
        finalImage.unlockFocus()
        
        return finalImage
    }
    
    private func drawPath(_ path: DrawingPath, in rect: NSRect) {
        guard path.points.count > 1 else { return }
        
        let bezierPath = NSBezierPath()
        
        let viewSize = drawingState.viewSize
        let scaleX = viewSize.width > 0 ? rect.width / viewSize.width : 1.0
        let scaleY = viewSize.height > 0 ? rect.height / viewSize.height : 1.0
        let scaledX = path.points[0].x * scaleX
        let scaledY = path.points[0].y * scaleY
        let flippedFirstPoint = CGPoint(x: scaledX, y: rect.height - scaledY)
        bezierPath.move(to: flippedFirstPoint)
        for i in 1..<path.points.count {
            let scaledX = path.points[i].x * scaleX
            let scaledY = path.points[i].y * scaleY
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
    
    @ViewBuilder
    private func videoOverlayText() -> some View {
        if let currentPlayingStamp = playlistManager.currentPlaylist.first {
            let tagLibrary = TagLibraryManager.shared
            
            let stampID = currentPlayingStamp.stampID
            let stamp = TimelineDataManager.shared.lines
                .flatMap { $0.stamps }
                .first { $0.id == stampID }
            let tag = tagLibrary.allTags.first { $0.id == currentPlayingStamp.mainTagID }
            let stampLabels = currentPlayingStamp.labelIDs.compactMap { labelID in
                tagLibrary.allLabels.first(where: { $0.id == labelID })
            }
            let selectedLabelGroups: [OverlayLabelGroupItem] = Dictionary(grouping: stampLabels) { label in
                tagLibrary.allLabelGroups.first(where: { $0.lables.contains(label.id) })
            }
            .compactMap { (group, labels) in
                guard let group = group else { return nil }
                return OverlayLabelGroupItem(group: group, selectedLabels: labels)
            }
            if let tag, let stamp {
                let overlayItem = OverlayItem(tag: tag, stamp: stamp, selectedLabelGroups: selectedLabelGroups, start: .zero, duration: .zero, videoSize: nil)
                let attributedString = NSAttributedString.attributedStringForTagInfo(overlayItem: overlayItem) ?? NSAttributedString(string: "")
                Text(AttributedString(attributedString))
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Rectangle()
                            .fill(.black.opacity(0.55))
                )
            }
        }
    }

}

struct DrawingOverlay: View {
    @ObservedObject var drawingState: DrawingState
    @State private var dragLocation: CGPoint = .zero
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                DispatchQueue.main.async {
                    if drawingState.viewSize != size {
                        drawingState.viewSize = size
                    }
                }
                
                for path in drawingState.completedPaths {
                    drawPath(path, in: context, size: size)
                }
                
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
    }
    
    private func drawPath(_ drawingPath: DrawingPath, in context: GraphicsContext, size: CGSize) {
        guard drawingPath.points.count > 1 else { return }
        
        var path = Path()
        path.move(to: drawingPath.points[0])
        
        for i in 1..<drawingPath.points.count {
            path.addLine(to: drawingPath.points[i])
        }
        
        var strokeStyle = StrokeStyle(lineWidth: drawingPath.lineWidth, lineCap: .round, lineJoin: .round)
        if let dashPattern = drawingPath.lineStyle.dashPattern {
            strokeStyle.dash = dashPattern
        }
        
        context.stroke(
            path,
            with: .color(drawingPath.color),
            style: strokeStyle
        )
    }
}

struct DrawingToolsMenu: View {
    @ObservedObject var drawingState: DrawingState
    @State private var showSettings = false
    let onReset: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Text(^String.Titles.drawingTools)
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 8)
            
            Divider()
            
            Button(action: {
                if drawingState.currentTool == .pencil && drawingState.isDrawingMode {
                    drawingState.isDrawingMode = false
                } else {
                    drawingState.currentTool = .pencil
                    drawingState.isDrawingMode = true
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.tip")
                        .font(.system(size: 16))
                        .foregroundColor(drawingState.currentTool == .pencil && drawingState.isDrawingMode ? .blue : .primary)
                    
                    Text(^String.Titles.pencil)
                        .font(.system(size: 13))
                    
                    Spacer()
                    
                    if drawingState.currentTool == .pencil && drawingState.isDrawingMode {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(drawingState.currentTool == .pencil && drawingState.isDrawingMode ? Color.blue.opacity(0.1) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                if drawingState.currentTool == .eraser && drawingState.isDrawingMode {
                    drawingState.isDrawingMode = false
                } else {
                    drawingState.currentTool = .eraser
                    drawingState.isDrawingMode = true
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "eraser")
                        .font(.system(size: 16))
                        .foregroundColor(drawingState.currentTool == .eraser && drawingState.isDrawingMode ? .blue : .primary)
                    
                    Text(^String.Titles.eraser)
                        .font(.system(size: 13))
                    
                    Spacer()
                    
                    if drawingState.currentTool == .eraser && drawingState.isDrawingMode {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(drawingState.currentTool == .eraser && drawingState.isDrawingMode ? Color.blue.opacity(0.1) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            Divider()
            
            Button(action: {
                showSettings = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                    
                    Text(^String.Titles.settings)
                        .font(.system(size: 13))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())
            
            Divider()
            
            Button(action: {
                onReset()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                    
                    Text(^String.Titles.reset)
                        .font(.system(size: 13))
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 8)
        .frame(width: 200)
        .sheet(isPresented: $showSettings) {
            DrawingSettingsSheet(settings: drawingState.settings)
        }
    }
}

struct DrawingSettingsSheet: View {
    @ObservedObject var settings: DrawingSettings
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(^String.Titles.drawingSettings)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.lineWidth)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        HStack {
                            Slider(value: $settings.lineWidth, in: 1...20, step: 1)
                            
                            Text("\(Int(settings.lineWidth)) \(^String.Titles.pixels)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                        
                        Rectangle()
                            .fill(settings.color)
                            .frame(height: settings.lineWidth)
                            .cornerRadius(settings.lineWidth / 2)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.lineStyleDrawing)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                settings.lineStyle = .solid
                            }) {
                                VStack(spacing: 4) {
                                    Rectangle()
                                        .fill(settings.lineStyle == .solid ? Color.blue : Color.gray)
                                        .frame(width: 60, height: 4)
                                    
                                    Text(^String.Titles.normal)
                                        .font(.system(size: 10))
                                        .foregroundColor(settings.lineStyle == .solid ? .blue : .secondary)
                                }
                                .padding(8)
                                .background(settings.lineStyle == .solid ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                settings.lineStyle = .dashed
                            }) {
                                VStack(spacing: 4) {
                                    HStack(spacing: 2) {
                                        ForEach(0..<3) { _ in
                                            Rectangle()
                                                .fill(settings.lineStyle == .dashed ? Color.blue : Color.gray)
                                                .frame(width: 12, height: 4)
                                        }
                                    }
                                    
                                    Text(^String.Titles.dashed)
                                        .font(.system(size: 10))
                                        .foregroundColor(settings.lineStyle == .dashed ? .blue : .secondary)
                                }
                                .padding(8)
                                .background(settings.lineStyle == .dashed ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.color)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        ColorPicker(^String.Titles.selectColor, selection: $settings.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.eraserWidth)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        HStack {
                            Slider(value: $settings.eraserWidth, in: 10...50, step: 5)
                            
                            Text("\(Int(settings.eraserWidth)) \(^String.Titles.pixels)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            Divider()
            
            HStack(spacing: 12) {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text(^String.Titles.closeButtonTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text(^String.Titles.apply)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 350, height: 500)
    }
}
