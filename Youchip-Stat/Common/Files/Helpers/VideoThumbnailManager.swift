//
//  VideoThumbnailManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import AVFoundation
import AppKit

class VideoThumbnailManager {
    
    static let shared = VideoThumbnailManager()
    
    func generateThumbnail(for url: URL, at time: CMTime = CMTime(seconds: 1, preferredTimescale: 600), completion: @escaping (NSImage?) -> Void) {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 200, height: 200)
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let image = NSImage(cgImage: cgImage, size: CGSize(width: 200, height: 200))
                DispatchQueue.main.async {
                    completion(image)
                }
            } catch {
                print("Ошибка генерации превью видео: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}
