//
//  GroupDuplicationService.swift
//  Youchip-Stat
//
//  Копирует группы тегов/лейблов из одной коллекции в другую (по id назначения),
//  регенерируя все id, чтобы не было конфликтов. Группы добавляются в конец списка
//  целевой коллекции. Работает как для обычных коллекций, так и для коллекций связок клавиш —
//  формат данных (CollectionData) у них общий.
//

import Foundation

enum GroupDuplicationService {

    struct TagGroupPayload {
        let group: TagGroup
        let tags: [Tag]
    }

    struct LabelGroupPayload {
        let group: LabelGroupData
        let labels: [Label]
    }

    /// Дублирует выбранные группы в целевую коллекцию. Возвращает true при успехе.
    ///
    /// Семантика повторяет одиночную вставку (`pasteTagGroup`/`pasteLabelGroup`):
    /// у тегов сохраняются только ссылки на группы лейблов, которые уже есть в целевой коллекции.
    @discardableResult
    static func duplicate(
        tagGroups: [TagGroupPayload],
        labelGroups: [LabelGroupPayload],
        intoCollectionID targetID: String
    ) -> Bool {
        guard var target = InMemoryStorageManager.shared.loadCollection(id: targetID) else { return false }

        for payload in labelGroups {
            appendLabelGroup(payload, to: &target)
        }
        for payload in tagGroups {
            appendTagGroup(payload, to: &target)
        }

        InMemoryStorageManager.shared.saveCollection(target)
        InMemoryStorageManager.shared.saveToDiskImmediate()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
        }
        return true
    }

    // MARK: - Private

    private static func appendTagGroup(_ payload: TagGroupPayload, to target: inout CollectionData) {
        let sourceByID = Dictionary(payload.tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingLabelGroupIDs = Set(target.labelGroups.map(\.id))
        let existingLabelIDs = Set(target.labels.map(\.id))
        let targetCollectionName = collectionName(for: target.id)

        var newTagIDs: [String] = []
        for tagID in payload.group.tags {
            guard let source = sourceByID[tagID] else { continue }
            let keptLabelGroups = source.lablesGroup.filter { existingLabelGroupIDs.contains($0) }
            let keptLabelHotkeys = source.labelHotkeys?.filter { existingLabelIDs.contains($0.key) }
            let newID = UUID().uuidString
            target.tags.append(
                Tag(
                    id: newID,
                    primaryID: source.primaryID,
                    name: source.name,
                    description: source.description,
                    color: source.color,
                    defaultTimeBefore: source.defaultTimeBefore,
                    defaultTimeAfter: source.defaultTimeAfter,
                    collection: targetCollectionName,
                    lablesGroup: keptLabelGroups,
                    hotkey: source.hotkey,
                    labelHotkeys: (keptLabelHotkeys?.isEmpty ?? true) ? nil : keptLabelHotkeys,
                    mapEnabled: source.mapEnabled,
                    isInterval: source.isInterval,
                    mapFieldId: nil
                )
            )
            newTagIDs.append(newID)
        }

        let name = uniqueName(payload.group.name, taken: target.tagGroups.map(\.name))
        target.tagGroups.append(TagGroup(id: UUID().uuidString, name: name, tags: newTagIDs))
    }

    private static func appendLabelGroup(_ payload: LabelGroupPayload, to target: inout CollectionData) {
        let sourceByID = Dictionary(payload.labels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var newLabelIDs: [String] = []
        for labelID in payload.group.lables {
            guard let source = sourceByID[labelID] else { continue }
            let newID = UUID().uuidString
            target.labels.append(Label(id: newID, name: source.name, description: source.description))
            newLabelIDs.append(newID)
        }

        let name = uniqueName(payload.group.name, taken: target.labelGroups.map(\.name))
        target.labelGroups.append(LabelGroupData(id: UUID().uuidString, name: name, lables: newLabelIDs))
    }

    private static func collectionName(for id: String) -> String {
        CollectionsBookmarksManager.shared.loadCollections().first(where: { $0.id == id })?.name ?? ""
    }

    private static func uniqueName(_ base: String, taken: [String]) -> String {
        guard taken.contains(base) else { return base }
        var suffix = 2
        var candidate = "\(base) \(suffix)"
        while taken.contains(candidate) {
            suffix += 1
            candidate = "\(base) \(suffix)"
        }
        return candidate
    }
}
