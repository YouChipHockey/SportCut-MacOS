//
//  TagLibraryManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct StandardCollection {
    let name: String
    let tags: [Tag]
    let tagGroups: [TagGroup]
    let labelGroups: [LabelGroupData]
    let labels: [Label]
    let timeEvents: [TimeEvent]
}

class TagLibraryManager: ObservableObject {
    static let shared = TagLibraryManager()
    @Published var tags: [Tag] = [] { didSet { tagsByID = Self.indexed(tags, by: \.id) } }
    @Published var tagGroups: [TagGroup] = []
    @Published var labelGroups: [LabelGroupData] = [] {
        didSet { groupByLabelID = Self.groupsByLabelID(labelGroups) }
    }
    @Published var labels: [Label] = [] { didSet { labelsByID = Self.indexed(labels, by: \.id) } }
    @Published var timeEvents: [TimeEvent] = []
    @Published var allTags: [Tag] = [] { didSet { allTagsByID = Self.indexed(allTags, by: \.id) } }
    @Published var allTagGroups: [TagGroup] = []
    @Published var allLabelGroups: [LabelGroupData] = [] {
        didSet { groupByAllLabelID = Self.groupsByLabelID(allLabelGroups) }
    }
    @Published var allLabels: [Label] = [] { didSet { allLabelsByID = Self.indexed(allLabels, by: \.id) } }
    @Published var allTimeEvents: [TimeEvent] = [] {
        didSet { allTimeEventsByID = Self.indexed(allTimeEvents, by: \.id) }
    }
    @Published var selectedTimeEvents: Set<String> = []

    // MARK: - Индексы по id
    //
    // Поиск по id раньше был линейным (`first(where:)`) и вызывался из горячих путей отрисовки:
    // имя и цвет штампа перерезолвятся при каждом рендере, лейблы — на каждый штамп, группа
    // лейбла — на каждое движение мыши по таймлайну. Индексы пересобираются только при смене
    // набора (смена/перезагрузка коллекции), то есть редко. См. TASK-007, 6.2.
    //
    // ВАЖНО: при совпадающих id побеждает ПЕРВЫЙ элемент — ровно как у `first(where:)`, который
    // эти словари заменяют. Дубли id между коллекциями — штатная ситуация (см. комментарий к
    // `findTagById` ниже), поэтому `uniquingKeysWith` обязателен: `uniqueKeysWithValues` уронил
    // бы приложение.

    private var tagsByID: [String: Tag] = [:]
    private var allTagsByID: [String: Tag] = [:]
    private var labelsByID: [String: Label] = [:]
    private var allLabelsByID: [String: Label] = [:]
    private var allTimeEventsByID: [String: TimeEvent] = [:]
    /// id лейбла → его группа. Обратный индекс: раньше группу искали перебором всех групп
    /// с `contains` внутри — O(групп × лейблов) на каждый лейбл.
    private var groupByLabelID: [String: LabelGroupData] = [:]
    private var groupByAllLabelID: [String: LabelGroupData] = [:]

    private static func indexed<T>(_ items: [T], by key: KeyPath<T, String>) -> [String: T] {
        Dictionary(items.map { ($0[keyPath: key], $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func groupsByLabelID(_ groups: [LabelGroupData]) -> [String: LabelGroupData] {
        var result: [String: LabelGroupData] = [:]
        for group in groups {
            for labelID in group.lables where result[labelID] == nil {
                result[labelID] = group
            }
        }
        return result
    }

    private var defaultTags: [Tag] = []
    private var defaultTagGroups: [TagGroup] = []
    private var defaultLabelGroups: [LabelGroupData] = []
    private var defaultLabels: [Label] = []
    private var defaultTimeEvents: [TimeEvent] = []
    
    @Published var currentCollectionType: TagCollection = .standard
    
    @Published var standardCollections: [StandardCollection] = []
    @Published var selectedStandardCollectionName: String? = nil
    
    private init() {
        loadBaseCollections()
        applyDefaultCollection()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTagUpdated),
            name: .tagUpdated,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCollectionDataChanged),
            name: .collectionDataChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppLanguageChanged),
            name: .appLanguageChanged,
            object: nil
        )

        allTags = tags
        allTagGroups = tagGroups
        allLabelGroups = labelGroups
        allLabels = labels
        allTimeEvents = timeEvents
        
        lastCollectionCount = CollectionsBookmarksManager.shared.loadCollections().count
        loadAllUserCollections()
    }
    
