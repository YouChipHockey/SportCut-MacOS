//
//  PixelTemplateTracker.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 3/20/26.
//

import Foundation
import CoreGraphics

class PixelTemplateTracker {
    
    let templateWidth: Int
    let templateHeight: Int
    let searchRadius: Int
    
    private let ovalMask: [Bool]
    private let maskPixelCount: Int
    
    private let scaleRate = 0.002
    private let minScale = 0.5
    private let maxScale = 2.0
    private let maxScaleChangePerFrame = 0.06
    
    init(templateWidth: Int = 22, templateHeight: Int = 36, searchRadius: Int = 40) {
        self.templateWidth = templateWidth
        self.templateHeight = templateHeight
        self.searchRadius = searchRadius
        
        let rx = Double(templateWidth) / 2.0
        let ry = Double(templateHeight) / 2.0
        var mask = [Bool](repeating: false, count: templateWidth * templateHeight)
        var count = 0
        for y in 0..<templateHeight {
            for x in 0..<templateWidth {
                let nx = (Double(x) - rx + 0.5) / rx
                let ny = (Double(y) - ry + 0.5) / ry
                let inside = (nx * nx + ny * ny) <= 1.0
                mask[y * templateWidth + x] = inside
                if inside { count += 1 }
            }
        }
        self.ovalMask = mask
        self.maskPixelCount = count
    }
    
    // MARK: - Template Capture
    
    func captureTemplate(from image: CGImage, at center: CGPoint, scale: Double = 1.0) -> PixelTemplate? {
        let cropW = Int(ceil(Double(templateWidth) * scale))
        let cropH = Int(ceil(Double(templateHeight) * scale))
        let halfW = cropW / 2
        let halfH = cropH / 2
        let x = max(0, min(Int(center.x) - halfW, image.width - cropW))
        let y = max(0, min(Int(center.y) - halfH, image.height - cropH))
        
        let cropRect = CGRect(x: x, y: y, width: cropW, height: cropH)
        guard let cropped = image.cropping(to: cropRect) else { return nil }
        
        if abs(scale - 1.0) > 0.01 {
            guard let rgb = extractRGBResized(from: cropped, toWidth: templateWidth, height: templateHeight) else { return nil }
            return PixelTemplate(rgbData: rgb, width: templateWidth, height: templateHeight)
        } else {
            guard let rgb = extractRGB(from: cropped) else { return nil }
            return PixelTemplate(rgbData: rgb, width: templateWidth, height: templateHeight)
        }
    }
    
    // MARK: - Template Matching (RGB SSD with oval mask, crop-first)
    
