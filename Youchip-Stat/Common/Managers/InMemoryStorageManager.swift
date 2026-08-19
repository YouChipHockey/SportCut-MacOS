import Foundation
import AppKit
import Combine

final class InMemoryStorageManager {
    
    static let shared = InMemoryStorageManager()
    
    private let userDefaults = UserDefaults.standard
    private let fileManager = FileManager.default
    /// Platform guard for CFPreferences payload size.
    /// Keep a small safety margin below the 4 MB hard limit.
    private let maxUserDefaultsBlobSize = 4_000_000
    
    private var saveToDiskTimer: Timer?
    private var pendingSave = false
    private let saveToDiskInterval: TimeInterval = 30.0
    
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    deinit {
        saveToDiskTimer?.invalidate()
    }
    
    @objc private func applicationWillTerminate() {
        saveToDiskTimer?.invalidate()
        // Сначала синхронно доводим до диска последний снимок разметки — иначе правки,
        // сделанные за секунду до выхода, не доедут.
        flushTimelinesNow()
        saveToDiskImmediate()
        CollectionsBookmarksManager.shared.saveToFileImmediate()
    }

    // MARK: - Таймлайны: отложенная запись
    //
    // Раньше `saveTimelines` кодировал весь массив и писал его в UserDefaults СИНХРОННО НА
    // ГЛАВНОМ ПОТОКЕ, а звался из ~12 точек мутации разметки (добавление тега, ресайз, перенос
    // штампа, правка лейблов, комментарий, удаление, сортировка). На проекте с 613 таймлайнами
    // и ~7000 тегов это многомегабайтный JSON на каждое действие — «нажал добавить тег, ждёшь
    // 5 секунд». См. TASK-007, 5.2/5.3.
    //
    // Теперь в память кладётся снимок, а кодирование и запись идут на фоновой очереди с
    // коалесингом: серия быстрых правок даёт одну запись. Пользователь диск не ждёт.
    //
    // ИНВАРИАНТ, на котором держится отсутствие потери данных: пока снимок не записан, он лежит
    // в `pendingTimelines`, и `loadTimelines` обязан читать ОТТУДА. Иначе переключение видео
    // сразу после правки прочитало бы с диска устаревшую версию. Точки принудительного сброса —
    // `flushTimelinesNow()`: выход из приложения и `saveToDiskImmediate()`.

    private let timelineIOQueue = DispatchQueue(label: "com.youchip.timelineIO", qos: .utility)
    private let pendingLock = NSLock()
    private var pendingTimelines: [String: [TimelineLine]] = [:]
    private var pendingFlushWork: DispatchWorkItem?
    private let timelineFlushDelay: TimeInterval = 0.4

    func saveTimelines(_ timelines: [TimelineLine], for videoId: String) {
        pendingLock.lock()
        pendingTimelines[videoId] = timelines
        // Предыдущий отложенный сброс отменяем — иначе серия правок даст серию записей.
        pendingFlushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushPendingTimelines() }
        pendingFlushWork = work
        pendingLock.unlock()

        // DispatchWorkItem, а не Timer: `saveTimelines` могут позвать не с главного потока,
        // и тогда Timer молча не сработал бы (не к тому раннлупу).
        timelineIOQueue.asyncAfter(deadline: .now() + timelineFlushDelay, execute: work)

