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
    private(set) var currentScreenshotsFolder: URL?

    /// Имена (без расширения) скриншотов, у которых на диске реально лежит PNG.
    ///
    /// Нужен затем, чтобы вьюха меток НЕ звала `FileManager.fileExists` из своего `body`.
    /// Раньше `ScreenshotMarkersView` проверяла файл на каждый скриншот при каждом пересчёте
    /// `body`, а пересчитывалась она на каждый тик плеера и на каждый кадр горизонтального
    /// скролла — это давало тысячи `stat()` в секунду на главном потоке (см. TASK-007).
    ///
    /// Набор строится из того же листинга папки, что и сами метаданные, так что лишнего
    /// обращения к диску не появляется.
    private(set) var existingImageBaseNames: Set<String> = []

    private init() {}

    /// Есть ли на диске картинка для этой метаданной. Дешёвая проверка по кэшу — звать из `body` можно.
    func hasImageFile(for screenshot: ScreenshotMetadata) -> Bool {
        existingImageBaseNames.contains(Self.baseName(screenshot.screenshotName))
    }

    /// `screenshotName` в метаданных встречается и с расширением, и без него — нормализуем.
    private static func baseName(_ screenshotName: String) -> String {
        screenshotName.hasSuffix(".png") ? String(screenshotName.dropLast(4)) : screenshotName
    }

    func loadScreenshots(from screenshotsFolder: URL) {
        currentScreenshotsFolder = screenshotsFolder
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

                // Тот же листинг, что и для метаданных — отдельного обхода диска не делаем.
                let imageNames = Set(
                    fileURLs
                        .filter { $0.pathExtension.lowercased() == "png" }
                        .map { $0.deletingPathExtension().lastPathComponent }
                )

                DispatchQueue.main.async {
                    self.existingImageBaseNames = imageNames
                    self.screenshots = metadataArray.sorted { $0.videoTime < $1.videoTime }
                }
            } catch {
                DispatchQueue.main.async {
                    self.existingImageBaseNames = []
                    self.screenshots = []
                }
            }
        }
    }

    func clearScreenshots() {
        screenshots = []
        existingImageBaseNames = []
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
            relatedStampIds: relatedStampIds,
            editorState: updatedScreenshot.editorState
        )
        screenshots[index] = updatedScreenshot
        
        // Сохраняем обновленные метаданные в JSON файл
        guard let videoId = TimelineDataManager.shared.currentVideoId,
              let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == videoId }) else {
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
        existingImageBaseNames.remove(Self.baseName(screenshotName))
        print("✅ Скриншот '\(screenshotName)' удален из менеджера")
    }
}

