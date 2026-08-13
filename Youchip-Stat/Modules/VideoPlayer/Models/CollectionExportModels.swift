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
    /// Первая карта — обратная совместимость со старыми экспортами.
    let playField: PlayFieldExport?
    /// Полный набор карт коллекции. nil в старых экспортах — тогда используется `playField`.
    let playFields: [PlayFieldExport]?
    /// Режим коллекции: "grouped" (обычная) или "free" (со связками клавиш). nil в старых экспортах = grouped.
    let tagLibraryDisplayMode: String?
    /// Раскладка холста и связки клавиш — только для коллекций со связками (free). Наличие = коллекция со связками.
    let freeLayout: TagFreeLayout?

    init(collectionManager: CustomCollectionManager) {
        self.version = "1.1"
        self.collectionName = collectionManager.collectionName
        self.exportDate = Date()
        self.tagGroups = collectionManager.tagGroups
        self.tags = collectionManager.tags
        self.labelGroups = collectionManager.labelGroups
        self.labels = collectionManager.labels
        self.timeEvents = collectionManager.timeEvents
        self.playField = collectionManager.playField.map { PlayFieldExport(from: $0) }
        self.playFields = collectionManager.playFields.isEmpty ? nil : collectionManager.playFields.map { PlayFieldExport(from: $0) }
        self.tagLibraryDisplayMode = collectionManager.tagLibraryDisplayMode.rawValue
        if collectionManager.tagLibraryDisplayMode == .free {
            self.freeLayout = TagFreeLayoutStorage.loadLayoutIfExists(
                collectionId: collectionManager.collectionID,
                tags: collectionManager.tags,
                labels: collectionManager.labels,
                timeEvents: collectionManager.timeEvents,
                playFields: collectionManager.playFields
            )
        } else {
            self.freeLayout = nil
        }
    }

    /// Частичный экспорт: заранее отфильтрованные наборы + готовая раскладка.
    init(collectionName: String,
         tagGroups: [TagGroup], tags: [Tag],
         labelGroups: [LabelGroupData], labels: [Label],
         timeEvents: [TimeEvent], playFields: [PlayField],
         displayMode: String, freeLayout: TagFreeLayout?) {
        self.version = "1.1"
        self.collectionName = collectionName
        self.exportDate = Date()
        self.tagGroups = tagGroups
        self.tags = tags
        self.labelGroups = labelGroups
        self.labels = labels
        self.timeEvents = timeEvents
        self.playField = playFields.first.map { PlayFieldExport(from: $0) }
        self.playFields = playFields.isEmpty ? nil : playFields.map { PlayFieldExport(from: $0) }
        self.tagLibraryDisplayMode = displayMode
        self.freeLayout = freeLayout
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

            // Карты: предпочитаем новый массив; иначе — одиночная карта (старые экспорты).
            var playFields: [PlayField] = []
            if let playFieldExports = exportData.playFields, !playFieldExports.isEmpty {
                playFields = playFieldExports.compactMap { $0.toPlayField() }
            } else if let playFieldExport = exportData.playField,
                      let playField = playFieldExport.toPlayField() {
                playFields = [playField]
            }

            // Авто-определение типа: коллекция со связками клавиш, если задан режим .free
            // или присутствует раскладка/связки (freeLayout). Иначе — обычная (grouped).
            let isFree = exportData.tagLibraryDisplayMode == CollectionTagLibraryDisplayMode.free.rawValue
                || exportData.freeLayout != nil
            collectionManager.tagLibraryDisplayMode = isFree ? .free : .grouped

            // Импорт сохраняет id из файла, поэтому повторный импорт одного и того же файла даёт
            // две коллекции с общими id — а глобальные пулы дедуплицируются по id и оставляют
            // копию из первой коллекции. Разводим id молча, вместе со ссылками, раскладкой и
            // связками (см. CollectionIdRegenerator).
            let occupied = CollectionIdRegenerator.occupiedIds()
            if CollectionIdRegenerator.collides(
                tags: exportData.tags,
                tagGroups: exportData.tagGroups,
                labelGroups: exportData.labelGroups,
                labels: exportData.labels,
                timeEvents: exportData.timeEvents,
                playFields: playFields,
                occupied: occupied
            ) {
                let fresh = CollectionIdRegenerator.regenerate(
                    tags: exportData.tags,
                    tagGroups: exportData.tagGroups,
                    labelGroups: exportData.labelGroups,
                    labels: exportData.labels,
                    timeEvents: exportData.timeEvents,
                    playFields: playFields,
                    layout: exportData.freeLayout,
                    collectionName: exportData.collectionName
                )
                collectionManager.tags = fresh.tags
                collectionManager.tagGroups = fresh.tagGroups
                collectionManager.labelGroups = fresh.labelGroups
                collectionManager.labels = fresh.labels
                collectionManager.timeEvents = fresh.timeEvents
                collectionManager.playFields = fresh.playFields
                if isFree {
                    collectionManager.pendingImportedLayout = fresh.layout
                }
                print("♻️ CollectionImport: id пересеклись с существующими коллекциями — перевыдал их")
            } else {
                collectionManager.tags = exportData.tags
                collectionManager.tagGroups = exportData.tagGroups
                collectionManager.labelGroups = exportData.labelGroups
                collectionManager.labels = exportData.labels
                collectionManager.timeEvents = exportData.timeEvents
                collectionManager.playFields = playFields
                if isFree {
                    // Раскладка/связки сохранятся под новым id при saveCollectionToFiles.
                    collectionManager.pendingImportedLayout = exportData.freeLayout
                }
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
