//
//  CollectionIdRegenerator.swift
//  Youchip-Stat
//
//  Переназначение id сущностей внутри коллекции с перевязкой ВСЕХ ссылок,
//  включая свободную раскладку и связки клавиш.
//

import Foundation

/// Разводит id коллекций, чтобы две коллекции никогда не делили идентификаторы.
///
/// Зачем: глобальные пулы `TagLibraryManager.allTags`/`allLabels`/… склеены из всех коллекций и
/// дедуплицированы по id (`Dictionary(grouping:).values.compactMap { $0.first }`), а порядок
/// склейки — порядок коллекций в `CollectionsBookmarks.json`. При совпадающих id всегда побеждает
/// копия из ПЕРВОЙ коллекции: переименование тега во второй не видно ни на таймлайне, ни в
/// экспорте. Приоритет текущей коллекции в `findTagById` это лечит по месту, а здесь мы убираем
/// саму причину.
///
/// Штатные источники дублей: повторный импорт одного и того же файла (импорт сохраняет id из
/// файла, новый генерируется только у самой коллекции) и дублирование коллекции.
enum CollectionIdRegenerator {

    /// Коллекция с новыми id и перевязанными ссылками.
    struct Result {
        var tags: [Tag]
        var tagGroups: [TagGroup]
        var labelGroups: [LabelGroupData]
        var labels: [Label]
        var timeEvents: [TimeEvent]
        var playFields: [PlayField]
        var layout: TagFreeLayout?
    }

    // MARK: - Проверка пересечения

    /// Id сущностей, уже занятые установленными коллекциями (пользовательскими и стандартными).
    static func occupiedIds() -> Set<String> {
        var result = Set<String>()

        for info in CollectionsBookmarksManager.shared.loadCollections() {
            guard let data = InMemoryStorageManager.shared.loadCollection(id: info.id) else { continue }
            data.tags.forEach { result.insert($0.id) }
            data.tagGroups.forEach { result.insert($0.id) }
            data.labels.forEach { result.insert($0.id) }
            data.labelGroups.forEach { result.insert($0.id) }
            data.timeEvents.forEach { result.insert($0.id) }
            let fields: [PlayField] = data.playFields ?? (data.playField.map { field in [field] } ?? [])
            fields.forEach { result.insert($0.id) }
        }

        // Стандартные коллекции тоже попадают в общий пул, поэтому пересечение с ними так же вредно.
        for std in TagLibraryManager.shared.standardCollections {
            std.tags.forEach { result.insert($0.id) }
            std.tagGroups.forEach { result.insert($0.id) }
            std.labels.forEach { result.insert($0.id) }
            std.labelGroups.forEach { result.insert($0.id) }
            std.timeEvents.forEach { result.insert($0.id) }
        }

        return result
    }

    /// Пересекается ли коллекция по id с уже занятыми.
    static func collides(
        tags: [Tag],
        tagGroups: [TagGroup],
        labelGroups: [LabelGroupData],
        labels: [Label],
        timeEvents: [TimeEvent],
        playFields: [PlayField],
        occupied: Set<String>
    ) -> Bool {
        guard !occupied.isEmpty else { return false }
        if tags.contains(where: { occupied.contains($0.id) }) { return true }
        if tagGroups.contains(where: { occupied.contains($0.id) }) { return true }
        if labels.contains(where: { occupied.contains($0.id) }) { return true }
        if labelGroups.contains(where: { occupied.contains($0.id) }) { return true }
        if timeEvents.contains(where: { occupied.contains($0.id) }) { return true }
        if playFields.contains(where: { occupied.contains($0.id) }) { return true }
        return false
    }

    // MARK: - Регенерация

