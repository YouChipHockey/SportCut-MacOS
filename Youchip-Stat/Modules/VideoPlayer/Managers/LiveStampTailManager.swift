//
//  LiveStampTailManager.swift
//  Youchip-Stat
//
//  Дозапись «хвостов» штампов в лайве: время после тега ещё не снято.
//

import Combine
import Foundation

/// Хвосты штампов, которые в лайве ещё не записаны.
///
/// В лайве видео пишется «прямо сейчас», поэтому `время после` тега физически не существует
/// в момент нажатия: раньше штамп просто обрезался (а с буфером `timelineDuration + 5` мог
/// ещё и залезть в неснятое). Теперь штамп кладётся по факту записанного, а недостающий
/// хвост дописывается по мере съёмки:
///
/// - пауза трансляции — `liveDuration` стоит, хвост не растёт;
/// - трансляцию остановили — в штампе остаётся ровно столько, сколько успело записаться;
/// - штамп (или его дорожку) удалили — хвост просто выбрасывается.
///
/// Растущая часть рисуется превью-слоем (`IntervalRecordingPreviewOverlay`) полупрозрачной,
/// а в данные разметки конец штампа пишется РЕДКО и целыми кусками:
///
/// - когда хвост дописан до конца;
/// - когда трансляцию поставили на паузу (пишем всё, что успело записаться);
/// - когда трансляцию остановили.
///
/// Промежуточных «подтягиваний» специально нет: иначе штамп на глазах докрашивался бы
/// кусками (пользователь видел бы полосатую дозапись), а мутация `TimelineDataManager.lines`
/// шла бы десятки раз в секунду и тянула перерисовку всего окна с дорожками.
final class LiveStampTailManager: ObservableObject {

    struct Tail: Identifiable, Equatable {
        /// id хвоста = id штампа: на один штамп больше одного хвоста быть не может.
        var id: UUID { stampID }
        let stampID: UUID
        let colorHex: String
        /// Конец штампа, до которого нужно дописать (время нажатия + «время после»).
        let desiredFinish: Double
    }

    static let shared = LiveStampTailManager()

    @Published private(set) var tails: [Tail] = []

    private var cancellables = Set<AnyCancellable>()

    private init() {}

    /// Ставит хвост в очередь на дозапись. Вызывается сразу после добавления штампа в лайве.
    func register(stampID: UUID, colorHex: String, desiredFinish: Double) {
        // Запись уже остановлена — дописывать нечего, в штампе остаётся записанное.
        guard LiveStreamManager.shared.isLive else { return }
        guard !tails.contains(where: { $0.stampID == stampID }) else { return }
        startObserving()
        tails.append(Tail(stampID: stampID, colorHex: colorHex, desiredFinish: desiredFinish))
    }

    /// Полный сброс без записи в данные — выход из проекта/окна разметки.
    func reset() {
        stopObserving()
        guard !tails.isEmpty else { return }
        tails = []
    }

    // MARK: - Подписки на трансляцию

    private func startObserving() {
        guard cancellables.isEmpty else { return }
        // 10 Гц — с этой частотой `LiveStreamManager` тикает длительность записи.
        LiveStreamManager.shared.$liveDuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recorded in self?.advance(recorded: recorded) }
            .store(in: &cancellables)
        LiveStreamManager.shared.$isLive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLive in
                guard !isLive else { return }
                self?.finalizeAll()
            }
            .store(in: &cancellables)
        // Пауза трансляции: дописываем в штампы всё, что успело записаться, но хвосты
        // оставляем — после снятия паузы они продолжат расти дальше.
        LiveStreamManager.shared.$isBroadcastPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPaused in
                guard isPaused else { return }
                self?.commitRecordedProgress()
            }
            .store(in: &cancellables)
    }

    private func stopObserving() {
        cancellables.removeAll()
    }

    // MARK: - Рост хвостов

    private func advance(recorded: Double) {
        guard !tails.isEmpty else { return }
        var completed: Set<UUID> = []

        for tail in tails {
            // Тик идёт 10 раз в секунду, поэтому пока хвост не дописан — только сравнение
            // чисел, без поиска штампа по всем дорожкам проекта.
            guard recorded >= tail.desiredFinish - 0.05 else { continue }
            // Штамп могли удалить (сам или вместе с дорожкой) — тогда хвост просто выбрасываем;
            // рисоваться он к этому моменту уже перестал.
            if let located = locate(stampID: tail.stampID) {
                commit(lineID: located.lineID, stamp: located.stamp, end: tail.desiredFinish)
            }
            completed.insert(tail.stampID)
        }

        guard !completed.isEmpty else { return }
        tails.removeAll { completed.contains($0.stampID) }
        if tails.isEmpty { stopObserving() }
    }

    /// Записывает в штампы то, что уже снято, не закрывая хвосты (пауза трансляции).
    private func commitRecordedProgress() {
        guard !tails.isEmpty else { return }
        let recorded = LiveStreamManager.shared.liveDuration
        for tail in tails {
            guard let located = locate(stampID: tail.stampID) else { continue }
            commit(lineID: located.lineID, stamp: located.stamp, end: min(tail.desiredFinish, recorded))
        }
    }

    /// Трансляция закончилась: в каждом штампе остаётся столько, сколько успело записаться.
    private func finalizeAll() {
        defer {
            tails = []
            stopObserving()
        }
        guard !tails.isEmpty else { return }
        let recorded = LiveStreamManager.shared.liveDuration
        for tail in tails {
            guard let located = locate(stampID: tail.stampID) else { continue }
            commit(lineID: located.lineID, stamp: located.stamp, end: min(tail.desiredFinish, recorded))
        }
    }

    /// Конец штампа только РАСТЁТ. `liveDuration` после остановки обнуляется, и без этой
    /// защиты финализация ужала бы штампы до нуля.
    private func commit(lineID: UUID, stamp: TimelineStamp, end: Double) {
        let newEnd = max(stamp.timeFinishSeconds, end)
        guard newEnd > stamp.timeFinishSeconds + 0.01 else { return }
        TimelineDataManager.shared.updateStampTime(
            lineID: lineID,
            stampID: stamp.id,
            newEnd: newEnd,
            persistChanges: true,
            // Штамп только удлиняется — отвязывать скриншоты не от чего, а проверка
            // перебирает все скриншоты проекта.
            runScreenshotUnlinkCheck: false
        )
    }

    private func locate(stampID: UUID) -> (lineID: UUID, stamp: TimelineStamp)? {
        for line in TimelineDataManager.shared.lines {
            if let stamp = line.stamps.first(where: { $0.id == stampID }) {
                return (line.id, stamp)
            }
        }
        return nil
    }
}
