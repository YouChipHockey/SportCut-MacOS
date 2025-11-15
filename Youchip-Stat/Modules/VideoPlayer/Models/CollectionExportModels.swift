//
//  CollectionExportModels.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import Foundation
import SwiftUI

// MARK: - Export Collection Data Structure

struct SportcutCollectionExport: Codable {
    let version: String
    let collectionName: String
    let exportDate: Date
    let tagGroups: [TagGroup]
    let tags: [Tag]
    let labelGroups: [LabelGroupData]
    let labels: [Label]
    let timeEvents: [TimeEvent]
    let playField: PlayFieldExport?
    
    init(collectionManager: CustomCollectionManager) {
        self.version = "1.0"
        self.collectionName = collectionManager.collectionName
        self.exportDate = Date()
        self.tagGroups = collectionManager.tagGroups
        self.tags = collectionManager.tags
        self.labelGroups = collectionManager.labelGroups
        self.labels = collectionManager.labels
        self.timeEvents = collectionManager.timeEvents
        self.playField = collectionManager.playField.map { PlayFieldExport(from: $0) }
    }
}

struct PlayFieldExport: Codable {
    let id: String
    let name: String
    let width: Double
    let height: Double
    let imageData: Data? // Base64 encoded image data
    
    init(from playField: PlayField) {
        self.id = playField.id
        self.name = playField.name
        self.width = playField.width
        self.height = playField.height
        
        if let imageBookmark = playField.imageBookmark {
            do {
                var isStale = false
                let imageURL = try URL(resolvingBookmarkData: imageBookmark, 
                                     options: .withSecurityScope, 
                                     relativeTo: nil, 
                                     bookmarkDataIsStale: &isStale)
                
                if imageURL.startAccessingSecurityScopedResource() {
                    defer { imageURL.stopAccessingSecurityScopedResource() }
                    
                    if let imageData = try? Data(contentsOf: imageURL) {
                        self.imageData = imageData
                    } else {
                        self.imageData = nil
                    }
                } else {
                    self.imageData = nil
                }
            } catch {
                self.imageData = nil
            }
        } else {
            self.imageData = nil
        }
    }
    
    func toPlayField() -> PlayField? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".png"
        let tempURL = tempDir.appendingPathComponent(fileName)
        
        do {
            if let imageData = imageData {
                try imageData.write(to: tempURL)
            } else {
                let placeholderSize = NSSize(width: width, height: height)
                let placeholderImage = NSImage(size: placeholderSize)
                placeholderImage.lockFocus()
                NSColor.gray.setFill()
                NSRect(origin: .zero, size: placeholderSize).fill()
                placeholderImage.unlockFocus()
                
                if let tiffData = placeholderImage.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    try pngData.write(to: tempURL)
                } else {
                    return nil
                }
            }
            
            let bookmarkData = try tempURL.bookmarkData(options: .withSecurityScope, 
                                                      includingResourceValuesForKeys: nil, 
                                                      relativeTo: nil)
            
            return PlayField(
                id: id,
                name: name,
                imagePath: tempURL.path,
                width: width,
                height: height,
                imageBookmark: bookmarkData
            )
        } catch {
            return nil
        }
    }
}

class CollectionImportManager: ObservableObject {
    @Published var isImporting = false
    @Published var importError: String?
    
    func importCollection(from url: URL) -> CustomCollectionManager? {
        isImporting = true
        importError = nil
        
        defer {
            isImporting = false
        }
        
        do {
            let data = try Data(contentsOf: url)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let exportData = try decoder.decode(SportcutCollectionExport.self, from: data)
            
            let collectionManager = CustomCollectionManager()
            collectionManager.collectionName = exportData.collectionName
            collectionManager.tagGroups = exportData.tagGroups
            collectionManager.tags = exportData.tags
            collectionManager.labelGroups = exportData.labelGroups
            collectionManager.labels = exportData.labels
            collectionManager.timeEvents = exportData.timeEvents
            
            if let playFieldExport = exportData.playField,
               let playField = playFieldExport.toPlayField() {
                collectionManager.playField = playField
            }
            
            return collectionManager
            
        } catch DecodingError.keyNotFound(let key, let context) {
            importError = "Отсутствует обязательное поле: \(key.stringValue). Путь: \(context.codingPath)"
            return nil
        } catch DecodingError.typeMismatch(let type, let context) {
            importError = "Неверный тип данных для поля: \(context.codingPath). Ожидался: \(type)"
            return nil
        } catch DecodingError.valueNotFound(let type, let context) {
            importError = "Отсутствует значение для поля: \(context.codingPath). Тип: \(type)"
            return nil
        } catch DecodingError.dataCorrupted(let context) {
            importError = "Поврежденные данные в файле. Путь: \(context.codingPath)"
            return nil
        } catch {
            importError = "Ошибка импорта коллекции: \(error.localizedDescription)"
            return nil
        }
    }
}
