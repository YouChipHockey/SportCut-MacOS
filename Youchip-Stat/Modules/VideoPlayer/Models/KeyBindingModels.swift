//
//  KeyBindingModels.swift
//  Youchip-Stat
//
//  Модели данных для системы связок клавиш в свободном отображении тегов.
//

import Foundation

// MARK: - Canvas button kind

/// Тип элемента на холсте свободной раскладки.
enum CanvasButtonKind: String, Codable, CaseIterable {
    case tag
    case label
    case timeEvent
    /// Карта (PlayField) прямо на холсте: зона, по которой кликают, ставя позицию на карте.
    /// Работает как лейбл (со всеми тегами, кроме эксклюзивных связок), но добавляет позицию.
    case map
    /// Секундомер/таймер (`ClockEntity`): самостоятельный счётчик реального времени. Активируется
    /// как тег (клик/связка), но следа на таймлайне не оставляет. См. ClockRuntimeManager.
    case clock
}

// MARK: - Binding type

/// Тип действия связки клавиш.
enum KeyBindingType: String, Codable, CaseIterable {
    /// Подсвечивает связанные кнопки; остальные остаются кликабельными до Esc или завершения пары.
    case highlight
    /// Активирует суб-кнопку (обычный тег — добавляет штамп; интервальный — зажимает).
    case activation
    /// Деактивирует суб-кнопку (только зажатый интервальный тег — отжимает).
    case deactivation
    /// Инверсия состояния интервального тега: зажат — отжат, отжат — зажат.
    case intervalInversion
    /// Синхронизация состояния: дублирует статус источника на цель в ОБЕ стороны и на активации,
    /// и на деактивации. Источник активировался — цель активировалась; источник выключился — цель
    /// выключилась. Осмысленна между «состоянийными» кнопками (интервальный тег / счётчик).
    case stateSync
    /// Сброс счётчика (секундомер — в 0, таймер — к стартовому значению). Только для целей-счётчиков.
    case clockReset
    /// Делает суб-кнопку видимой.
    case visibility
    /// Делает суб-кнопку невидимой.
    case invisibility
    /// Инверсия видимости: видима — невидима, невидима — видима.
    case visibilityInversion
    /// Эксклюзивная связка: тег↔тег — противоположное состояние; тег↔лейбл — только эти пары + подсветка партнёра.
    case exclusive
}

// MARK: - KeyBinding

/// Одна связка между двумя кнопками холста.
struct KeyBinding: Codable, Identifiable, Equatable {
    var id: String
    /// Источник — кнопка, при нажатии которой срабатывает связка.
    var sourceId: String
    var sourceKind: CanvasButtonKind
    /// Цель — кнопка, на которую воздействует связка.
    var targetId: String
    var targetKind: CanvasButtonKind
    var type: KeyBindingType
    /// Задержка в секундах перед отработкой. nil = немедленно.
    var delaySeconds: Double?
    /// Оверрайд defaultTimeBefore тега (activation/highlight-цепочка).
    var overrideTimeBefore: Double?
    /// Оверрайд defaultTimeAfter тега.
    var overrideTimeAfter: Double?
    /// Горячая клавиша суб-кнопки в режиме подсветки (только для .highlight).
    var highlightHotkey: String?
    /// Показывать ли суб-кнопку при активации подсветки (для .highlight).
    var showTargetOnHighlight: Bool?
    /// Возвращать ли видимость суб-кнопки в исходное состояние после её нажатия.
    /// Применимо к .highlight (если showTargetOnHighlight), .visibility, .invisibility.
    var revertVisibilityAfterPress: Bool?

    init(
        id: String = UUID().uuidString,
        sourceId: String,
        sourceKind: CanvasButtonKind,
        targetId: String,
        targetKind: CanvasButtonKind,
        type: KeyBindingType = .highlight,
        delaySeconds: Double? = nil,
        overrideTimeBefore: Double? = nil,
        overrideTimeAfter: Double? = nil,
        highlightHotkey: String? = nil,
        showTargetOnHighlight: Bool? = nil,
        revertVisibilityAfterPress: Bool? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.sourceKind = sourceKind
        self.targetId = targetId
        self.targetKind = targetKind
        self.type = type
        self.delaySeconds = delaySeconds
        self.overrideTimeBefore = overrideTimeBefore
        self.overrideTimeAfter = overrideTimeAfter
        self.highlightHotkey = highlightHotkey
        self.showTargetOnHighlight = showTargetOnHighlight
        self.revertVisibilityAfterPress = revertVisibilityAfterPress
    }
}

// MARK: - Group key

/// Ключ для группировки нескольких связок между одной парой кнопок.
struct KeyBindingGroupKey: Hashable {
    let sourceId: String
    let sourceKind: CanvasButtonKind
    let targetId: String
    let targetKind: CanvasButtonKind

    /// Составной ключ кнопки-источника: "kind:id".
    var sourceButtonKey: String { "\(sourceKind.rawValue):\(sourceId)" }
    /// Составной ключ кнопки-цели: "kind:id".
    var targetButtonKey: String { "\(targetKind.rawValue):\(targetId)" }
}

// MARK: - Convenience

extension KeyBinding {
    var groupKey: KeyBindingGroupKey {
        KeyBindingGroupKey(
            sourceId: sourceId, sourceKind: sourceKind,
            targetId: targetId, targetKind: targetKind
        )
    }

    /// Составной ключ кнопки-цели: "kind:id".
    var targetButtonKey: String { "\(targetKind.rawValue):\(targetId)" }
    /// Составной ключ кнопки-источника: "kind:id".
    var sourceButtonKey: String { "\(sourceKind.rawValue):\(sourceId)" }
}

extension KeyBindingType {
    /// Отображаемое имя типа связки (русский по умолчанию, ключ локализации).
    var localizationKey: String {
        switch self {
        case .highlight:          return "keyBindingTypeHighlight"
        case .activation:         return "keyBindingTypeActivation"
        case .deactivation:       return "keyBindingTypeDeactivation"
        case .intervalInversion:  return "keyBindingTypeIntervalInversion"
        case .stateSync:          return "keyBindingTypeStateSync"
        case .clockReset:         return "keyBindingTypeClockReset"
        case .visibility:         return "keyBindingTypeVisibility"
        case .invisibility:       return "keyBindingTypeInvisibility"
        case .visibilityInversion: return "keyBindingTypeVisibilityInversion"
        case .exclusive:          return "keyBindingTypeExclusive"
        }
    }

    /// Типы, предлагаемые в пикере для конкретной пары кнопок. «Сброс счётчика» осмыслен только
    /// там, где ОДНА из сторон — счётчик (направление стрелки для сброса не важно: связку рисуют
    /// и от тега к счётчику, и наоборот).
    /// `current` всегда остаётся в списке, иначе пикер потеряет уже выбранное значение.
    static func options(
        source: CanvasButtonKind,
        target: CanvasButtonKind,
        current: KeyBindingType
    ) -> [KeyBindingType] {
        allCases.filter { type in
            if type == .clockReset {
                return source == .clock || target == .clock || current == .clockReset
            }
            if type == .stateSync {
                // Синхронизация состояния осмысленна только между «состоянийными» кнопками —
                // интервальным тегом и счётчиком (у них есть вкл/выкл, которое можно зеркалить).
                let stateful: Set<CanvasButtonKind> = [.tag, .clock]
                return (stateful.contains(source) && stateful.contains(target)) || current == .stateSync
            }
            return true
        }
    }
}
