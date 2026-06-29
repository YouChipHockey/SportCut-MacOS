//
//  TagLibraryFreeLayoutFitStore.swift
//  Youchip-Stat
//
//  Кэш fit-масштаба свободной раскладки: один раз на проект + коллекцию.
//

import Foundation
import CoreGraphics

final class TagLibraryFreeLayoutFitStore {

    static let shared = TagLibraryFreeLayoutFitStore()

    private var projectId: String = ""
    private var scales: [String: CGFloat] = [:]

    private init() {}

    func resetForProject(_ id: String) {
        guard !id.isEmpty, projectId != id else { return }
        projectId = id
        scales.removeAll()
    }

    func fitScale(for key: String) -> CGFloat? {
        scales[key]
    }

    func storeFitScale(_ scale: CGFloat, for key: String) {
        scales[key] = scale
    }

    func makeLayoutKey(
        projectId: String,
        collectionId: String,
        layout: TagFreeLayout
    ) -> String {
        // Ключ зависит от размеров контента (а не фиксированного холста), чтобы fit-масштаб
        // пересчитывался при изменении раскладки (библиотека обрезается по контенту).
        let rect = layout.contentRect()
            ?? CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight)
        return "\(projectId)_\(collectionId)_\(Int(rect.width))_\(Int(rect.height))"
    }
}