    /// Новая копия коллекции: у всех сущностей свежие id, все ссылки перевязаны.
    ///
    /// `primaryID` тега НЕ трогаем — это сквозной идентификатор смысла тега между копиями
    /// (так же поступает `startFromTemplate`), по нему сшивается разметка разных проектов.
    static func regenerate(
        tags srcTags: [Tag],
        tagGroups srcTagGroups: [TagGroup],
        labelGroups srcLabelGroups: [LabelGroupData],
        labels srcLabels: [Label],
        timeEvents srcTimeEvents: [TimeEvent],
        playFields srcPlayFields: [PlayField],
        layout srcLayout: TagFreeLayout?,
        collectionName: String? = nil
    ) -> Result {
        var labelIdMap: [String: String] = [:]
        let newLabels = srcLabels.map { lbl -> Label in
            let nid = UUID().uuidString
            labelIdMap[lbl.id] = nid
            return Label(id: nid, name: lbl.name, description: lbl.description)
        }

        var labelGroupIdMap: [String: String] = [:]
        let newLabelGroups = srcLabelGroups.map { g -> LabelGroupData in
            let nid = UUID().uuidString
            labelGroupIdMap[g.id] = nid
            return LabelGroupData(id: nid, name: g.name, lables: g.lables.compactMap { labelIdMap[$0] })
        }

        var playFieldIdMap: [String: String] = [:]
        let newPlayFields = srcPlayFields.map { pf -> PlayField in
            let nid = UUID().uuidString
            playFieldIdMap[pf.id] = nid
            return PlayField(
                id: nid, name: pf.name, imagePath: pf.imagePath,
                width: pf.width, height: pf.height, imageBookmark: pf.imageBookmark
            )
        }

        var timeEventIdMap: [String: String] = [:]
        let newTimeEvents = srcTimeEvents.map { event -> TimeEvent in
            let nid = UUID().uuidString
            timeEventIdMap[event.id] = nid
            return TimeEvent(id: nid, name: event.name)
        }

        var tagIdMap: [String: String] = [:]
        let newTags = srcTags.map { t -> Tag in
            let nid = UUID().uuidString
            tagIdMap[t.id] = nid
            // Ключи labelHotkeys — это id лейблов, их тоже надо перевязать.
            var newLabelHotkeys: [String: String]? = nil
            if let lh = t.labelHotkeys {
                newLabelHotkeys = Dictionary(uniqueKeysWithValues: lh.compactMap { key, value in
                    labelIdMap[key].map { ($0, value) }
                })
            }
            return Tag(
                id: nid,
                primaryID: t.primaryID,
                name: t.name,
                description: t.description,
                color: t.color,
                defaultTimeBefore: t.defaultTimeBefore,
                defaultTimeAfter: t.defaultTimeAfter,
                collection: collectionName ?? t.collection,
                lablesGroup: t.lablesGroup.compactMap { labelGroupIdMap[$0] },
                hotkey: t.hotkey,
                labelHotkeys: newLabelHotkeys,
                mapEnabled: t.mapEnabled,
                isInterval: t.isInterval,
                mapFieldId: t.mapFieldId.flatMap { playFieldIdMap[$0] },
                mapFieldIds: t.resolvedMapFieldIds.compactMap { playFieldIdMap[$0] }
            )
        }

        let newTagGroups = srcTagGroups.map { g -> TagGroup in
            TagGroup(id: UUID().uuidString, name: g.name, tags: g.tags.compactMap { tagIdMap[$0] })
        }

        let newLayout = srcLayout.map { layout in
            remapLayout(
                layout,
                tagIdMap: tagIdMap,
                labelIdMap: labelIdMap,
                timeEventIdMap: timeEventIdMap,
                playFieldIdMap: playFieldIdMap
            )
        }

        return Result(
            tags: newTags,
            tagGroups: newTagGroups,
            labelGroups: newLabelGroups,
            labels: newLabels,
            timeEvents: newTimeEvents,
            playFields: newPlayFields,
            layout: newLayout
        )
    }

    // MARK: - Раскладка и связки

    /// Перевязывает элементы холста и связки клавиш на новые id.
    /// Элементы и связки, чей id не удалось отобразить, выкидываются — иначе останутся висеть
    /// на несуществующих сущностях (`normalizeLayout` их всё равно вычистит, но уже молча).
    private static func remapLayout(
        _ layout: TagFreeLayout,
        tagIdMap: [String: String],
        labelIdMap: [String: String],
        timeEventIdMap: [String: String],
        playFieldIdMap: [String: String]
    ) -> TagFreeLayout {
        func mapped(_ id: String, kind: CanvasButtonKind) -> String? {
            switch kind {
            case .tag:       return tagIdMap[id]
            case .label:     return labelIdMap[id]
            case .timeEvent: return timeEventIdMap[id]
            case .map:       return playFieldIdMap[id]
            }
        }

        let newItems: [TagFreeLayoutItem] = layout.items.compactMap { item in
            guard let nid = mapped(item.elementId, kind: item.kind) else { return nil }
            var copy = item
            copy.elementId = nid
            return copy
        }

        let newBindings: [KeyBinding] = layout.bindings.compactMap { binding in
            guard let src = mapped(binding.sourceId, kind: binding.sourceKind),
                  let dst = mapped(binding.targetId, kind: binding.targetKind) else { return nil }
            var copy = binding
            copy.id = UUID().uuidString
            copy.sourceId = src
            copy.targetId = dst
            return copy
        }

        return TagFreeLayout(
            canvasWidth: layout.canvasWidth,
            canvasHeight: layout.canvasHeight,
            items: newItems,
            bindings: newBindings
        )
    }
}