        // Раньше отсюда уходило уведомление .projectTimelinesDidChange, по которому режим
        // просмотра пересинкивал все свои сессии под этот проект. Убрано намеренно: идущий
        // счётчик обновляет свой штамп раз в секунду, и такой посекундный пересинк (со записью
        // на диск) давал рывок на больших проектах. Просмотр теперь догоняет разметку в явных
        // точках — см. SportCutMarkupSyncManager.
    }

    /// Синхронно доводит отложенный снимок до диска. Для выхода из приложения и для мест,
    /// которым нужна гарантия записи.
    func flushTimelinesNow() {
        pendingLock.lock()
        pendingFlushWork?.cancel()
        pendingFlushWork = nil
        pendingLock.unlock()
        // Зовётся с главного потока, поэтому `sync` на другой очереди не даёт дедлока.
        timelineIOQueue.sync { self.flushPendingTimelines() }
    }

    private func flushPendingTimelines() {
        pendingLock.lock()
        let snapshot = pendingTimelines
        pendingTimelines.removeAll()
        pendingFlushWork = nil
        pendingLock.unlock()

        guard !snapshot.isEmpty else { return }
        for (videoId, timelines) in snapshot {
            writeTimelines(timelines, for: videoId)
        }
    }

    private func writeTimelines(_ timelines: [TimelineLine], for videoId: String) {
        let key = "timeline_\(videoId)"
        guard let data = try? JSONEncoder().encode(timelines) else { return }

        // Файл пишем ВСЕГДА: он и есть надёжное хранилище. UserDefaults остаётся только
        // быстрым кэшем для чтения — и лишь пока блоб влезает под лимит CFPreferences.
        // Раньше файл появлялся лишь через 30-секундный таймер, который потом заново обходил
        // все ключи UserDefaults; теперь мы уже на фоне, ждать незачем.
        if data.count > maxUserDefaultsBlobSize {
            userDefaults.removeObject(forKey: key)
        } else {
            userDefaults.set(data, forKey: key)
        }
        saveTimelineDataToFile(data, videoId: videoId)
    }

    func loadTimelines(for videoId: String) -> [TimelineLine] {
        // Незаписанный снимок — самый свежий. Читать в этот момент с диска = потерять правки.
        pendingLock.lock()
        let pending = pendingTimelines[videoId]
        pendingLock.unlock()
        if let pending { return pending }

        let key = "timeline_\(videoId)"
        if let data = userDefaults.data(forKey: key),
           let timelines = Self.decodeTimelinesLenient(data) {
            return timelines
        }
        return loadTimelinesFromFile(for: videoId)
    }

    /// Разбор таймлайнов, устойчивый к битой строке: сперва целиком, иначе построчно (битая
    /// строка → пропуск, а не потеря всего проекта). nil — данных нет/совсем не разобрались.
    static func decodeTimelinesLenient(_ data: Data) -> [TimelineLine]? {
        if let t = try? JSONDecoder().decode([TimelineLine].self, from: data) { return t }
        if let lenient = try? JSONDecoder().decode([FailableLine].self, from: data) {
            return lenient.compactMap(\.value)
        }
        return nil
    }

    func deleteTimelines(for videoId: String) {
        let key = "timeline_\(videoId)"
        // Снимаем отложенную запись, иначе она воскресила бы только что удалённые таймлайны.
        pendingLock.lock()
        pendingTimelines.removeValue(forKey: videoId)
        pendingLock.unlock()

        userDefaults.removeObject(forKey: key)
        deleteTimelinesFile(for: videoId)
    }
    
    // Коллекции: файлы в Documents — источник правды, блоб в UserDefaults — только кэш.
    //
    // Раньше было наоборот: `loadCollection` брал блоб `collection_<id>`, а `saveCollectionsToDisk`
    // потом перезаписывал из него ВСЕ файлы коллекций. Любое изменение файлов мимо UserDefaults
    // (восстановление из бэкапа, импорт, перенос с другой машины, запись старой сборкой) делало
    // блоб устаревшим — и приложение молча откатывало коллекцию к нему. Так, в частности,
    // терялся `isInterval` у тегов: в старом блобе его нет, `Bool?` декодируется в nil, а при
    // кодировании ключ не пишется вовсе. См. vault/tasks TASK-008.

    func saveCollection(_ collection: CollectionData) {
        let key = "collection_\(collection.id)"
        if let data = try? JSONEncoder().encode(collection) {
            userDefaults.set(data, forKey: key)
        }
        // Файл пишем сразу: раз он источник правды при чтении, отложенная запись оставляла бы
        // окно, в котором файл старее только что сохранённых правок.
        saveCollectionToFile(collection)
        scheduleSaveToDisk()
    }

    func loadCollection(id: String) -> CollectionData? {
        if let fromFile = loadCollectionFromFile(id: id) {
            return fromFile
        }
        let key = "collection_\(id)"
        guard let data = userDefaults.data(forKey: key),
              let collection = try? JSONDecoder().decode(CollectionData.self, from: data) else {
            return nil
        }
        return collection
    }
    
    func deleteCollection(id: String) {
        let key = "collection_\(id)"
        userDefaults.removeObject(forKey: key)
        scheduleSaveToDisk()
    }
    
    private func scheduleSaveToDisk() {
        guard !pendingSave else { return }
        pendingSave = true
        
        saveToDiskTimer?.invalidate()
        saveToDiskTimer = Timer.scheduledTimer(withTimeInterval: saveToDiskInterval, repeats: false) { [weak self] _ in
            self?.saveToDiskImmediate()
        }
    }
    
    func saveToDiskImmediate() {
        // Это API «гарантированно положить всё на диск», поэтому отложенный снимок разметки
        // сбрасываем до проверки `pendingSave`: он живёт своей очередью и к этому флагу
        // отношения не имеет.
        flushTimelinesNow()

        guard pendingSave else { return }
        pendingSave = false

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.saveTimelinesToDisk()
            self?.saveCollectionsToDisk()
        }
    }
    
    private func saveTimelinesToDisk() {
        let timelinesDirectory = getTimelinesDirectory()
        fileManager.createDirectoryIfNeeded(url: timelinesDirectory)
        
        let keys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("timeline_") }
        
        for key in keys {
            guard let data = userDefaults.data(forKey: key) else { continue }
            let videoId = String(key.dropFirst("timeline_".count))
            let fileURL = timelinesDirectory.appendingPathComponent("\(videoId).json")
            try? data.write(to: fileURL)
        }
    }
    
    private func saveCollectionsToDisk() {
        let keys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("collection_") }
        let cachedCollectionIds = Set(keys.map { String($0.dropFirst("collection_".count)) })
        // Список коллекций описывает CollectionsBookmarks.json, а не наличие кэш-блоба:
        // у восстановленной или принесённой извне папки блоба ещё нет, и раньше её тут удаляли.
        let declaredCollectionIds = Set(CollectionsBookmarksManager.shared.loadCollections().map { $0.id })

        let collectionsDirectory = getCollectionsDirectory()
        guard fileManager.fileExists(atPath: collectionsDirectory.path) else { return }

        do {
            let folderContents = try fileManager.contentsOfDirectory(at: collectionsDirectory, includingPropertiesForKeys: nil)

            for folderURL in folderContents where folderURL.hasDirectoryPath {
                let folderId = folderURL.lastPathComponent
                if !cachedCollectionIds.contains(folderId) && !declaredCollectionIds.contains(folderId) {
                    try? fileManager.removeItem(at: folderURL)
                }
            }
        } catch {}

        // Пишем только те коллекции, файлов которых ещё нет: файл авторитетнее кэша,
        // и затирать его старым блобом нельзя.
        for key in keys {
            guard let data = userDefaults.data(forKey: key),
                  let collection = try? JSONDecoder().decode(CollectionData.self, from: data) else {
                continue
            }
            let tagsURL = collectionsDirectory
                .appendingPathComponent(collection.id, isDirectory: true)
                .appendingPathComponent("tags.json")
            guard !fileManager.fileExists(atPath: tagsURL.path) else { continue }
            saveCollectionToFile(collection)
        }
    }
    
    private func loadTimelinesFromFile(for videoId: String) -> [TimelineLine] {
        let fileURL = getTimelinesDirectory().appendingPathComponent("\(videoId).json")
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let timelines = Self.decodeTimelinesLenient(data) else {
            return []
        }
        
        let key = "timeline_\(videoId)"
        if data.count <= maxUserDefaultsBlobSize {
            userDefaults.set(data, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
        return timelines
    }

    private func saveTimelineDataToFile(_ data: Data, videoId: String) {
        let timelinesDirectory = getTimelinesDirectory()
        fileManager.createDirectoryIfNeeded(url: timelinesDirectory)
        let fileURL = timelinesDirectory.appendingPathComponent("\(videoId).json")
        try? data.write(to: fileURL, options: .atomic)
    }
    
    private func deleteTimelinesFile(for videoId: String) {
        let fileURL = getTimelinesDirectory().appendingPathComponent("\(videoId).json")
        try? fileManager.removeItem(at: fileURL)
    }
    
    private func loadCollectionFromFile(id: String) -> CollectionData? {
        let collectionFolderUrl = getCollectionsDirectory().appendingPathComponent(id, isDirectory: true)
        
        guard fileManager.fileExists(atPath: collectionFolderUrl.path) else {
            return nil
        }
        
        let tagGroupsURL = collectionFolderUrl.appendingPathComponent("tagGroups.json")
        let tagsURL = collectionFolderUrl.appendingPathComponent("tags.json")
        let labelGroupsURL = collectionFolderUrl.appendingPathComponent("labelGroups.json")
        let labelsURL = collectionFolderUrl.appendingPathComponent("labels.json")
        let timeEventsURL = collectionFolderUrl.appendingPathComponent("timeEvents.json")
        let playFieldURL = collectionFolderUrl.appendingPathComponent("playField.json")
        
        guard let tagGroupsData = try? Data(contentsOf: tagGroupsURL),
              let tagsData = try? Data(contentsOf: tagsURL),
              let labelGroupsData = try? Data(contentsOf: labelGroupsURL),
              let labelsData = try? Data(contentsOf: labelsURL),
              let tagGroups = try? JSONDecoder().decode(TagGroupsData.self, from: tagGroupsData),
              let tags = try? JSONDecoder().decode(TagsData.self, from: tagsData),
              let labelGroups = try? JSONDecoder().decode(LabelGroupsData.self, from: labelGroupsData),
              let labels = try? JSONDecoder().decode(LabelsData.self, from: labelsData) else {
            return nil
        }
        
        let timeEvents: [TimeEvent]
        if fileManager.fileExists(atPath: timeEventsURL.path),
           let timeEventsData = try? Data(contentsOf: timeEventsURL),
           let decoded = try? JSONDecoder().decode(TimeEventsData.self, from: timeEventsData) {
            timeEvents = decoded.events
        } else {
            timeEvents = []
        }
        
        let playField: PlayField?
        if fileManager.fileExists(atPath: playFieldURL.path),
           let playFieldData = try? Data(contentsOf: playFieldURL),
           let decoded = try? JSONDecoder().decode(PlayField.self, from: playFieldData) {
            playField = decoded
        } else {
            playField = nil
        }

        // Полный набор карт (новый формат). Если файла нет — падаем на единственную карту.
        let playFieldsURL = collectionFolderUrl.appendingPathComponent("playFields.json")
        let playFields: [PlayField]?
        if fileManager.fileExists(atPath: playFieldsURL.path),
           let data = try? Data(contentsOf: playFieldsURL),
           let decoded = try? JSONDecoder().decode([PlayField].self, from: data) {
            playFields = decoded
        } else {
            playFields = playField.map { [$0] }
        }

        // Секундомеры/таймеры (новый формат). Файла нет в старых коллекциях.
        let clocksURL = collectionFolderUrl.appendingPathComponent("clocks.json")
        let clocks: [ClockEntity]?
        if fileManager.fileExists(atPath: clocksURL.path),
           let data = try? Data(contentsOf: clocksURL),
           let decoded = try? JSONDecoder().decode([ClockEntity].self, from: data) {
            clocks = decoded
        } else {
            clocks = nil
        }

        let collection = CollectionData(
            id: id,
            tagGroups: tagGroups.tagGroups,
            tags: tags.tags,
            labelGroups: labelGroups.labelGroups,
            labels: labels.labels,
            timeEvents: timeEvents,
            playField: playField,
            playFields: playFields,
            clocks: clocks
        )
        
        // Обновляем кэш, только если он реально разошёлся с файлами: чтение коллекций идёт
        // пачкой на каждое изменение, лишние записи в CFPreferences тут ни к чему.
        let key = "collection_\(id)"
        if let data = try? JSONEncoder().encode(collection), userDefaults.data(forKey: key) != data {
            userDefaults.set(data, forKey: key)
        }

        return collection
    }
    
    private func saveCollectionToFile(_ collection: CollectionData) {
        let collectionFolderUrl = getCollectionsDirectory().appendingPathComponent(collection.id, isDirectory: true)
        
        fileManager.createDirectoryIfNeeded(url: collectionFolderUrl)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        if let tagGroupsData = try? encoder.encode(TagGroupsData(tagGroups: collection.tagGroups)) {
            try? tagGroupsData.write(to: collectionFolderUrl.appendingPathComponent("tagGroups.json"))
        }
        
        if let tagsData = try? encoder.encode(TagsData(tags: collection.tags)) {
            try? tagsData.write(to: collectionFolderUrl.appendingPathComponent("tags.json"))
        }
        
        if let labelGroupsData = try? encoder.encode(LabelGroupsData(labelGroups: collection.labelGroups)) {
            try? labelGroupsData.write(to: collectionFolderUrl.appendingPathComponent("labelGroups.json"))
        }
        
        if let labelsData = try? encoder.encode(LabelsData(labels: collection.labels)) {
            try? labelsData.write(to: collectionFolderUrl.appendingPathComponent("labels.json"))
        }
        
        if !collection.timeEvents.isEmpty,
           let timeEventsData = try? encoder.encode(TimeEventsData(events: collection.timeEvents)) {
            try? timeEventsData.write(to: collectionFolderUrl.appendingPathComponent("timeEvents.json"))
        }
        
        if let playField = collection.playField,
           let playFieldData = try? encoder.encode(playField) {
            try? playFieldData.write(to: collectionFolderUrl.appendingPathComponent("playField.json"))
        }

        // Полный набор карт (новый формат). Пишем всегда, когда есть хотя бы одна карта.
        let playFieldsURL = collectionFolderUrl.appendingPathComponent("playFields.json")
        if let playFields = collection.playFields, !playFields.isEmpty,
           let data = try? encoder.encode(playFields) {
            try? data.write(to: playFieldsURL)
        } else if fileManager.fileExists(atPath: playFieldsURL.path) {
            try? fileManager.removeItem(at: playFieldsURL)
        }

        // Секундомеры/таймеры.
        let clocksURL = collectionFolderUrl.appendingPathComponent("clocks.json")
        if let clocks = collection.clocks, !clocks.isEmpty,
           let data = try? encoder.encode(clocks) {
            try? data.write(to: clocksURL)
        } else if fileManager.fileExists(atPath: clocksURL.path) {
            try? fileManager.removeItem(at: clocksURL)
        }
    }
    
    private func getTimelinesDirectory() -> URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("YouChip-Stat/Timelines", isDirectory: true)
    }
    
    private func getCollectionsDirectory() -> URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("YouChip-Stat/Collections", isDirectory: true)
    }
}

