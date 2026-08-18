//
//  ClockTimelineRecorder.swift
//  Youchip-Stat
//
//  Пишет работу секундомеров/таймеров в разметку: каждый отрезок «запустили → остановили»
//  становится штампом на скрытом таймлайне счётчиков (`ClockTimelineConstants`). По сути это
//  интервальный тег, просто линия не показывается пользователю без ⌘⌃0.
//
//  Зачем: имея границы отрезка в ВРЕМЕНИ ВИДЕО и показания счётчика на его концах, мы позже
//  восстанавливаем счётчик в пересмотре момента и в экспорте — без обращения к коллекции.
//

import Foundation
import SwiftUI

final class ClockTimelineRecorder {

    static let shared = ClockTimelineRecorder()

    /// Открытые отрезки: счётчик запущен, но ещё не остановлен.
    private struct OpenInterval {
        let videoStart: Double
        let startValue: Double
        let entity: ClockEntity
    }

    private var open: [String: OpenInterval] = [:]

    private init() {}

    // MARK: - Запись

    /// Счётчик запущен: запоминаем момент видео и показание — штамп появится по остановке.
    func began(clock: ClockEntity, value: Double) {
        guard let videoTime = currentVideoTime() else { return }
        open[clock.id] = OpenInterval(videoStart: videoTime, startValue: value, entity: clock)
    }

    /// Счётчик остановлен: закрываем отрезок штампом на скрытом таймлайне.
    func finished(clockId: String, value: Double) {
        guard let interval = open.removeValue(forKey: clockId),
              let videoTime = currentVideoTime() else { return }

        let start = min(interval.videoStart, videoTime)
        let finish = max(interval.videoStart, videoTime)
        // Мгновенные включения-выключения (меньше кадра) в разметке бессмысленны.
        guard finish - start > 0.04 else { return }

        let entity = interval.entity
        let info = StampClockInfo(
            clockId: entity.id,
            name: entity.name,
            mode: entity.mode,
            appearance: entity.appearance,
            showCentiseconds: entity.showCentiseconds,
            caption: entity.caption,
            startValue: interval.startValue,
            endValue: value
        )

        let stamp = TimelineStamp(
            tagRefs: [StampTagRef(id: entity.id, tagGroupId: ClockTimelineConstants.clocksGroupID)],
            primaryID: entity.id,
            timeStartSeconds: start,
            timeFinishSeconds: finish,
            colorHex: ClockTimelineConstants.stampColorHex,
            label: entity.caption.isEmpty ? entity.name : "\(entity.name) — \(entity.caption)",
            labels: [],
            clockInfo: info
        )

        DispatchQueue.main.async {
            let timelineData = TimelineDataManager.shared
            let lineID = Self.ensureClocksTimelineExists()
            guard let index = timelineData.lines.firstIndex(where: { $0.id == lineID }) else { return }
            timelineData.lines[index].stamps.append(stamp)
            timelineData.lines[index].stamps.sort { $0.timeStartSeconds < $1.timeStartSeconds }
            timelineData.updateTimelines()
        }
    }

    /// Незакрытые отрезки (выход из проекта/смена видео) — просто забываем: счётчики к этому
    /// моменту уже остановлены `pauseAll()`, а он проходит через `finished`.
    func dropOpenIntervals() {
        open.removeAll()
    }

    // MARK: - Внутреннее

    /// Текущее время видео разметки. nil — видео нет, писать некуда.
    private func currentVideoTime() -> Double? {
        guard VideoPlayerManager.shared.player != nil else { return nil }
        return VideoPlayerManager.shared.currentTime
    }

    /// Линия счётчиков стоит сразу под линией рисунков: обе служебные и всегда наверху списка.
    @discardableResult
    static func ensureClocksTimelineExists() -> UUID {
        let timelineData = TimelineDataManager.shared
        let clocksID = ClockTimelineConstants.clocksTimelineID
        if let existing = timelineData.lines.firstIndex(where: { $0.id == clocksID }) {
            let target = insertionIndex(in: timelineData.lines)
            if existing != target {
                let line = timelineData.lines.remove(at: existing)
                timelineData.lines.insert(line, at: min(target, timelineData.lines.count))
                timelineData.updateTimelines()
            }
            return clocksID
        }

        let line = TimelineLine(
            id: clocksID,
            name: ClockTimelineConstants.clocksTimelineName,
            stamps: [],
            tagIdForMode: ""
        )
        timelineData.lines.insert(line, at: min(insertionIndex(in: timelineData.lines), timelineData.lines.count))
        timelineData.updateTimelines()
        return clocksID
    }

    /// Сразу после линии рисунков, а если её нет — самой первой.
    private static func insertionIndex(in lines: [TimelineLine]) -> Int {
        if let drawings = lines.firstIndex(where: { $0.isDrawingsTimeline }) { return drawings + 1 }
        return 0
    }
}