    func findBestMatch(
        template: PixelTemplate,
        in image: CGImage,
        searchCenter: CGPoint,
        scale: Double = 1.0
    ) -> (position: CGPoint, score: Double)? {
        let tw = templateWidth
        let th = templateHeight
        let scaledHalfW = Int(ceil(Double(tw) * scale / 2.0))
        let scaledHalfH = Int(ceil(Double(th) * scale / 2.0))
        let effectiveRadius = max(20, Int(round(Double(searchRadius) * scale)))
        
        let regionX = max(0, Int(searchCenter.x) - effectiveRadius - scaledHalfW)
        let regionY = max(0, Int(searchCenter.y) - effectiveRadius - scaledHalfH)
        let regionRight = min(image.width, Int(searchCenter.x) + effectiveRadius + scaledHalfW)
        let regionBottom = min(image.height, Int(searchCenter.y) + effectiveRadius + scaledHalfH)
        let regionW = regionRight - regionX
        let regionH = regionBottom - regionY
        
        let minCropW = Int(ceil(Double(tw) * scale))
        let minCropH = Int(ceil(Double(th) * scale))
        guard regionW > minCropW, regionH > minCropH else { return nil }
        
        guard let regionImage = image.cropping(to: CGRect(x: regionX, y: regionY, width: regionW, height: regionH)) else { return nil }
        
        let matchW: Int
        let matchH: Int
        let regionPixels: [UInt8]
        
        if abs(scale - 1.0) > 0.01 {
            matchW = max(tw + 1, Int(round(Double(regionW) / scale)))
            matchH = max(th + 1, Int(round(Double(regionH) / scale)))
            guard let pixels = extractRGBResized(from: regionImage, toWidth: matchW, height: matchH) else { return nil }
            regionPixels = pixels
        } else {
            matchW = regionW
            matchH = regionH
            guard let pixels = extractRGB(from: regionImage) else { return nil }
            regionPixels = pixels
        }
        
        let searchW = matchW - tw
        let searchH = matchH - th
        guard searchW > 0, searchH > 0 else { return nil }
        
        let tData = template.rgbData
        let rw3 = matchW * 3
        let tw3 = tw * 3
        
        var bestSSD: Int64 = .max
        var bestX = searchW / 2
        var bestY = searchH / 2
        
        tData.withUnsafeBufferPointer { tBuf in
            regionPixels.withUnsafeBufferPointer { rBuf in
                ovalMask.withUnsafeBufferPointer { mBuf in
                    let tPtr = tBuf.baseAddress!
                    let rPtr = rBuf.baseAddress!
                    let mPtr = mBuf.baseAddress!
                    
                    // Coarse pass: step=2 in search space, skip alternate template rows
                    for sy in stride(from: 0, through: searchH, by: 2) {
                        for sx in stride(from: 0, through: searchW, by: 2) {
                            var ssd: Int64 = 0
                            var rejected = false
                            
                            for dy in stride(from: 0, to: th, by: 2) {
                                let rRowOff = (sy + dy) * rw3 + sx * 3
                                let tRowOff = dy * tw3
                                let mRowOff = dy * tw
                                
                                for dx in 0..<tw {
                                    if mPtr[mRowOff + dx] {
                                        let px = dx * 3
                                        let d0 = Int64(rPtr[rRowOff + px]) - Int64(tPtr[tRowOff + px])
                                        let d1 = Int64(rPtr[rRowOff + px + 1]) - Int64(tPtr[tRowOff + px + 1])
                                        let d2 = Int64(rPtr[rRowOff + px + 2]) - Int64(tPtr[tRowOff + px + 2])
                                        ssd += d0 * d0 + d1 * d1 + d2 * d2
                                    }
                                }
                                
                                if ssd >= bestSSD { rejected = true; break }
                            }
                            
                            if !rejected && ssd < bestSSD {
                                bestSSD = ssd
                                bestX = sx
                                bestY = sy
                            }
                        }
                    }
                    
                    // Refine pass: step=1, all template rows, +-3 around coarse best
                    let refMinX = max(0, bestX - 3)
                    let refMinY = max(0, bestY - 3)
                    let refMaxX = min(searchW, bestX + 3)
                    let refMaxY = min(searchH, bestY + 3)
                    
                    bestSSD = .max
                    
                    for sy in refMinY...refMaxY {
                        for sx in refMinX...refMaxX {
                            var ssd: Int64 = 0
                            var rejected = false
                            
                            for dy in 0..<th {
                                let rRowOff = (sy + dy) * rw3 + sx * 3
                                let tRowOff = dy * tw3
                                let mRowOff = dy * tw
                                
                                for dx in 0..<tw {
                                    if mPtr[mRowOff + dx] {
                                        let px = dx * 3
                                        let d0 = Int64(rPtr[rRowOff + px]) - Int64(tPtr[tRowOff + px])
                                        let d1 = Int64(rPtr[rRowOff + px + 1]) - Int64(tPtr[tRowOff + px + 1])
                                        let d2 = Int64(rPtr[rRowOff + px + 2]) - Int64(tPtr[tRowOff + px + 2])
                                        ssd += d0 * d0 + d1 * d1 + d2 * d2
                                    }
                                }
                                
                                if ssd >= bestSSD { rejected = true; break }
                            }
                            
                            if !rejected && ssd < bestSSD {
                                bestSSD = ssd
                                bestX = sx
                                bestY = sy
                            }
                        }
                    }
                }
            }
        }
        
        let avgDiff = sqrt(Double(bestSSD) / Double(maskPixelCount * 3))
        if avgDiff > 50 { return nil }
        
        let globalX = CGFloat(regionX) + (CGFloat(bestX) + CGFloat(tw) / 2.0) * CGFloat(scale)
        let globalY = CGFloat(regionY) + (CGFloat(bestY) + CGFloat(th) / 2.0) * CGFloat(scale)
        
        return (CGPoint(x: globalX, y: globalY), avgDiff)
    }
    
