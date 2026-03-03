//
//  LiveStreamManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 14/02/26.
//

import Foundation
import AVFoundation
import Combine
import AppKit
import CoreImage
import HaishinKit
import ObjectiveC

/// Manages live capture using HaishinKit's MediaMixer for camera/mic capture and MTHKView for preview.
/// Recording is done via a custom MediaMixerOutput that writes to AVAssetWriter.
class LiveStreamManager: NSObject, ObservableObject {
    
    static let shared = LiveStreamManager()
    
    // MARK: - Published State
    
    @Published var isLive: Bool = false
    @Published var isBroadcastPaused: Bool = false
    @Published var liveDuration: Double = 0.0
    @Published var availableVideoDevices: [AVCaptureDevice] = []
    @Published var availableAudioDevices: [AVCaptureDevice] = []
    @Published var isSessionConfigured: Bool = false
    
    // MARK: - HaishinKit
    
    /// MediaMixer actor — the heart of HaishinKit: manages camera/mic capture and routes frames.
    private(set) var mixer: MediaMixer?
    
    /// Custom recorder output that receives frames from MediaMixer and writes to AVAssetWriter.
    private var recorder: LiveStreamRecorder?
    
    /// MTHKView instance for Metal-based preview rendering.
    private(set) var previewView: MTHKView?
    
    /// Output that keeps the latest video frame for editor capture (Metal view doesn't give a valid bitmap).
    private var latestFrameCapture: LiveFrameCaptureOutput?
    
    // MARK: - Recording state
    
    /// Incremented each time a new review snapshot is ready; triggers review player refresh.
    @Published var reviewFileVersion: Int = 0
    /// All finalized recording segments (stop-restart per refresh cycle). Used for composition.
    private(set) var allSegmentURLs: [URL] = []
    private var isReviewRefreshInProgress: Bool = false
    
    private var durationTimer: DispatchSourceTimer?
    private var reviewRefreshTimer: DispatchSourceTimer?
    private var recordingStartDate: Date?
    private var accumulatedDurationBeforePause: Double = 0.0
    
    private var tempFileURL: URL?
    private var currentVideoId: String?
    private var isAudioAttached: Bool = false
    
    /// Unique session ID to prevent stale async callbacks from overwriting a newer session.
    private var sessionId: UUID = UUID()
    
    // MARK: - Init
    
    override init() {
        super.init()
    }
    
    // MARK: - Device Discovery
    
    func discoverDevices() {
        let videoDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        availableVideoDevices = videoDiscovery.devices
        
        let audioDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        availableAudioDevices = audioDiscovery.devices
    }
    
    func getAvailableFormats(for device: AVCaptureDevice) -> [(format: AVCaptureDevice.Format, description: String)] {
        var results: [(format: AVCaptureDevice.Format, description: String)] = []
        var seenResolutions = Set<String>()
        
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let width = Int(dimensions.width)
            let height = Int(dimensions.height)
            let key = "\(width)x\(height)"
            
            guard !seenResolutions.contains(key) else { continue }
            seenResolutions.insert(key)
            
            // Use first (preferred) range so picker shows realistic FPS (e.g. 50 for PAL camera, 30 for iPhone).
            let preferredFps = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30
            let description = "\(width) x \(height) @ \(Int(preferredFps))fps"
            results.append((format: format, description: description))
        }
        
        results.sort { lhs, rhs in
            let lhsDims = CMVideoFormatDescriptionGetDimensions(lhs.format.formatDescription)
            let rhsDims = CMVideoFormatDescriptionGetDimensions(rhs.format.formatDescription)
            return Int(lhsDims.width) * Int(lhsDims.height) > Int(rhsDims.width) * Int(rhsDims.height)
        }
        
