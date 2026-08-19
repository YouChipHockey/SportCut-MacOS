//
//  ClockRuntimeManager.swift
//  Youchip-Stat
//
//  Движок секундомеров/таймеров. Считает ВРЕМЯ ВИДЕО (а не реальное) — как интервальный тег:
//  при ускоренном просмотре идёт быстрее, при перемотке прыгает вперёд/назад, на паузе видео
//  замирает. Плюс у счётчика есть СВОЯ пауза (заморозка): пока он на своей паузе, он всё ещё
//  активен и пишется на таймлайн, но значение не меняется, что бы ни делали с видео, — до
//  снятия паузы. Единственное, что прекращает запись, — СБРОС.
//
//  Три состояния счётчика:
//   • простаивает (recording=false) — сброшен, на таймлайн не пишется;
//   • идёт (recording=true, runningSinceVideo!=nil) — следует за временем видео;
//   • на своей паузе (recording=true, runningSinceVideo==nil) — значение заморожено, но пишется.
//
//  Значения публикуются в `displaySeconds` (пересчёт по тику часов видео).
//
//  ЯКОРЬ ЗАПИСИ. Как и у интервального тега, счётчик запоминает при пуске, по какому плейхеду его
//  пишут: лайв (белый) или пересмотр (бирюзовый, режим «Разметка пересмотра», Opt+W). Дальше он
//  живёт по ЭТОЙ шкале до самого сброса — переключение режима посреди сеанса якорь не меняет,
//  иначе показания и границы отрезка склеились бы из двух разных времён.
//

import Foundation
import Combine

final class ClockRuntimeManager: ObservableObject {

    static let shared = ClockRuntimeManager()

    /// Текущее отображаемое значение (сек) по каждому счётчику.
    @Published private(set) var displaySeconds: [String: Double] = [:]
    /// Активные (пишущиеся) счётчики: идущие И на своей паузе.
    @Published private(set) var activeIDs: Set<String> = []
    /// Счётчики текущей коллекции (чтобы оверлей на видео не пробрасывать через дерево вью).
    @Published private(set) var registeredClocks: [ClockEntity] = []

    private struct RuntimeState {
        var entity: ClockEntity
        /// Накоплено ВИДЕО-секунд за завершённые отрезки бега (без учёта текущего отрезка).
        var accumulated: Double
        /// Пишется ли счётчик сейчас (идёт или на своей паузе). false — сброшен/простаивает.
        var recording: Bool
        /// Видео-время начала текущего идущего отрезка. nil при recording — счётчик на своей паузе.
        var runningSinceVideo: Double?
        /// По какому плейхеду идёт ЭТОТ сеанс: пересмотр (true) или лайв/обычное видео (false).
        /// Снимается на пуске из простоя и держится до сброса.
        var usesReviewTime: Bool = false
    }

    private var states: [String: RuntimeState] = [:]
    private var timeCancellable: AnyCancellable?
    private var reviewTimeCancellable: AnyCancellable?

    /// Таймер добрался до нуля и настроен запускать свои связки (`firesBindingsOnZero`).
    var onReachedZero: ((_ clockId: String) -> Void)?

    /// Сменилось состояние ИГРЫ счётчика (плей=активирован / пауза=деактивирован; сброс из «идёт»
    /// тоже деактивация). Пауза и снятие с паузы зеркалятся так же, как старт/остановка. Нужен
    /// связкам «синхронизация состояния». Подавляется на `finalizeAll`.
    var onStateChanged: ((_ clockId: String, _ isActive: Bool) -> Void)?

    private var suppressStateChanged = false

