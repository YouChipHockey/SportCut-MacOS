//
//  PlayFieldImageCache.swift
//  Youchip-Stat
//
//  Кэш декодированных изображений карт (PlayField) по id — чтобы не декодировать
//  security-scoped bookmark на каждый кадр при отрисовке карты на холсте.
//

import AppKit

final class PlayFieldImageCache {

    static let shared = PlayFieldImageCache()

    private var cache: [String: NSImage] = [:]

    private init() {}

    func image(for field: PlayField) -> NSImage? {
        if let cached = cache[field.id] { return cached }
        guard let bookmark = field.imageBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        var image: NSImage?
        if url.startAccessingSecurityScopedResource() {
            image = NSImage(contentsOf: url)
            url.stopAccessingSecurityScopedResource()
        }
        if let image { cache[field.id] = image }
        return image
    }

    func invalidate(_ id: String) { cache.removeValue(forKey: id) }

    /// Декодирует изображение по произвольному security-scoped bookmark (фон кнопки-тега).
    func image(forBookmark bookmark: Data) -> NSImage? {
        let key = "bm:" + bookmark.base64EncodedString()
        if let cached = cache[key] { return cached }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        var image: NSImage?
        if url.startAccessingSecurityScopedResource() {
            image = NSImage(contentsOf: url)
            url.stopAccessingSecurityScopedResource()
        }
        if let image { cache[key] = image }
        return image
    }
}
