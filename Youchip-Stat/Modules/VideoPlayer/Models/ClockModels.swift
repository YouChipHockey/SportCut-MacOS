//
//  ClockModels.swift
//  Youchip-Stat
//
//  Секундомер и таймер как объекты холста связок клавиш. Логика одинаковая, отличие — направление:
//  секундомер идёт вперёд, таймер — назад (обратный отсчёт от initialSeconds). Считают РЕАЛЬНОЕ
//  время, пока объект активен (как интервальный тег по семантике «активен → идёт»), но следа на
//  таймлайне не оставляют — это самостоятельный счётчик. Внешний вид кастомится (варианты + стиль).
//

import Foundation

/// Направление счёта.
enum ClockMode: String, Codable, CaseIterable {
    case stopwatch   // вперёд от 0
    case timer       // назад от initialSeconds к 0
}

/// Что делает таймер, когда обратный отсчёт дошёл до нуля. Секундомер игнорирует.
enum ClockZeroAction: String, Codable, CaseIterable {
    /// Замереть на нуле (поведение по умолчанию).
    case stop
    /// Остановиться и вернуть начальное значение.
    case reset
    /// Начать отсчёт заново, не останавливаясь (цикл).
    case restart

    var localizationKey: String {
        switch self {
        case .stop:    return "clockZeroActionStop"
        case .reset:   return "clockZeroActionReset"
        case .restart: return "clockZeroActionRestart"
        }
    }
}

/// Вариант внешнего вида счётчика.
enum ClockAppearance: String, Codable, CaseIterable {
    case segments    // 8 прямоугольников с цифрами HH.MM.SS.CC
    case analog      // аналоговый циферблат со стрелками
    case ring        // кольцо-прогресс + цифры в центре
    case text        // простой текст HH:MM:SS(.CC)

    var localizationKey: String {
        switch self {
        case .segments: return "clockAppearanceSegments"
        case .analog:   return "clockAppearanceAnalog"
        case .ring:     return "clockAppearanceRing"
        case .text:     return "clockAppearanceText"
        }
    }
}

/// Сущность-счётчик в пуле коллекции. На холст кладётся `TagFreeLayoutItem(kind: .clock, elementId: id)`,
/// внешний вид (цвета/размер/шрифт/форма фона) берётся из item'а, а вариант/режим/оверлей — отсюда.
struct ClockEntity: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var mode: ClockMode
    /// Стартовое значение таймера (сек) для обратного отсчёта. Секундомер игнорирует.
    var initialSeconds: Double
    var appearance: ClockAppearance
    /// Показывать сотые доли секунды (последняя пара сегментов / .CC в тексте).
    var showCentiseconds: Bool
    /// Выводить ли счётчик оверлеем поверх видео (по той же логике: если пишется — показывать,
    /// если пересматривается его запись — показывать). Только для счётчиков с этим флагом.
    var showOnVideo: Bool
    /// Авто-действие таймера при достижении нуля.
    var zeroAction: ClockZeroAction
    /// Запускать исходящие связки счётчика при достижении нуля (таймер как источник цепочки).
    var firesBindingsOnZero: Bool
    /// Подпись под счётчиком: видна на холсте, в библиотеке тегов, на видео и в записи разметки.
    var caption: String
    /// Горячая клавиша для нажатия счётчика в режиме разметки (как у тега — просто способ нажатия).
    var hotkey: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        mode: ClockMode,
        initialSeconds: Double = 600,
        appearance: ClockAppearance = .segments,
        showCentiseconds: Bool = true,
        showOnVideo: Bool = false,
        zeroAction: ClockZeroAction = .stop,
        firesBindingsOnZero: Bool = false,
        caption: String = "",
        hotkey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.initialSeconds = initialSeconds
        self.appearance = appearance
        self.showCentiseconds = showCentiseconds
        self.showOnVideo = showOnVideo
        self.zeroAction = zeroAction
        self.firesBindingsOnZero = firesBindingsOnZero
        self.caption = caption
        self.hotkey = hotkey
    }

    enum CodingKeys: String, CodingKey {
        case id, name, mode, initialSeconds, appearance, showCentiseconds, showOnVideo
        case zeroAction, firesBindingsOnZero, caption, hotkey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mode = try c.decodeIfPresent(ClockMode.self, forKey: .mode) ?? .stopwatch
        initialSeconds = try c.decodeIfPresent(Double.self, forKey: .initialSeconds) ?? 600
        appearance = try c.decodeIfPresent(ClockAppearance.self, forKey: .appearance) ?? .segments
        showCentiseconds = try c.decodeIfPresent(Bool.self, forKey: .showCentiseconds) ?? true
        showOnVideo = try c.decodeIfPresent(Bool.self, forKey: .showOnVideo) ?? false
        zeroAction = try c.decodeIfPresent(ClockZeroAction.self, forKey: .zeroAction) ?? .stop
        firesBindingsOnZero = try c.decodeIfPresent(Bool.self, forKey: .firesBindingsOnZero) ?? false
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey)
    }
}

