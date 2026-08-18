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
    /// Показывать ли счётчик оверлеем поверх видео (галочка в настройках объекта в редакторе).
    var showOnVideo: Bool
    /// Показывать сотые доли секунды (последняя пара сегментов / .CC в тексте).
    var showCentiseconds: Bool
    /// Авто-действие таймера при достижении нуля.
    var zeroAction: ClockZeroAction
    /// Запускать исходящие связки счётчика при достижении нуля (таймер как источник цепочки).
    var firesBindingsOnZero: Bool
    /// Подпись под счётчиком: видна на холсте, в библиотеке тегов, на видео и в записи разметки.
    var caption: String

    init(
        id: String = UUID().uuidString,
        name: String,
        mode: ClockMode,
        initialSeconds: Double = 600,
        appearance: ClockAppearance = .segments,
        showOnVideo: Bool = false,
        showCentiseconds: Bool = true,
        zeroAction: ClockZeroAction = .stop,
        firesBindingsOnZero: Bool = false,
        caption: String = ""
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.initialSeconds = initialSeconds
        self.appearance = appearance
        self.showOnVideo = showOnVideo
        self.showCentiseconds = showCentiseconds
        self.zeroAction = zeroAction
        self.firesBindingsOnZero = firesBindingsOnZero
        self.caption = caption
    }

    enum CodingKeys: String, CodingKey {
        case id, name, mode, initialSeconds, appearance, showOnVideo, showCentiseconds
        case zeroAction, firesBindingsOnZero, caption
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mode = try c.decodeIfPresent(ClockMode.self, forKey: .mode) ?? .stopwatch
        initialSeconds = try c.decodeIfPresent(Double.self, forKey: .initialSeconds) ?? 600
        appearance = try c.decodeIfPresent(ClockAppearance.self, forKey: .appearance) ?? .segments
        showOnVideo = try c.decodeIfPresent(Bool.self, forKey: .showOnVideo) ?? false
        showCentiseconds = try c.decodeIfPresent(Bool.self, forKey: .showCentiseconds) ?? true
        zeroAction = try c.decodeIfPresent(ClockZeroAction.self, forKey: .zeroAction) ?? .stop
        firesBindingsOnZero = try c.decodeIfPresent(Bool.self, forKey: .firesBindingsOnZero) ?? false
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
    }
}

// MARK: - Запись счётчика в разметке

/// Отрезок работы счётчика, записанный на скрытый таймлайн разметки.
///
/// Живёт внутри `TimelineStamp` (штамп даёт границы отрезка в ВРЕМЕНИ ВИДЕО), а здесь — всё,
/// что нужно, чтобы позже воспроизвести счётчик в пересмотре момента и в экспорте, не заглядывая
/// в коллекцию: вид, режим, подпись и показания на концах отрезка. Поэтому запись остаётся
/// рабочей, даже если коллекцию потом изменят или откроют проект с другой коллекцией.
struct StampClockInfo: Codable, Equatable {
    var clockId: String
    var name: String
    var mode: ClockMode
    var appearance: ClockAppearance
    var showCentiseconds: Bool
    var caption: String
    /// Показание счётчика в начале отрезка (сек).
    var startValue: Double
    /// Показание счётчика в конце отрезка (сек).
    var endValue: Double

    /// Показание счётчика в произвольный момент видео.
    ///
    /// Интерполируем между концами отрезка, а не «начало + прошедшее время»: счётчик считает
    /// реальное время, и если во время записи видео ставили на паузу или перематывали, видео-время
    /// отрезка не равно набежавшему. Линейная интерполяция даёт корректные показания в обоих случаях.
    func value(atVideoTime time: Double, start: Double, finish: Double) -> Double {
        let span = finish - start
        guard span > 0 else { return startValue }
        let progress = min(max((time - start) / span, 0), 1)
        return startValue + (endValue - startValue) * progress
    }

    /// Пересчёт показаний под новые границы штампа (потянули за край клипа).
    ///
    /// Сохраняем ТЕМП счётчика и доводим значения на концах по старой шкале — в том числе за её
    /// пределы. Если этого не делать, растянутый клип «замедлял» бы счётчик, а укороченный —
    /// ускорял: интерполяция всегда раскладывает те же показания на всю новую длину.
    mutating func rescale(oldStart: Double, oldFinish: Double, newStart: Double, newFinish: Double) {
        let oldSpan = oldFinish - oldStart
        guard oldSpan > 0 else { return }
        let rate = (endValue - startValue) / oldSpan
        // Счётчик не уходит в минус: таймер стоит на нуле, секундомер — на нуле.
        startValue = max(0, startValue + (newStart - oldStart) * rate)
        endValue = max(0, startValue + (newFinish - newStart) * rate)
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