    // MARK: - Batch Tracking with Velocity Prediction
    
    func trackMarker(
        _ marker: PlayerMarker,
        through frames: [CGImage],
        startFrameIndex: Int,
        progress: @escaping (Float) -> Void
    ) -> [Int: TrackedPosition] {
        guard var currentTemplate = marker.template,
              let startPos = marker.positions[startFrameIndex] else {
            return marker.positions
        }
        
        var positions = marker.positions
        var lastPos = startPos.center
        var velocity = CGPoint.zero
        let total = frames.count
        var goodMatchCount = 0
        var consecutiveFailures = 0
        let baseMaxJump: CGFloat = 25.0
        var currentScale = 1.0
        
        for (offset, frame) in frames.enumerated() {
            let frameIndex = startFrameIndex + offset
            let effectiveMaxJump = baseMaxJump * CGFloat(currentScale)
            
            if let existing = positions[frameIndex], existing.isManualOverride {
                if offset > 0, let prev = positions[startFrameIndex + offset - 1] {
                    let manualDy = existing.center.y - prev.center.y
                    let rawChange = Double(manualDy) * scaleRate
                    let clampedChange = max(-maxScaleChangePerFrame, min(maxScaleChangePerFrame, rawChange))
                    currentScale = max(minScale, min(maxScale, currentScale + clampedChange))
                    velocity = CGPoint(
                        x: existing.center.x - prev.center.x,
                        y: existing.center.y - prev.center.y
                    )
                }
                lastPos = existing.center
                consecutiveFailures = 0
                if let refreshed = captureTemplate(from: frame, at: existing.center, scale: currentScale) {
                    currentTemplate = refreshed
                }
                progress(Float(offset + 1) / Float(total))
                continue
            }
            
            if frameIndex == startFrameIndex {
                progress(Float(offset + 1) / Float(total))
                continue
            }
            
            let predicted = CGPoint(
                x: lastPos.x + velocity.x,
                y: lastPos.y + velocity.y
            )
            
            if let (newPos, score) = findBestMatch(template: currentTemplate, in: frame, searchCenter: predicted, scale: currentScale) {
                let dx = newPos.x - lastPos.x
                let dy = newPos.y - lastPos.y
                let dist = hypot(dx, dy)
                let clampedPos: CGPoint
                if dist > effectiveMaxJump {
                    let s = effectiveMaxJump / dist
                    clampedPos = CGPoint(x: lastPos.x + dx * s, y: lastPos.y + dy * s)
                } else {
                    clampedPos = newPos
                }
                
                // Update scale from vertical displacement: down = bigger, up = smaller
                let verticalDelta = Double(clampedPos.y - lastPos.y)
                let rawScaleChange = verticalDelta * scaleRate
                let clampedScaleChange = max(-maxScaleChangePerFrame, min(maxScaleChangePerFrame, rawScaleChange))
                currentScale = max(minScale, min(maxScale, currentScale + clampedScaleChange))
                
                let newVel = CGPoint(x: clampedPos.x - lastPos.x, y: clampedPos.y - lastPos.y)
                velocity = CGPoint(
                    x: newVel.x * 0.7 + velocity.x * 0.3,
                    y: newVel.y * 0.7 + velocity.y * 0.3
                )
                positions[frameIndex] = TrackedPosition(center: clampedPos, isManualOverride: false)
                lastPos = clampedPos
                consecutiveFailures = 0
                goodMatchCount += 1
                
                if goodMatchCount % 15 == 0 && score < 25 {
                    if let refreshed = captureTemplate(from: frame, at: clampedPos, scale: currentScale) {
                        currentTemplate = refreshed
                    }
                }
            } else {
                consecutiveFailures += 1
                let decayFactor = max(0.3, 0.8 - Double(consecutiveFailures) * 0.1)
                var fallback = CGPoint(
                    x: lastPos.x + velocity.x * decayFactor,
                    y: lastPos.y + velocity.y * decayFactor
                )
                let fbDx = fallback.x - lastPos.x
                let fbDy = fallback.y - lastPos.y
                let fbDist = hypot(fbDx, fbDy)
                if fbDist > effectiveMaxJump {
                    let s = effectiveMaxJump / fbDist
                    fallback = CGPoint(x: lastPos.x + fbDx * s, y: lastPos.y + fbDy * s)
                }
                fallback.x = max(0, min(fallback.x, CGFloat(frame.width)))
                fallback.y = max(0, min(fallback.y, CGFloat(frame.height)))
                
                let verticalDelta = Double(fallback.y - lastPos.y)
                let rawScaleChange = verticalDelta * scaleRate
                let clampedScaleChange = max(-maxScaleChangePerFrame, min(maxScaleChangePerFrame, rawScaleChange))
                currentScale = max(minScale, min(maxScale, currentScale + clampedScaleChange))
                
                positions[frameIndex] = TrackedPosition(center: fallback, isManualOverride: false)
                lastPos = fallback
                velocity = CGPoint(x: velocity.x * 0.7, y: velocity.y * 0.7)
                
                if consecutiveFailures == 5 {
                    if let refreshed = captureTemplate(from: frame, at: fallback, scale: currentScale) {
                        currentTemplate = refreshed
                    }
                }
            }
            
            progress(Float(offset + 1) / Float(total))
        }
        
        return positions
    }
    
