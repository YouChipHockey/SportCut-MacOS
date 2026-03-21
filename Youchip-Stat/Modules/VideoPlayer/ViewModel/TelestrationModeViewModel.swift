//
//  TelestrationModeViewModel.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 3/20/26.
//

import SwiftUI
import AVFoundation
import Combine

class TelestrationModeViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var currentTool: TelestrationModeTool = .playerMarker
    @Published var markers: [PlayerMarker] = []
    @Published var zones: [TelestrationZone] = []
    @Published var arrows: [TelestrationAnimatedArrow] = []
    
    @Published var currentFrameIndex: Int = 0
    @Published var totalFrames: Int = 0
    @Published var isPlaying: Bool = false
    @Published var isTracking: Bool = false
    @Published var trackingProgress: Float = 0
    
    @Published var currentFrameImage: NSImage?
    @Published var imageSize: CGSize = .zero
    
    @Published var markerColor: Color = .red
    @Published var zoneSelectingMarkerIDs: [UUID] = []
    @Published var arrowPlacementPhase: ArrowPlacementPhase = .placingStart
    @Published var pendingArrow: TelestrationAnimatedArrow?
    
    @Published var arrowColor: Color = .white
    @Published var arrowAnimationDuration: Double = 1.5
    @Published var zoneColor: Color = .yellow
    
    @Published var draggedMarkerID: UUID?
    
    @Published var pauseBeforePlay: Double = 2.0
    
    // MARK: - Private
    
    private let videoURL: URL
    private let clipStartTime: Double
    private let clipEndTime: Double
    private let frameRate: Double
    
    private var extractedFrames: [CGImage] = []
    private let tracker = PixelTemplateTracker(templateWidth: 22, templateHeight: 36, searchRadius: 40)
    private var playbackTimer: Timer?
    private var playbackStartDate: Date?
    
    private static let markerColors: [Color] = [.red, .blue, .green, .orange, .purple, .cyan, .pink, .yellow]
    private var nextColorIndex = 0
    
    // MARK: - Init
    
    init(videoURL: URL, clipStartTime: Double, clipEndTime: Double, frameRate: Double = 30) {
        self.videoURL = videoURL
        self.clipStartTime = clipStartTime
        self.clipEndTime = clipEndTime
        self.frameRate = min(frameRate, 15.0)
        
        let duration = clipEndTime - clipStartTime
        self.totalFrames = max(1, Int(ceil(duration * self.frameRate)))
    }
    
    // MARK: - Frame Extraction
    
    func extractFrames(completion: @escaping () -> Void) {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var frames: [CGImage] = []
            
            for i in 0..<self.totalFrames {
                let time = self.clipStartTime + Double(i) / self.frameRate
                let cmTime = CMTime(seconds: time, preferredTimescale: 600)
                
                if let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) {
                    frames.append(cgImage)
                    
                    if i == 0 {
                        let size = CGSize(width: cgImage.width, height: cgImage.height)
                        DispatchQueue.main.async {
                            self.imageSize = size
                            self.currentFrameImage = NSImage(cgImage: cgImage, size: size)
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.extractedFrames = frames
                self.totalFrames = frames.count
                if !frames.isEmpty {
                    self.updateDisplayedFrame()
                }
                completion()
            }
        }
    }
    
    func extractFirstFrame() {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        let cmTime = CMTime(seconds: clipStartTime, preferredTimescale: 600)
        if let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) {
            let size = CGSize(width: cgImage.width, height: cgImage.height)
            DispatchQueue.main.async { [weak self] in
                self?.imageSize = size
                self?.currentFrameImage = NSImage(cgImage: cgImage, size: size)
                self?.extractedFrames = [cgImage]
            }
        }
    }
    
    // MARK: - Tool Actions
    
    func handleCanvasClick(at imagePoint: CGPoint) {
        guard imagePoint.x >= 0, imagePoint.y >= 0,
              imagePoint.x <= imageSize.width, imagePoint.y <= imageSize.height else { return }
        
        switch currentTool {
        case .playerMarker:
            addMarker(at: imagePoint)
        case .zone:
            toggleMarkerForZone(at: imagePoint)
        case .animatedArrow:
            handleArrowClick(at: imagePoint)
        }
    }
    
    // MARK: - Player Marker
    
    private func addMarker(at point: CGPoint) {
        guard currentFrameIndex < extractedFrames.count else { return }
        let frame = extractedFrames[currentFrameIndex]
        
        let template = tracker.captureTemplate(from: frame, at: point)
        
        let color = Self.markerColors[nextColorIndex % Self.markerColors.count]
        nextColorIndex += 1
        
        var marker = PlayerMarker(color: color)
        marker.template = template
        marker.positions[currentFrameIndex] = TrackedPosition(center: point, isManualOverride: true)
        
        markers.append(marker)
    }
    
    func removeMarker(_ markerID: UUID) {
        markers.removeAll { $0.id == markerID }
        for i in zones.indices {
            zones[i].markerIDs.removeAll { $0 == markerID }
        }
        zones.removeAll { $0.markerIDs.count < 2 }
        zoneSelectingMarkerIDs.removeAll { $0 == markerID }
    }
    
    // MARK: - Zone
    
    private func toggleMarkerForZone(at point: CGPoint) {
        guard let closestMarker = findClosestMarker(to: point, threshold: 40) else { return }
        
        if zoneSelectingMarkerIDs.contains(closestMarker.id) {
            zoneSelectingMarkerIDs.removeAll { $0 == closestMarker.id }
        } else {
            zoneSelectingMarkerIDs.append(closestMarker.id)
        }
    }
    
    func confirmZone() {
        guard zoneSelectingMarkerIDs.count >= 2 else { return }
        let zone = TelestrationZone(
            markerIDs: zoneSelectingMarkerIDs,
            fillColor: zoneColor,
            edgeColor: zoneColor.opacity(0.8)
        )
        zones.append(zone)
        zoneSelectingMarkerIDs.removeAll()
    }
    
    func removeZone(_ zoneID: UUID) {
        zones.removeAll { $0.id == zoneID }
    }
    
    // MARK: - Animated Arrow
    
    private func handleArrowClick(at point: CGPoint) {
        switch arrowPlacementPhase {
        case .placingStart:
            var arrow = TelestrationAnimatedArrow(color: arrowColor, animationDuration: arrowAnimationDuration)
            arrow.startPoint = point
            pendingArrow = arrow
            arrowPlacementPhase = .placingEnd
        case .placingEnd:
            guard var arrow = pendingArrow else { return }
            arrow.endPoint = point
            arrows.append(arrow)
            pendingArrow = nil
            arrowPlacementPhase = .placingStart
        }
    }
    
    func cancelArrowPlacement() {
        pendingArrow = nil
        arrowPlacementPhase = .placingStart
    }
    
    func removeArrow(_ arrowID: UUID) {
        arrows.removeAll { $0.id == arrowID }
    }
    
    // MARK: - Manual Correction (Drag Marker)
    
    func startDraggingMarker(at point: CGPoint) -> UUID? {
        guard let marker = findClosestMarker(to: point, threshold: 30) else { return nil }
        draggedMarkerID = marker.id
        return marker.id
    }
    
    func dragMarker(to point: CGPoint) {
        guard let markerID = draggedMarkerID,
              let idx = markers.firstIndex(where: { $0.id == markerID }) else { return }
        
        let clampedPoint = CGPoint(
            x: max(0, min(point.x, imageSize.width)),
            y: max(0, min(point.y, imageSize.height))
        )
        
        markers[idx].positions[currentFrameIndex] = TrackedPosition(
            center: clampedPoint,
            isManualOverride: true
        )
        
        // Re-capture template at new position for better tracking forward
        if currentFrameIndex < extractedFrames.count {
            let frame = extractedFrames[currentFrameIndex]
            markers[idx].template = tracker.captureTemplate(from: frame, at: clampedPoint)
        }
        
        // Invalidate tracked positions after this frame
        for key in markers[idx].positions.keys where key > currentFrameIndex {
            if let pos = markers[idx].positions[key], !pos.isManualOverride {
                markers[idx].positions.removeValue(forKey: key)
            }
        }
    }
    
    func endDraggingMarker() {
        draggedMarkerID = nil
    }
    
    // MARK: - Frame Navigation
    
    func seekToFrame(_ index: Int) {
        let clamped = max(0, min(index, totalFrames - 1))
        currentFrameIndex = clamped
        updateDisplayedFrame()
    }
    
    func stepForward() {
        seekToFrame(currentFrameIndex + 1)
    }
    
    func stepBackward() {
        seekToFrame(currentFrameIndex - 1)
    }
    
    private func updateDisplayedFrame() {
        guard currentFrameIndex < extractedFrames.count else { return }
        let cgImage = extractedFrames[currentFrameIndex]
        currentFrameImage = NSImage(cgImage: cgImage, size: imageSize)
    }
    
    // MARK: - Tracking
    
    func runTracking(completion: @escaping () -> Void) {
        guard !markers.isEmpty else {
            completion()
            return
        }
        
        isTracking = true
        trackingProgress = 0
        
        let markersToTrack = markers.filter { $0.template != nil }
        guard !markersToTrack.isEmpty else {
            isTracking = false
            completion()
            return
        }
        
        // Ensure all frames are extracted
        if extractedFrames.count < totalFrames {
            extractFrames { [weak self] in
                self?.performTracking(markersToTrack: markersToTrack, completion: completion)
            }
        } else {
            performTracking(markersToTrack: markersToTrack, completion: completion)
        }
    }
    
    private func performTracking(markersToTrack: [PlayerMarker], completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let totalMarkers = markersToTrack.count
            let markersCopy = self.markers
            let framesCopy = self.extractedFrames
            
            let lock = NSLock()
            var allResults: [(idx: Int, positions: [Int: TrackedPosition])] = []
            
            DispatchQueue.concurrentPerform(iterations: totalMarkers) { markerIndex in
                let marker = markersToTrack[markerIndex]
                guard let idx = markersCopy.firstIndex(where: { $0.id == marker.id }) else { return }
                
                let startFrame = marker.positions.keys.min() ?? 0
                guard startFrame < framesCopy.count else { return }
                let framesToTrack = Array(framesCopy[startFrame...])
                
                let trackedPositions = self.tracker.trackMarker(
                    markersCopy[idx],
                    through: framesToTrack,
                    startFrameIndex: startFrame
                ) { frameProgress in
                    let overall = (Float(markerIndex) + frameProgress) / Float(totalMarkers)
                    DispatchQueue.main.async {
                        self.trackingProgress = max(self.trackingProgress, overall)
                    }
                }
                
                let smoothedPositions = self.tracker.smoothPositions(trackedPositions)
                
                lock.lock()
                allResults.append((idx: idx, positions: smoothedPositions))
                lock.unlock()
            }
            
            DispatchQueue.main.async {
                for result in allResults {
                    if result.idx < self.markers.count {
                        self.markers[result.idx].positions = result.positions
                    }
                }
                self.isTracking = false
                self.trackingProgress = 1.0
                completion()
            }
        }
    }
    
    // MARK: - Tracking (standalone)
    
    func trackMarkers() {
        guard !isTracking else { return }
        runTracking { }
    }
    
    // MARK: - Playback
    
    func play() {
        guard !isPlaying else { return }
        
        updateDisplayedFrame()
        isPlaying = true
        playbackStartDate = Date()
        
        let interval = 1.0 / self.frameRate
        playbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.currentFrameIndex < self.totalFrames - 1 {
                self.currentFrameIndex += 1
                self.updateDisplayedFrame()
            } else {
                self.stop()
            }
        }
    }
    
    func stop() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackStartDate = nil
    }
    
    func togglePlayPause() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }
    
    // MARK: - Helpers
    
    private func findClosestMarker(to point: CGPoint, threshold: CGFloat) -> PlayerMarker? {
        var closestMarker: PlayerMarker?
        var closestDistance: CGFloat = threshold
        
        for marker in markers {
            guard let pos = marker.position(at: currentFrameIndex) else { continue }
            let distance = hypot(pos.x - point.x, pos.y - point.y)
            if distance < closestDistance {
                closestDistance = distance
                closestMarker = marker
            }
        }
        
        return closestMarker
    }
    
    /// Current playback time offset within the clip (seconds from clip start)
    var currentClipTime: Double {
        Double(currentFrameIndex) / frameRate
    }
    
    /// Total clip duration in seconds
    var clipDuration: Double {
        clipEndTime - clipStartTime
    }
    
    /// Access to extracted frames (for export)
    var frames: [CGImage] {
        extractedFrames
    }
    
    var videoAssetURL: URL {
        videoURL
    }
    
    var clipStart: Double {
        clipStartTime
    }
    
    var clipEnd: Double {
        clipEndTime
    }
    
    var fps: Double {
        frameRate
    }
    
    deinit {
        playbackTimer?.invalidate()
    }
}
