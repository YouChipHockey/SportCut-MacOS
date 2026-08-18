//
//  ClockRuntimeManager.swift
//  Youchip-Stat
//
//  Движок секундомеров/таймеров: считает РЕАЛЬНОЕ время, пока счётчик активен. Активация —
//  как у интервального тега (клик по кнопке холста или связка). Следа на таймлайне не оставляет.
//  Значения публикуются в `displaySeconds`, чтобы кнопки холста и оверлей на видео обновлялись.
//

import Foundation
import Combine

final class ClockRuntimeManager: ObservableObject {

    static let shared = ClockRuntimeManager()

    /// Текущее отображаемое значение (сек) по каждому счётчику — обновляется тикером ~20 Гц.
    @Published private(set) var displaySeconds: [String: Double] = [:]
    /// Идущие сейчас счётчики (для подсветки активной кнопки).
    @Published private(set) var activeIDs: Set<String> = []
    /// Счётчики текущей коллекции (чтобы оверлей на видео не пробрасывать через дерево вью).
    @Published private(set) var registeredClocks: [ClockEntity] = []

    private struct RuntimeState {
        var entity: ClockEntity
        /// Накоплено секунд активности (без учёта текущего запущенного отрезка).
        var accumulated: Double
        /// Момент последнего запуска; nil — счётчик стоит.
        var lastResume: Date?
    }

    private var states: [String: RuntimeState] = [:]
    private var ticker: Timer?
    private let tickInterval: TimeInterval = 1.0 / 20.0

    /// Таймер добрался до нуля и настроен запускать свои связки (`firesBindingsOnZero`).
    /// Подключается в `TagLibraryView.wireRuntimeCallbacks` — сюда движок связок не тянем,
    /// чтобы счётчики оставались самостоятельными (их вид/тик не зависит от раскладки).
    var onReachedZero: ((_ clockId: String) -> Void)?

    private init() {}

    // MARK: - Registration

    /// Регистрирует/обновляет счётчики текущей коллекции, сохраняя уже накопленное состояние.
    func register(_ entities: [ClockEntity]) {
        registeredClocks = entities
        let ids = Set(entities.map(\.id))
        for entity in entities {
            if var st = states[entity.id] {
                st.entity = entity
                states[entity.id] = st
            } else {
                states[entity.id] = RuntimeState(entity: entity, accumulated: 0, lastResume: nil)
            }
            if let st = states[entity.id] {
                displaySeconds[entity.id] = value(for: st)
            }
        }
        for id in Array(states.keys) where !ids.contains(id) {
            states[id] = nil
            displaySeconds[id] = nil
            activeIDs.remove(id)
        }
        updateTicker()
    }

    // MARK: - Control

    func isActive(_ id: String) -> Bool { states[id]?.lastResume != nil }

    func toggle(_ id: String) { isActive(id) ? stop(id) : start(id) }

    func start(_ id: String) {
        guard var st = states[id], st.lastResume == nil else { return }
        // Таймер, уже дошедший до нуля, при запуске начинает заново.
        if st.entity.mode == .timer, value(for: st) <= 0 { st.accumulated = 0 }
        st.lastResume = Date()
        states[id] = st
        activeIDs.insert(id)
        // Отрезок работы счётчика уходит в разметку (скрытый таймлайн счётчиков).
        ClockTimelineRecorder.shared.began(clock: st.entity, value: value(for: st))
        updateTicker()
    }

    func stop(_ id: String) {
        guard var st = states[id], let resumed = st.lastResume else { return }
        st.accumulated += Date().timeIntervalSince(resumed)
        st.lastResume = nil
        states[id] = st
        activeIDs.remove(id)
        displaySeconds[id] = value(for: st)
        ClockTimelineRecorder.shared.finished(clockId: id, value: value(for: st))
        updateTicker()
    }

    func reset(_ id: String) {
        guard var st = states[id] else { return }
        st.accumulated = 0
        if st.lastResume != nil { st.lastResume = Date() }
        states[id] = st
        displaySeconds[id] = value(for: st)
    }

    /// Сброс с остановкой (значение возвращается к стартовому, счётчик стоит).
    func stopAndReset(_ id: String) {
        stop(id)
        reset(id)
    }

    /// Ставит на паузу ВСЕ идущие счётчики, сохраняя накопленное. Нужно там, где разметка
    /// уходит из-под рук пользователя: выход из проекта, открытие редактора — счётчик не должен
    /// продолжать тикать в фоне (иначе, вернувшись, пользователь видит «уехавшее» время).
    func pauseAll() {
        for id in Array(activeIDs) { stop(id) }
    }

    /// Текущее значение (сек). Секундомер — накоплено; таймер — max(0, initial − накоплено).
    func currentSeconds(_ id: String) -> Double {
        guard let st = states[id] else { return 0 }
        return value(for: st)
    }

    /// Доля заполнения для кольца (0…1). Таймер — остаток/initial; секундомер — доля текущей минуты.
    func progressFraction(_ id: String) -> Double {
        guard let st = states[id] else { return 0 }
        switch st.entity.mode {
        case .timer:
            guard st.entity.initialSeconds > 0 else { return 0 }
            return min(1, max(0, value(for: st) / st.entity.initialSeconds))
        case .stopwatch:
            return (value(for: st).truncatingRemainder(dividingBy: 60)) / 60
        }
    }

    // MARK: - Internals

    private func liveAccumulated(_ st: RuntimeState) -> Double {
        var acc = st.accumulated
        if let resumed = st.lastResume { acc += Date().timeIntervalSince(resumed) }
        return acc
    }

    private func value(for st: RuntimeState) -> Double {
        let acc = liveAccumulated(st)
        switch st.entity.mode {
        case .stopwatch: return acc
        case .timer:     return max(0, st.entity.initialSeconds - acc)
        }
    }

    private func updateTicker() {
        let hasActive = !activeIDs.isEmpty
        if hasActive, ticker == nil {
            let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        } else if !hasActive, ticker != nil {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func tick() {
        var reachedZero: [String] = []
        for id in activeIDs {
            guard let st = states[id] else { continue }
            let v = value(for: st)
            displaySeconds[id] = v
            if st.entity.mode == .timer, v <= 0 { reachedZero.append(id) }
        }
        for id in reachedZero { handleReachedZero(id) }
    }

    /// Обратный отсчёт дошёл до нуля: применяем авто-действие объекта и, если включено,
    /// запускаем его исходящие связки (таймер как источник цепочки).
    private func handleReachedZero(_ id: String) {
        guard let st = states[id] else { return }
        let entity = st.entity

        switch entity.zeroAction {
        case .stop:
            stop(id)
        case .reset:
            stopAndReset(id)
        case .restart:
            // Нулевой initial зациклил бы «достижение нуля» на каждом тике — такой таймер просто стоит.
            if entity.initialSeconds > 0 { restartCycle(id) } else { stop(id) }
        }

        if entity.firesBindingsOnZero {
            onReachedZero?(id)
        }
    }

    /// Новый круг обратного отсчёта без остановки.
    private func restartCycle(_ id: String) {
        guard var st = states[id] else { return }
        st.accumulated = 0
        st.lastResume = Date()
        states[id] = st
        displaySeconds[id] = value(for: st)
    }
}
