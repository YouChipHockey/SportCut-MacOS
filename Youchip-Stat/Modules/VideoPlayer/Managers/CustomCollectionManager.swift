//
//  CustomCollectionManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers

/// Шаблон, с которого стартует новая коллекция: стандартная (по имени) или пользовательская (по id).
enum CollectionTemplate {
    case standard(name: String)
    case user(id: String, name: String)
}

class CustomCollectionManager: ObservableObject {
    
    var changedTags: [(id: String, newName: String)] = []
    /// Полный набор карт коллекции (источник истины). Может быть несколько.
    @Published var playFields: [PlayField] = []
    /// Первая карта — обратная совместимость с кодом, работающим с одной картой.
    var playField: PlayField? {
        get { playFields.first }
        set {
            if let newValue {
                if playFields.isEmpty { playFields = [newValue] }
                else { playFields[0] = newValue }
            } else {
                playFields = []
            }
        }
    }
    @Published var tagGroups: [TagGroup] = []
    @Published var tags: [Tag] = []
    @Published var labelGroups: [LabelGroupData] = []
    @Published var labels: [Label] = []
    @Published var timeEvents: [TimeEvent] = []
    /// Секундомеры/таймеры коллекции (объекты холста связок).
    @Published var clocks: [ClockEntity] = []
    @Published var collectionName: String = ^String.Titles.myCollection
    @Published var collectionID: String = UUID().uuidString
    @Published var isEditingExisting: Bool = false
    @Published var tagLibraryDisplayMode: CollectionTagLibraryDisplayMode = .grouped
    @Published var allCollections: [StandardCollection] = []
    var originalName: String = ""
    /// Раскладка/связки импортированной коллекции со связками клавиш — сохраняется после записи коллекции
    /// (когда уже известен финальный collectionID).
    var pendingImportedLayout: TagFreeLayout?

    var isKeyBindingsMode: Bool {
        tagLibraryDisplayMode == .free
    }

    private var allLabelGroupIDs: [String] {
        labelGroups.map(\.id)
    }
    
    init() {}

    init(initialDisplayMode: CollectionTagLibraryDisplayMode) {
        self.tagLibraryDisplayMode = initialDisplayMode
    }

    /// Новая коллекция выбранного типа, предзаполненная копией шаблона (стандартной/пользовательской).
    convenience init(initialDisplayMode: CollectionTagLibraryDisplayMode, template: CollectionTemplate?) {
        self.init(initialDisplayMode: initialDisplayMode)
        applyTemplate(template)
    }
    
    init(withBookmark bookmark: CollectionBookmark) {
        self.isEditingExisting = true
        self.originalName = bookmark.name
        self.collectionName = bookmark.name
        self.collectionID = bookmark.id
        loadCollectionFromBookmarks(named: bookmark.name)
        loadAllCollections()
    }
    
    // MARK: - Reordering
    //
    // Reordering is driven by drag & drop of ids (see `CollectionReorderDropDelegate`)
    // rather than List's `.onMove`: the editor rows carry their own tap gestures, which
    // swallow the built-in drag on macOS.

    /// Moves `draggedID` onto `targetID`'s position, matching the timeline reorder feel.
    private func reorder<T>(_ array: inout [T], draggedID: String, targetID: String, id: (T) -> String) {
        guard let draggedIndex = array.firstIndex(where: { id($0) == draggedID }),
              let targetIndex = array.firstIndex(where: { id($0) == targetID }),
              draggedIndex != targetIndex else { return }
        let item = array.remove(at: draggedIndex)
        // При движении вниз обычно вставляем перед целью (targetIndex - 1), но если цель —
        // последний элемент, разрешаем встать в самый конец (иначе низ недостижим).
        let newIndex: Int
        if draggedIndex < targetIndex {
            newIndex = (targetIndex == array.count) ? targetIndex : targetIndex - 1
        } else {
            newIndex = targetIndex
        }
        array.insert(item, at: newIndex)
    }

    func reorderTagGroups(draggedID: String, targetID: String) {
        reorder(&tagGroups, draggedID: draggedID, targetID: targetID, id: { $0.id })
        objectWillChange.send()
    }

    func reorderLabelGroups(draggedID: String, targetID: String) {
        reorder(&labelGroups, draggedID: draggedID, targetID: targetID, id: { $0.id })
        objectWillChange.send()
    }

    func reorderTimeEvents(draggedID: String, targetID: String) {
        reorder(&timeEvents, draggedID: draggedID, targetID: targetID, id: { $0.id })
        objectWillChange.send()
    }

    /// Order of tags inside a group is the group's own id list — that is what the markup
    /// tag library renders, so reordering edits it rather than the flat `tags` array.
    func reorderTags(inGroup groupID: String, draggedID: String, targetID: String) {
        guard let index = tagGroups.firstIndex(where: { $0.id == groupID }) else { return }
        var ids = tagGroups[index].tags
        reorder(&ids, draggedID: draggedID, targetID: targetID, id: { $0 })
        tagGroups[index] = TagGroup(id: tagGroups[index].id, name: tagGroups[index].name, tags: ids)
        objectWillChange.send()
    }

    /// Same idea as `reorderTags(inGroup:...)` — the label picker renders `group.lables` order.
    func reorderLabels(inGroup groupID: String, draggedID: String, targetID: String) {
        guard let index = labelGroups.firstIndex(where: { $0.id == groupID }) else { return }
        var ids = labelGroups[index].lables
        reorder(&ids, draggedID: draggedID, targetID: targetID, id: { $0 })
        labelGroups[index] = LabelGroupData(id: labelGroups[index].id, name: labelGroups[index].name, lables: ids)
        objectWillChange.send()
    }

    // MARK: - Pasting groups copied from another collection

