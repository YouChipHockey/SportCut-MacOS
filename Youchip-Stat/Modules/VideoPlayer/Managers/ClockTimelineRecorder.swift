//
//  ClockTimelineRecorder.swift
//  Youchip-Stat
//
//  Пишет работу секундомеров/таймеров в разметку: сеанс «пуск → сброс» становится ОДНИМ штампом
//  на линии ЭТОГО счётчика (у каждого своя, как у тега в режиме «таймлайн на тег»). Имя линии —
//  подпись счётчика, а если её нет — название. Линии видны по умолчанию, ⌘⌃0 скрывает/показывает.
//
//  ЖИВОЙ ШТАМП. Пока сеанс идёт, на линии живёт ТОТ ЖЕ САМЫЙ штамп (по фиксированному id), который
//  обновляется ~раз в секунду: растут границы и опорные точки хода. Поэтому таймер, идущий 30 минут,
//  можно пересматривать/смотреть в любой момент без сброса — данные уже на таймлайне. Сброс лишь
//  дописывает последнюю точку в тот же штамп. Новый штамп на каждую секунду НЕ создаётся.
//
//  Зачем: имея границы отрезка в ВРЕМЕНИ ВИДЕО и показания счётчика (опорные точки), мы позже
//  восстанавливаем счётчик в пересмотре момента и в экспорте — без обращения к коллекции.
//

import Foundation
import SwiftUI

final class ClockTimelineRecorder {

    static let shared = ClockTimelineRecorder()

    /// Открытый сеанс счётчика: пуск был, сброса ещё нет. Копит опорные точки хода и держит id
    /// живого штампа на таймлайне, который обновляется по ходу сеанса.
    private struct OpenSession {
        let entity: ClockEntity
        var keyframes: [ClockKeyframe]
        let stampID: UUID
        let lineID: UUID
        /// Время видео последней записи живого штампа — для троттлинга ~1 c.
        var lastWriteVideoTime: Double
    }

    private var sessions: [String: OpenSession] = [:]
    /// Обновлять живой штамп не чаще, чем раз в столько секунд ВРЕМЕНИ ВИДЕО.
    private let liveWriteInterval: Double = 1.0

    private init() {}

    // MARK: - Запись (ОДИН живой штамп на сеанс)

    /// Пуск: открыть сеанс с первой опорной точкой и завести живой штамп на линии счётчика.
    /// `usesReviewTime` больше не нужен записи (границы уже посчитаны по нужной шкале в
    /// `ClockRuntimeManager`), параметр оставлен для совместимости вызова.
    func beginSession(clock: ClockEntity, value: Double, videoTime: Double, usesReviewTime: Bool = false) {
        let stampID = UUID()
        Self.onMain {
            let lineID = Self.ensureClockTimelineExists(for: clock)
            let session = OpenSession(
                entity: clock,
                keyframes: [ClockKeyframe(videoTime: videoTime, value: value)],
                stampID: stampID,
                lineID: lineID,
                lastWriteVideoTime: videoTime
            )
            self.sessions[clock.id] = session
            self.commit(session, tip: nil)
            // ПЛАВНЫЙ рост: поверх реального штампа (который обновляется раз в секунду и потому
            // «скачет») кладём растущий «призрачный» штамп — тот же, что у пишущегося интервального
            // тега. Он тянется к плейхеду на 30 Гц и прячет ступеньки реального штампа под собой,
            // а реальный штамп остаётся ради пересмотра на ходу.
            IntervalRecordingPreviewStore.shared.beginClockRecording(
                IntervalRecordingPreviewStore.Item(
                    id: clock.id,
                    tagId: clock.id,
                    name: Self.displayName(for: clock),
                    colorHex: ClockTimelineConstants.stampColorHex,
                    visualStart: videoTime,
                    usesReviewTime: usesReviewTime,
                    lineID: lineID
                )
            )
        }
    }

    /// Граница участка (пауза / снятие паузы): добавить опорную точку и сразу обновить штамп.
    func addKeyframe(clockId: String, value: Double, videoTime: Double) {
        Self.onMain {
            guard var session = self.sessions[clockId] else { return }
            session.keyframes.append(ClockKeyframe(videoTime: videoTime, value: value))
            session.lastWriteVideoTime = videoTime
            self.sessions[clockId] = session
            self.commit(session, tip: nil)
        }
    }

    /// Тик по ходу сеанса (из `ClockRuntimeManager` на каждое изменение времени видео). Обновляет
    /// живой штамп не чаще раза в секунду: тянет «носик» (текущее время → текущее показание).
    func tickLiveStamp(clockId: String, value: Double, videoTime: Double) {
        Self.onMain {
            guard var session = self.sessions[clockId] else { return }
            guard abs(videoTime - session.lastWriteVideoTime) >= self.liveWriteInterval else { return }
            session.lastWriteVideoTime = videoTime
            self.sessions[clockId] = session
            self.commit(session, tip: ClockKeyframe(videoTime: videoTime, value: value))
        }
    }

