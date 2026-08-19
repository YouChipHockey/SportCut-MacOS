//
//  SportCutClockSnapshot.swift
//  Youchip-Stat
//
//  Счётчики, пришитые к клипу плейлиста.
//
//  Правило: клип плейлиста сохраняется ВСЕГДА и СО ВСЕМ — рисунки, комментарии, счётчики — и
//  продолжает работать, даже если проект/разметку, откуда его вытащили, снесли (без исходника
//  нельзя менять только длину клипа). Записи счётчиков живут в разметке источника, поэтому при
//  добавлении клипа в плейлист мы копируем их в само событие (`SportCutEvent.clockRecords`)
//  в «плоском» виде `ClockRecordSnapshot`: показания + границы в времени исходника.
//
//  Пока источник в сессии жив — показываем и экспортируем по его СВЕЖИМ дорожкам (там правки
//  разметки и ресайз штампов). Как только записей в источнике не стало (проект удалён, разметка
//  снесена) — берём снимок клипа. Точных соответствий он не знает и не должен: показаний и границ
//  хватает, чтобы счётчик шёл ровно так, как шёл вживую.
//

import Foundation

enum SportCutClockSnapshotBuilder {

    /// Запас по краям клипа для снимка: клип можно потянуть за край, и запись, лежавшая рядом,
    /// должна остаться доступной. Сам снимок при живом источнике всё равно обновляется.
    private static let clipMargin: Double = 60

    // MARK: - Primary Counter момента

    /// Primary Counter тега этого момента. Порядок: сохранённый в штампе id → снимок тегов
    /// ИСТОЧНИКА (он едет вместе с сессией и работает без коллекции) → глобальный пул приложения.
    static func primaryClockIds(forStamp stamp: TimelineStamp?, mainTagID: String?, source: SportCutSource?) -> Set<String> {
        var result = Set<String>()
        if let pc = stamp?.primaryClockId, !pc.isEmpty { return [pc] }

        var tagIds: [String] = stamp?.idTags ?? []
        if let mainTagID, !mainTagID.isEmpty, !tagIds.contains(mainTagID) { tagIds.append(mainTagID) }

        for tagId in tagIds {
            if let pc = source?.findTag(byID: tagId)?.primaryClockId, !pc.isEmpty {
                result.insert(pc)
                continue
            }
            if let pc = TagLibraryManager.shared.primaryClockId(forTagId: tagId), !pc.isEmpty {
                result.insert(pc)
            }
        }
        return result
    }

    /// Штамп события в дорожках источника (события ссылаются на разметку по `stampID`).
    static func sourceStamp(for event: SportCutEvent, source: SportCutSource?) -> TimelineStamp? {
        guard let source else { return nil }
        for line in source.timelines where !line.isServiceTimeline {
            if let stamp = line.stamps.first(where: { $0.id == event.stampID }) { return stamp }
        }
        return nil
    }

    // MARK: - Снимок для клипа

    /// Записи счётчиков, которые нужно пришить к клипу штампа.
    static func records(forStamp stamp: TimelineStamp, source: SportCutSource, clipStart: Double, clipFinish: Double) -> [ClockRecordSnapshot]? {
        let primary = primaryClockIds(forStamp: stamp, mainTagID: stamp.idTag, source: source)
        return filtered(
            source.timelines.clockRecordSnapshots(primaryClockIds: primary),
            clipStart: clipStart,
            clipFinish: clipFinish
        )
    }

    private static func filtered(_ records: [ClockRecordSnapshot], clipStart: Double, clipFinish: Double) -> [ClockRecordSnapshot]? {
        guard !records.isEmpty else { return nil }
        let from = clipStart - clipMargin
        let to = clipFinish + clipMargin
        // Только видимое на клипе (свой флаг или Primary Counter момента) — чтобы не таскать
        // в сессии счётчики соседних тегов.
        let result = records.filter { $0.finish >= from && $0.start <= to && $0.isVisibleOnVideo }
        return result.isEmpty ? nil : result
    }

    // MARK: - Что показывать/наносить

    /// Записи счётчиков клипа для оверлея и экспорта: свежие из источника, а если разметки уже
    /// нет — пришитый к клипу снимок.
    static func resolvedRecords(for event: SportCutEvent, source: SportCutSource?) -> [ClockRecordSnapshot] {
        if let source, !source.timelines.clockStamps.isEmpty {
            let stamp = sourceStamp(for: event, source: source)
            let primary = primaryClockIds(forStamp: stamp, mainTagID: event.mainTagID, source: source)
            return source.timelines.clockRecordSnapshots(primaryClockIds: primary)
        }
        return event.clockRecords ?? []
    }
}