        return results
    }
    
    // MARK: - Session Configuration (using HaishinKit MediaMixer)
    
    func configureSession(
        videoDevice: AVCaptureDevice,
        audioDevice: AVCaptureDevice?,
        format: AVCaptureDevice.Format?
    ) -> Bool {
        AVCaptureDevice.applyFrameDurationPatchIfNeeded(for: videoDevice)
        let thisSessionId = UUID()
        self.sessionId = thisSessionId
        
        // ── Synchronous teardown of previous session ──
        let oldMixer = self.mixer
        let oldRecorder = self.recorder
        let oldPreview = self.previewView
        let oldFrameCapture = self.latestFrameCapture
        
        self.mixer = nil
        self.recorder = nil
        self.previewView = nil
        self.latestFrameCapture = nil
        self.isSessionConfigured = false
        self.isLive = false
        self.isBroadcastPaused = false
        
        if let oldMixer = oldMixer {
            Task {
                if let oldRecorder = oldRecorder {
                    await oldMixer.removeOutput(oldRecorder)
                }
                if let oldPreview = oldPreview {
                    await oldMixer.removeOutput(oldPreview)
                }
                if let oldFrameCapture = oldFrameCapture {
                    await oldMixer.removeOutput(oldFrameCapture)
                }
                await oldMixer.stopRunning()
                try? await oldMixer.attachVideo(nil)
                try? await oldMixer.attachAudio(nil)
            }
        }
        oldRecorder?.cancelRecording()
        
        // ── Create new session ──
        let newMixer = MediaMixer(useManualCapture: true)
        
        // Reuse existing preview view if it already exists in the SwiftUI hierarchy.
        let view: MTHKView
        if let existingView = self.previewView {
            view = existingView
        } else {
            let createdView = MTHKView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
            createdView.videoGravity = .resizeAspect
            view = createdView
        }
        
        if let format = format {
            do {
                try videoDevice.lockForConfiguration()
                videoDevice.activeFormat = format
                if let range = format.videoSupportedFrameRateRanges.first {
                    // Use the device's exact frame durations from the supported range.
                    // Physical capture cards require these exact values (e.g. 1000000/60000240),
                    // not arbitrary 1/fps, otherwise setActiveVideoMinFrameDuration throws.
                    videoDevice.activeVideoMinFrameDuration = range.minFrameDuration
                    videoDevice.activeVideoMaxFrameDuration = range.maxFrameDuration
                }
                videoDevice.unlockForConfiguration()
            } catch {
                print("LiveStreamManager: Failed to set device format: \(error)")
            }
        }
        let activeFormat = format ?? videoDevice.activeFormat
        let initialFrameRate = activeFormat.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30
        isAudioAttached = false
        Task {
            do {
                await newMixer.setFrameRate(initialFrameRate)
                try await newMixer.attachVideo(videoDevice, track: 0)
                
                // Use actual device frame duration after attach so mixer FPS matches capture (avoids slow-mo).
                // Device may have been clamped by our patch or driver (e.g. 50 fps camera with 60 in format).
                var actualFps: Double = initialFrameRate
                do {
                    try videoDevice.lockForConfiguration()
                    defer { videoDevice.unlockForConfiguration() }
                    let minDuration = videoDevice.activeVideoMinFrameDuration
                    let sec = CMTimeGetSeconds(minDuration)
                    if sec > 0 {
                        actualFps = 1.0 / sec
                    }
                } catch { /* keep initialFrameRate */ }
                await newMixer.setFrameRate(actualFps)
                
                // Always use system microphone (MacBook mic) for now.
                var audioAttached = false
                if let systemAudio = AVCaptureDevice.default(for: .audio)
                    ?? self.availableAudioDevices.first(where: { $0.deviceType == .builtInMicrophone })
                    ?? self.availableAudioDevices.first {
                    do {
                        try await newMixer.attachAudio(systemAudio, track: 0)
                        audioAttached = true
                        print("LiveStreamManager: Using system audio device: \(systemAudio.localizedName)")
                    } catch {
                        print("LiveStreamManager: Failed to attach system audio device: \(error)")
                    }
                }
                
                var videoMixerSettings = await newMixer.videoMixerSettings
                videoMixerSettings.mode = .passthrough
                await newMixer.setVideoMixerSettings(videoMixerSettings)
                
                await newMixer.addOutput(view)
                
                let frameCapture = LiveFrameCaptureOutput()
                await newMixer.addOutput(frameCapture)
                
                await MainActor.run {
                    guard self.sessionId == thisSessionId else { return }
                    self.mixer = newMixer
                    self.previewView = view
                    self.latestFrameCapture = frameCapture
                    self.isSessionConfigured = true
                    self.isAudioAttached = audioAttached
                }
            } catch {
                print("LiveStreamManager: Failed to configure HaishinKit mixer: \(error)")
                await MainActor.run {
                    guard self.sessionId == thisSessionId else { return }
                    self.isSessionConfigured = false
                }
            }
        }
        
        return true
    }
    
    // MARK: - Start Live Stream
    
    func startLiveStream(videoId: String) {
        guard let mixer = mixer else { return }
        
        currentVideoId = videoId
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let liveDir = tempDir.appendingPathComponent("LiveRecordings")
        if !fileManager.fileExists(atPath: liveDir.path) {
            try? fileManager.createDirectory(at: liveDir, withIntermediateDirectories: true)
        }
        
        tempFileURL = liveDir.appendingPathComponent("\(videoId).mov")
        
        if let url = tempFileURL, fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        
        let newRecorder = LiveStreamRecorder(outputURL: tempFileURL!, enableAudio: isAudioAttached)
        self.recorder = newRecorder
        
        Task {
            await mixer.addOutput(newRecorder)
            await mixer.startRunning()
            newRecorder.startRecording()
            
            await MainActor.run {
                self.isLive = true
                self.isBroadcastPaused = false
                self.liveDuration = 0.0
                self.accumulatedDurationBeforePause = 0.0
                self.recordingStartDate = Date()
                self.allSegmentURLs = []
                self.isReviewRefreshInProgress = false
                self.reviewFileVersion = 0
                self.startDurationTimer()
                self.performStartupPauseResume()
            }
        }
    }
    
    // MARK: - Startup stabilization
    
    private func performStartupPauseResume() {
        // Simulate user pressing "pause broadcast" and then "continue"
        // to stabilize the first frames and avoid black video on new sessions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard LiveStreamManager.shared.isLive else { return }
            VideoPlayerManager.shared.stopBroadcast()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard LiveStreamManager.shared.isLive else { return }
                VideoPlayerManager.shared.resumeBroadcast()
            }
        }
    }
    
    // MARK: - Pause / Resume Broadcast
    
    func pauseBroadcast() {
        guard isLive, !isBroadcastPaused else { return }
        
        recorder?.pauseRecording()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isBroadcastPaused = true
            self.accumulatedDurationBeforePause = self.liveDuration
            self.stopDurationTimer()
        }
    }
    
    func resumeBroadcast() {
        guard isLive, isBroadcastPaused else { return }
        
        recorder?.resumeRecording()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isBroadcastPaused = false
            self.recordingStartDate = Date()
            self.startDurationTimer()
        }
    }
    
    /// Захват текущего кадра для редактора (режим real-time). Берёт последний кадр из потока микшера (Metal-превью не даёт растр). Вызывать с main queue.
    func captureCurrentFrame() -> NSImage? {
        guard Thread.isMainThread else { return nil }
        return latestFrameCapture?.takeSnapshot()
    }
    
    /// Финализирует текущий фрагмент записи и отдаёт копию файла для экспорта (при паузе или во время записи); затем запускает новый рекордер.
    func prepareCurrentRecordingForExport(completion: @escaping (URL?) -> Void) {
        guard isLive, let currentRecorder = recorder, let videoId = currentVideoId else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let sessionId = self.sessionId
        currentRecorder.stopRecording { [weak self] in
            guard let self = self, self.sessionId == sessionId else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let sourceURL = self.tempFileURL!
            let exportCopyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("LiveExport_\(videoId)_\(UUID().uuidString).mov")
            do {
                if FileManager.default.fileExists(atPath: exportCopyURL.path) {
                    try FileManager.default.removeItem(at: exportCopyURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: exportCopyURL)
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(exportCopyURL) }
            Task { [weak self] in
                await self?.replaceRecorderAfterExport()
            }
        }
    }
    
    /// Строит composition из уже завершённых сегментов без остановки текущей записи.
    /// Безопасен для вызова в любой момент — запись не прерывается.
    func snapshotCompositionForExport(completion: @escaping (AVAsset?) -> Void) {
        let segments = allSegmentURLs
        guard !segments.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        Task { [weak self] in
            guard let self = self else { DispatchQueue.main.async { completion(nil) }; return }
            let composition = await self.buildCompositionFromSegments(segments)
            await MainActor.run { completion(composition) }
        }
    }

    /// Финализирует все накопленные сегменты + текущий, строит composition из всей записи и возвращает его как AVAsset для экспорта.
    /// Затем запускает новый рекордер для продолжения записи.
    func prepareFullCompositionForExport(completion: @escaping (AVAsset?) -> Void) {
        guard isLive, let currentRecorder = recorder, let _ = currentVideoId else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let sessionId = self.sessionId
        currentRecorder.stopRecording { [weak self] in
            guard let self = self, self.sessionId == sessionId else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            if let currentURL = self.tempFileURL {
                self.allSegmentURLs.append(currentURL)
            }
            let allSegments = self.allSegmentURLs
            Task { [weak self] in
                guard let self = self else { DispatchQueue.main.async { completion(nil) }; return }
                let composition = await self.buildCompositionFromSegments(allSegments)
                DispatchQueue.main.async { completion(composition) }
                await self.replaceRecorderAfterExport()
            }
        }
    }

    /// После экспорта при паузе: подменяем рекордер на новый (пишем в новый файл при возобновлении).
    private func replaceRecorderAfterExport() async {
        guard let mixer = mixer, let videoId = currentVideoId else { return }
        let fileManager = FileManager.default
        let liveDir = fileManager.temporaryDirectory.appendingPathComponent("LiveRecordings")
        if !fileManager.fileExists(atPath: liveDir.path) {
            try? fileManager.createDirectory(at: liveDir, withIntermediateDirectories: true)
        }
        let newTempURL = liveDir.appendingPathComponent("\(videoId)_resumed_\(UUID().uuidString).mov")
        let oldRecorder = recorder
        let newRecorder = LiveStreamRecorder(outputURL: newTempURL)
        await mixer.removeOutput(oldRecorder!)
        await mixer.addOutput(newRecorder)
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.recorder = newRecorder
            self.tempFileURL = newTempURL
            newRecorder.startRecording()
        }
    }
    
    // MARK: - Stop & Finalize
    
    func stopAndFinalize(completion: @escaping (URL?) -> Void) {
        guard isLive else {
            completion(nil)
            return
        }
        
        stopDurationTimer()
        stopReviewRefresher()
        
        let mixerToStop = self.mixer
        let recorderToStop = self.recorder
        let previewToRemove = self.previewView
        let finalizeSessionId = self.sessionId
        let currentTempURL = self.tempFileURL
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.sessionId == finalizeSessionId else { return }
            self.isLive = false
            self.isBroadcastPaused = false
        }
        
        recorderToStop?.stopRecording { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // Add the last segment to the list.
            if let url = currentTempURL {
                self.allSegmentURLs.append(url)
            }
            let allSegments = self.allSegmentURLs
            
            Task {
                // Concatenate all segments if there are multiple; otherwise just move the single file.
                let finalURL: URL?
                if allSegments.count <= 1 {
                    finalURL = self.moveToPermanentLocation()
                } else {
                    finalURL = await self.concatenateSegmentsToFinalLocation(segments: allSegments)
                }
                
                if let mixerToStop = mixerToStop {
                    if let recorderToStop = recorderToStop {
                        await mixerToStop.removeOutput(recorderToStop)
                    }
                    if let previewToRemove = previewToRemove {
                        await mixerToStop.removeOutput(previewToRemove)
                    }
                    await mixerToStop.stopRunning()
                }
                
                await MainActor.run {
                    completion(finalURL)
                }
            }
        }
    }
    
    // MARK: - Segment Concatenation
    
    /// Builds an AVMutableComposition from the given segment URLs (no export, for direct playback).
    func buildCompositionFromSegments(_ urls: [URL]) async -> AVMutableComposition {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return composition }
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var insertTime = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            do {
                let duration = try await asset.load(.duration)
                guard duration.isValid && duration.seconds > 0 else { continue }
                let timeRange = CMTimeRange(start: .zero, duration: duration)
                if let vt = try? await asset.loadTracks(withMediaType: .video).first {
                    try? videoTrack.insertTimeRange(timeRange, of: vt, at: insertTime)
                }
                if let at = try? await asset.loadTracks(withMediaType: .audio).first {
                    try? audioTrack?.insertTimeRange(timeRange, of: at, at: insertTime)
                }
                insertTime = CMTimeAdd(insertTime, duration)
            } catch {
                print("LiveStreamManager: Failed to load segment \(url.lastPathComponent): \(error)")
            }
        }
        return composition
    }
    
    private func concatenateSegmentsToFinalLocation(segments: [URL]) async -> URL? {
        guard let videoId = currentVideoId else { return nil }
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = documentsDir.appendingPathComponent("Recordings")
        if !fileManager.fileExists(atPath: recordingsDir.path) {
            try? fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }
        let finalURL = recordingsDir.appendingPathComponent("\(videoId).mov")
        if fileManager.fileExists(atPath: finalURL.path) {
            try? fileManager.removeItem(at: finalURL)
        }
        
        let composition = await buildCompositionFromSegments(segments)
        
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            return moveToPermanentLocation()
        }
        exporter.outputURL = finalURL
        exporter.outputFileType = .mov
        await exporter.export()
        
        if exporter.status == .completed {
            // Remove intermediate segment files.
            for url in segments {
                try? fileManager.removeItem(at: url)
            }
            return finalURL
        } else {
            print("LiveStreamManager: Concatenation export failed: \(exporter.error?.localizedDescription ?? "unknown")")
            return moveToPermanentLocation()
        }
    }
    
    func abort() {
        let abortSessionId = self.sessionId
        
        stopDurationTimer()
        stopReviewRefresher()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.sessionId == abortSessionId else { return }
            self.isLive = false
            self.isBroadcastPaused = false
            self.liveDuration = 0.0
        }
        
        let mixerToStop = mixer
        let recorderToStop = recorder
        let previewToRemove = previewView
        
        recorderToStop?.cancelRecording()
        
        Task {
            if let mixerToStop = mixerToStop {
                if let recorderToStop = recorderToStop {
                    await mixerToStop.removeOutput(recorderToStop)
                }
                if let previewToRemove = previewToRemove {
                    await mixerToStop.removeOutput(previewToRemove)
                }
                await mixerToStop.stopRunning()
                try? await mixerToStop.attachVideo(nil)
                try? await mixerToStop.attachAudio(nil)
            }
        }
        
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        cleanupSession()
    }
    
    // MARK: - Move temp file to permanent location
    
    private func moveToPermanentLocation() -> URL? {
        guard let tempURL = tempFileURL, let videoId = currentVideoId else { return nil }
        
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = documentsDir.appendingPathComponent("Recordings")
        
        if !fileManager.fileExists(atPath: recordingsDir.path) {
            try? fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }
        
        let finalURL = recordingsDir.appendingPathComponent("\(videoId).mov")
        
        if fileManager.fileExists(atPath: finalURL.path) {
            try? fileManager.removeItem(at: finalURL)
        }
        
        do {
            try fileManager.moveItem(at: tempURL, to: finalURL)
            return finalURL
        } catch {
            print("LiveStreamManager: Failed to move file: \(error)")
            return tempURL
        }
    }
    
    // MARK: - Duration Timer
    
    private func startDurationTimer() {
        stopDurationTimer()
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self = self, let startDate = self.recordingStartDate else { return }
            let elapsed = Date().timeIntervalSince(startDate)
            self.liveDuration = self.accumulatedDurationBeforePause + elapsed
        }
        durationTimer = timer
        timer.resume()
    }
    
    private func stopDurationTimer() {
        durationTimer?.cancel()
        durationTimer = nil
    }
    
    // MARK: - Review Mode Refresh
    
    func startReviewRefresher() {
        stopReviewRefresher()
        // Trigger an immediate snapshot so the review window has content right away.
        refreshReviewSnapshot()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 5.0, repeating: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.refreshReviewSnapshot()
        }
        reviewRefreshTimer = timer
        timer.resume()
    }
    
    func stopReviewRefresher() {
        reviewRefreshTimer?.cancel()
        reviewRefreshTimer = nil
    }
    
    /// Finalizes the current recording segment, adds it to the segments list, then starts a fresh recorder.
    /// This ensures the review player always gets a properly finalized MOV with correct duration.
    private func refreshReviewSnapshot() {
        guard isLive, !isBroadcastPaused, !isReviewRefreshInProgress,
              let currentRecorder = recorder, let videoId = currentVideoId,
              let currentTempURL = tempFileURL else { return }
        
        isReviewRefreshInProgress = true
        let sessionId = self.sessionId
        
        currentRecorder.stopRecording { [weak self] in
            guard let self = self, self.sessionId == sessionId else { return }
            
            self.allSegmentURLs.append(currentTempURL)
            self.reviewFileVersion += 1
            
            Task { [weak self] in
                await self?.startNewSegmentRecorder(videoId: videoId, sessionId: sessionId)
                await MainActor.run { [weak self] in
                    self?.isReviewRefreshInProgress = false
                }
            }
        }
    }
    
    private func startNewSegmentRecorder(videoId: String, sessionId: UUID) async {
        guard let mixer = mixer, self.sessionId == sessionId else { return }
        let fileManager = FileManager.default
        let liveDir = fileManager.temporaryDirectory.appendingPathComponent("LiveRecordings")
        if !fileManager.fileExists(atPath: liveDir.path) {
            try? fileManager.createDirectory(at: liveDir, withIntermediateDirectories: true)
        }
        let segIndex = allSegmentURLs.count
        let newTempURL = liveDir.appendingPathComponent("\(videoId)_seg\(segIndex).mov")
        let oldRecorder = recorder
        let newRecorder = LiveStreamRecorder(outputURL: newTempURL, enableAudio: isAudioAttached)
        if let oldRecorder = oldRecorder {
            await mixer.removeOutput(oldRecorder)
        }
        await mixer.addOutput(newRecorder)
        await MainActor.run { [weak self] in
            guard let self = self, self.sessionId == sessionId else { return }
            self.recorder = newRecorder
            self.tempFileURL = newTempURL
            newRecorder.startRecording()
            // Restore paused state if broadcast was paused before the refresh.
            if self.isBroadcastPaused {
                newRecorder.pauseRecording()
            }
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanupSession() {
        let cleanupSessionId = self.sessionId
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.sessionId == cleanupSessionId else { return }
            self.mixer = nil
            self.recorder = nil
            self.isSessionConfigured = false
            self.currentVideoId = nil
        }
    }
    
    func fullCleanup() {
        let cleanupSessionId = self.sessionId
        
        stopDurationTimer()
        stopReviewRefresher()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.sessionId == cleanupSessionId else { return }
            self.isLive = false
            self.isBroadcastPaused = false
            self.liveDuration = 0.0
            self.reviewFileVersion = 0
            self.allSegmentURLs = []
            self.isReviewRefreshInProgress = false
        }
        
        let mixerToStop = mixer
        let recorderToCancel = recorder
        
        Task {
            if let mixerToStop = mixerToStop {
                await mixerToStop.stopRunning()
                try? await mixerToStop.attachVideo(nil)
                try? await mixerToStop.attachAudio(nil)
            }
        }
        
        recorderToCancel?.cancelRecording()
        cleanupSession()
    }
}

