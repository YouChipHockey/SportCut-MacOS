//
//  AppSettingsStore.swift
//  Youchip-Stat
//
//  Глобальные пользовательские настройки приложения (единый экран настроек).
//  Сюда складываем простые тоглы/значения, которые нужны в разных местах.
//

import Foundation
import Combine

final class AppSettingsStore: ObservableObject {

    static let shared = AppSettingsStore()

    private enum Keys {
        static let exportClipsWithWatermark = "exportClipsWithWatermark"
    }

    /// Накладывать ли логотип клуба (вотермарку) на клипы при быстром сохранении
    /// (Cmd+S / Opt+Cmd+S). Работает и для одиночного клипа, и для набора выбранных.
    @Published var exportClipsWithWatermark: Bool {
        didSet { UserDefaults.standard.set(exportClipsWithWatermark, forKey: Keys.exportClipsWithWatermark) }
    }

    private init() {
        exportClipsWithWatermark = UserDefaults.standard.bool(forKey: Keys.exportClipsWithWatermark)
    }
}