    private var isReloadingCollections = false
    /// Во время пересборки пулов пришло ещё одно изменение — нужен повторный прогон.
    private var needsAnotherReload = false
    private var lastCollectionCount = 0
    
    @objc private func handleCollectionDataChanged(_ notification: Notification) {
        let changedCollectionName = notification.userInfo?[Notification.Key.collectionName] as? String
        
        if let name = changedCollectionName {
            invalidateCollectionCache(for: name)
            guard let data = getCollectionData(for: name) else { return }
            let apply: () -> Void = { [weak self] in
                guard let self = self else { return }
                if case .user(name) = self.currentCollectionType {
                    self.tags = data.tags
                    self.tagGroups = data.tagGroups
                    self.labelGroups = data.labelGroups
                    self.labels = data.labels
                    self.timeEvents = data.timeEvents
                    self.selectedTimeEvents.removeAll()
                    self.objectWillChange.send()
                    HotKeyManager.shared.clearHotkeys()
                    HotKeyManager.shared.registerHotkeys(from: data.tags, for: .user(name: name))
                    NotificationCenter.default.post(name: .currentCollectionRefreshed, object: nil)
                }
            }
            if Thread.isMainThread {
                apply()
            } else {
                DispatchQueue.main.async(execute: apply)
            }
            // Глобальный пул обязан пересобраться и в этой ветке: из него читаются теги в режиме
            // связок клавиш. Без этого после правки настроек тега пул оставался со старой версией.
            reloadAllCollectionsIfIdle()
            return
        }

        let currentCollections = CollectionsBookmarksManager.shared.loadCollections()
        let currentCount = currentCollections.count
        if currentCount != lastCollectionCount {
            lastCollectionCount = currentCount
        }
        
        cacheLock.lock()
        loadedCollectionsCache.removeAll()
        diskPrimaryClockIndex = nil
        cacheLock.unlock()
        
        if case .user(let collectionName) = currentCollectionType,
           let data = getCollectionData(for: collectionName) {
            let name = collectionName
            let apply: () -> Void = { [weak self] in
                guard let self = self else { return }
                self.tags = data.tags
                self.tagGroups = data.tagGroups
                self.labelGroups = data.labelGroups
                self.labels = data.labels
                self.timeEvents = data.timeEvents
                self.selectedTimeEvents.removeAll()
                self.objectWillChange.send()
                HotKeyManager.shared.clearHotkeys()
                HotKeyManager.shared.registerHotkeys(from: data.tags, for: .user(name: name))
                NotificationCenter.default.post(name: .currentCollectionRefreshed, object: nil)
            }
            if Thread.isMainThread {
                apply()
            } else {
                DispatchQueue.main.async(execute: apply)
            }
        }
        
        reloadAllCollectionsIfIdle()
    }

