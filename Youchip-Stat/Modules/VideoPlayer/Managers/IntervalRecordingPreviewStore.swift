//
//  IntervalRecordingPreviewStore.swift
//  Youchip-Stat
//
//  «Призрачные» штампы интервальных тегов, которые ещё пишутся.
//

import Foundation
import SwiftUI

/// Активные интервальные записи для отрисовки на таймлайне.
///
/// Раньше интервальный тег появлялся на дорожке только по второму нажатию (когда штамп
/// уже создан) — то есть всё время записи на таймлайне не было ничего. Здесь лежит
/// «черновик» записи: по нему `IntervalRecordingPreviewOverlay` рисует растущий штамп
/// сразу после старта.
///
/// **Данных разметки это не трогает.** В `TimelineDataManager` по-прежнему попадает один
/// готовый штамп при остановке записи — превью живёт только на экране. Единственное
/// исключение — режим `tagBased`, где дорожка заводится на тег: её создаём заранее
/// (`ensureLines`), иначе рисовать растущий штамп негде. Если запись отменили, пустую
/// заведённую дорожку убираем (`cancelRecording`).
final class IntervalRecordingPreviewStore: ObservableObject {

    struct Item: Identifiable, Equatable {
        /// Совпадает с `TagLibraryView.ActiveIntervalTag.id`.
        let id: String
        let tagId: String
        let name: String
        let colorHex: String
        /// Левый край будущего штампа: время нажатия минус «время до» тега — ровно там,
        /// где окажется готовый штамп, чтобы при остановке ничего не прыгало.
        let visualStart: Double
        /// Запись идёт по плейхеду ПЕРЕСМОТРА (бирюзовому). Якорь фиксируется на старте: если
        /// посреди записи переключить «Разметка лайва / пересмотра», штамп продолжает расти за
        /// тем плейхедом, с которого начали, — как и его будущие границы.
        var usesReviewTime: Bool = false
        /// Явная дорожка для превью. Счётчики пишутся каждый на свою линию, там незачем искать
        /// строку по тегу/выделению. У тегов — nil.
        var lineID: UUID? = nil
    }

    static let shared = IntervalRecordingPreviewStore()

    /// Пишущиеся интервальные ТЕГИ (полностью пересобираются из `TagLibraryView.sync`).
    @Published private(set) var items: [Item] = []
    /// Пишущиеся СЧЁТЧИКИ — отдельный список: `sync` их не видит и не должен затирать.
    @Published private(set) var clockItems: [Item] = []

    /// Всё, что рисует оверлей.
    var allItems: [Item] { items + clockItems }

    // MARK: - Счётчики

    /// Счётчик запустили: показать растущий штамп на его линии.
    func beginClockRecording(_ item: Item) {
        if let index = clockItems.firstIndex(where: { $0.id == item.id }) {
            guard clockItems[index] != item else { return }
            clockItems[index] = item
        } else {
            clockItems.append(item)
        }
    }

    /// Счётчик сбросили: превью снимаем — вместо него на дорожке появляется готовый штамп.
    func endClockRecording(clockId: String) {
        guard clockItems.contains(where: { $0.id == clockId }) else { return }
        clockItems.removeAll { $0.id == clockId }
    }

    func resetClockRecordings() {
        guard !clockItems.isEmpty else { return }
        clockItems = []
    }

    /// Дорожки, заведённые ради превью (режим «таймлайн на тег»): tagId → lineID.
    /// Нужны только чтобы убрать пустую дорожку, если запись отменили.
    private var autoCreatedLines: [String: UUID] = [:]

    private init() {}

    /// Приводит превью к текущему списку активных записей. Вызывается из `TagLibraryView`
    /// на любое изменение `activeIntervalTags` — старт, стоп, отмена, смена времени начала.
    func sync(_ newItems: [Item]) {
        ensureLines(for: newItems)
        // Забываем дорожки записей, которые уже закончились: удалять их нельзя — штамп
        // как раз в них и лёг.
        let activeTagIds = Set(newItems.map(\.tagId))
        autoCreatedLines = autoCreatedLines.filter { activeTagIds.contains($0.key) }

        guard items != newItems else { return }
        items = newItems
    }

    /// Запись отменили (закрыли лист лейблов «Отменой») — штампа не будет, значит и
    /// заведённая под него пустая дорожка не нужна. Вызывать ДО очистки `activeIntervalTags`.
    func cancelRecording(tagId: String) {
        guard let lineID = autoCreatedLines.removeValue(forKey: tagId) else { return }
        let timelineData = TimelineDataManager.shared
        guard let line = timelineData.lines.first(where: { $0.id == lineID }),
              line.stamps.isEmpty else { return }
        timelineData.removeLine(lineID: lineID)
    }

    /// Полный сброс — при выходе из проекта/закрытии окна разметки.
    /// Полный сброс ТЕГОВЫХ превью. Счётчики сюда не входят: они переживают закрытие окна
    /// разметки (продолжают идти), и при следующем открытии их растущие штампы должны быть на
    /// месте. Счётчики снимает `ClockTimelineRecorder` — по сбросу или финализации.
    func reset() {
        autoCreatedLines.removeAll()
        guard !items.isEmpty else { return }
        items = []
    }

    /// В режиме `tagBased` штамп ложится в дорожку своего тега (`findOrCreateTimelineForTag`),
    /// и до первого штампа её просто нет. Заводим заранее, чтобы растущему штампу было где
    /// рисоваться; в `standard` дорожку выбирает пользователь — там ничего не создаём.
    private func ensureLines(for newItems: [Item]) {
        guard MarkupMode.current == .tagBased else { return }
        let timelineData = TimelineDataManager.shared
        for item in newItems {
            guard timelineData.lines.contains(where: { $0.tagIdForMode == item.tagId }) == false else { continue }
            guard let tag = TagLibraryManager.shared.findTagById(item.tagId) else { continue }
            let lineID = timelineData.findOrCreateTimelineForTag(tag: tag)
            autoCreatedLines[item.tagId] = lineID
        }
    }
}
