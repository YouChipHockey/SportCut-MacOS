//
//  ScreenshotsMetadataManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import Foundation
import Combine

class ScreenshotsMetadataManager: ObservableObject {
    static let shared = ScreenshotsMetadataManager()
    
    @Published var screenshots: [ScreenshotMetadata] = []
    
    private init() {}
    
    func loadScreenshots(from screenshotsFolder: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: screenshotsFolder,
                                                                     includingPropertiesForKeys: nil)
                
                let jsonURLs = fileURLs.filter { $0.pathExtension.lowercased() == "json" }
                
                let metadataArray = jsonURLs.compactMap { url -> ScreenshotMetadata? in
                    guard let data = try? Data(contentsOf: url),
                          let metadata = try? JSONDecoder().decode(ScreenshotMetadata.self, from: data) else {
                        return nil
                    }
                    print("📥 Loaded screenshot metadata '\(metadata.screenshotName)' with displayDuration: \(metadata.displayDuration) seconds")
                    return metadata
                }
                
                DispatchQueue.main.async {
                    self.screenshots = metadataArray.sorted { $0.videoTime < $1.videoTime }
                }
            } catch {
                DispatchQueue.main.async {
                    self.screenshots = []
                }
            }
        }
    }
    
    func clearScreenshots() {
        screenshots = []
    }
    
    func updateScreenshotRelatedStamps(screenshotName: String, relatedStampIds: [UUID]) {
        guard let index = screenshots.firstIndex(where: { $0.screenshotName == screenshotName }) else {
            return
        }
        
        var updatedScreenshot = screenshots[index]
        updatedScreenshot = ScreenshotMetadata(
            screenshotName: updatedScreenshot.screenshotName,
            videoTime: updatedScreenshot.videoTime,
            createdAt: updatedScreenshot.createdAt,
            saveAsTag: updatedScreenshot.saveAsTag,
            displayDuration: updatedScreenshot.displayDuration,
            relatedStampIds: relatedStampIds
        )
        screenshots[index] = updatedScreenshot
        
        // Сохраняем обновленные метаданные в JSON файл
        guard let currentBookmark = TimelineDataManager.shared.currentBookmark,
              let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.bookmark == currentBookmark }) else {
            print("❌ Не найден filesFile для сохранения метаданных")
            return
        }
        
        let screenshotsFolder = filesFile.screenshotsFolder
        let jsonFileName = "\(screenshotName).json"
        let jsonURL = screenshotsFolder.appendingPathComponent(jsonFileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(screenshots[index])
            try data.write(to: jsonURL)
            print("✅ Обновлены метаданные для скриншота '\(screenshotName)': \(relatedStampIds.count) связанных тегов")
        } catch {
            print("❌ Ошибка сохранения метаданных скриншота: \(error.localizedDescription)")
        }
    }
    
    func removeScreenshot(screenshotName: String) {
        screenshots.removeAll { $0.screenshotName == screenshotName }
        print("✅ Скриншот '\(screenshotName)' удален из менеджера")
    }
}

