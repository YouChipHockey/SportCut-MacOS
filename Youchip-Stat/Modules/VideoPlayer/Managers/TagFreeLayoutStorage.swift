//
//  TagFreeLayoutStorage.swift
//  Youchip-Stat
//
//  Хранение и загрузка свободной раскладки тегов и лейблов по коллекциям.
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

    // MARK: - Public API

    /// Загрузить раскладку, если она существует. Не создаёт дефолтную.
    static func loadLayoutIfExists(
        collectionId: String,
        tags: [Tag],
        labels: [Label] = [],
        timeEvents: [TimeEvent] = []
    ) -> TagFreeLayout? {
        let url = layoutFileURL(forCollectionId: collectionId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(TagFreeLayout.self, from: data) else {
            return nil
        }
        return normalizeLayout(decoded, tags: tags, labels: labels, timeEvents: timeEvents)
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

    /// Создать дефолтную сеточную раскладку для всех тегов (лейблы не добавляются автоматически).
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

            items.append(TagFreeLayoutItem(
                elementId: tag.id,
                kind: .tag,
                center: CGPoint(x: x, y: y),
                size: CGSize(width: itemWidth, height: itemHeight),
                rotation: 0,
                shape: .square
            ))

            column += 1
            if column >= columns {
                column = 0
                row += 1
            }
        }

        let canvasHeight = max(verticalSpacing + CGFloat(row + 1) * (itemHeight + verticalSpacing), 800)
        return TagFreeLayout(canvasWidth: canvasWidth, canvasHeight: canvasHeight, items: items)
    }

    // MARK: - Normalization

    /// Синхронизирует раскладку с актуальным набором тегов и лейблов:
    /// - удаляет элементы для удалённых тегов
    /// - добавляет элементы для новых тегов в конец
    /// - удаляет элементы для удалённых лейблов (лейблы не добавляются автоматически)
    /// - удаляет связки, у которых source или target больше не существуют
    static func normalizeLayout(
        _ layout: TagFreeLayout,
        tags: [Tag],
        labels: [Label] = [],
        timeEvents: [TimeEvent] = []
    ) -> TagFreeLayout {
        let existingTagIds = Set(tags.map { $0.id })
        let existingLabelIds = Set(labels.map { $0.id })
        let existingTimeEventIds = Set(timeEvents.map { $0.id })

        // Filter items: keep tags that still exist and labels that still exist
        var filteredItems = layout.items.filter { item in
            switch item.kind {
            case .tag:       return existingTagIds.contains(item.elementId)
            case .label:     return existingLabelIds.contains(item.elementId)
            case .timeEvent: return existingTimeEventIds.contains(item.elementId)
            }
        }

        // Add items for new tags (labels are added manually via palette)
        let existingTagItemIds = Set(filteredItems.filter { $0.kind == .tag }.map { $0.elementId })
        let missingTags = tags.filter { !existingTagItemIds.contains($0.id) }
        if !missingTags.isEmpty {
            let defaultLayout = makeDefaultLayout(for: missingTags)
            filteredItems.append(contentsOf: defaultLayout.items)
        }

        // Filter bindings: remove bindings whose source or target no longer exist
        let allValidIds: Set<String> = Set(filteredItems.map { $0.id })
        let filteredBindings = layout.bindings.filter { binding in
            allValidIds.contains(binding.sourceButtonKey) && allValidIds.contains(binding.targetButtonKey)
        }

        return TagFreeLayout(
            canvasWidth: layout.canvasWidth,
            canvasHeight: layout.canvasHeight,
            items: filteredItems,
            bindings: filteredBindings
        )
    }

    // MARK: - Canvas item helpers

    /// Вернуть тег на холст (если его убрали с поля, но он есть в коллекции).
    static func addTagToLayout(_ layout: inout TagFreeLayout, tag: Tag) {
        guard !layout.items.contains(where: { $0.elementId == tag.id && $0.kind == .tag }) else { return }
        let maxY = layout.items.map { $0.center.y + $0.size.height / 2 }.max() ?? 100
        let newItem = TagFreeLayoutItem(
            elementId: tag.id,
            kind: .tag,
            center: CGPoint(x: layout.canvasWidth / 2, y: maxY + 80),
            size: CGSize(width: 180, height: 70),
            rotation: 0,
            shape: .square
        )
        layout.items.append(newItem)
    }

    static func addLabelToLayout(_ layout: inout TagFreeLayout, label: Label) {
        guard !layout.items.contains(where: { $0.elementId == label.id && $0.kind == .label }) else { return }
        let maxY = layout.items.map { $0.center.y + $0.size.height / 2 }.max() ?? 100
        let newItem = TagFreeLayoutItem(
            elementId: label.id,
            kind: .label,
            center: CGPoint(x: layout.canvasWidth / 2, y: maxY + 80),
            size: CGSize(width: 160, height: 55),
            rotation: 0,
            shape: .capsule,
            fillOpacity: 0.85,
            strokeWidth: 1.0,
            fontSize: 12,
            fontWeight: .medium,
            showLabel: true,
            cornerRadius: 8
        )
        layout.items.append(newItem)
    }

    static func addTimeEventToLayout(_ layout: inout TagFreeLayout, event: TimeEvent) {
        guard !layout.items.contains(where: { $0.elementId == event.id && $0.kind == .timeEvent }) else { return }
        let maxY = layout.items.map { $0.center.y + $0.size.height / 2 }.max() ?? 100
        let newItem = TagFreeLayoutItem(
            elementId: event.id,
            kind: .timeEvent,
            center: CGPoint(x: layout.canvasWidth / 2, y: maxY + 80),
            size: CGSize(width: 160, height: 55),
            rotation: 0,
            shape: .capsule,
            fillOpacity: 0.85,
            strokeWidth: 1.0,
            fontSize: 12,
            fontWeight: .medium,
            showLabel: true,
            cornerRadius: 8
        )
        layout.items.append(newItem)
    }
}
