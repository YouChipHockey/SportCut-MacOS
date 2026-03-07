//
//  TagFreeLayoutStorage.swift
//  Youchip-Stat
//
//  Хранение и загрузка свободной раскладки тегов по коллекциям.
//

import Foundation

struct TagFreeLayoutStorage {
    
    private static let fileName = "tagLayout.json"
    
    /// Базовая папка с коллекциями (совпадает с InMemoryStorageManager).
    private static var collectionsDirectory: URL {
        URL.appDocumentsDirectory.appendingPathComponent("YouChip-Stat/Collections", isDirectory: true)
    }
    
    /// Путь к файлу раскладки для указанной коллекции.
    private static func layoutFileURL(forCollectionId id: String) -> URL {
        let folder = collectionsDirectory.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }
    
    /// Загрузить раскладку, если она существует. Не создаёт дефолтную.
    static func loadLayoutIfExists(collectionId: String, tags: [Tag]) -> TagFreeLayout? {
        let url = layoutFileURL(forCollectionId: collectionId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(TagFreeLayout.self, from: data) else {
            return nil
        }
        return normalizeLayout(decoded, tags: tags)
    }
    
    /// Сохранить раскладку для коллекции.
    static func saveLayout(_ layout: TagFreeLayout, collectionId: String) {
        let url = layoutFileURL(forCollectionId: collectionId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(layout) {
            try? data.write(to: url)
        }
    }
    
    /// Создать дефолтную сеточную раскладку для всех тегов.
    static func makeDefaultLayout(for tags: [Tag]) -> TagFreeLayout {
        let canvasWidth: CGFloat = 1000
        let itemWidth: CGFloat = 180
        let itemHeight: CGFloat = 70
        let horizontalSpacing: CGFloat = 40
        let verticalSpacing: CGFloat = 40
        
        let totalItemWidth = itemWidth + horizontalSpacing
        let columns = max(Int((canvasWidth - horizontalSpacing) / totalItemWidth), 1)
        
        var items: [TagFreeLayoutItem] = []
        var row = 0
        var column = 0
        
        for tag in tags {
            let x = horizontalSpacing + CGFloat(column) * totalItemWidth + itemWidth / 2
            let y = verticalSpacing + CGFloat(row) * (itemHeight + verticalSpacing) + itemHeight / 2
            
            let center = CGPoint(x: x, y: y)
            let size = CGSize(width: itemWidth, height: itemHeight)
            
            let item = TagFreeLayoutItem(
                tagId: tag.id,
                center: center,
                size: size,
                rotation: 0,
                shape: .square
            )
            items.append(item)
            
            column += 1
            if column >= columns {
                column = 0
                row += 1
            }
        }
        
        let canvasHeight = max(verticalSpacing + CGFloat(row + 1) * (itemHeight + verticalSpacing), 800)
        
        return TagFreeLayout(
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            items: items
        )
    }
    
    /// Синхронизация раскладки с актуальным набором тегов:
    /// - удаляем элементы для удалённых тегов
    /// - добавляем элементы для новых тегов в конец.
    private static func normalizeLayout(_ layout: TagFreeLayout, tags: [Tag]) -> TagFreeLayout {
        let existingTagIds = Set(tags.map { $0.id })
        
        var filteredItems = layout.items.filter { existingTagIds.contains($0.tagId) }
        let itemIds = Set(filteredItems.map { $0.tagId })
        
        let missingTags = tags.filter { !itemIds.contains($0.id) }
        if !missingTags.isEmpty {
            var defaultLayout = makeDefaultLayout(for: missingTags)
            // Используем уже заданную ширину/высоту, если она больше.
            defaultLayout.canvasWidth = max(defaultLayout.canvasWidth, layout.canvasWidth)
            defaultLayout.canvasHeight = max(defaultLayout.canvasHeight, layout.canvasHeight)
            filteredItems.append(contentsOf: defaultLayout.items)
        }
        
        return TagFreeLayout(
            canvasWidth: layout.canvasWidth,
            canvasHeight: layout.canvasHeight,
            items: filteredItems
        )
    }
}