    /// Запускает пересборку глобальных пулов. Если пересборка уже идёт — не бросает изменение,
    /// а ставит отметку и повторяет прогон по завершении: иначе сохранение, попавшее в окно
    /// текущей загрузки, молча терялось и пул оставался со старыми данными.
    private func reloadAllCollectionsIfIdle() {
        guard !isReloadingCollections else {
            needsAnotherReload = true
            return
        }
        isReloadingCollections = true

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .collectionsLoadingStarted, object: nil)
        }

        loadAllUserCollections()
    }
        
    private func getAppCollectionLanguage() -> String {
        // Учитываем выбор языка в приложении (см. LanguageManager). При отсутствии выбора
        // возвращается системный язык. Базовые коллекции есть для всех этих языков; если
        // для языка коллекций нет — сработает фолбэк на "en" в loadBaseCollections().
        return LanguageManager.shared.effectiveLanguage.rawValue
    }
    
    private func getCollectionFileURL(for resourceName: String, collectionName: String) -> URL? {
        let fullResourceName = "\(resourceName)(\(collectionName))"
        return Bundle.main.url(forResource: fullResourceName, withExtension: "json")
    }
    
    private func loadBaseCollections() {
        guard let namesUrl = Bundle.main.url(forResource: "names", withExtension: "json") else { return }
        
        guard let languageCollectionsData: LanguageCollectionsData = loadJSON(url: namesUrl) else { return }
        
        let currentLanguage = getAppCollectionLanguage()

        let languageCollection = languageCollectionsData.collections.first(where: { $0.language == currentLanguage })
            ?? languageCollectionsData.collections.first(where: { $0.language == "en" })
        guard let languageCollection else { return }

        loadCollections(languageCollection.resolvedItems)
    }

    private func loadCollections(_ items: [LanguageCollectionItem]) {
        for item in items {
            let folder = item.folder
            let tagsURL = getCollectionFileURL(for: "tags", collectionName: folder)
            let tagsGroupsURL = getCollectionFileURL(for: "tagsGroups", collectionName: folder)
            let labelsGroupsURL = getCollectionFileURL(for: "labelsGroups", collectionName: folder)
            let labelsURL = getCollectionFileURL(for: "labels", collectionName: folder)
            let timeEventsURL = getCollectionFileURL(for: "timeEvents", collectionName: folder)
            
            var tags: [Tag] = []
            var tagGroups: [TagGroup] = []
            var labelGroups: [LabelGroupData] = []
            var labels: [Label] = []
            var timeEvents: [TimeEvent] = []
            
            if let tagsURL = tagsURL {
                if let loadedTags: TagsData = loadJSON(url: tagsURL) {
                    tags = loadedTags.tags
                }
            }
            
            if let tagsGroupsURL = tagsGroupsURL {
                if let loadedTags: TagGroupsData = loadJSON(url: tagsGroupsURL) {
                    tagGroups = loadedTags.tagGroups
                }
            }
            
            if let labelsGroupsURL = labelsGroupsURL {
                if let loadedTags: LabelGroupsData = loadJSON(url: labelsGroupsURL) {
                    labelGroups = loadedTags.labelGroups
                }
            }
            
            if let labelsURL = labelsURL {
                if let loadedTags: LabelsData = loadJSON(url: labelsURL) {
                    labels = loadedTags.labels
                }
            }
            
            if let timeEventsURL = timeEventsURL {
                if let loadedTags: TimeEventsData = loadJSON(url: timeEventsURL) {
                    timeEvents = loadedTags.events
                }
            }
            
            let displayName = item.name
            let collection = StandardCollection(
                name: displayName,
                tags: tags,
                tagGroups: tagGroups,
                labelGroups: labelGroups,
                labels: labels,
                timeEvents: timeEvents
            )
            standardCollections.append(collection)
        }
    }
    
    /// Перезагружает базовые (стандартные) коллекции под текущий язык приложения.
    /// Если сейчас выбрана стандартная коллекция — переключает на аналогичную (тот же
    /// вид спорта по индексу) на новом языке. Пользовательские коллекции не трогаем.
    @objc private func handleAppLanguageChanged() {
        let work: () -> Void = { [weak self] in
            guard let self = self else { return }

            var reapplyIndex: Int? = nil
            if case .standard = self.currentCollectionType,
               let selected = self.selectedStandardCollectionName,
               let idx = self.standardCollections.firstIndex(where: { $0.name == selected }) {
                reapplyIndex = idx
            }

            self.standardCollections.removeAll()
            self.loadBaseCollections()

            if let idx = reapplyIndex, idx < self.standardCollections.count {
                let name = self.standardCollections[idx].name
                self.applyStandardCollection(named: name)
                self.selectedStandardCollectionName = name
                NotificationCenter.default.post(name: .currentCollectionRefreshed, object: nil)
            }

            self.objectWillChange.send()
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func applyStandardCollection(named name: String) {
        guard let collection = standardCollections.first(where: { $0.name == name }) else { return }
        UserDefaults.standard.set(name, forKey: UserDefaults.Keys.lastSelectedCollection)
        tags = collection.tags
        tagGroups = collection.tagGroups
        labelGroups = collection.labelGroups
        labels = collection.labels
        timeEvents = collection.timeEvents
        currentCollectionType = .standard
        selectedStandardCollectionName = name
        selectedTimeEvents.removeAll()
        refreshGlobalPools()
        applyHotkeysFromCurrentCollection()
    }
    
    // MARK: - Поиск по id
    //
    // Правило для ВСЕХ поисков: сначала ВЫБРАННАЯ сейчас коллекция (`tags`/`labels`/`tagGroups`),
    // и только потом глобальный пул (`allTags`/…).
    //
    // Пул склеен из всех коллекций и дедуплицирован по id:
    // `Dictionary(grouping: mergedTags, by: { $0.id }).values.compactMap { $0.first }`.
    // `grouping` сохраняет порядок внутри группы, а `mergedTags` строится по порядку коллекций из
    // `CollectionsBookmarks.json` — значит при совпадающих id побеждает копия из ПЕРВОЙ коллекции.
    // Одинаковые id — штатная ситуация: `duplicateCollection` копирует теги как есть, а импорт
    // сохраняет id из файла (новый генерируется только у самой коллекции), поэтому повторный
    // импорт того же файла даёт полный комплект дублей.
    //
    // Без приоритета текущей коллекции это било по всему, что резолвит тег по id, — в том числе по
    // ОТРИСОВКЕ штампа: имя на таймлайне берётся не из штампа, а перерезолвится через
    // `findTagById`, поэтому переименованный тег показывался старым именем из соседней коллекции.
    // Фолбэк на пул оставлен для «чужих» id (разметка из другого проекта/коллекции).

    func findTagById(_ id: String) -> Tag? {
        tagsByID[id] ?? allTagsByID[id]
    }

    /// Primary Counter тега — счётчик, чья запись всегда выводится на видео для момента этого тега.
    ///
    /// Смотрим ОБА пула и берём первый непустой: снимок выбранной коллекции (`tags`) мог быть снят
    /// до того, как тегу назначили счётчик, и хранить nil, тогда как глобальный пул (`allTags`)
    /// уже пересобран. Обычный `findTagById` в таком случае возвращал устаревший тег и primary
    /// молча пропадал из пересмотра и экспорта.
    func primaryClockId(forTagId id: String) -> String? {
        if let value = tagsByID[id]?.primaryClockId, !value.isEmpty { return value }
        if let value = allTagsByID[id]?.primaryClockId, !value.isEmpty { return value }
        // Последний рубеж — сами файлы коллекций. Пулы в памяти могли быть собраны до того, как
        // тегу назначили счётчик (или пересобраны из устаревшего кэша), а на диске значение уже
        // есть. Путь холодный: срабатывает, только когда оба пула промахнулись, и кэшируется.
        return diskPrimaryClockId(forTagId: id)
    }

    /// tagId → primaryClockId по файлам всех коллекций. Строится один раз и сбрасывается вместе
    /// с кэшем коллекций.
    private var diskPrimaryClockIndex: [String: String]? = nil

    private func diskPrimaryClockId(forTagId id: String) -> String? {
        cacheLock.lock()
        let cached = diskPrimaryClockIndex
        cacheLock.unlock()
        if let cached { return cached[id] }

        var index: [String: String] = [:]
        for info in CollectionsBookmarksManager.shared.loadCollections() {
            guard let collection = InMemoryStorageManager.shared.loadCollection(id: info.id) else { continue }
            for tag in collection.tags {
                if let value = tag.primaryClockId, !value.isEmpty { index[tag.id] = value }
            }
        }
        cacheLock.lock()
        diskPrimaryClockIndex = index
        cacheLock.unlock()
        return index[id]
    }

    func findLabelById(_ id: String) -> Label? {
        labelsByID[id] ?? allLabelsByID[id]
    }

    /// Событие по id. Раньше во всех вызывающих местах писали `allTimeEvents.first(where:)`
    /// вручную — в том числе в отрисовке чипов на каждом штампе.
    func findTimeEventById(_ id: String) -> TimeEvent? {
        allTimeEventsByID[id]
    }

    /// Группа, которой принадлежит лейбл. Приоритет — как у остальных `find*`: сначала выбранная
    /// коллекция, потом общий пул.
    ///
    /// ⚠️ НЕ полная замена инлайн-поискам группы, которые сейчас есть в отрисовке
    /// (`TimelineLineView.menuForTag`, `TimelineMouseTracker`). Они отличаются в двух местах:
    /// ищут только по пулу `allLabelGroups` (без приоритета выбранной коллекции) и имеют второй
    /// фолбэк — по `FullLabelWithGroup.lableGroupId`. Переводить их сюда = менять поведение,
    /// поэтому это отложено в фазу 3.4 и требует отдельного решения (см. TASK-007).
    func findGroupForLabel(_ labelID: String) -> LabelGroupData? {
        groupByLabelID[labelID] ?? groupByAllLabelID[labelID]
    }

    func findTagGroupForTag(_ tagID: String) -> TagGroup? {
        tagGroups.first { $0.tags.contains(tagID) }
            ?? allTagGroups.first { $0.tags.contains(tagID) }
    }

    func findLabelsForTag(_ tag: Tag) -> [Label] {
        // Optimize using Set for O(1) lookup
        let labelGroupIdsSet = Set(tag.lablesGroup)
        // Группы и лейблы тоже сначала из текущей коллекции — иначе у тега-дубля подтянутся
        // лейблы соседней коллекции.
        let ownGroups = labelGroups.filter { labelGroupIdsSet.contains($0.id) }
        let groups = ownGroups.isEmpty
            ? allLabelGroups.filter { labelGroupIdsSet.contains($0.id) }
            : ownGroups
        let relevantLabelIdsSet = Set(groups.flatMap { $0.lables })
        let own = labels.filter { relevantLabelIdsSet.contains($0.id) }
        return own.isEmpty ? allLabels.filter { relevantLabelIdsSet.contains($0.id) } : own
    }
    
    private var loadedCollectionsCache: [String: (tags: [Tag], tagGroups: [TagGroup], labelGroups: [LabelGroupData], labels: [Label], timeEvents: [TimeEvent])] = [:]
    private let collectionLoadingQueue = DispatchQueue(label: "com.youchip.collectionLoading", qos: .userInitiated)
    private let cacheLock = NSLock()
    
    func invalidateCollectionCache(for name: String) {
        cacheLock.lock()
        loadedCollectionsCache.removeValue(forKey: name)
        diskPrimaryClockIndex = nil
        cacheLock.unlock()
    }
    
    private func loadAllUserCollections() {
        collectionLoadingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let userCollections = CollectionsBookmarksManager.shared.loadCollections()
            print("📚 TagLibraryManager: Loading \(userCollections.count) user collections")
            
            var loadedData: [(tags: [Tag], tagGroups: [TagGroup], labelGroups: [LabelGroupData], labels: [Label], timeEvents: [TimeEvent])] = []
            
            for collectionInfo in userCollections {
                print("📚 TagLibraryManager: Loading collection '\(collectionInfo.name)' (id: \(collectionInfo.id))")
                
                guard let collection = InMemoryStorageManager.shared.loadCollection(id: collectionInfo.id) else {
                    print("❌ TagLibraryManager: Failed to load collection '\(collectionInfo.name)'")
                    continue
                }
                
                print("✅ TagLibraryManager: Successfully loaded collection '\(collectionInfo.name)' - tags: \(collection.tags.count), tagGroups: \(collection.tagGroups.count)")
                
                let collectionData = (
                    tags: collection.tags,
                    tagGroups: collection.tagGroups,
                    labelGroups: collection.labelGroups,
                    labels: collection.labels,
                    timeEvents: collection.timeEvents
                )
                
                self.cacheLock.lock()
                self.loadedCollectionsCache[collectionInfo.name] = collectionData
                self.cacheLock.unlock()
                
                loadedData.append(collectionData)
            }
            
            for collection in self.standardCollections {
                loadedData.append((
                    tags: collection.tags,
                    tagGroups: collection.tagGroups,
                    labelGroups: collection.labelGroups,
                    labels: collection.labels,
                    timeEvents: collection.timeEvents
                ))
            }
            
            var mergedTags: [Tag] = []
            var mergedTagGroups: [TagGroup] = []
            var mergedLabelGroups: [LabelGroupData] = []
            var mergedLabels: [Label] = []
            var mergedTimeEvents: [TimeEvent] = []
            
            for data in loadedData {
                mergedTags.append(contentsOf: data.tags)
                mergedTagGroups.append(contentsOf: data.tagGroups)
                mergedLabelGroups.append(contentsOf: data.labelGroups)
                mergedLabels.append(contentsOf: data.labels)
                mergedTimeEvents.append(contentsOf: data.timeEvents)
            }
            
            let finalTags = Array(Dictionary(grouping: mergedTags, by: { $0.id }).values.compactMap { $0.first })
            let finalTagGroups = Array(Dictionary(grouping: mergedTagGroups, by: { $0.id }).values.compactMap { $0.first })
            let finalLabelGroups = Array(Dictionary(grouping: mergedLabelGroups, by: { $0.id }).values.compactMap { $0.first })
            let finalLabels = Array(Dictionary(grouping: mergedLabels, by: { $0.id }).values.compactMap { $0.first })
            let finalTimeEvents = Array(Dictionary(grouping: mergedTimeEvents, by: { $0.id }).values.compactMap { $0.first })
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.allTags = finalTags
                self.allTagGroups = finalTagGroups
                self.allLabelGroups = finalLabelGroups
                self.allLabels = finalLabels
                self.allTimeEvents = finalTimeEvents
                self.isReloadingCollections = false
                print("✅ TagLibraryManager: Finished loading all collections - total tags: \(finalTags.count), tagGroups: \(finalTagGroups.count)")

                NotificationCenter.default.post(name: .collectionsLoadingFinished, object: nil)

                // Пока собирали, пришло ещё одно изменение — прогоняем заново.
                if self.needsAnotherReload {
                    self.needsAnotherReload = false
                    self.reloadAllCollectionsIfIdle()
                }
            }
        }
    }
    
    func getCollectionData(for collectionName: String) -> (tags: [Tag], tagGroups: [TagGroup], labelGroups: [LabelGroupData], labels: [Label], timeEvents: [TimeEvent])? {
        cacheLock.lock()
        let cached = loadedCollectionsCache[collectionName]
        cacheLock.unlock()
        
        if let cached = cached {
            return cached
        }
        
        let collectionManager = CustomCollectionManager()
        if collectionManager.loadCollectionFromBookmarks(named: collectionName) {
            let data = (
                tags: collectionManager.tags,
                tagGroups: collectionManager.tagGroups,
                labelGroups: collectionManager.labelGroups,
                labels: collectionManager.labels,
                timeEvents: collectionManager.timeEvents
            )
            cacheLock.lock()
            loadedCollectionsCache[collectionName] = data
            cacheLock.unlock()
            return data
        }
        
        return nil
    }
    
    func findOrCreateTimeEvent(id: String, name: String, shouldCreate: Bool = true) -> TimeEvent? {
        if let existingEvent = allTimeEvents.first(where: { $0.id == id }) {
            return existingEvent
        } else if shouldCreate {
            let newEvent = TimeEvent(id: id, name: name)
            allTimeEvents.append(newEvent)
            return newEvent
        } else {
            return nil
        }
    }
    
    
    func toggleTimeEvent(id: String) {
        if selectedTimeEvents.contains(id) {
            selectedTimeEvents.remove(id)
        } else {
            selectedTimeEvents.insert(id)
        }
    }
    
    @objc private func handleTagUpdated(_ notification: Notification) {
        guard let tagId = notification.userInfo?["tagId"] as? String else { return }
        
        for i in 0..<allTagGroups.count {
            if let tagIndex = allTagGroups[i].tags.firstIndex(where: { $0 == tagId }) {
                var updatedTags = allTagGroups[i].tags
                updatedTags[tagIndex] = tagId
                allTagGroups[i] = TagGroup(
                    id: allTagGroups[i].id,
                    name: allTagGroups[i].name,
                    tags: updatedTags
                )
            }
        }
        
        refreshGlobalPools()
    }
    
    func refreshGlobalPools() {
        let standardTags = tags
        let standardTagGroups = tagGroups
        let standardLabelGroups = labelGroups
        let standardLabels = labels
        let standardTimeEvents = timeEvents
        
        allTags = standardTags
        allTagGroups = standardTagGroups
        allLabelGroups = standardLabelGroups
        allLabels = standardLabels
        allTimeEvents = standardTimeEvents
        loadAllUserCollections()
        applyHotkeysFromCurrentCollection()
    }
    
    func restoreDefaultData() {
        applyDefaultCollection()
        currentCollectionType = .standard
        selectedTimeEvents.removeAll()
        refreshGlobalPools()
    }

    func applyHotkeysFromCurrentCollection() {
        HotKeyManager.shared.clearHotkeys()
        HotKeyManager.shared.registerHotkeys(from: tags, for: currentCollectionType)
    }
    
    func applyDefaultCollection() {
        let lastSelectedCollectionName = UserDefaults.standard.string(forKey: UserDefaults.Keys.lastSelectedCollection)
        let collectionManager = CustomCollectionManager()
        if let lastSelectedCollectionName, collectionManager.loadCollectionFromBookmarks(named: lastSelectedCollectionName) {
            tags = collectionManager.tags
            tagGroups = collectionManager.tagGroups
            labelGroups = collectionManager.labelGroups
            labels = collectionManager.labels
            timeEvents = collectionManager.timeEvents
            selectedTimeEvents.removeAll()
            currentCollectionType = .user(name: lastSelectedCollectionName)
            HotKeyManager.shared.clearHotkeys()
            HotKeyManager.shared.registerHotkeys(from: tags, for: .user(name: lastSelectedCollectionName))
            selectedStandardCollectionName = lastSelectedCollectionName
        } else if let standardCollection =
                    standardCollections.first(where: { $0.name == lastSelectedCollectionName }) ??
                    standardCollections.first
        {
            applyStandardCollection(named: standardCollection.name)
            selectedStandardCollectionName = standardCollection.name
        }
    }
}
