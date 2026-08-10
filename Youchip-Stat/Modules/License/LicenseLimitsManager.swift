//
//  LicenseLimitsManager.swift
//  Youchip-Stat
//
//  Единый источник правды по лимитам бесплатного использования:
//  • разметка — 3 бесплатных видео (импорт / лайв-запись / дозапись / merge);
//  • режим просмотра — 3 бесплатные сессии (проекта просмотра).
//  При активной лицензии лимитов нет. Когда лимит исчерпан — соответствующие действия блокируются.
//

import Foundation
import Combine

final class LicenseLimitsManager: ObservableObject {

    static let shared = LicenseLimitsManager()

    // MARK: - Constants

    let maxFreeVideos = 3
    let maxFreeViewingSessions = 3

    private let addedVideosCountKey = "added_videos_count"
    private let addedViewingSessionsCountKey = "added_viewing_sessions_count"
    private let authDeadlineKey = "auth_deadline"

    // MARK: - Published counters (для авто-обновления бейджей)

    @Published private(set) var addedVideosCount: Int
    @Published private(set) var addedViewingSessionsCount: Int

    private init() {
        addedVideosCount = UserDefaults.standard.integer(forKey: addedVideosCountKey)
        addedViewingSessionsCount = UserDefaults.standard.integer(forKey: addedViewingSessionsCountKey)
    }

    // MARK: - License state

    /// Активна ли лицензия (или debug-сборка). Вычисляется из UserDefaults, чтобы быть доступной
    /// из любого модуля без экземпляра `AuthManager`.
    var isLicenseActive: Bool {
        if AppConfig.isDebug { return true }
        guard let deadlineString = UserDefaults.standard.string(forKey: authDeadlineKey),
              let deadline = Self.date(from: deadlineString) else { return false }
        return deadline > Date()
    }

    // MARK: - Markup videos (разметка)

    var remainingMarkupVideos: Int { max(0, maxFreeVideos - addedVideosCount) }

    /// Можно ли завести новое видео разметки (импорт / лайв / дозапись / merge).
    var canAddMarkupVideo: Bool { isLicenseActive || remainingMarkupVideos > 0 }

    /// Списывает 1 лимит видео разметки (только при неактивной лицензии).
    func consumeMarkupVideoIfNeeded() {
        guard !isLicenseActive else { return }
        addedVideosCount = UserDefaults.standard.integer(forKey: addedVideosCountKey) + 1
        UserDefaults.standard.set(addedVideosCount, forKey: addedVideosCountKey)
    }

    // MARK: - Viewing sessions (режим просмотра)

    var remainingViewingSessions: Int { max(0, maxFreeViewingSessions - addedViewingSessionsCount) }

    /// Можно ли создать новую сессию просмотра.
    var canCreateViewingSession: Bool { isLicenseActive || remainingViewingSessions > 0 }

    /// Можно ли добавлять источники в существующие сессии просмотра (не списывает лимит,
    /// но блокируется, когда лимиты исчерпаны и лицензия неактивна).
    var canModifyViewing: Bool { isLicenseActive || remainingViewingSessions > 0 }

    /// Списывает 1 лимит сессии просмотра (только при неактивной лицензии).
    func consumeViewingSessionIfNeeded() {
        guard !isLicenseActive else { return }
        addedViewingSessionsCount = UserDefaults.standard.integer(forKey: addedViewingSessionsCountKey) + 1
        UserDefaults.standard.set(addedViewingSessionsCount, forKey: addedViewingSessionsCountKey)
    }

    // MARK: - Helpers

    private static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter.date(from: string)
    }
}
