//
//  TelestrationExporter.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 3/20/26.
//

import Foundation
import AVFoundation
import CoreGraphics
import SwiftUI

class TelestrationExporter: ObservableObject {
    
    @Published var progress: Float = 0
    @Published var isExporting: Bool = false
    
    // MARK: - Export with Annotations Burned In
    
    func exportAnnotatedClip(
        viewModel: TelestrationModeViewModel,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        isExporting = true
        progress = 0
        
        let videoURL = viewModel.videoAssetURL
        let asset = AVURLAsset(url: videoURL)
        let clipStart = viewModel.clipStart
        let clipEnd = viewModel.clipEnd
        let fps = viewModel.fps
        let pauseDuration = viewModel.pauseBeforePlay
        
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            isExporting = false
            completion(.failure(makeError("Video track not found")))
            return
        }
        
        let transform = videoTrack.preferredTransform
        let naturalSize = videoTrack.naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("telestration_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
                
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: Int(renderSize.width),
                    AVVideoHeightKey: Int(renderSize.height),
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 8_000_000,
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                    ]
                ]
                
                let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                writerInput.expectsMediaDataInRealTime = false
                
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: writerInput,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                        kCVPixelBufferWidthKey as String: Int(renderSize.width),
                        kCVPixelBufferHeightKey as String: Int(renderSize.height)
                    ]
                )
                
                // Audio track
                let audioTrack = asset.tracks(withMediaType: .audio).first
                var audioWriterInput: AVAssetWriterInput?
                var audioReader: AVAssetReader?
                var audioReaderOutput: AVAssetReaderTrackOutput?
                
                if let aTrack = audioTrack,
                   !aTrack.formatDescriptions.isEmpty {
                    // Force cast is safe: formatDescriptions always contains CMFormatDescription
                    let formatDesc = aTrack.formatDescriptions[0] as! CMFormatDescription
                    let audioInput = AVAssetWriterInput(
                        mediaType: .audio,
                        outputSettings: nil,
                        sourceFormatHint: formatDesc
                    )
                    audioInput.expectsMediaDataInRealTime = false
                    writer.add(audioInput)
                    audioWriterInput = audioInput
                    
                    let reader = try AVAssetReader(asset: asset)
                    let output = AVAssetReaderTrackOutput(track: aTrack, outputSettings: nil)
                    reader.add(output)
                    
                    let startTime = CMTime(seconds: clipStart, preferredTimescale: 600)
                    let duration = CMTime(seconds: clipEnd - clipStart, preferredTimescale: 600)
                    reader.timeRange = CMTimeRange(start: startTime, duration: duration)
                    
                    audioReader = reader
                    audioReaderOutput = output
                }
                
                writer.add(writerInput)
                writer.startWriting()
                writer.startSession(atSourceTime: .zero)
                
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.requestedTimeToleranceBefore = .zero
                imageGenerator.requestedTimeToleranceAfter = .zero
                
                let totalClipDuration = clipEnd - clipStart
                let totalVideoFrames = Int(ceil(totalClipDuration * fps))
                
                // Phase 1: Pause frame with annotations
                let pauseFrames = Int(pauseDuration * fps)
                
                // Phase 2: Animated playback
                let totalOutputFrames = pauseFrames + totalVideoFrames
                
                var frameCount = 0
                
                // Phase 1: Render the first frame paused with all annotations visible
                if pauseFrames > 0 {
                    let firstFrameTime = CMTime(seconds: clipStart, preferredTimescale: 600)
                    if let cgImage = try? imageGenerator.copyCGImage(at: firstFrameTime, actualTime: nil) {
                        let annotated = self.renderAnnotations(
                            on: cgImage,
                            viewModel: viewModel,
                            frameIndex: 0,
                            renderSize: renderSize,
                            isAnimating: false,
                            clipTimeSeconds: 0
                        )
                        
                        for i in 0..<pauseFrames {
                            while !writerInput.isReadyForMoreMediaData {
                                Thread.sleep(forTimeInterval: 0.01)
                            }
                            
                            let presentationTime = CMTime(seconds: Double(frameCount) / fps, preferredTimescale: 600)
                            if let pixelBuffer = self.pixelBuffer(from: annotated, size: renderSize, adaptor: adaptor) {
                                adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                            }
                            frameCount += 1
                            
                            DispatchQueue.main.async {
                                self.progress = Float(frameCount) / Float(totalOutputFrames)
                            }
                        }
                    }
                }
                
                // Phase 2: Render each frame with tracked annotations
                for videoFrame in 0..<totalVideoFrames {
                    let time = clipStart + Double(videoFrame) / fps
                    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
                    
                    guard let cgImage = try? imageGenerator.copyCGImage(at: cmTime, actualTime: nil) else {
                        continue
                    }
                    
                    let annotated = self.renderAnnotations(
                        on: cgImage,
                        viewModel: viewModel,
                        frameIndex: videoFrame,
                        renderSize: renderSize,
                        isAnimating: true,
                        clipTimeSeconds: Double(videoFrame) / fps
                    )
                    
                    while !writerInput.isReadyForMoreMediaData {
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                    
                    let presentationTime = CMTime(seconds: Double(frameCount) / fps, preferredTimescale: 600)
                    if let pixelBuffer = self.pixelBuffer(from: annotated, size: renderSize, adaptor: adaptor) {
                        adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                    }
                    frameCount += 1
                    
                    DispatchQueue.main.async {
                        self.progress = Float(frameCount) / Float(totalOutputFrames)
                    }
                }
                
                writerInput.markAsFinished()
                
                // Write audio
                if let audioInput = audioWriterInput,
                   let reader = audioReader,
                   let output = audioReaderOutput {
                    reader.startReading()
                    let audioGroup = DispatchGroup()
                    audioGroup.enter()
                    
                    audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.youchip.telestration.audio")) {
                        while audioInput.isReadyForMoreMediaData {
                            if let sampleBuffer = output.copyNextSampleBuffer() {
                                audioInput.append(sampleBuffer)
                            } else {
                                audioInput.markAsFinished()
                                audioGroup.leave()
                                break
                            }
                        }
                    }
                    audioGroup.wait()
                }
                
                let semaphore = DispatchSemaphore(value: 0)
                writer.finishWriting {
                    semaphore.signal()
                }
                semaphore.wait()
                
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.progress = 1.0
                    
                    if writer.status == .completed {
                        completion(.success(outputURL))
                    } else {
                        completion(.failure(writer.error ?? self.makeError("Unknown export error")))
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isExporting = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Render Annotations onto Frame
    
    private func renderAnnotations(
        on baseImage: CGImage,
        viewModel: TelestrationModeViewModel,
        frameIndex: Int,
        renderSize: CGSize,
        isAnimating: Bool,
        clipTimeSeconds: Double
    ) -> CGImage {
        let w = Int(renderSize.width)
        let h = Int(renderSize.height)
        
        guard let context = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return baseImage
        }
        
        // CG coordinates are flipped: origin at bottom-left
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        
        // Flip to top-left origin for drawing
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: 1, y: -1)
        
        // Draw zones
        for zone in viewModel.zones {
            let points = zone.points(from: viewModel.markers, at: frameIndex)
            guard points.count >= 3 else { continue }
            
            let hull = ConvexHull.compute(from: points)
            
            // Fill
            let fillComponents = NSColor(zone.fillColor.opacity(zone.fillOpacity)).cgColor.components ?? [1, 1, 0, 0.25]
            context.setFillColor(CGColor(
                red: fillComponents.count > 0 ? fillComponents[0] : 1,
                green: fillComponents.count > 1 ? fillComponents[1] : 1,
                blue: fillComponents.count > 2 ? fillComponents[2] : 0,
                alpha: fillComponents.count > 3 ? fillComponents[3] : 0.25
            ))
            
            context.beginPath()
            context.move(to: hull[0])
            for p in hull.dropFirst() { context.addLine(to: p) }
            context.closePath()
            context.fillPath()
            
            // Stroke
            let edgeComponents = NSColor(zone.edgeColor).cgColor.components ?? [1, 0.6, 0, 0.8]
            context.setStrokeColor(CGColor(
                red: edgeComponents.count > 0 ? edgeComponents[0] : 1,
                green: edgeComponents.count > 1 ? edgeComponents[1] : 0.6,
                blue: edgeComponents.count > 2 ? edgeComponents[2] : 0,
                alpha: edgeComponents.count > 3 ? edgeComponents[3] : 0.8
            ))
            context.setLineWidth(2.5)
            context.beginPath()
            context.move(to: hull[0])
            for p in hull.dropFirst() { context.addLine(to: p) }
            context.closePath()
            context.strokePath()
        }
        
        // Draw markers
        for marker in viewModel.markers {
            guard let pos = marker.position(at: frameIndex) else { continue }
            let r = marker.radius
            
            let markerComponents = NSColor(marker.color).cgColor.components ?? [1, 0, 0, 1]
            let cgMarkerColor = CGColor(
                red: markerComponents.count > 0 ? markerComponents[0] : 1,
                green: markerComponents.count > 1 ? markerComponents[1] : 0,
                blue: markerComponents.count > 2 ? markerComponents[2] : 0,
                alpha: markerComponents.count > 3 ? markerComponents[3] : 1
            )
            
            let outerRect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            context.setFillColor(cgMarkerColor.copy(alpha: 0.3)!)
            context.fillEllipse(in: outerRect)
            
            context.setStrokeColor(cgMarkerColor)
            context.setLineWidth(2.5)
            context.strokeEllipse(in: outerRect)
            
            let innerRect = CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)
            context.setFillColor(cgMarkerColor)
            context.fillEllipse(in: innerRect)
        }
        
        // Draw arrows
        for arrow in viewModel.arrows {
            let start = arrow.startPoint
            let end = arrow.endPoint
            
            let animProgress: Double
            if isAnimating {
                animProgress = min(1.0, clipTimeSeconds / arrow.animationDuration)
            } else {
                animProgress = 1.0
            }
            
            guard animProgress > 0.01 else { continue }
            
            let currentEnd = CGPoint(
                x: start.x + (end.x - start.x) * animProgress,
                y: start.y + (end.y - start.y) * animProgress
            )
            
            let arrowComponents = NSColor(arrow.color).cgColor.components ?? [1, 1, 1, 1]
            let cgArrowColor = CGColor(
                red: arrowComponents.count > 0 ? arrowComponents[0] : 1,
                green: arrowComponents.count > 1 ? arrowComponents[1] : 1,
                blue: arrowComponents.count > 2 ? arrowComponents[2] : 1,
                alpha: arrowComponents.count > 3 ? arrowComponents[3] : 1
            )
            
            context.setStrokeColor(cgArrowColor)
            context.setLineWidth(arrow.lineWidth)
            context.beginPath()
            context.move(to: start)
            context.addLine(to: currentEnd)
            context.strokePath()
            
            // Arrowhead
            let dx = currentEnd.x - start.x
            let dy = currentEnd.y - start.y
            let angle = atan2(dy, dx)
            let headLength: CGFloat = 16
            let headWidth: CGFloat = 10
            
            let p1 = CGPoint(
                x: currentEnd.x - headLength * cos(angle) + headWidth * cos(angle + .pi / 2),
                y: currentEnd.y - headLength * sin(angle) + headWidth * sin(angle + .pi / 2)
            )
            let p2 = CGPoint(
                x: currentEnd.x - headLength * cos(angle) - headWidth * cos(angle + .pi / 2),
                y: currentEnd.y - headLength * sin(angle) - headWidth * sin(angle + .pi / 2)
            )
            
            context.setFillColor(cgArrowColor)
            context.beginPath()
            context.move(to: currentEnd)
            context.addLine(to: p1)
            context.addLine(to: p2)
            context.closePath()
            context.fillPath()
        }
        
        return context.makeImage() ?? baseImage
    }
    
    // MARK: - Pixel Buffer Creation
    
    private func pixelBuffer(from image: CGImage, size: CGSize, adaptor: AVAssetWriterInputPixelBufferAdaptor) -> CVPixelBuffer? {
        let w = Int(size.width)
        let h = Int(size.height)
        
        var pixelBuffer: CVPixelBuffer?
        
        if let pool = adaptor.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h,
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
            ]
            CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer)
        }
        
        guard let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        guard let context = CGContext(
            data: baseAddress,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        
        return buffer
    }
    
    // MARK: - Save Dialog
    
    func showSaveDialog(for outputURL: URL) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedFileTypes = ["mp4"]
            panel.nameFieldStringValue = "telestration_export.mp4"
            
            if panel.runModal() == .OK, let saveURL = panel.url {
                do {
                    if FileManager.default.fileExists(atPath: saveURL.path) {
                        try FileManager.default.removeItem(at: saveURL)
                    }
                    try FileManager.default.copyItem(at: outputURL, to: saveURL)
                } catch {
                    print("Error saving telestration export: \(error)")
                }
            }
            
            try? FileManager.default.removeItem(at: outputURL)
        }
    }
    
    // MARK: - Helpers
    
    private func makeError(_ message: String) -> NSError {
        NSError(domain: "TelestrationExport", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
