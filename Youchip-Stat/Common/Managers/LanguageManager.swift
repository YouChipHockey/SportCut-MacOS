//
//  LanguageManager.swift
//  Youchip-Stat
//
//  Runtime-переключаемая локализация без перезапуска приложения.
//
//  Как работает:
//  - Стартовый язык определяется автоматически по системным настройкам (как раньше).
//  - Пользователь может выбрать язык прямо в приложении. Выбор сохраняется в UserDefaults.
//  - Подмена бандла (`Bundle.setLanguage`) заставляет `NSLocalizedString` (а значит и
//    оператор `^`) читать строки из нужной `.lproj`-папки.
//  - `refreshToken` меняется при переключении; корневой `ContentView` завязан на него
//    через `.id(...)`, поэтому всё дерево SwiftUI перестраивается и перечитывает строки.
//

import Foundation
import SwiftUI

// MARK: - Подмена бандла

private var languageBundleKey: UInt8 = 0

/// Подкласс `Bundle`, который перенаправляет запросы строк в выбранную языковую `.lproj`.
private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &languageBundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Задаёт язык для `Bundle.main`. `nil` — вернуться к системному (автоопределению).
    static func setLanguage(_ language: String?) {
        // Один раз меняем класс main-бандла на наш подкласс.
        object_setClass(Bundle.main, LocalizedBundle.self)

        let value: Bundle?
        if let language,
           let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            value = bundle
        } else {
            value = nil
        }
        objc_setAssociatedObject(Bundle.main, &languageBundleKey, value, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - Доступные языки

/// Языки, для которых в проекте есть `.lproj` (см. knownRegions в pbxproj).
enum AppLanguage: String, CaseIterable, Identifiable {
    case ru
    case en
    case es
    case fr
    case uz
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    /// Название языка на самом языке — так принято показывать в списках выбора языка.
    var nativeName: String {
        switch self {
        case .ru:     return "Русский"
        case .en:     return "English"
        case .es:     return "Español"
        case .fr:     return "Français"
        case .uz:     return "Oʻzbekcha"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        }
    }
}

// MARK: - Менеджер языка

final class LanguageManager: ObservableObject {

    static let shared = LanguageManager()

    /// Ключ хранения выбранного языка. Отсутствие ключа = автоопределение по системе.
    private static let overrideKey = "appLanguageOverride"

    /// Текущий выбранный язык (`nil` — как в системе).
    @Published private(set) var current: AppLanguage?

    /// Токен обновления: смена значения перестраивает дерево SwiftUI через `.id(...)`.
    @Published private(set) var refreshToken = UUID()

    private init() {}

    /// Язык, который реально сейчас показывается (учитывая автоопределение).
    var effectiveLanguage: AppLanguage {
        if let current { return current }
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return AppLanguage(rawValue: preferred)
            ?? AppLanguage(rawValue: String(preferred.prefix(2)))
            ?? .en
    }

    /// Вызывать один раз при старте — до отрисовки UI. Восстанавливает сохранённый выбор.
    func setupAtLaunch() {
        if let raw = UserDefaults.standard.string(forKey: Self.overrideKey),
           let lang = AppLanguage(rawValue: raw) {
            current = lang
            Bundle.setLanguage(lang.rawValue)
        }
        // Если ничего не сохранено — оставляем системное автоопределение (подмена не нужна).
    }

    /// Применяет язык на лету. `nil` — вернуться к автоопределению по системе.
    func apply(_ language: AppLanguage?) {
        current = language

        if let language {
            UserDefaults.standard.set(language.rawValue, forKey: Self.overrideKey)
            Bundle.setLanguage(language.rawValue)
            // Чтобы системные форматтеры/диалоги совпали с выбором после перезапуска.
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: Self.overrideKey)
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            Bundle.setLanguage(nil)
        }

        refreshToken = UUID()
        NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
    }
}

extension Notification.Name {
    /// Отправляется при смене языка приложения на лету.
    static let appLanguageChanged = Notification.Name("appLanguageChanged")
}
