//
//  ImageEditorProjectsManager.swift
//  Youchip-Stat
//
//  Проекты самостоятельного «Редактора картинок»: загруженное фото + слой
//  рисовалки (EditorStateSnapshot) + добавленные пользователем картинки.
//  Хранится в ~/Documents/YouChip-Stat/EditorProjects/{id}/.
//

import AppKit
import Foundation

/// Метаданные проекта редактора для списка.
struct ImageEditorProjectMeta: Codable, Identifiable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var baseImageFileName: String
}

final class ImageEditorProjectsManager: ObservableObject {

    static let shared = ImageEditorProjectsManager()

    @Published private(set) var projects: [ImageEditorProjectMeta] = []

    private let fileManager = FileManager.default

    private init() {
        reload()
    }

    // MARK: - Пути

    private var rootFolder: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("YouChip-Stat", isDirectory: true)
            .appendingPathComponent("EditorProjects", isDirectory: true)
    }

    func projectFolder(_ id: UUID) -> URL {
        rootFolder.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Папка добавленных пользователем картинок (объектов) внутри проекта.
    func addedImagesFolder(_ id: UUID) -> URL {
        projectFolder(id).appendingPathComponent("images", isDirectory: true)
    }

    private func metaURL(_ id: UUID) -> URL { projectFolder(id).appendingPathComponent("meta.json") }
    private func snapshotURL(_ id: UUID) -> URL { projectFolder(id).appendingPathComponent("snapshot.json") }
    func thumbnailURL(_ id: UUID) -> URL { projectFolder(id).appendingPathComponent("thumbnail.png") }
    func baseImageURL(_ id: UUID, fileName: String) -> URL { projectFolder(id).appendingPathComponent(fileName) }

    // MARK: - Список

    func reload() {
        var result: [ImageEditorProjectMeta] = []
        guard let dirs = try? fileManager.contentsOfDirectory(at: rootFolder, includingPropertiesForKeys: nil) else {
            projects = []
            return
        }
        for dir in dirs where dir.hasDirectoryPath {
            let meta = dir.appendingPathComponent("meta.json")
            if let data = try? Data(contentsOf: meta),
               let m = try? JSONDecoder().decode(ImageEditorProjectMeta.self, from: data) {
                result.append(m)
            }
        }
        projects = result.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Создание/удаление

    /// Создаёт новый проект из выбранного изображения (heic/png/jpeg…), конвертируя базу в PNG.
    @discardableResult
    func createProject(fromImageAt url: URL, name: String) -> ImageEditorProjectMeta? {
        guard let image = NSImage(contentsOf: url), let png = Self.pngData(from: image) else { return nil }
        let id = UUID()
        let folder = projectFolder(id)
        try? fileManager.createDirectory(at: addedImagesFolder(id), withIntermediateDirectories: true)

        let baseFileName = "base.png"
        do {
            try png.write(to: folder.appendingPathComponent(baseFileName))
        } catch {
            return nil
        }

        let now = Date()
        let meta = ImageEditorProjectMeta(id: id, name: name, createdAt: now, updatedAt: now, baseImageFileName: baseFileName)
        writeMeta(meta)
        // Пустой снапшот, чтобы проект сразу открывался.
        writeSnapshot(EditorStateSnapshot(viewSizeWidth: 0, viewSizeHeight: 0), for: id)
        // Превью = базовая картинка до первого сохранения.
        try? png.write(to: thumbnailURL(id))
        reload()
        return meta
    }

    func deleteProject(_ id: UUID) {
        try? fileManager.removeItem(at: projectFolder(id))
        reload()
    }

    func renameProject(_ id: UUID, to name: String) {
        guard var meta = meta(for: id) else { return }
        meta.name = name
        meta.updatedAt = Date()
        writeMeta(meta)
        reload()
    }

    // MARK: - Загрузка/сохранение

    func meta(for id: UUID) -> ImageEditorProjectMeta? {
        guard let data = try? Data(contentsOf: metaURL(id)) else { return nil }
        return try? JSONDecoder().decode(ImageEditorProjectMeta.self, from: data)
    }

    /// Базовая картинка проекта.
    func loadBaseImage(_ id: UUID) -> NSImage? {
        guard let meta = meta(for: id) else { return nil }
        return NSImage(contentsOf: baseImageURL(id, fileName: meta.baseImageFileName))
    }

    /// Восстанавливает состояние рисовалки, подгружая NSImage для объектов-картинок.
    func loadDrawingState(_ id: UUID) -> EditorDrawingState {
        let state = EditorDrawingState()
        guard let data = try? Data(contentsOf: snapshotURL(id)),
              let snapshot = try? JSONDecoder().decode(EditorStateSnapshot.self, from: data) else {
            return state
        }
        snapshot.apply(to: state)
        // Подгружаем файлы добавленных картинок.
        let folder = addedImagesFolder(id)
        state.images = state.images.map { obj in
            var o = obj
            o.image = NSImage(contentsOf: folder.appendingPathComponent(obj.fileName))
            return o
        }
        return state
    }

    /// Сохраняет проект: снапшот рисовалки, файлы новых картинок и превью.
    func saveProject(_ id: UUID, drawingState: EditorDrawingState, thumbnail: NSImage?) {
        // Сохраняем файлы объектов-картинок, которых ещё нет на диске.
        let folder = addedImagesFolder(id)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for obj in drawingState.images {
            let dest = folder.appendingPathComponent(obj.fileName)
            if !fileManager.fileExists(atPath: dest.path), let image = obj.image, let png = Self.pngData(from: image) {
                try? png.write(to: dest)
            }
        }
        // Чистим осиротевшие файлы картинок.
        let used = Set(drawingState.images.map { $0.fileName })
        if let existing = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for f in existing where !used.contains(f.lastPathComponent) {
                try? fileManager.removeItem(at: f)
            }
        }

        writeSnapshot(EditorStateSnapshot.from(drawingState: drawingState), for: id)

        if let thumb = thumbnail, let png = Self.pngData(from: thumb) {
            try? png.write(to: thumbnailURL(id))
        }

        if var meta = meta(for: id) {
            meta.updatedAt = Date()
            writeMeta(meta)
        }
        reload()
    }

    // MARK: - Скачивание

    /// Итоговое (сплющенное) изображение проекта = текущее превью.
    func exportedImage(_ id: UUID) -> NSImage? {
        NSImage(contentsOf: thumbnailURL(id))
    }

    // MARK: - Приватное

    private func writeMeta(_ meta: ImageEditorProjectMeta) {
        try? fileManager.createDirectory(at: projectFolder(meta.id), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaURL(meta.id))
        }
    }

    private func writeSnapshot(_ snapshot: EditorStateSnapshot, for id: UUID) {
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: snapshotURL(id))
        }
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