// MARK: - Запись счётчика в разметке

/// Опорная точка хода счётчика: показание `value` в момент видео `videoTime`. Между соседними
/// точками показания линейны. Пауза счётчика = две точки с ОДИНАКОВЫМ значением (плоский участок).
struct ClockKeyframe: Codable, Equatable {
    var videoTime: Double
    var value: Double
}

/// Запись ОДНОГО сеанса счётчика (пуск → сброс), записанная на скрытый таймлайн разметки.
///
/// Живёт внутри `TimelineStamp` (штамп даёт границы сеанса в ВРЕМЕНИ ВИДЕО), а здесь — всё, что
/// нужно, чтобы воспроизвести счётчик в пересмотре момента и в экспорте, не заглядывая в коллекцию:
/// вид, режим, подпись и ход показаний. Ход хранится опорными точками `keyframes` — так один штамп
/// точно повторяет счётчик, ВКЛЮЧАЯ его собственные ПАУЗЫ (плоские участки), без дробления на
/// несколько штампов. `startValue`/`endValue` оставлены для обратной совместимости и как фолбэк
/// (старые записи без keyframes).
struct StampClockInfo: Codable, Equatable {
    var clockId: String
    var name: String
    var mode: ClockMode
    var appearance: ClockAppearance
    var showCentiseconds: Bool
    var caption: String
    /// Был ли у счётчика флаг «Показывать на видео» на момент записи — по нему оверлей решает,
    /// выводить ли эту запись на кадр при пересмотре (default false для старых записей).
    var showOnVideo: Bool = false
    /// Показание счётчика в начале сеанса (сек).
    var startValue: Double
    /// Показание счётчика в конце сеанса (сек).
    var endValue: Double
    /// Опорные точки хода счётчика (абсолютное время видео). nil/<2 — фолбэк на startValue→endValue.
    var keyframes: [ClockKeyframe]?

    /// Показание счётчика в произвольный момент видео.
    ///
    /// Есть keyframes → кусочно-линейная интерполяция по ним (учитывает паузы = плоские участки).
    /// Долю позиции внутри `[start, finish]` проецируем на диапазон времён keyframes — поэтому ресайз
    /// клипа растягивает/сжимает ход пропорционально. Иначе — линейно между startValue и endValue.
    func value(atVideoTime time: Double, start: Double, finish: Double) -> Double {
        if let kf = keyframes, kf.count >= 2, let first = kf.first, let last = kf.last {
            let span = finish - start
            let progress = span > 0 ? min(max((time - start) / span, 0), 1) : 0
            let target = first.videoTime + progress * (last.videoTime - first.videoTime)
            return Self.interpolate(kf, atVideoTime: target)
        }
        let span = finish - start
        guard span > 0 else { return startValue }
        let progress = min(max((time - start) / span, 0), 1)
        return startValue + (endValue - startValue) * progress
    }

    /// Кусочно-линейная интерполяция показаний по опорным точкам (по возрастанию времени видео).
    private static func interpolate(_ kf: [ClockKeyframe], atVideoTime t: Double) -> Double {
        guard let first = kf.first, let last = kf.last else { return 0 }
        if t <= first.videoTime { return first.value }
        if t >= last.videoTime { return last.value }
        for i in 1..<kf.count {
            if t <= kf[i].videoTime {
                let a = kf[i - 1], b = kf[i]
                let seg = b.videoTime - a.videoTime
                guard seg > 0 else { return b.value }
                return a.value + (b.value - a.value) * ((t - a.videoTime) / seg)
            }
        }
        return last.value
    }

    /// Пересчёт под новые границы штампа (потянули за край клипа). При наличии keyframes переносим
    /// их времена пропорционально новой длине (значения сохраняем — привязка к времени видео). Без
    /// keyframes — прежняя логика: сохраняем ТЕМП и доводим значения на концах.
    mutating func rescale(oldStart: Double, oldFinish: Double, newStart: Double, newFinish: Double) {
        let oldSpan = oldFinish - oldStart
        guard oldSpan > 0 else { return }
        let newSpan = newFinish - newStart
        if var kf = keyframes, !kf.isEmpty {
            for i in kf.indices {
                let frac = (kf[i].videoTime - oldStart) / oldSpan
                kf[i].videoTime = newStart + frac * newSpan
            }
            keyframes = kf
            startValue = kf.first?.value ?? startValue
            endValue = kf.last?.value ?? endValue
            return
        }
        let rate = (endValue - startValue) / oldSpan
        // Счётчик не уходит в минус: таймер стоит на нуле, секундомер — на нуле.
        startValue = max(0, startValue + (newStart - oldStart) * rate)
        endValue = max(0, startValue + (newFinish - newStart) * rate)
    }
}

