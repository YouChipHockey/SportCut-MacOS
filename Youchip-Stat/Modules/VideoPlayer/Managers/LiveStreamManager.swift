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
    
    // MARK: - Recording state
    
    private var durationTimer: DispatchSourceTimer?
    private var recordingStartDate: Date?
    private var accumulatedDurationBeforePause: Double = 0.0
    
    private var tempFileURL: URL?
    private var currentVideoId: String?
    
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
        
        self.mixer = nil
        self.recorder = nil
        self.previewView = nil
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
                await oldMixer.stopRunning()
                try? await oldMixer.attachVideo(nil)
                try? await oldMixer.attachAudio(nil)
            }
        }
        oldRecorder?.cancelRecording()
        
        // ── Create new session ──
        let newMixer = MediaMixer(useManualCapture: true)
        
        let view = MTHKView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        view.videoGravity = .resizeAspect
        
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
                
                if let audioDevice = audioDevice {
                    try await newMixer.attachAudio(audioDevice, track: 0)
                }
                
                var videoMixerSettings = await newMixer.videoMixerSettings
                videoMixerSettings.mode = .passthrough
                await newMixer.setVideoMixerSettings(videoMixerSettings)
                
                await newMixer.addOutput(view)
                
                await MainActor.run {
                    guard self.sessionId == thisSessionId else { return }
                    self.mixer = newMixer
                    self.previewView = view
                    self.isSessionConfigured = true
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
        
        let newRecorder = LiveStreamRecorder(outputURL: tempFileURL!)
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
                self.startDurationTimer()
                self.performStartupPauseResume()
            }
        }
    }
    
    // MARK: - Startup stabilization
    
    private func performStartupPauseResume() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.isLive else { return }
            self.recorder?.pauseRecording()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, self.isLive else { return }
                self.recorder?.resumeRecording()
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
    
    // MARK: - Stop & Finalize
    
    func stopAndFinalize(completion: @escaping (URL?) -> Void) {
        guard isLive else {
            completion(nil)
            return
        }
        
        stopDurationTimer()
        
        let mixerToStop = self.mixer
        let recorderToStop = self.recorder
        let previewToRemove = self.previewView
        let finalizeSessionId = self.sessionId
        
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
            
            let finalURL = self.moveToPermanentLocation()
            
            Task {
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
    
    func abort() {
        let abortSessionId = self.sessionId
        
        stopDurationTimer()
        
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
    
    // MARK: - Cleanup
    
    private func cleanupSession() {
        let cleanupSessionId = self.sessionId
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.sessionId == cleanupSessionId else { return }
            self.mixer = nil
            self.recorder = nil
            self.previewView = nil
            self.isSessionConfigured = false
            self.currentVideoId = nil
        }
    }
    
    func fullCleanup() {
        let cleanupSessionId = self.sessionId
        
        stopDurationTimer()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.sessionId == cleanupSessionId else { return }
            self.isLive = false
            self.isBroadcastPaused = false
            self.liveDuration = 0.0
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

// MARK: - LiveStreamRecorder

final class LiveStreamRecorder: MediaMixerOutput, @unchecked Sendable {
    
    var videoTrackId: UInt8? { get async { return UInt8.max } }
    var audioTrackId: UInt8? { get async { return UInt8.max } }
    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}
    
    private let outputURL: URL
    private let writerQueue = DispatchQueue(label: "com.youchip.liveRecorder", qos: .userInitiated)
    
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
    
    init(outputURL: URL) {
        self.outputURL = outputURL
    }
    
    func startRecording() {
        isPaused = false
        writerQueue.async { [weak self] in
            self?.isRecording = true
            self?.totalPauseOffset = .zero
            self?.pauseStartPTS = .invalid
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
        guard !isPaused else {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writerQueue.async { [weak self] in
                guard let self = self else { return }
                if !self.pauseStartPTS.isValid {
                    self.pauseStartPTS = pts
                }
            }
            return
        }
        
        writerQueue.async { [weak self] in
            guard let self = self, self.isRecording else { return }
            guard !self.isPaused else {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if !self.pauseStartPTS.isValid {
                    self.pauseStartPTS = pts
                }
                return
            }
            
            if !self.isWriterStarted {
                self.setupWriter(with: sampleBuffer)
            }
            
            guard self.isWriterStarted,
                  let writer = self.assetWriter,
                  writer.status == .writing,
                  let input = self.videoWriterInput,
                  input.isReadyForMoreMediaData else { return }
            
            let originalPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let adjustedPTS = self.adjustedTimestamp(for: originalPTS, isVideo: true)
            
            if self.totalPauseOffset == .zero {
                input.append(sampleBuffer)
            } else {
                if let adjustedBuffer = self.sampleBufferWithAdjustedTime(sampleBuffer, newPTS: adjustedPTS) {
                    input.append(adjustedBuffer)
                }
            }
        }
    }
    
    nonisolated func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        guard !isPaused else { return }
        
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
                    AVVideoAverageBitRateKey: 6_000_000,
                    AVVideoExpectedSourceFrameRateKey: clampedFrameRate,
                    AVVideoMaxKeyFrameIntervalKey: clampedFrameRate
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
