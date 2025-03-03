//
//  VideosPreviewManager.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 04.07.2024.
//

import SwiftUI
import AppKit
import Cocoa
import QuickLookThumbnailing
import AVFoundation

class VideosPreviewManager {
    
    static let shared = VideosPreviewManager()
    
    func saveThumbnail(for url: URL, completion: (() -> Void)?) {
        if url.isVideo {
            VideoThumbnailManager.shared.generateThumbnail(for: url) { [weak self] image in
                self?.saveThumbnailImage(nsImage: image, for: url)
                completion?()
            }
        } else {
            generateThumbnail(for: url, size: CGSize(width: 200, height: 200)) { [weak self] image in
                self?.saveThumbnailImage(nsImage: image, for: url)
                completion?()
            }
        }
    }
    
    private func generateThumbnail(for url: URL, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: size,
                                                   scale: scale,
                                                   representationTypes: .all)
        
        let generator = QLThumbnailGenerator.shared
        generator.generateBestRepresentation(for: request) { (thumbnail, error) in
            if let error = error {
                print("Ошибка генерации миниатюры: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let cgImage = thumbnail?.cgImage else {
                completion(nil)
                return
            }
            
            let image = NSImage(cgImage: cgImage, size: size)
            completion(image)
        }
    }
    
    func getThumbnail(for url: URL?) -> NSImage? {
        guard let url = url else { return nil }
        let imagePath = URL.previewsDirectory.appendingPathComponent(url.makePreviewName())
        
        do {
            let imageData = try Data(contentsOf: imagePath)
            if let nsImage = NSImage(data: imageData) {
                return nsImage
            }
        } catch {
            print("Ошибка загрузки миниатюры: \(error.localizedDescription)")
        }
        return nil
    }
    
    private func saveThumbnailImage(nsImage: NSImage?, for url: URL) {
        guard let nsImage = nsImage, let cgImage = nsImage.toCGImage() else { return }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }
        
        let imagePath = URL.previewsDirectory.appendingPathComponent(url.makePreviewName())
        do {
            try pngData.write(to: imagePath)
        } catch {
            print("Ошибка сохранения миниатюры: \(error.localizedDescription)")
        }
    }
}

private extension URL {
    var isVideo: Bool {
        let videoExtensions: Set<String> = ["mp4", "mov", "avi", "mkv"]
        return videoExtensions.contains(self.pathExtension.lowercased())
    }
}
