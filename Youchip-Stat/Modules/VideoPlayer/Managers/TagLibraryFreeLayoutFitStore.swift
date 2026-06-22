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
        "\(projectId)_\(collectionId)_\(layout.canvasWidth)_\(layout.canvasHeight)"
    }
}
