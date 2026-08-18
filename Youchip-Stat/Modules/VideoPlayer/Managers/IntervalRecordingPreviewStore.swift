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
    }

    static let shared = IntervalRecordingPreviewStore()

    @Published private(set) var items: [Item] = []

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
