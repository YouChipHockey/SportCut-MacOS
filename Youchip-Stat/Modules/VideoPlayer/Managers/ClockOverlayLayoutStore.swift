//
//  ClockOverlayLayoutStore.swift
//  Youchip-Stat
//
//  Где и какого размера показывать счётчик поверх видео. Позиция хранится НОРМАЛИЗОВАННОЙ
//  (доли ширины/высоты видео-области), поэтому переживает ресайз окна и разные разрешения:
//  в пикселях счётчик уезжал бы за край при первом же изменении размера.
//
//  Раскладка — настройка отображения, а не часть коллекции, поэтому живёт в UserDefaults и
//  не тянет за собой пересохранение файлов коллекции при каждом перетаскивании.
//

import Foundation
import CoreGraphics
import Combine

/// Положение и масштаб одного счётчика на видео.
struct ClockOverlayLayout: Codable, Equatable {
    /// Центр в долях области видео (0…1).
    var centerX: Double
    var centerY: Double
    /// Множитель базового размера счётчика.
    var scale: Double

    static let defaultScale: Double = 1.0
}

final class ClockOverlayLayoutStore: ObservableObject {

    static let shared = ClockOverlayLayoutStore()

    private static let storageKey = "clockVideoOverlayLayouts"
    /// Границы масштаба: мельче — не читается, крупнее — перекрывает половину кадра.
    static let minScale: Double = 0.4
    static let maxScale: Double = 4.0

    @Published private(set) var layouts: [String: ClockOverlayLayout] = [:]

    private init() {
        load()
    }

    func layout(for clockId: String) -> ClockOverlayLayout? {
        layouts[clockId]
    }

    /// Вызывается по ОКОНЧАНИИ жеста: пока тащат, раскладка живёт в локальном состоянии вьюхи —
    /// публиковать её на каждом кадре значит перерисовывать весь оверлей и дёргать перетаскивание.
    func setLayout(_ layout: ClockOverlayLayout, for clockId: String) {
        var updated = layout
        updated.centerX = min(max(updated.centerX, 0), 1)
        updated.centerY = min(max(updated.centerY, 0), 1)
        updated.scale = min(max(updated.scale, Self.minScale), Self.maxScale)
        layouts[clockId] = updated
        save()
    }

    /// Возврат к раскладке по умолчанию (стопка в правом верхнем углу).
    func resetLayout(for clockId: String) {
        guard layouts[clockId] != nil else { return }
        layouts[clockId] = nil
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: ClockOverlayLayout].self, from: data)
        else { return }
        layouts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