struct CollectionData: Codable {
    let id: String
    var tagGroups: [TagGroup]
    var tags: [Tag]
    var labelGroups: [LabelGroupData]
    var labels: [Label]
    var timeEvents: [TimeEvent]
    /// Первая карта (для обратной совместимости со старым форматом).
    var playField: PlayField?
    /// Полный набор карт коллекции. nil в старых данных — тогда используется `playField`.
    var playFields: [PlayField]?
    /// Секундомеры/таймеры коллекции. nil/пусто в старых данных.
    var clocks: [ClockEntity]?

    init(id: String, tagGroups: [TagGroup], tags: [Tag], labelGroups: [LabelGroupData], labels: [Label], timeEvents: [TimeEvent], playField: PlayField?, playFields: [PlayField]? = nil, clocks: [ClockEntity]? = nil) {
        self.id = id
        self.tagGroups = tagGroups
        self.tags = tags
        self.labelGroups = labelGroups
        self.labels = labels
        self.timeEvents = timeEvents
        self.playFields = playFields ?? playField.map { [$0] }
        self.playField = self.playFields?.first ?? playField
        self.clocks = clocks
    }
}

/// Обёртка для «мягкого» декодирования строки таймлайна: битая строка → nil, а не падение всего массива.
private struct FailableLine: Decodable {
    let value: TimelineLine?
    init(from decoder: Decoder) throws {
        value = try? TimelineLine(from: decoder)
    }
}