    /// Сброс: дописать последнюю точку в ТОТ ЖЕ штамп и закрыть сеанс.
    func endSession(clockId: String, value: Double, videoTime: Double) {
        Self.onMain {
            // Реальный штамп сперва дописываем до конца, ПОТОМ снимаем призрак — в один проход
            // рендера, поэтому подмены «призрак → готовый штамп» на глаз не видно.
            guard var session = self.sessions.removeValue(forKey: clockId) else {
                IntervalRecordingPreviewStore.shared.endClockRecording(clockId: clockId)
                return
            }
            session.keyframes.append(ClockKeyframe(videoTime: videoTime, value: value))
            let times = session.keyframes.map(\.videoTime)
            // Слишком короткий сеанс — убираем живой штамп совсем.
            if let minT = times.min(), let maxT = times.max(), maxT - minT > 0.04 {
                self.commit(session, tip: nil)
            } else {
                self.removeStamp(stampID: session.stampID, lineID: session.lineID)
            }
            IntervalRecordingPreviewStore.shared.endClockRecording(clockId: clockId)
        }
    }

    /// Незакрытые сеансы (выход из проекта/смена видео): `finalizeAll()` уже дописал активные
    /// счётчики через `endSession`. Оставшиеся живые штампы уже лежат на таймлайне — не трогаем.
    func dropOpenIntervals() {
        Self.onMain {
            self.sessions.removeAll()
            IntervalRecordingPreviewStore.shared.resetClockRecordings()
        }
    }

    // MARK: - Внутреннее

    /// Собрать/обновить живой штамп сеанса (по фиксированному id) на его линии. `tip` — текущий
    /// «носик» (для идущего/паузного счётчика между опорными точками), nil на границах и сбросе.
    private func commit(_ session: OpenSession, tip: ClockKeyframe?) {
        var kfs = session.keyframes
        if let tip { kfs.append(tip) }
        let sorted = kfs.sorted { $0.videoTime < $1.videoTime }
        guard let minT = sorted.first?.videoTime, let maxT = sorted.last?.videoTime else { return }
        let entity = session.entity

        let info = StampClockInfo(
            clockId: entity.id,
            name: entity.name,
            mode: entity.mode,
            appearance: entity.appearance,
            showCentiseconds: entity.showCentiseconds,
            caption: entity.caption,
            showOnVideo: entity.showOnVideo,
            startValue: sorted.first?.value ?? 0,
            endValue: sorted.last?.value ?? 0,
            keyframes: sorted
        )

        let stamp = TimelineStamp(
            id: session.stampID,
            tagRefs: [StampTagRef(id: entity.id, tagGroupId: ClockTimelineConstants.clocksGroupID)],
            primaryID: entity.id,
            timeStartSeconds: minT,
            timeFinishSeconds: maxT,
            colorHex: ClockTimelineConstants.stampColorHex,
            label: Self.displayName(for: entity),
            labels: [],
            clockInfo: info
        )

        let timelineData = TimelineDataManager.shared
        guard let li = timelineData.lines.firstIndex(where: { $0.id == session.lineID }) else { return }
        if let si = timelineData.lines[li].stamps.firstIndex(where: { $0.id == session.stampID }) {
            timelineData.lines[li].stamps[si] = stamp
        } else {
            timelineData.lines[li].stamps.append(stamp)
            timelineData.lines[li].stamps.sort { $0.timeStartSeconds < $1.timeStartSeconds }
        }
        timelineData.updateTimelines()
    }

    private func removeStamp(stampID: UUID, lineID: UUID) {
        let timelineData = TimelineDataManager.shared
        guard let li = timelineData.lines.firstIndex(where: { $0.id == lineID }) else { return }
        let before = timelineData.lines[li].stamps.count
        timelineData.lines[li].stamps.removeAll { $0.id == stampID }
        if timelineData.lines[li].stamps.count != before { timelineData.updateTimelines() }
    }

    /// Таймлайны — главный поток. Синхронно, если мы уже на нём: при финализации лайва снимок
    /// разметки берут сразу после `finalizeAll`, и отложить запись нельзя.
    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Имя счётчика для разметки: подпись, а если её нет — название.
    static func displayName(for clock: ClockEntity) -> String {
        clock.caption.isEmpty ? clock.name : clock.caption
    }

    /// Линия ЭТОГО счётчика: своя у каждого, стоит в блоке служебных линий под рисунками.
    /// Имя держим в актуальном виде — переименовали счётчик или задали подпись, линия догоняет.
    @discardableResult
    static func ensureClockTimelineExists(for clock: ClockEntity) -> UUID {
        let timelineData = TimelineDataManager.shared
        let name = displayName(for: clock)

        if let existing = timelineData.lines.firstIndex(where: { $0.clockId == clock.id }) {
            if timelineData.lines[existing].name != name {
                timelineData.lines[existing].name = name
                timelineData.updateTimelines()
            }
            return timelineData.lines[existing].id
        }

        // Старый проект с единой линией счётчиков: продолжаем писать в неё, чтобы уже записанное
        // и новое не разъезжались по разным дорожкам.
        if let legacy = timelineData.lines.firstIndex(where: { $0.id == ClockTimelineConstants.clocksTimelineID }) {
            return timelineData.lines[legacy].id
        }

        let line = TimelineLine(
            name: name,
            stamps: [],
            tagIdForMode: "",
            clockId: clock.id
        )
        timelineData.lines.insert(line, at: min(insertionIndex(in: timelineData.lines), timelineData.lines.count))
        timelineData.updateTimelines()
        return line.id
    }

    /// Сразу после линии рисунков и уже заведённых линий счётчиков, а если их нет — самой первой.
    private static func insertionIndex(in lines: [TimelineLine]) -> Int {
        if let lastClock = lines.lastIndex(where: { $0.isClocksTimeline }) { return lastClock + 1 }
        if let drawings = lines.firstIndex(where: { $0.isDrawingsTimeline }) { return drawings + 1 }
        return 0
    }
}
