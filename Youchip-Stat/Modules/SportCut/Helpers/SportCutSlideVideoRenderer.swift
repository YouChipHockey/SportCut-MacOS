//
//  SportCutSlideVideoRenderer.swift
//  Youchip-Stat
//
//  Renders a title slide (SportCutSlide) into a short silent .mov so it can be
//  baked into the playlist film (both in-app playback and export) as a normal
//  video segment. Results are cached on disk by slide content.
//

import AVFoundation
import AppKit

enum SportCutSlideVideoRenderer {

    static let renderSize = CGSize(width: 1920, height: 1080)
    private static let fps: Int32 = 15

    private static var cacheDir: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("YouChipSlides", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cacheKey(for slide: SportCutSlide) -> String {
        var hasher = Hasher()
        hasher.combine(slide.title)
        hasher.combine(slide.durationSeconds)
        hasher.combine(slide.backgroundColorHex)
        hasher.combine(slide.textColorHex)
        hasher.combine(slide.textSize)
        hasher.combine(slide.imageData)
        for el in slide.elements {
            hasher.combine(el.kind)
            hasher.combine(el.centerX); hasher.combine(el.centerY)
            hasher.combine(el.width); hasher.combine(el.height)
            hasher.combine(el.text); hasher.combine(el.fontName)
            hasher.combine(el.fontSize); hasher.combine(el.colorHex)
            hasher.combine(el.bold); hasher.combine(el.alignment)
            hasher.combine(el.imageData)
        }
        return String(UInt(bitPattern: hasher.finalize()))
    }

    /// Возвращает URL готового видео слайда (из кэша или отрендерив). Колбэк на главном потоке.
    static func renderVideo(for slide: SportCutSlide, completion: @escaping (URL?) -> Void) {
        let outURL = cacheDir.appendingPathComponent("slide_\(cacheKey(for: slide)).mov")
        if FileManager.default.fileExists(atPath: outURL.path) {
            completion(outURL)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = renderSync(slide: slide, to: outURL)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Отрендерить набор слайдов; колбэк с картой slideID → URL (главный поток).
    static func renderVideos(for slides: [SportCutSlide], completion: @escaping ([UUID: URL]) -> Void) {
        guard !slides.isEmpty else { completion([:]); return }
        let group = DispatchGroup()
        var result: [UUID: URL] = [:]
        let lock = NSLock()
        for slide in slides {
            group.enter()
            renderVideo(for: slide) { url in
                if let url {
                    lock.lock(); result[slide.id] = url; lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(result) }
    }

    private static func renderSync(slide: SportCutSlide, to outURL: URL) -> URL? {
        try? FileManager.default.removeItem(at: outURL)

        guard let writer = try? AVAssetWriter(outputURL: outURL, fileType: .mov) else { return nil }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: renderSize.width,
            AVVideoHeightKey: renderSize.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: Int(renderSize.width),
            kCVPixelBufferHeightKey as String: Int(renderSize.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)

        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        guard let buffer = pixelBuffer(from: SportCutSlideRenderer.renderImage(for: slide, size: renderSize)) else {
            writer.cancelWriting()
            return nil
        }

        let totalFrames = max(1, Int(slide.durationSeconds * Double(fps)))
        var frame = 0
        let sema = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "youchip.slide.writer")
        input.requestMediaDataWhenReady(on: queue) {
            while input.isReadyForMoreMediaData {
                if frame >= totalFrames {
                    input.markAsFinished()
                    writer.finishWriting { sema.signal() }
                    return
                }
                let pts = CMTime(value: CMTimeValue(frame), timescale: fps)
                adaptor.append(buffer, withPresentationTime: pts)
                frame += 1
            }
        }
        sema.wait()
        return writer.status == .completed ? outURL : nil
    }

    private static func pixelBuffer(from image: NSImage) -> CVPixelBuffer? {
        let w = Int(renderSize.width)
        let h = Int(renderSize.height)
        var pb: CVPixelBuffer?
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32ARGB, attrs, &pb) == kCVReturnSuccess,
              let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        var rect = CGRect(x: 0, y: 0, width: w, height: h)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        ctx.draw(cg, in: rect)
        return buffer
    }
}