// MARK: - LiveFrameCaptureOutput

/// Хранит последний видеокадр из микшера для захвата в редактор (Metal-превью через cacheDisplay даёт чёрный экран).
/// Конвертация в NSImage откладывается до момента реального запроса (takeSnapshot), чтобы не тратить GPU на каждый кадр.
final class LiveFrameCaptureOutput: MediaMixerOutput {
    
    var videoTrackId: UInt8? { get async { return UInt8.max } }
    var audioTrackId: UInt8? { get async { return UInt8.max } }
    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}
    
    // Store the raw pixel buffer – converted to NSImage only when actually requested.
    private var _latestPixelBuffer: CVImageBuffer?
    private let bufferLock = NSLock()
    
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    nonisolated func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // O(1): just retain the pixel buffer reference; no rendering here.
        bufferLock.lock()
        _latestPixelBuffer = pixelBuffer
        bufferLock.unlock()
    }
    
    nonisolated func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {}
    
    /// Конвертирует последний сохранённый кадр в NSImage. Вызывать с main queue.
    func takeSnapshot() -> NSImage? {
        assert(Thread.isMainThread)
        bufferLock.lock()
        let pixelBuffer = _latestPixelBuffer
        bufferLock.unlock()
        guard let pixelBuffer else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        guard extent.width >= 1, extent.height >= 1,
              let cgImage = LiveFrameCaptureOutput.ciContext.createCGImage(ciImage, from: extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

// MARK: - LiveStreamRecorder

final class LiveStreamRecorder: MediaMixerOutput, @unchecked Sendable {
    
    var videoTrackId: UInt8? { get async { return UInt8.max } }
    var audioTrackId: UInt8? { get async { return UInt8.max } }
    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}
    
    private let outputURL: URL
    private let enableAudio: Bool
    // .utility keeps disk writes off the high-priority capture thread pool, reducing preview FPS drops.
    private let writerQueue = DispatchQueue(label: "com.youchip.liveRecorder", qos: .utility)
    /// Target FPS for recording (preview can be higher).
    private let targetVideoFPS: Int = 30
    
    // Pre-throttle state – checked BEFORE dispatching to avoid flooding writerQueue with dropped frames.
    private let preThrottleLock = NSLock()
    private var _preThrottleLastPTS: CMTime = .invalid
    
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var isWriterStarted = false
    private var isRecording = false
    
    private let pauseLock = NSLock()
    private var _isPaused = false
    private var isPaused: Bool {
        get { pauseLock.lock(); defer { pauseLock.unlock() }; return _isPaused }
        set { pauseLock.lock(); _isPaused = newValue; pauseLock.unlock() }
    }
    
    private var totalPauseOffset: CMTime = .zero
    private var pauseStartPTS: CMTime = .invalid
    private var lastVideoTimestampBeforePause: CMTime = .invalid
    private var lastAudioTimestampBeforePause: CMTime = .invalid
    private var needsOffsetRecalculation = false
    private var lastVideoWrittenPTS: CMTime = .invalid
    
    init(outputURL: URL, enableAudio: Bool = true) {
        self.outputURL = outputURL
        self.enableAudio = enableAudio
    }
    
    func startRecording() {
        isPaused = false
        preThrottleLock.lock()
        _preThrottleLastPTS = .invalid
        preThrottleLock.unlock()
        writerQueue.async { [weak self] in
            self?.isRecording = true
            self?.totalPauseOffset = .zero
            self?.pauseStartPTS = .invalid
            self?.lastVideoWrittenPTS = .invalid
            self?.lastVideoTimestampBeforePause = .invalid
            self?.lastAudioTimestampBeforePause = .invalid
            self?.needsOffsetRecalculation = false
        }
    }
    
    func pauseRecording() {
        isPaused = true
    }
    
    func resumeRecording() {
        writerQueue.async { [weak self] in
            guard let self = self else { return }
            self.needsOffsetRecalculation = true
            self.isPaused = false
        }
    }
    
    func stopRecording(completion: @escaping () -> Void) {
        writerQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion() }
                return
            }
            
            self.isRecording = false
            
            guard let writer = self.assetWriter, writer.status == .writing else {
                DispatchQueue.main.async { completion() }
                return
            }
            
            self.videoWriterInput?.markAsFinished()
            self.audioWriterInput?.markAsFinished()
            
            writer.finishWriting {
                DispatchQueue.main.async { completion() }
            }
        }
    }
    
    func cancelRecording() {
        writerQueue.async { [weak self] in
            self?.isRecording = false
            self?.assetWriter?.cancelWriting()
            self?.assetWriter = nil
            self?.videoWriterInput = nil
            self?.audioWriterInput = nil
        }
    }
    
    private func adjustedTimestamp(for pts: CMTime, isVideo: Bool) -> CMTime {
        if needsOffsetRecalculation {
            if pauseStartPTS.isValid {
                let pauseGap = CMTimeSubtract(pts, pauseStartPTS)
                if pauseGap.seconds > 0 {
                    totalPauseOffset = CMTimeAdd(totalPauseOffset, pauseGap)
                }
            }
            needsOffsetRecalculation = false
            pauseStartPTS = .invalid
        }
        
        let adjusted = CMTimeSubtract(pts, totalPauseOffset)
        if isVideo {
            lastVideoTimestampBeforePause = adjusted
        } else {
            lastAudioTimestampBeforePause = adjusted
        }
        return adjusted
    }
    
    private func sampleBufferWithAdjustedTime(_ sampleBuffer: CMSampleBuffer, newPTS: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: newPTS,
            decodeTimeStamp: .invalid
        )
        var newSampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &newSampleBuffer
        )
        return status == noErr ? newSampleBuffer : nil
    }
    
    nonisolated func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        guard !isPaused else {
            // Record pause start PTS with minimal queue overhead.
            writerQueue.async { [weak self] in
                guard let self = self else { return }
                if !self.pauseStartPTS.isValid {
                    self.pauseStartPTS = pts
                }
            }
            return
        }
        
        // Pre-throttle: drop frames before dispatching so writerQueue never accumulates
        // a backlog of closures for frames that would be discarded anyway.
        if targetVideoFPS > 0 {
            preThrottleLock.lock()
            let last = _preThrottleLastPTS
            let frameInterval = 1.0 / Double(targetVideoFPS)
            let shouldDrop: Bool
            if last.isValid {
                let delta = CMTimeSubtract(pts, last)
                shouldDrop = delta.seconds >= 0 && delta.seconds < frameInterval
            } else {
                shouldDrop = false
            }
            if !shouldDrop { _preThrottleLastPTS = pts }
            preThrottleLock.unlock()
            // Always let the very first frame through (isWriterStarted == false) regardless.
            if shouldDrop && isWriterStarted { return }
        }
        
        writerQueue.async { [weak self] in
            guard let self = self, self.isRecording else { return }
            guard !self.isPaused else {
                if !self.pauseStartPTS.isValid {
                    self.pauseStartPTS = pts
                }
                return
            }
            
            // Initialize writer on the first frame we actually want to record.
            if !self.isWriterStarted {
                self.setupWriter(with: sampleBuffer)
                self.lastVideoWrittenPTS = pts
            } else {
                // Secondary in-queue throttle as safety net for timing jitter.
                if self.targetVideoFPS > 0, self.lastVideoWrittenPTS.isValid {
                    let frameInterval = 1.0 / Double(self.targetVideoFPS)
                    let delta = CMTimeSubtract(pts, self.lastVideoWrittenPTS)
                    if delta.seconds >= 0 && delta.seconds < frameInterval {
                        return
                    }
                }
            }
            
            guard self.isWriterStarted,
                  let writer = self.assetWriter,
                  writer.status == .writing,
                  let input = self.videoWriterInput,
                  input.isReadyForMoreMediaData else { return }
            
            let adjustedPTS = self.adjustedTimestamp(for: pts, isVideo: true)
            
            if self.totalPauseOffset == .zero {
                input.append(sampleBuffer)
            } else {
                if let adjustedBuffer = self.sampleBufferWithAdjustedTime(sampleBuffer, newPTS: adjustedPTS) {
                    input.append(adjustedBuffer)
                }
            }
            
            self.lastVideoWrittenPTS = pts
        }
    }
    
    nonisolated func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        guard enableAudio, !isPaused else { return }
        
        writerQueue.async { [weak self] in
            guard let self = self, self.isRecording, self.isWriterStarted else { return }
            guard !self.isPaused else { return }
            
            let sampleRate = buffer.format.sampleRate
            let originalPTS = CMTime(seconds: Double(when.sampleTime) / sampleRate, preferredTimescale: CMTimeScale(sampleRate))
            let adjustedPTS = self.adjustedTimestamp(for: originalPTS, isVideo: false)
            
            guard let sampleBuffer = self.createAudioSampleBuffer(from: buffer, presentationTime: adjustedPTS) else { return }
            
            guard let writer = self.assetWriter,
                  writer.status == .writing,
                  let input = self.audioWriterInput,
                  input.isReadyForMoreMediaData else { return }
            
            input.append(sampleBuffer)
        }
    }
    
    private func setupWriter(with sampleBuffer: CMSampleBuffer) {
        do {
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            
            guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            
            // Use actual capture frame rate so recording is not slow-motion (was hardcoded 30 while capture can be 60).
            let frameDuration = CMSampleBufferGetDuration(sampleBuffer)
            let frameRateSeconds = CMTimeGetSeconds(frameDuration)
            let sourceFrameRate: Int = frameRateSeconds > 0
                ? Int(round(1.0 / frameRateSeconds))
                : 30
            let clampedFrameRate = min(max(sourceFrameRate, 15), 60)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(dimensions.width),
                AVVideoHeightKey: Int(dimensions.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000,
                    AVVideoExpectedSourceFrameRateKey: clampedFrameRate,
                    // Longer keyframe interval = fewer I-frames = lower encoder CPU load.
                    AVVideoMaxKeyFrameIntervalKey: clampedFrameRate * 2,
                    // Baseline profile: no B-frames, least encoder complexity.
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
                    // Disable B-frames explicitly – reduces encoder latency and CPU.
                    AVVideoAllowFrameReorderingKey: false
                ]
            ]
            
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            if writer.canAdd(videoInput) { writer.add(videoInput) }
            self.videoWriterInput = videoInput
            
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) { writer.add(audioInput) }
            self.audioWriterInput = audioInput
            
            self.assetWriter = writer
            
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: timestamp)
            self.isWriterStarted = true
            self.lastVideoTimestampBeforePause = timestamp
            
        } catch {
            print("LiveStreamRecorder: Failed to create AVAssetWriter: \(error)")
        }
    }
    
    private func createAudioSampleBuffer(from buffer: AVAudioPCMBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        let format = buffer.format
        guard let formatDescription = format.formatDescription as CMFormatDescription? else { return nil }
        
        let frameCount = buffer.frameLength
        guard let audioBufferList = buffer.audioBufferList.pointee.mBuffers.mData else { return nil }
        let dataSize = Int(buffer.audioBufferList.pointee.mBuffers.mDataByteSize)
        
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &block
        )
        
        guard let blk = block else { return nil }
        
        CMBlockBufferReplaceDataBytes(
            with: audioBufferList,
            blockBuffer: blk,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )
        
        var sampleBuffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blk,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(frameCount),
            presentationTimeStamp: presentationTime,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
}

