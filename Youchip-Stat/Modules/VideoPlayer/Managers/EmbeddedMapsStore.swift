//
//  EmbeddedMapsStore.swift
//  Youchip-Stat
//
//  Durable-репозиторий «id карты (PlayField.id) → картинка поля», не зависящий от коллекций.
//  Наполняется в трёх точках: (1) при разметке точки (там есть PlayField с картинкой);
//  (2) при экспорте проекта — backfill из доступных коллекций для встреченных id; (3) при импорте
//  проекта — из `ProjectExportModel.embeddedMaps`. Визуализация читает картинку сначала из
//  коллекции, а если её нет — отсюда (группа «Импортированное»).
//
//  Хранение по-файлово: `~/Documents/YouChip-Stat/EmbeddedMaps/<id>.json` (одна карта — один файл),
//  чтобы не переписывать общий блоб при каждом добавлении. Дедуп — по имени файла (= id карты).
//

import Foundation
import AppKit

final class EmbeddedMapsStore {

    static let shared = EmbeddedMapsStore()

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "embeddedMapsStore.io")
    private let cacheLock = NSLock()
    /// Кэш разобранных карт по id (ленивый). NSImage кэшируем отдельно — он тяжёлый.
    private var mapCache: [String: EmbeddedFieldMap] = [:]
    private var imageCache: [String: NSImage] = [:]

    private init() {}

    private var directory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("YouChip-Stat/EmbeddedMaps", isDirectory: true)
    }

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    // MARK: - Чтение

    /// Есть ли встроенная карта с таким id (в кэше или на диске).
    func contains(id: String) -> Bool {
        cacheLock.lock()
        let cached = mapCache[id] != nil
        cacheLock.unlock()
        if cached { return true }
        return fileManager.fileExists(atPath: fileURL(for: id).path)
    }

    /// Встроенная карта по id (ленивая загрузка с диска + кэш).
    func map(for id: String) -> EmbeddedFieldMap? {
        cacheLock.lock()
        if let cached = mapCache[id] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let data = try? Data(contentsOf: fileURL(for: id)),
              let map = try? JSONDecoder().decode(EmbeddedFieldMap.self, from: data) else {
            return nil
        }
        cacheLock.lock()
        mapCache[id] = map
        cacheLock.unlock()
        return map
    }

    /// Картинка встроенной карты по id (кэшируется).
    func image(for id: String) -> NSImage? {
        cacheLock.lock()
        if let img = imageCache[id] {
            cacheLock.unlock()
            return img
        }
        cacheLock.unlock()

        guard let map = map(for: id), let img = NSImage(data: map.imageData) else { return nil }
        cacheLock.lock()
        imageCache[id] = img
        cacheLock.unlock()
        return img
    }

    /// Карты для указанных id (в порядке переданных id), пропуская отсутствующие. Для экспорта.
    func maps(forIds ids: [String]) -> [EmbeddedFieldMap] {
        ids.compactMap { map(for: $0) }
    }

    // MARK: - Запись

    /// Сохраняет карту, если её ещё нет (дедуп по id). Пишет асинхронно.
    func storeIfNeeded(_ map: EmbeddedFieldMap) {
        guard !contains(id: map.id) else { return }
        write(map)
    }

    /// Кладёт/обновляет карту (используется при импорте — свежие данные важнее старых). Асинхронно.
    func importMaps(_ maps: [EmbeddedFieldMap]) {
        for map in maps { write(map, overwrite: true) }
    }

    /// Синхронно: строит встроенную карту из `PlayField` (если ещё нет) и сохраняет. Возвращает
    /// готовую карту. Для backfill при экспорте, где результат нужен сразу.
    @discardableResult
    func capture(from playField: PlayField) -> EmbeddedFieldMap? {
        if let existing = map(for: playField.id) { return existing }
        guard let imageData = Self.imageData(from: playField) else { return nil }
        let map = EmbeddedFieldMap(id: playField.id, name: playField.name,
                                   width: playField.width, height: playField.height,
                                   imageData: imageData)
        write(map, sync: true)
        return map
    }

    /// Если карты с этим id ещё нет — достаёт байты из `PlayField` (через его bookmark) и сохраняет.
    /// Тяжёлое I/O уходит на фон.
    func captureIfNeeded(from playField: PlayField) {
        let id = playField.id
        guard !contains(id: id) else { return }
        ioQueue.async { [weak self] in
            guard let self else { return }
            guard !self.contains(id: id) else { return }
            guard let imageData = Self.imageData(from: playField) else { return }
            let map = EmbeddedFieldMap(id: id, name: playField.name,
                                       width: playField.width, height: playField.height,
                                       imageData: imageData)
            self.write(map, sync: true)
        }
    }

    // MARK: - Приватное

    private func write(_ map: EmbeddedFieldMap, overwrite: Bool = false, sync: Bool = false) {
        let work: () -> Void = { [weak self] in
            guard let self else { return }
            if !overwrite, self.fileManager.fileExists(atPath: self.fileURL(for: map.id).path) {
                // На всякий случай обновим кэш и выйдем.
                self.cacheLock.lock(); self.mapCache[map.id] = map; self.cacheLock.unlock()
                return
            }
            self.fileManager.createDirectoryIfNeeded(url: self.directory)
            if let data = try? JSONEncoder().encode(map) {
                try? data.write(to: self.fileURL(for: map.id), options: .atomic)
            }
            self.cacheLock.lock()
            self.mapCache[map.id] = map
            self.imageCache[map.id] = nil // пусть перечитается из свежих байтов
            self.cacheLock.unlock()
        }
        if sync { work() } else { ioQueue.async(execute: work) }
    }

    /// Достаёт сырые байты картинки из `PlayField.imageBookmark` (security-scoped). Логика та же,
    /// что в `PlayFieldExport`.
    static func imageData(from playField: PlayField) -> Data? {
        guard let bookmark = playField.imageBookmark else { return nil }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                              relativeTo: nil, bookmarkDataIsStale: &isStale)
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }
            return try? Data(contentsOf: url)
        } catch {
            return nil
        }
    }
}