    /// Pastes a copied tag group as an independent copy with fresh IDs.
    ///
    /// New IDs are mandatory: the global pool merges collections and de-duplicates by id,
    /// so reusing the source ids would make one collection's tags shadow the other's.
    /// References that don't exist here (label groups, label hotkeys) are dropped.
    func pasteTagGroup(_ group: TagGroup, tags sourceTags: [Tag]) {
        let sourceByID = Dictionary(sourceTags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingLabelGroupIDs = Set(labelGroups.map(\.id))
        let existingLabelIDs = Set(labels.map(\.id))

        var newTagIDs: [String] = []
        for tagID in group.tags {
            guard let source = sourceByID[tagID] else { continue }
            let keptLabelGroups = source.lablesGroup.filter { existingLabelGroupIDs.contains($0) }
            let keptLabelHotkeys = source.labelHotkeys?.filter { existingLabelIDs.contains($0.key) }
            let newID = UUID().uuidString
            tags.append(
                Tag(
                    id: newID,
                    primaryID: source.primaryID,
                    name: source.name,
                    description: source.description,
                    color: source.color,
                    defaultTimeBefore: source.defaultTimeBefore,
                    defaultTimeAfter: source.defaultTimeAfter,
                    collection: collectionName,
                    lablesGroup: keptLabelGroups,
                    hotkey: source.hotkey,
                    labelHotkeys: (keptLabelHotkeys?.isEmpty ?? true) ? nil : keptLabelHotkeys,
                    mapEnabled: source.mapEnabled,
                    isInterval: source.isInterval
                )
            )
            newTagIDs.append(newID)
        }

        let name = uniqueName(group.name, taken: tagGroups.map(\.name))
        tagGroups.append(TagGroup(id: UUID().uuidString, name: name, tags: newTagIDs))
        objectWillChange.send()
    }

    /// Pastes a copied label group as an independent copy with fresh IDs.
    func pasteLabelGroup(_ group: LabelGroupData, labels sourceLabels: [Label]) {
        let sourceByID = Dictionary(sourceLabels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var newLabelIDs: [String] = []
        for labelID in group.lables {
            guard let source = sourceByID[labelID] else { continue }
            let newID = UUID().uuidString
            labels.append(Label(id: newID, name: source.name, description: source.description))
            newLabelIDs.append(newID)
        }

        let name = uniqueName(group.name, taken: labelGroups.map(\.name))
        labelGroups.append(LabelGroupData(id: UUID().uuidString, name: name, lables: newLabelIDs))
        objectWillChange.send()
    }

    /// Appends a numeric suffix when `base` is already taken, so a pasted group never
    /// silently collides with an existing one.
    private func uniqueName(_ base: String, taken: [String]) -> String {
        guard taken.contains(base) else { return base }
        var suffix = 2
        var candidate = "\(base) \(suffix)"
        while taken.contains(candidate) {
            suffix += 1
            candidate = "\(base) \(suffix)"
        }
        return candidate
    }

    func renameTagGroup(id: String, newName: String) {
        if let index = tagGroups.firstIndex(where: { $0.id == id }) {
            tagGroups[index] = TagGroup(
                id: id,
                name: newName,
                tags: tagGroups[index].tags
            )
            objectWillChange.send()
        }
    }
    
    func renameLabelGroup(id: String, newName: String) {
        if let index = labelGroups.firstIndex(where: { $0.id == id }) {
            labelGroups[index] = LabelGroupData(
                id: id,
                name: newName,
                lables: labelGroups[index].lables
            )
            objectWillChange.send()
        }
    }
    
    func renameTimeEvent(id: String, newName: String) {
        if let index = timeEvents.firstIndex(where: { $0.id == id }) {
            timeEvents[index] = TimeEvent(
                id: id,
                name: newName
            )
            objectWillChange.send()
        }
    }
    
    func updateLabel(id: String, name: String, description: String, hotkey: String? = nil) {
        if let index = labels.firstIndex(where: { $0.id == id }) {
            labels[index] = Label(
                id: id,
                name: name,
                description: description,
                hotkey: hotkey
            )
            objectWillChange.send()
        }
    }
    
    func updateTimeEvent(id: String, newName: String) {
        if let index = timeEvents.firstIndex(where: { $0.id == id }) {
            timeEvents[index] = TimeEvent(
                id: id,
                name: newName
            )
            objectWillChange.send()
        }
    }
    
    func createTagGroup(name: String) -> TagGroup {
        let newGroup = TagGroup(id: UUID().uuidString, name: name, tags: [])
        tagGroups.insert(newGroup, at: 0) // новая группа — вверху списка
        return newGroup
    }
    
    func createTag(name: String, description: String, color: String,
                   defaultTimeBefore: Double, defaultTimeAfter: Double,
                   inGroup groupID: String, hotkey: String? = nil, isInterval: Bool) -> Tag {
        if let hotkey = hotkey, !hotkey.isEmpty {
            if tags.contains(where: { $0.hotkey == hotkey }) {
                return createTagWithValidatedHotkey(name: name, description: description, color: color,
                                                    defaultTimeBefore: defaultTimeBefore,
                                                    defaultTimeAfter: defaultTimeAfter,
                                                    inGroup: groupID, hotkey: nil, isInterval: isInterval)
            }
        }
        
        return createTagWithValidatedHotkey(name: name, description: description, color: color,
                                            defaultTimeBefore: defaultTimeBefore,
                                            defaultTimeAfter: defaultTimeAfter,
                                            inGroup: groupID, hotkey: hotkey, isInterval: isInterval)
    }
    
    func deleteTag(id: String) {
        for index in tagGroups.indices {
            tagGroups[index].tags.removeAll { $0 == id }
        }
        for tagIndex in tags.indices {
            if tags[tagIndex].id == id {
                tags[tagIndex].lablesGroup = []
                tags[tagIndex].labelHotkeys = [:]
            }
        }
        
        tags.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    func deleteTagGroup(id: String) {
        if let group = tagGroups.first(where: { $0.id == id }) {
            let tagsToRemove = group.tags.filter { tagId in
                !tagGroups.contains { otherGroup in
                    otherGroup.id != id && otherGroup.tags.contains(tagId)
                }
            }
            for tagId in tagsToRemove {
                deleteTag(id: tagId)
            }
        }
        
        tagGroups.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    func deleteLabel(id: String) {
        for index in labelGroups.indices {
            labelGroups[index].lables.removeAll { $0 == id }
        }
        for tagIndex in tags.indices {
            tags[tagIndex].labelHotkeys?.removeValue(forKey: id)
        }
        labels.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    func deleteTimeEvent(id: String) {
        timeEvents.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    func deleteLabelGroup(id: String) {
        if let group = labelGroups.first(where: { $0.id == id }) {
            let labelsToRemove = group.lables.filter { labelId in
                !labelGroups.contains { otherGroup in
                    otherGroup.id != id && otherGroup.lables.contains(labelId)
                }
            }
            for labelId in labelsToRemove {
                deleteLabel(id: labelId)
            }
            for tagIndex in tags.indices {
                tags[tagIndex].lablesGroup.removeAll { $0 == id }
            }
        }
        labelGroups.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    private func createTagWithValidatedHotkey(name: String, description: String, color: String,
                                              defaultTimeBefore: Double, defaultTimeAfter: Double,
                                              inGroup groupID: String, hotkey: String?, isInterval: Bool?) -> Tag {
        let id = UUID().uuidString
        let newTag = Tag(
            id: id,
            primaryID: id,
            name: name,
            description: description,
            color: color,
            defaultTimeBefore: defaultTimeBefore,
            defaultTimeAfter: defaultTimeAfter,
            collection: collectionName,
            lablesGroup: [],
            hotkey: hotkey,
            labelHotkeys: [:],
            isInterval: isInterval
        )
        
        tags.append(newTag)
        if let index = tagGroups.firstIndex(where: { $0.id == groupID }) {
            var updatedGroup = tagGroups[index]
            var updatedTags = updatedGroup.tags
            updatedTags.append(newTag.id)
            tagGroups[index] = TagGroup(
                id: updatedGroup.id,
                name: updatedGroup.name,
                tags: updatedTags
            )
        }

        if isKeyBindingsMode, let index = tags.firstIndex(where: { $0.id == id }) {
            tags[index].lablesGroup = allLabelGroupIDs
        }
        
        return newTag
    }

    /// В режиме связок клавиш каждый тег связан со всеми группами лейблов.
    func syncKeyBindingsLabelGroupLinks() {
        guard isKeyBindingsMode else { return }
        let allIDs = allLabelGroupIDs
        var changed = false
        for index in tags.indices {
            if Set(tags[index].lablesGroup) != Set(allIDs) {
                tags[index].lablesGroup = allIDs
                changed = true
            }
        }
        if changed {
            objectWillChange.send()
        }
    }

    private func attachLabelGroupToAllTags(_ groupID: String) {
        guard isKeyBindingsMode else { return }
        for index in tags.indices where !tags[index].lablesGroup.contains(groupID) {
            tags[index].lablesGroup.append(groupID)
        }
    }
    
    func createLabelGroup(name: String) -> LabelGroupData {
        let newGroup = LabelGroupData(id: UUID().uuidString, name: name, lables: [])
        labelGroups.insert(newGroup, at: 0) // новая группа — вверху списка
        attachLabelGroupToAllTags(newGroup.id)
        if isKeyBindingsMode {
            objectWillChange.send()
        }
        return newGroup
    }
    
    func createLabel(name: String, description: String, inGroup groupID: String) -> Label {
        let newLabel = Label(
            id: UUID().uuidString,
            name: name,
            description: description
        )
        
        labels.append(newLabel)
        if let index = labelGroups.firstIndex(where: { $0.id == groupID }) {
            var updatedGroup = labelGroups[index]
            var updatedLabels = updatedGroup.lables
            updatedLabels.append(newLabel.id)
            labelGroups[index] = LabelGroupData(
                id: updatedGroup.id,
                name: updatedGroup.name,
                lables: updatedLabels
            )
        }
        
        return newLabel
    }
    func updateTagLabelGroups(tagID: String, labelGroupIDs: [String]) {
        if let index = tags.firstIndex(where: { $0.id == tagID }) {
            tags[index] = Tag(
                id: tags[index].id,
                primaryID: tags[index].primaryID,
                name: tags[index].name,
                description: tags[index].description,
                color: tags[index].color,
                defaultTimeBefore: tags[index].defaultTimeBefore,
                defaultTimeAfter: tags[index].defaultTimeAfter,
                collection: tags[index].collection,
                lablesGroup: labelGroupIDs,
                hotkey: tags[index].hotkey,
                labelHotkeys: tags[index].labelHotkeys
            )
        }
    }
    
    func addTagToGroup(tagID: String, groupID: String) {
        if let index = tagGroups.firstIndex(where: { $0.id == groupID }) {
            var updatedGroup = tagGroups[index]
            if !updatedGroup.tags.contains(tagID) {
                var updatedTags = updatedGroup.tags
                updatedTags.append(tagID)
                tagGroups[index] = TagGroup(
                    id: updatedGroup.id,
                    name: updatedGroup.name,
                    tags: updatedTags
                )
            }
        }
    }
    
    func removeTagFromGroup(tagID: String, groupID: String) {
        if let index = tagGroups.firstIndex(where: { $0.id == groupID }) {
            var updatedGroup = tagGroups[index]
            var updatedTags = updatedGroup.tags
            updatedTags.removeAll(where: { $0 == tagID })
            tagGroups[index] = TagGroup(
                id: updatedGroup.id,
                name: updatedGroup.name,
                tags: updatedTags
            )
        }
    }
    
    func saveCollectionToFiles() -> Bool {
        collectionName = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        syncKeyBindingsLabelGroupLinks()
                
        if collectionName == originalName || collectionName.isEmpty {
            collectionName = originalName.isEmpty ? collectionID : originalName
        } else {
            collectionName = ensureUniqueCollectionName(collectionName, collectionID: collectionID)
        }
        
        let collection = CollectionData(
            id: collectionID,
            tagGroups: tagGroups,
            tags: tags,
            labelGroups: labelGroups,
            labels: labels,
            timeEvents: timeEvents,
            playField: playField,
            playFields: playFields.isEmpty ? nil : playFields,
            clocks: clocks.isEmpty ? nil : clocks
        )

        InMemoryStorageManager.shared.saveCollection(collection)
        
        CollectionsBookmarksManager.shared.saveCollection(
            id: collectionID,
            name: collectionName,
            tagLibraryDisplayMode: tagLibraryDisplayMode
        )

        // Импортированная коллекция со связками клавиш: сохраняем её раскладку/связки под новым id.
        if let layout = pendingImportedLayout {
            TagFreeLayoutStorage.saveLayout(layout, collectionId: collectionID)
            pendingImportedLayout = nil
        }

        originalName = collectionName
        if !isEditingExisting {
            isEditingExisting = true
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(
                name: .collectionDataChanged,
                object: nil,
                userInfo: [Notification.Key.collectionName: collectionName]
            )
        }
        
        for tag in changedTags {
            NotificationCenter.default.post(
                name: .tagUpdated,
                object: nil,
                userInfo: ["tagId": tag.id, "newName": tag.newName]
            )
        }
        changedTags.removeAll()
        
        return true
    }
    
    func ensureUniqueCollectionName(_ baseName: String, collectionID: String) -> String {
        let existingNames = CollectionsBookmarksManager.shared
            .loadCollections()
            .filter { $0.id != collectionID }
            .map(\.name)
        if (isEditingExisting && baseName == originalName) || !existingNames.contains(baseName) {
            return baseName
        }
        var counter = 1
        var newName = "\(baseName) (\(counter))"
        
        while existingNames.contains(newName) {
            counter += 1
            newName = "\(baseName) (\(counter))"
        }
        
        return newName
    }
    
    @discardableResult
    func loadCollectionFromBookmarks(named collectionName: String) -> Bool {
        let allCollections = CollectionsBookmarksManager.shared.loadCollections()
        
        guard let collectionInfo = allCollections.first(where: { $0.name == collectionName }) else {
            print("❌ CustomCollectionManager: Collection '\(collectionName)' not found")
            return false
        }
        
        guard let collection = InMemoryStorageManager.shared.loadCollection(id: collectionInfo.id) else {
            print("❌ CustomCollectionManager: Failed to load collection '\(collectionName)'")
            return false
        }
        
        if Thread.isMainThread {
            self.collectionID = collection.id
            self.collectionName = collectionName
            self.tagLibraryDisplayMode = collectionInfo.displayMode
            self.tagGroups = collection.tagGroups
            self.tags = collection.tags
            self.labelGroups = collection.labelGroups
            self.labels = collection.labels
            self.timeEvents = collection.timeEvents
            self.playFields = collection.playFields ?? collection.playField.map { [$0] } ?? []
            self.clocks = collection.clocks ?? []
        } else {
            DispatchQueue.main.sync {
                self.collectionID = collection.id
                self.collectionName = collectionName
                self.tagLibraryDisplayMode = collectionInfo.displayMode
                self.tagGroups = collection.tagGroups
                self.tags = collection.tags
                self.labelGroups = collection.labelGroups
                self.labels = collection.labels
                self.timeEvents = collection.timeEvents
                self.playFields = collection.playFields ?? collection.playField.map { [$0] } ?? []
                self.clocks = collection.clocks ?? []
            }
        }
        
        syncKeyBindingsLabelGroupLinks()
        print("✅ CustomCollectionManager: Successfully loaded collection '\(collectionName)'")
        return true
    }
    
    private func loadAllCollections() {
        _ = CollectionsBookmarksManager.shared.loadCollections()
    }

    /// Применяет шаблон (стандартная коллекция по имени или пользовательская по id) с регенерацией id.
    func applyTemplate(_ template: CollectionTemplate?) {
        guard let template else { return }
        switch template {
        case .standard(let name):
            guard let std = TagLibraryManager.shared.standardCollections.first(where: { $0.name == name }) else { return }
            startFromTemplate(
                name: std.name,
                tags: std.tags,
                tagGroups: std.tagGroups,
                labelGroups: std.labelGroups,
                labels: std.labels,
                timeEvents: std.timeEvents
            )
        case .user(let id, let name):
            guard let data = InMemoryStorageManager.shared.loadCollection(id: id) else { return }
            startFromTemplate(
                name: name,
                tags: data.tags,
                tagGroups: data.tagGroups,
                labelGroups: data.labelGroups,
                labels: data.labels,
                timeEvents: data.timeEvents,
                playFields: data.playFields ?? (data.playField.map { [$0] } ?? []),
                clocks: data.clocks ?? []
            )
        }
    }

    /// Заполняет ТЕКУЩУЮ (новую) коллекцию копией переданной, регенерируя ВСЕ id (теги, группы, лейблы,
    /// группы лейблов, события, карты), чтобы не было конфликтов с исходной коллекцией. Ссылки сохраняются.
    func startFromTemplate(
        name: String,
        tags srcTags: [Tag],
        tagGroups srcTagGroups: [TagGroup],
        labelGroups srcLabelGroups: [LabelGroupData],
        labels srcLabels: [Label],
        timeEvents srcTimeEvents: [TimeEvent],
        playFields srcPlayFields: [PlayField] = [],
        clocks srcClocks: [ClockEntity] = []
    ) {
        let copySuffix = NSLocalizedString("CollectionsCopySuffix", comment: "")
        let newName = copySuffix.isEmpty ? name : "\(name) \(copySuffix)"

        // Перевязку id держим в одном месте — иначе правила разъезжаются между шаблоном,
        // импортом и дублированием. У шаблона своей раскладки нет, поэтому layout: nil.
        let fresh = CollectionIdRegenerator.regenerate(
            tags: srcTags,
            tagGroups: srcTagGroups,
            labelGroups: srcLabelGroups,
            labels: srcLabels,
            timeEvents: srcTimeEvents,
            playFields: srcPlayFields,
            clocks: srcClocks,
            layout: nil,
            collectionName: newName
        )

        collectionID = UUID().uuidString
        isEditingExisting = false
        originalName = ""
        collectionName = newName
        labels = fresh.labels
        labelGroups = fresh.labelGroups
        tags = fresh.tags
        tagGroups = fresh.tagGroups
        timeEvents = fresh.timeEvents
        playFields = fresh.playFields
        clocks = fresh.clocks
        objectWillChange.send()
    }
    
    func updateTagMapEnabled(id: String, mapEnabled: Bool) -> Bool {
        if let index = tags.firstIndex(where: { $0.id == id }) {
            let updatedTag = Tag(
                id: tags[index].id,
                primaryID: tags[index].primaryID,
                name: tags[index].name,
                description: tags[index].description,
                color: tags[index].color,
                defaultTimeBefore: tags[index].defaultTimeBefore,
                defaultTimeAfter: tags[index].defaultTimeAfter,
                collection: tags[index].collection,
                lablesGroup: tags[index].lablesGroup,
                hotkey: tags[index].hotkey,
                labelHotkeys: tags[index].labelHotkeys,
                mapEnabled: mapEnabled,
                isInterval: tags[index].isInterval,
                mapFieldId: mapEnabled ? tags[index].mapFieldId : nil,
                mapFieldIds: mapEnabled ? tags[index].mapFieldIds : nil
            )

            tags[index] = updatedTag
            objectWillChange.send()
            return true
        }
        return false
    }

    /// Назначает тегу конкретную карту (PlayField) для разметки (одиночный выбор, legacy).
    @discardableResult
    func updateTagMapField(id: String, mapFieldId: String?) -> Bool {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return false }
        tags[index].mapFieldId = mapFieldId
        objectWillChange.send()
        return true
    }

    /// Назначает тегу «Primary Counter» — счётчик, чья запись всегда выводится на видео для момента
    /// этого тега (пересмотр/экспорт), даже без флага «Показывать на видео». nil — снять.
    @discardableResult
    func updateTagPrimaryClock(id: String, clockId: String?) -> Bool {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return false }
        tags[index].primaryClockId = (clockId?.isEmpty == true) ? nil : clockId
        objectWillChange.send()
        return true
    }

    /// Назначает тегу набор карт (PlayField) для разметки. При разметке точку нужно
    /// поставить на каждой карте — на каждую создаётся отдельный штамп.
    @discardableResult
    func updateTagMapFields(id: String, mapFieldIds: [String]) -> Bool {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return false }
        tags[index].mapFieldIds = mapFieldIds.isEmpty ? nil : mapFieldIds
        // Держим legacy-поле согласованным: первая карта из набора.
        tags[index].mapFieldId = mapFieldIds.first
        objectWillChange.send()
        return true
    }

    /// Добавляет/убирает карту из набора карт тега (multi-select).
    @discardableResult
    func toggleTagMapField(id: String, mapFieldId: String) -> Bool {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return false }
        var ids = tags[index].resolvedMapFieldIds
        if let pos = ids.firstIndex(of: mapFieldId) {
            ids.remove(at: pos)
        } else {
            ids.append(mapFieldId)
        }
        return updateTagMapFields(id: id, mapFieldIds: ids)
    }
    
    func savePlayFieldForCollection() -> Bool {
        guard let playField = playField else { return true }
        
        do {
            let fileManager = FileManager.default
            let playFieldsFolder = URL.appDocumentsDirectory
                .appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
                .fixedFile()
            
            if !fileManager.fileExists(atPath: playFieldsFolder.path) {
                try fileManager.createDirectory(at: playFieldsFolder, withIntermediateDirectories: true)
            }
            
            let playFieldDataPath = playFieldsFolder.appendingPathComponent("\(collectionName).json")
            
            let imagePathToSave = playField.imagePath.isEmpty ? "\(collectionName).png" : playField.imagePath
            let updatedField = PlayField(
                id: playField.id,
                name: playField.name,
                imagePath: imagePathToSave,
                width: playField.width,
                height: playField.height
            )
            
            let data = try JSONEncoder().encode(updatedField)
            try data.write(to: playFieldDataPath)
            
            return true
        } catch {
            return false
        }
    }

    func loadPlayFieldForCollection() {
        let fileManager = FileManager.default
        let playFieldsFolder = URL.appDocumentsDirectory
            .appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
            .fixedFile()
        
        let newPlayFieldDataPath = playFieldsFolder.appendingPathComponent("\(collectionName).json")
        
        if fileManager.fileExists(atPath: newPlayFieldDataPath.path),
           let data = try? Data(contentsOf: newPlayFieldDataPath) {
            if var field = try? JSONDecoder().decode(PlayField.self, from: data) {
                if field.imagePath.isEmpty {
                    field.imagePath = "\(collectionName).png"
                }
                let imageURL = playFieldsFolder.appendingPathComponent(field.imagePath)
                if fileManager.fileExists(atPath: imageURL.path), let bookmark = imageURL.makeBookmark() {
                    playField = PlayField(
                        id: field.id,
                        name: field.name,
                        imagePath: field.imagePath,
                        width: field.width,
                        height: field.height,
                        imageBookmark: bookmark
                    )
                } else {
                    playField = field
                }
                return
            }
        }
        
        let oldPlayFieldDataPath = playFieldsFolder
            .appendingPathComponent("\(collectionName)/field.json")
        
        if fileManager.fileExists(atPath: oldPlayFieldDataPath.path),
           let data = try? Data(contentsOf: oldPlayFieldDataPath) {
            if var field = try? JSONDecoder().decode(PlayField.self, from: data) {
                field.imagePath = "\(collectionName).png"
                playField = field
                
                try? savePlayFieldForCollection()
                
                let oldDirectory = playFieldsFolder.appendingPathComponent(collectionName)
                let contents = try? fileManager.contentsOfDirectory(atPath: oldDirectory.path)
                if contents?.isEmpty ?? false {
                    try? fileManager.removeItem(at: oldDirectory)
                }
            }
        }
    }
    
    func setFieldImage(from url: URL) -> Bool {
        do {
            let fileManager = FileManager.default
            let playFieldsFolder = URL.appDocumentsDirectory
                .appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
                .fixedFile()
            
            if !fileManager.fileExists(atPath: playFieldsFolder.path) {
                try fileManager.createDirectory(at: playFieldsFolder, withIntermediateDirectories: true)
            }
            
            let imageName = "\(collectionName).png"
            let destinationURL = playFieldsFolder.appendingPathComponent(imageName)
            
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            try fileManager.copyItem(at: url, to: destinationURL)
            
            guard let imageBookmark = destinationURL.makeBookmark() else {
                print("❌ Error setting field image: failed to create bookmark")
                return false
            }
            
            if let existingField = playField {
                playField = PlayField(
                    id: existingField.id,
                    name: existingField.name,
                    imagePath: imageName,
                    width: existingField.width,
                    height: existingField.height,
                    imageBookmark: imageBookmark
                )
            } else {
                playField = PlayField(
                    id: UUID().uuidString,
                    name: "Field",
                    imagePath: imageName,
                    width: 100.0,
                    height: 60.0,
                    imageBookmark: imageBookmark
                )
            }
            _ = savePlayFieldForCollection()
            objectWillChange.send()
            _ = saveCollectionToFiles()
            return true
        } catch {
            print("❌ Error setting field image: \(error)")
            return false
        }
    }

    /// Добавляет ещё одну карту в коллекцию (несколько карт). Возвращает id новой карты.
    @discardableResult
    func addFieldImage(from url: URL, name: String? = nil) -> String? {
        do {
            let fileManager = FileManager.default
            let playFieldsFolder = URL.appDocumentsDirectory
                .appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
                .fixedFile()
            if !fileManager.fileExists(atPath: playFieldsFolder.path) {
                try fileManager.createDirectory(at: playFieldsFolder, withIntermediateDirectories: true)
            }

            let mapId = UUID().uuidString
            // Первая карта коллекции хранится под легаси-именем "{collection}.png" ради совместимости.
            let imageName = playFields.isEmpty ? "\(collectionName).png" : "\(collectionName)__\(mapId).png"
            let destinationURL = playFieldsFolder.appendingPathComponent(imageName)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: url, to: destinationURL)

            guard let imageBookmark = destinationURL.makeBookmark() else { return nil }

            let field = PlayField(
                id: mapId,
                name: name?.isEmpty == false ? name! : String.Titles.fieldMapName.format(playFields.count + 1),
                imagePath: imageName,
                width: 100.0,
                height: 60.0,
                imageBookmark: imageBookmark
            )
            playFields.append(field)
            _ = savePlayFieldForCollection()
            objectWillChange.send()
            _ = saveCollectionToFiles()
            return mapId
        } catch {
            print("❌ Error adding field image: \(error)")
            return nil
        }
    }

    /// Удаляет карту по id: файл изображения, запись и привязки тегов к ней.
    func removeFieldImage(id: String) {
        guard let idx = playFields.firstIndex(where: { $0.id == id }) else { return }
        let field = playFields[idx]

        let fileManager = FileManager.default
        let playFieldsFolder = URL.appDocumentsDirectory
            .appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
            .fixedFile()
        let imagePath = playFieldsFolder.appendingPathComponent(field.imagePath)
        if fileManager.fileExists(atPath: imagePath.path) {
            try? fileManager.removeItem(at: imagePath)
        }

        playFields.remove(at: idx)

        // Снимаем привязку к удалённой карте у тегов (и из одиночного поля, и из набора).
        for i in tags.indices {
            var touched = false
            if tags[i].mapFieldId == id {
                tags[i].mapFieldId = nil
                touched = true
            }
            if let ids = tags[i].mapFieldIds, ids.contains(id) {
                let filtered = ids.filter { $0 != id }
                tags[i].mapFieldIds = filtered.isEmpty ? nil : filtered
                touched = true
            }
            if touched {
                // Держим legacy-поле согласованным с набором.
                if tags[i].mapFieldId == nil { tags[i].mapFieldId = tags[i].mapFieldIds?.first }
                if playFields.isEmpty { tags[i].mapEnabled = false }
            }
        }

        objectWillChange.send()
        _ = savePlayFieldForCollection()
        _ = saveCollectionToFiles()
    }

    func deleteFieldImage() {
        guard let field = playField else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let fileManager = FileManager.default
            let playFieldsFolder = URL.appDocumentsDirectory
                .appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
                .fixedFile()
            
            let imagePath = playFieldsFolder.appendingPathComponent(field.imagePath)
            
            if fileManager.fileExists(atPath: imagePath.path) {
                try? fileManager.removeItem(at: imagePath)
            }
            
            DispatchQueue.main.async {
                for i in 0..<self.tags.count {
                    if self.tags[i].mapEnabled == true {
                        self.tags[i] = Tag(
                            id: self.tags[i].id,
                            primaryID: self.tags[i].primaryID,
                            name: self.tags[i].name,
                            description: self.tags[i].description,
                            color: self.tags[i].color,
                            defaultTimeBefore: self.tags[i].defaultTimeBefore,
                            defaultTimeAfter: self.tags[i].defaultTimeAfter,
                            collection: self.tags[i].collection,
                            lablesGroup: self.tags[i].lablesGroup,
                            hotkey: self.tags[i].hotkey,
                            labelHotkeys: self.tags[i].labelHotkeys,
                            mapEnabled: false
                        )
                    }
                }
                
                self.playField = nil
                self.objectWillChange.send()
                _ = self.saveCollectionToFiles()
            }
        }
    }
    
    func updateFieldDimensions(width: Double, height: Double) {
        guard var updatedField = playField else { return }
        updatedField.width = width
        updatedField.height = height
        playField = updatedField
    }

    /// Обновляет размеры конкретной карты (по id) — при нескольких картах.
    func updateFieldDimensions(id: String, width: Double, height: Double) {
        guard let idx = playFields.firstIndex(where: { $0.id == id }) else { return }
        playFields[idx].width = width
        playFields[idx].height = height
        objectWillChange.send()
        _ = saveCollectionToFiles()
    }

    /// Переименовывает карту (по id).
    func renameFieldMap(id: String, name: String) {
        guard let idx = playFields.firstIndex(where: { $0.id == id }) else { return }
        playFields[idx].name = name
        objectWillChange.send()
        _ = saveCollectionToFiles()
    }
    
    
    func createTimeEvent(name: String) -> TimeEvent {
        let newEvent = TimeEvent(
            id: UUID().uuidString,
            name: name
        )

        timeEvents.insert(newEvent, at: 0) // новое событие — вверху списка
        return newEvent
    }
    
    func removeTimeEvent(id: String) {
        timeEvents.removeAll { $0.id == id }
    }

    // MARK: - Секундомеры / таймеры

    @discardableResult
    func createClock(name: String, mode: ClockMode) -> ClockEntity {
        let clock = ClockEntity(name: name, mode: mode)
        clocks.insert(clock, at: 0)
        return clock
    }

    func updateClock(_ clock: ClockEntity) {
        if let idx = clocks.firstIndex(where: { $0.id == clock.id }) {
            clocks[idx] = clock
        }
    }

    func removeClock(id: String) {
        clocks.removeAll { $0.id == id }
    }

    @discardableResult
    func duplicateClock(id: String, nameSuffix: String) -> ClockEntity? {
        guard let src = clocks.first(where: { $0.id == id }) else { return nil }
        var copy = src
        copy.id = UUID().uuidString
        copy.name = src.name + nameSuffix
        clocks.insert(copy, at: 0)
        return copy
    }
    
    func isHotkeyAssigned(_ hotkey: String?) -> Bool {
        guard let normalized = normalizedHotkey(hotkey) else { return false }
        return tags.contains { normalizedHotkey($0.hotkey) == normalized }
    }
    
    func isHotkeyAssigned(_ hotkey: String?, excludingTagID: String) -> Bool {
        guard let normalized = normalizedHotkey(hotkey) else { return false }
        return tags.contains { normalizedHotkey($0.hotkey) == normalized && $0.id != excludingTagID }
    }
    
    func hasLabelHotkeyConflict(_ hotkey: String?, labelID: String, excludingTagID: String) -> Bool {
        guard let normalized = normalizedHotkey(hotkey) else { return false }
        for tag in tags where tag.id != excludingTagID {
            guard let labelHotkeys = tag.labelHotkeys else { continue }
            for (existingLabelID, existingHotkey) in labelHotkeys {
                if existingLabelID == labelID {
                    continue
                }
                if normalizedHotkey(existingHotkey) == normalized {
                    return true
                }
            }
        }
        return false
    }
    
    func hasAnyLabelHotkeyConflicts(labelHotkeys: [String: String], excludingTagID: String) -> Bool {
        for (labelID, hotkey) in labelHotkeys {
            if hasLabelHotkeyConflict(hotkey, labelID: labelID, excludingTagID: excludingTagID) {
                return true
            }
        }
        return false
    }
    
    func updateTag(id: String, primaryID: String?, name: String, description: String, color: String,
                   defaultTimeBefore: Double, defaultTimeAfter: Double,
                   labelGroupIDs: [String], hotkey: String?, labelHotkeys: [String: String], isInterval: Bool, mapEnabled: Bool) -> Bool {
        if let hotkey = hotkey, !hotkey.isEmpty,
           isHotkeyAssigned(hotkey, excludingTagID: id) {
            return false
        }
        
        if hasAnyLabelHotkeyConflicts(labelHotkeys: labelHotkeys, excludingTagID: id) {
            return false
        }
        
        if let index = tags.firstIndex(where: { $0.id == id }) {
            let originalTag = tags[index]
            let resolvedLabelGroupIDs = isKeyBindingsMode ? allLabelGroupIDs : labelGroupIDs
            
            if !changedTags.contains(where: { $0.id == id}) {
                changedTags.append((id, name))
            }
            
            tags[index] = Tag(
                id: id,
                primaryID: primaryID,
                name: name,
                description: description,
                color: color,
                defaultTimeBefore: defaultTimeBefore,
                defaultTimeAfter: defaultTimeAfter,
                collection: originalTag.collection,
                lablesGroup: resolvedLabelGroupIDs,
                hotkey: hotkey,
                labelHotkeys: labelHotkeys,
                mapEnabled: mapEnabled,
                isInterval: isInterval,
                // Не теряем при правке остальных настроек — их задают отдельные методы.
                mapFieldId: originalTag.mapFieldId,
                mapFieldIds: originalTag.mapFieldIds,
                primaryClockId: originalTag.primaryClockId
            )
            
            for i in 0..<tagGroups.count {
                if let tagIndex = tagGroups[i].tags.firstIndex(where: { $0 == id }) {
                    var updatedTags = tagGroups[i].tags
                    updatedTags[tagIndex] = id // maybe not needed (remove)
                    tagGroups[i] = TagGroup(
                        id: tagGroups[i].id,
                        name: tagGroups[i].name,
                        tags: updatedTags
                    )
                }
            }
            
            objectWillChange.send()
            return true
        }
        return false
    }
    
    private func normalizedHotkey(_ hotkey: String?) -> String? {
        guard let hotkey = hotkey?.trimmingCharacters(in: .whitespacesAndNewlines), !hotkey.isEmpty else {
            return nil
        }
        return hotkey.lowercased()
    }
    
    func createTestCollection() {
        collectionName = ^String.Titles.testCollection
        
        let tagGroup = TagGroup(
            id: UUID().uuidString,
            name: ^String.Titles.testTags,
            tags: []
        )
        tagGroups.append(tagGroup)
        
        let tag = Tag(
            id: UUID().uuidString,
            primaryID: nil,
            name: ^String.Titles.testTag,
            description: ^String.Titles.testTagDescription,
            color: "FF5733",
            defaultTimeBefore: 2.0,
            defaultTimeAfter: 3.0,
            collection: collectionName,
            lablesGroup: [],
            hotkey: "T",
            labelHotkeys: nil,
            mapEnabled: true,
            isInterval: false
        )
        tags.append(tag)
        
        if let index = tagGroups.firstIndex(where: { $0.id == tagGroup.id }) {
            tagGroups[index].tags.append(tag.id)
        }
        
        let labelGroup = LabelGroupData(
            id: UUID().uuidString,
            name: ^String.Titles.testLabels,
            lables: []
        )
        labelGroups.append(labelGroup)
        
        let label = Label(
            id: UUID().uuidString,
            name: ^String.Titles.testLabel,
            description: ^String.Titles.testLabelDescription
        )
        labels.append(label)
        if let index = labelGroups.firstIndex(where: { $0.id == labelGroup.id }) {
            labelGroups[index].lables.append(label.id)
        }
        
        let timeEvent = TimeEvent(
            id: UUID().uuidString,
            name: ^String.Titles.testEvent
        )
        timeEvents.append(timeEvent)
    }
    
    func exportCollection() -> URL? {
        writeExport(SportcutCollectionExport(collectionManager: self), suggestedName: collectionName)
    }

    /// Частичный экспорт по выбранным на холсте элементам ("kind:elementId").
    func exportSelectedCanvasItems(_ selectedItemIds: Set<String>, layout: TagFreeLayout?) -> URL? {
        var tagIds = Set<String>(), labelIds = Set<String>(), eventIds = Set<String>(), mapIds = Set<String>()
        for key in selectedItemIds {
            let parts = key.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let id = String(parts[1])
            switch String(parts[0]) {
            case CanvasButtonKind.tag.rawValue: tagIds.insert(id)
            case CanvasButtonKind.label.rawValue: labelIds.insert(id)
            case CanvasButtonKind.timeEvent.rawValue: eventIds.insert(id)
            case CanvasButtonKind.map.rawValue: mapIds.insert(id)
            default: break
            }
        }
        return exportFiltered(tagIds: tagIds, labelIds: labelIds, eventIds: eventIds, mapIds: mapIds, layout: layout)
    }

    /// Экспорт части коллекции: только выбранные сущности, их группы (с отфильтрованными членами),
    /// связки МЕЖДУ выбранными и раскладка (позиции) выбранных.
    func exportFiltered(tagIds: Set<String>, labelIds: Set<String>, eventIds: Set<String>,
                        mapIds: Set<String>, layout: TagFreeLayout?) -> URL? {
        let fTags = tags.filter { tagIds.contains($0.id) }
        let fTagGroups = tagGroups.compactMap { g -> TagGroup? in
            let m = g.tags.filter { tagIds.contains($0) }
            return m.isEmpty ? nil : TagGroup(id: g.id, name: g.name, tags: m)
        }
        let fLabels = labels.filter { labelIds.contains($0.id) }
        let fLabelGroups = labelGroups.compactMap { g -> LabelGroupData? in
            let m = g.lables.filter { labelIds.contains($0) }
            return m.isEmpty ? nil : LabelGroupData(id: g.id, name: g.name, lables: m)
        }
        let fEvents = timeEvents.filter { eventIds.contains($0.id) }
        let fPlayFields = playFields.filter { mapIds.contains($0.id) }

        var fLayout: TagFreeLayout? = nil
        if tagLibraryDisplayMode == .free, let layout = layout {
            let keys = Set(
                tagIds.map { "\(CanvasButtonKind.tag.rawValue):\($0)" }
                + labelIds.map { "\(CanvasButtonKind.label.rawValue):\($0)" }
                + eventIds.map { "\(CanvasButtonKind.timeEvent.rawValue):\($0)" }
                + mapIds.map { "\(CanvasButtonKind.map.rawValue):\($0)" }
            )
            let items = layout.items.filter { keys.contains($0.id) }
            // Связку сохраняем только если ОБА её конца попали в экспорт.
            let bindings = layout.bindings.filter { keys.contains($0.sourceButtonKey) && keys.contains($0.targetButtonKey) }
            fLayout = TagFreeLayout(canvasWidth: layout.canvasWidth, canvasHeight: layout.canvasHeight, items: items, bindings: bindings)
        }

        let export = SportcutCollectionExport(
            collectionName: collectionName,
            tagGroups: fTagGroups, tags: fTags,
            labelGroups: fLabelGroups, labels: fLabels,
            timeEvents: fEvents, playFields: fPlayFields,
            displayMode: tagLibraryDisplayMode.rawValue,
            freeLayout: fLayout
        )
        return writeExport(export, suggestedName: "\(collectionName)-part")
    }

    private func writeExport(_ export: SportcutCollectionExport, suggestedName: String) -> URL? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(export)

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "\(suggestedName).sportcutCollection"
            savePanel.title = ^String.Titles.exportCollectionTitle
            savePanel.message = ^String.Titles.selectCollectionSaveLocation

            if savePanel.runModal() == .OK, let url = savePanel.url {
                try jsonData.write(to: url)
                return url
            }
        } catch {
            print(error)
        }
        return nil
    }
}