    private init() {
        // Тик по ВРЕМЕНИ ВИДЕО: на каждое изменение времени пересчитываем идущие счётчики. На паузе
        // видео часы не публикуют — значит счётчики сами замирают, отдельного кода не надо.
        // Подписаны ОБЕ шкалы: счётчик, запущенный по плейхеду пересмотра, тикает по нему.
        timeCancellable = PlaybackClock.shared.$time
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshRunning() }
        reviewTimeCancellable = ReviewPlaybackClock.shared.$time
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshRunning() }
    }

    /// Время разметки по умолчанию (для простаивающих счётчиков и регистрации) — по текущему режиму.
    private var videoTime: Double { VideoPlayerManager.shared.markupTime }

    /// Время видео для КОНКРЕТНОГО счётчика — по якорю его сеанса.
    private func videoTime(for st: RuntimeState) -> Double {
        VideoPlayerManager.shared.markupTime(usesReview: st.usesReviewTime)
    }

    // MARK: - Registration

    /// Регистрирует/обновляет счётчики текущей коллекции, сохраняя уже накопленное состояние.
    func register(_ entities: [ClockEntity]) {
        registeredClocks = entities
        let ids = Set(entities.map(\.id))
        let vt = videoTime
        for entity in entities {
            if var st = states[entity.id] {
                st.entity = entity
                states[entity.id] = st
            } else {
                states[entity.id] = RuntimeState(entity: entity, accumulated: 0, recording: false, runningSinceVideo: nil)
            }
            if let st = states[entity.id] {
                displaySeconds[entity.id] = value(for: st, atVideoTime: vt)
            }
        }
        for id in Array(states.keys) where !ids.contains(id) {
            states[id] = nil
            displaySeconds[id] = nil
            activeIDs.remove(id)
        }
    }

    // MARK: - State queries

    /// Пишется ли счётчик (идёт ИЛИ на своей паузе).
    func isActive(_ id: String) -> Bool { states[id]?.recording ?? false }

    /// По какому плейхеду пишется этот счётчик: пересмотр (true) или лайв/обычное видео (false).
    /// Нужен оверлею на видео — «живой» счётчик показывается на экране СВОЕГО плейхеда.
    func isAnchoredToReview(_ id: String) -> Bool { states[id]?.usesReviewTime ?? false }

    /// Идёт ли счётчик прямо сейчас (не на своей паузе).
    func isRunning(_ id: String) -> Bool {
        guard let st = states[id] else { return false }
        return st.recording && st.runningSinceVideo != nil
    }

    // MARK: - Control

    /// Клик по счётчику: простаивает → пуск; идёт → на паузу; на паузе → снять с паузы.
    func toggle(_ id: String) {
        guard let st = states[id] else { return }
        if !st.recording {
            activate(id)
        } else if st.runningSinceVideo != nil {
            pause(id)
        } else {
            activate(id)
        }
    }

    /// Включить: простаивающий — пуск (новая запись), на паузе — снять с паузы (продолжить запись).
    func activate(_ id: String) {
        guard var st = states[id] else { return }
        if !st.recording {
            // Простаивал → пуск. Здесь и только здесь снимается якорь сеанса: по какому плейхеду
            // пишем — по лайву или по пересмотру (как у интервального тега на старте записи).
            st.usesReviewTime = VideoPlayerManager.shared.markupAnchorUsesReview
            let vt = videoTime(for: st)
            // Таймер, дошедший до нуля, начинает заново.
            if st.entity.mode == .timer, value(for: st, atVideoTime: vt) <= 0 { st.accumulated = 0 }
            st.recording = true
            st.runningSinceVideo = vt
            states[id] = st
            activeIDs.insert(id)
            let v = value(for: st, atVideoTime: vt)
            displaySeconds[id] = v
            ClockTimelineRecorder.shared.beginSession(
                clock: st.entity, value: v, videoTime: vt, usesReviewTime: st.usesReviewTime
            )
            if !suppressStateChanged { onStateChanged?(id, true) }
        } else if st.runningSinceVideo == nil {
            // На своей паузе → снять с паузы. Опорная точка закрывает плоский участок паузы.
            let vt = videoTime(for: st)
            let v = value(for: st, atVideoTime: vt)
            st.runningSinceVideo = vt
            states[id] = st
            ClockTimelineRecorder.shared.addKeyframe(clockId: id, value: v, videoTime: vt)
            // Снятие с паузы = АКТИВАЦИЯ (плей): зеркалим на stateSync-партнёров.
            if !suppressStateChanged { onStateChanged?(id, true) }
        }
        // Идёт → пуск игнорируем.
    }

    /// Своя пауза счётчика: значение замирает, но счётчик остаётся активным (пишется). ПАУЗА =
    /// ДЕАКТИВАЦИЯ (в отличие от сброса — тот ещё и обнуляет): зеркалим деактивацию на партнёров.
    func pause(_ id: String) {
        guard var st = states[id], st.recording, let since = st.runningSinceVideo else { return }
        let vt = videoTime(for: st)
        st.accumulated = max(0, st.accumulated + (vt - since))
        st.runningSinceVideo = nil
        states[id] = st
        let v = value(for: st, atVideoTime: vt)
        displaySeconds[id] = v
        // Опорная точка закрывает идущий участок; дальше значение стоит (плоский участок паузы).
        ClockTimelineRecorder.shared.addKeyframe(clockId: id, value: v, videoTime: vt)
        // Пауза = деактивация → зеркалим на stateSync-партнёров (плей=актив, пауза=деактив).
        if !suppressStateChanged { onStateChanged?(id, false) }
    }

    /// Сброс — ЕДИНСТВЕННОЕ, что прекращает запись. Дописывает отрезок, обнуляет значение,
    /// счётчик простаивает. Сброс = ДЕАКТИВАЦИЯ + обнуление: если счётчик ШЁЛ, зеркалим
    /// деактивацию (если он уже был на паузе — деактивация уже зеркалилась при паузе).
    func reset(_ id: String) {
        guard var st = states[id] else { return }
        let vt = videoTime(for: st)
        if st.recording {
            let v = value(for: st, atVideoTime: vt)
            ClockTimelineRecorder.shared.endSession(clockId: id, value: v, videoTime: vt)
        }
        let wasRunning = st.recording && st.runningSinceVideo != nil
        st.recording = false
        st.runningSinceVideo = nil
        st.accumulated = 0
        // Сеанс закрыт — якорь снимается: следующий пуск снимет его заново по текущему режиму.
        st.usesReviewTime = false
        states[id] = st
        activeIDs.remove(id)
        displaySeconds[id] = value(for: st, atVideoTime: vt)
        if wasRunning, !suppressStateChanged { onStateChanged?(id, false) }
    }

    /// Пересмотр закрывается: счётчики, которые писались ПО ЕГО плейхеду, дальше писать некуда —
    /// закрываем их и кладём отрезки на таймлайн. Вызывать ДО сброса `isReviewMode`, иначе конец
    /// отрезка посчитается по лайву. Счётчики на якоре лайва не трогаем — они идут дальше.
    func finalizeReviewAnchored() {
        let doomed = states.filter { $0.value.recording && $0.value.usesReviewTime }.map(\.key)
        for id in doomed { reset(id) }
    }

    /// Финализация всех активных счётчиков (выход из проекта): дописываем записи и сбрасываем.
    /// stateSync при этом не дёргаем (связанные интервалы завершать не надо).
    func finalizeAll() {
        suppressStateChanged = true
        for id in Array(activeIDs) { reset(id) }
        suppressStateChanged = false
        ClockTimelineRecorder.shared.dropOpenIntervals()
    }

    /// Текущее значение (сек).
    func currentSeconds(_ id: String) -> Double {
        guard let st = states[id] else { return 0 }
        return value(for: st, atVideoTime: videoTime(for: st))
    }

    /// Доля заполнения для кольца (0…1). Таймер — остаток/initial; секундомер — доля текущей минуты.
    func progressFraction(_ id: String) -> Double {
        guard let st = states[id] else { return 0 }
        let v = value(for: st, atVideoTime: videoTime(for: st))
        switch st.entity.mode {
        case .timer:
            guard st.entity.initialSeconds > 0 else { return 0 }
            return min(1, max(0, v / st.entity.initialSeconds))
        case .stopwatch:
            return (v.truncatingRemainder(dividingBy: 60)) / 60
        }
    }

    // MARK: - Internals

    /// Значение счётчика в заданное время видео. Идёт → накоплено + (видео-время − старт отрезка);
    /// на паузе/простое → только накопленное. Не уходит ниже нуля при перемотке назад.
    private func value(for st: RuntimeState, atVideoTime vt: Double) -> Double {
        var elapsed = st.accumulated
        if let since = st.runningSinceVideo { elapsed += (vt - since) }
        elapsed = max(0, elapsed)
        switch st.entity.mode {
        case .stopwatch: return elapsed
        case .timer:     return max(0, st.entity.initialSeconds - elapsed)
        }
    }

    /// Пересчёт показаний идущих счётчиков + проверка достижения нуля. Время каждый счётчик
    /// берёт по СВОЕМУ якорю: лайв или пересмотр.
    private func refreshRunning() {
        var reachedZero: [String] = []
        for (id, st) in states where st.recording {
            let vt = videoTime(for: st)
            let v = value(for: st, atVideoTime: vt)
            if st.runningSinceVideo != nil {
                if displaySeconds[id] != v { displaySeconds[id] = v }
                if st.entity.mode == .timer, v <= 0 { reachedZero.append(id) }
            }
            // Живой штамп таймера/секундомера растёт по ходу сеанса (~раз в секунду, троттлинг внутри),
            // чтобы его можно было смотреть/пересматривать не дожидаясь сброса. Для паузы тянем плоский
            // «носик» — значение заморожено, но границы участка растут вместе с временем видео.
            ClockTimelineRecorder.shared.tickLiveStamp(clockId: id, value: v, videoTime: vt)
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
            // Замереть на нуле: своя пауза (счётчик остаётся активным/пишется).
            pause(id)
        case .reset:
            reset(id)
        case .restart:
            // Нулевой initial зациклил бы «достижение нуля» на каждом тике — такой таймер стоит.
            if entity.initialSeconds > 0 { restartCycle(id) } else { pause(id) }
        }

        if entity.firesBindingsOnZero {
            onReachedZero?(id)
        }
    }

    /// Новый круг обратного отсчёта без остановки. В записи круг — отдельный сеанс (свой штамп):
    /// показание скачком возвращается к initial, одним штампом это не выразить.
    private func restartCycle(_ id: String) {
        guard var st = states[id], st.recording else { return }
        // Круг — новый сеанс того же счётчика: якорь у него тот же, что и у прошлого.
        let vt = videoTime(for: st)
        let vOld = value(for: st, atVideoTime: vt)   // ~0
        st.accumulated = 0
        st.runningSinceVideo = vt
        states[id] = st
        let vNew = value(for: st, atVideoTime: vt)   // ~initial
        displaySeconds[id] = vNew
        // Дописываем прошедший круг (до нуля) отдельным штампом и начинаем новый.
        ClockTimelineRecorder.shared.endSession(clockId: id, value: vOld, videoTime: vt)
        ClockTimelineRecorder.shared.beginSession(
            clock: st.entity, value: vNew, videoTime: vt, usesReviewTime: st.usesReviewTime
        )
    }
}