    // MARK: - Post-Tracking Smoothing (Moving Average)
    
    func smoothPositions(
        _ positions: [Int: TrackedPosition],
        windowSize: Int = 5
    ) -> [Int: TrackedPosition] {
        let sortedKeys = positions.keys.sorted()
        guard sortedKeys.count > windowSize else { return positions }
        
        var smoothed = positions
        let halfWindow = windowSize / 2
        
        for i in 0..<sortedKeys.count {
            let key = sortedKeys[i]
            if positions[key]?.isManualOverride == true { continue }
            
            let windowStart = max(0, i - halfWindow)
            let windowEnd = min(sortedKeys.count - 1, i + halfWindow)
            
            var sumX: CGFloat = 0
            var sumY: CGFloat = 0
            var count: CGFloat = 0
            
            for j in windowStart...windowEnd {
                let neighborKey = sortedKeys[j]
                guard let pos = positions[neighborKey] else { continue }
                
                let distance = abs(j - i)
                let weight: CGFloat = 1.0 / CGFloat(1 + distance)
                sumX += pos.center.x * weight
                sumY += pos.center.y * weight
                count += weight
            }
            
            guard count > 0 else { continue }
            smoothed[key] = TrackedPosition(
                center: CGPoint(x: sumX / count, y: sumY / count),
                isManualOverride: false
            )
        }
        
        return smoothed
    }
    
    // MARK: - RGB Pixel Extraction
    
    private func extractRGB(from image: CGImage) -> [UInt8]? {
        let w = image.width
        let h = image.height
        let bytesPerRow = w * 4
        
        guard let context = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return nil }
        
        let totalPixels = w * h
        let rgba = data.bindMemory(to: UInt8.self, capacity: totalPixels * 4)
        
        var rgb = [UInt8](repeating: 0, count: totalPixels * 3)
        rgb.withUnsafeMutableBufferPointer { rgbBuf in
            let dst = rgbBuf.baseAddress!
            for i in 0..<totalPixels {
                dst[i * 3]     = rgba[i * 4]
                dst[i * 3 + 1] = rgba[i * 4 + 1]
                dst[i * 3 + 2] = rgba[i * 4 + 2]
            }
        }
        return rgb
    }
    
    private func extractRGBResized(from image: CGImage, toWidth width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        
        let totalPixels = width * height
        let rgba = data.bindMemory(to: UInt8.self, capacity: totalPixels * 4)
        
        var rgb = [UInt8](repeating: 0, count: totalPixels * 3)
        rgb.withUnsafeMutableBufferPointer { rgbBuf in
            let dst = rgbBuf.baseAddress!
            for i in 0..<totalPixels {
                dst[i * 3]     = rgba[i * 4]
                dst[i * 3 + 1] = rgba[i * 4 + 1]
                dst[i * 3 + 2] = rgba[i * 4 + 2]
            }
        }
        return rgb
    }
}
