//
//  ClockVideoOverlayView.swift
//  Youchip-Stat
//
//  Секундомеры/таймеры поверх главного видео. Показываем ДВА источника (флага «показывать на
//  видео» больше нет):
//   1) счётчики, которые ПИШУТСЯ прямо сейчас — реальное время из `ClockRuntimeManager`;
//   2) записанные счётчики, чей отрезок ПЕРЕСЕКАЕТ плейхед — показания из записи на скрытом
//      таймлайне (`StampClockInfo`), интерполированные на текущее время видео (как в пересмотре
//      момента). Пример: включили секундомер в начале лайва — при пересмотре разметки он идёт
//      на видео всё то время, что шёл при записи.
//
//  Каждый счётчик можно таскать по кадру и менять размер — положение и масштаб хранит
//  `ClockOverlayLayoutStore` в долях кадра, по `clockId` (запись и «живой» счётчик одного объекта
//  делят одну позицию). Пока счётчик не трогали, он лежит в стопке в правом верхнем углу.
//

import SwiftUI

struct ClockVideoOverlayView: View {

    /// Экран, на котором висит оверлей: видео ПЕРЕСМОТРА (true) или основное/лайв (false).
    /// От него зависит и время (какой плейхед), и какие «живые» счётчики показывать: счётчик
    /// виден на экране ТОГО плейхеда, по которому его пишут (см. якорь в `ClockRuntimeManager`).
    var usesReviewTime: Bool = false

    @ObservedObject private var runtime = ClockRuntimeManager.shared
    /// Время плейхеда: по нему находим пересечённые записи и интерполируем их показания.
    @ObservedObject private var clock = PlaybackClock.shared
    @ObservedObject private var reviewClock = ReviewPlaybackClock.shared
    /// Записанные отрезки счётчиков живут на скрытом таймлайне — подписка нужна, чтобы новая
    /// запись появлялась/исчезала на видео сразу (в т.ч. на паузе).
    @ObservedObject private var timelineData = TimelineDataManager.shared

    /// Что показываем сейчас: пишущиеся счётчики + записи, пересечённые плейхедом.
    private func overlayItems() -> [ClockOverlayItem] {
        var result: [ClockOverlayItem] = []
        var seen = Set<String>()

        // 1. Пишутся прямо сейчас — реальное время из рантайма. Только «свои» (по якорю плейхеда)
        // и только с флагом «Показывать на видео».
        for entity in runtime.registeredClocks
        where entity.showOnVideo && runtime.isActive(entity.id) && runtime.isAnchoredToReview(entity.id) == usesReviewTime {
            let seconds = runtime.displaySeconds[entity.id] ?? (entity.mode == .timer ? entity.initialSeconds : 0)
            let progress: Double? = entity.appearance == .ring ? runtime.progressFraction(entity.id) : nil
            result.append(ClockOverlayItem(
                clockId: entity.id,
                seconds: seconds,
                appearance: entity.appearance,
                showCentiseconds: entity.showCentiseconds,
                caption: entity.caption,
                progress: progress
            ))
            seen.insert(entity.id)
        }

        // 2. Записи, чей отрезок пересекает плейхед ЭТОГО экрана — показания из записи
        // (пересматриваем момент, где шёл счётчик, — он идёт и на кадре).
        let t = usesReviewTime ? reviewClock.time : clock.time
        for stamp in timelineData.lines.clockStamps {
            guard let info = stamp.clockInfo, info.showOnVideo,
                  t >= stamp.timeStartSeconds, t <= stamp.timeFinishSeconds,
                  !seen.contains(info.clockId) else { continue }
            let seconds = info.value(atVideoTime: t, start: stamp.timeStartSeconds, finish: stamp.timeFinishSeconds)
            result.append(ClockOverlayItem(
                clockId: info.clockId,
                seconds: seconds,
                appearance: info.appearance,
                showCentiseconds: info.showCentiseconds,
                caption: info.caption,
                progress: nil
            ))
            seen.insert(info.clockId)
        }

        // Порядок стабильный (по clockId) — иначе стопка не-позиционированных прыгала бы.
        return result.sorted { $0.clockId < $1.clockId }
    }

    var body: some View {
        ClockOverlayCanvas(items: overlayItems())
    }
}