// MARK: - AVCaptureDevice frame duration patch for discrete frame-rate devices (e.g. capture cards)
// HaishinKit sets activeVideoMinFrameDuration using 100/6000 for 60 fps; many capture cards
// only accept exact values from videoSupportedFrameRateRanges (e.g. 1000000/60000240).
// We swizzle the setters once per device class and clamp to a supported range when needed.
extension AVCaptureDevice {
    private static var swizzledFrameDurationClasses: Set<String> = []
    private static let swizzleLock = NSLock()

    static func applyFrameDurationPatchIfNeeded(for device: AVCaptureDevice) {
        swizzleLock.lock()
        defer { swizzleLock.unlock() }
        let className = String(describing: type(of: device))
        guard !swizzledFrameDurationClasses.contains(className) else { return }
        let deviceClass: AnyClass = type(of: device)
        let minSel = Selector("setActiveVideoMinFrameDuration:")
        let maxSel = Selector("setActiveVideoMaxFrameDuration:")
        guard let minOriginal = class_getInstanceMethod(deviceClass, minSel),
              let maxOriginal = class_getInstanceMethod(deviceClass, maxSel),
              let minReplacement = class_getInstanceMethod(AVCaptureDevice.self, #selector(AVCaptureDevice._patched_setActiveVideoMinFrameDuration(_:))),
              let maxReplacement = class_getInstanceMethod(AVCaptureDevice.self, #selector(AVCaptureDevice._patched_setActiveVideoMaxFrameDuration(_:))) else {
            return
        }
        method_exchangeImplementations(minOriginal, minReplacement)
        method_exchangeImplementations(maxOriginal, maxReplacement)
        swizzledFrameDurationClasses.insert(className)
    }

    private func _clampFrameDurationToSupported(_ duration: CMTime, isMin: Bool) -> CMTime {
        let format = activeFormat
        let ranges = format.videoSupportedFrameRateRanges
        guard !ranges.isEmpty else { return duration }
        let requestedSeconds = CMTimeGetSeconds(duration)
        let requestedFps = requestedSeconds > 0 ? 1.0 / requestedSeconds : 60.0
        var best: (range: AVFrameRateRange, distance: Double)?
        for range in ranges {
            let rangeFps = Double(range.maxFrameRate)
            let distance = abs(rangeFps - requestedFps)
            if best == nil || distance < best!.distance {
                best = (range, distance)
            }
        }
        guard let b = best else { return duration }
        return isMin ? b.range.minFrameDuration : b.range.maxFrameDuration
    }

    @objc fileprivate func _patched_setActiveVideoMinFrameDuration(_ duration: CMTime) {
        let clamped = _clampFrameDurationToSupported(duration, isMin: true)
        _patched_setActiveVideoMinFrameDuration(clamped)
    }

    @objc fileprivate func _patched_setActiveVideoMaxFrameDuration(_ duration: CMTime) {
        let clamped = _clampFrameDurationToSupported(duration, isMin: false)
        _patched_setActiveVideoMaxFrameDuration(clamped)
    }
}