// ВАЖНО: свой Codable в РАСШИРЕНИИ (мембервайз-init сохраняется). Синтезированный `Decodable` НЕ
// использует дефолты — для НЕобязательного поля с `= false` он звал бы `decode` и падал на СТАРЫХ
// записях без ключа `showOnVideo`, роняя всю разметку/сессию с таймерами. Тут — `decodeIfPresent`.
extension StampClockInfo {
    enum CodingKeys: String, CodingKey {
        case clockId, name, mode, appearance, showCentiseconds, caption, showOnVideo, startValue, endValue, keyframes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clockId = try c.decode(String.self, forKey: .clockId)
        name = try c.decode(String.self, forKey: .name)
        mode = try c.decode(ClockMode.self, forKey: .mode)
        appearance = try c.decode(ClockAppearance.self, forKey: .appearance)
        showCentiseconds = try c.decodeIfPresent(Bool.self, forKey: .showCentiseconds) ?? true
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        showOnVideo = try c.decodeIfPresent(Bool.self, forKey: .showOnVideo) ?? false
        startValue = try c.decodeIfPresent(Double.self, forKey: .startValue) ?? 0
        endValue = try c.decodeIfPresent(Double.self, forKey: .endValue) ?? 0
        keyframes = try c.decodeIfPresent([ClockKeyframe].self, forKey: .keyframes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clockId, forKey: .clockId)
        try c.encode(name, forKey: .name)
        try c.encode(mode, forKey: .mode)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(showCentiseconds, forKey: .showCentiseconds)
        try c.encode(caption, forKey: .caption)
        try c.encode(showOnVideo, forKey: .showOnVideo)
        try c.encode(startValue, forKey: .startValue)
        try c.encode(endValue, forKey: .endValue)
        try c.encodeIfPresent(keyframes, forKey: .keyframes)
    }
}

/// Запись счётчика, ОТОРВАННАЯ от разметки: показания + границы в ВРЕМЕНИ ИСХОДНОГО видео
/// (+ признак «это Primary Counter тега момента»).
///
/// Зачем: клип плейлиста обязан работать сам по себе — даже если проект/разметку снесли. Штампы
/// счётчиков живут в разметке, поэтому при добавлении клипа в плейлист мы копируем их в это
/// «плоское» описание прямо в событие (`SportCutEvent.clockRecords`). Точных связей с коллекцией
/// оно не знает и не должно: показаний и границ хватает, чтобы счётчик шёл ровно как шёл вживую.
/// В этом же виде записи принимает экспорт (`ClockExportOverlayBuilder`).
struct ClockRecordSnapshot: Codable, Equatable {
    /// Копия записи счётчика (вид, подпись, ход показаний).
    var info: StampClockInfo
    /// Границы записи в времени ИСХОДНОГО видео.
    var start: Double
    var finish: Double
    /// Primary Counter тега того момента, к которому пришита запись: показываем даже без флага
    /// «Показывать на видео».
    var isPrimary: Bool

    init(info: StampClockInfo, start: Double, finish: Double, isPrimary: Bool) {
        self.info = info
        self.start = start
        self.finish = finish
        self.isPrimary = isPrimary
    }

    /// Нужно ли выводить запись на кадр: свой флаг ЛИБО Primary Counter момента.
    var isVisibleOnVideo: Bool { info.showOnVideo || isPrimary }

    /// Показание в произвольный момент ИСХОДНОГО видео.
    func value(atVideoTime time: Double) -> Double {
        info.value(atVideoTime: time, start: start, finish: finish)
    }

    /// Попадает ли момент исходника внутрь записи.
    func contains(_ time: Double) -> Bool {
        time >= start && time <= finish
    }
}

// MARK: - Time formatting

/// Разбор секунд на компоненты для отрисовки (часы/минуты/секунды/сотые).
struct ClockTimeComponents {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let centis: Int

    init(_ total: Double) {
        let clamped = max(0, total)
        let totalCentis = Int((clamped * 100).rounded(.down))
        centis = totalCentis % 100
        let totalSeconds = totalCentis / 100
        seconds = totalSeconds % 60
        minutes = (totalSeconds / 60) % 60
        hours = totalSeconds / 3600
    }

    func string(showCentis: Bool) -> String {
        showCentis
            ? String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, centis)
            : String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// 8 цифр для сегментного вида: HH MM SS CC.
    var digits8: [Int] {
        [hours / 10 % 10, hours % 10,
         minutes / 10, minutes % 10,
         seconds / 10, seconds % 10,
         centis / 10, centis % 10]
    }
}
