//
//  KeyBindingRuntimeManager.swift
//  Youchip-Stat
//
//  Движок связок клавиш в свободном режиме просмотра тегов.
//  Управляет подсветкой, видимостью и активацией кнопок согласно настроенным связкам.
//

import Foundation
import Combine

// MARK: - Callback types

typealias AddTagCallback = (
    _ tagId: String,
    _ overrideTimeBefore: Double?,
    _ overrideTimeAfter: Double?,
    _ labelIds: [String],
    _ onAdded: (() -> Void)?
) -> Void
typealias IntervalTagCallback = (_ tagId: String) -> Void
typealias StopIntervalTagCallback = (_ tagId: String) -> Void
typealias IsIntervalActiveCallback = (_ tagId: String) -> Bool
typealias AttachLabelsToAnchorCallback = (
    _ anchorTagId: String,
    _ labelIds: [String],
    _ onDone: (() -> Void)?
) -> Void
typealias AttachLabelsToLastStampCallback = (
    _ labelIds: [String],
    _ onDone: (() -> Void)?
) -> Void
typealias AttachLabelsIfTagMatchesCallback = (
    _ labelIds: [String],
    _ allowedTagIds: Set<String>,
    _ onDone: (() -> Void)?
) -> Void
typealias AttachTimeEventsToAnchorCallback = (
    _ anchorTagId: String,
    _ timeEventIds: [String],
    _ onDone: (() -> Void)?
) -> Void

// MARK: - Diagnostics

/// Диагностика движка связок. Временная — включается одним флагом, чтобы видеть в консоли
/// весь путь нажатия: конфигурация → цепочка связок → колбэки в библиотеку тегов.
enum KeyBindingLog {
    static var isEnabled = true

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("🔗 KB: \(message())")
    }
}

// MARK: - Manager

final class KeyBindingRuntimeManager: ObservableObject {

    static let shared = KeyBindingRuntimeManager()

    // MARK: - Published state

    @Published private(set) var highlightModeActive: Bool = false
    @Published private(set) var highlightedButtonIds: Set<String> = []
    @Published var runtimeVisibility: [String: Bool] = [:]

    // MARK: - Internal state

    private(set) var anchorTagId: String?
    private(set) var highlightOriginButtonKey: String?
    @Published private(set) var activatedLabelIds: [String] = []
    @Published private(set) var pendingTimeEventIds: Set<String> = []
    private(set) var didCompleteHighlightPair: Bool = false
    /// Во время обработки нажатия цепочка связок добавила/запустила тег (с забандленными лейблами).
    private var didActivateTagInChain: Bool = false
    private var bindings: [KeyBinding] = []
    private var items: [TagFreeLayoutItem] = []
    private(set) var highlightHotkeys: [String: String] = [:]
    private var pendingWork: [DispatchWorkItem] = []

    // MARK: - Callbacks (set by TagLibraryView)

    var onAddTag: AddTagCallback?
    var onStartIntervalTag: IntervalTagCallback?
    var onStopIntervalTag: StopIntervalTagCallback?
    var isIntervalTagActive: IsIntervalActiveCallback?
    /// Секундомеры/таймеры как цели связок (активация/деактивация/инверсия → старт/стоп/toggle,
    /// отдельный тип связки `.clockReset` → сброс).
    var onStartClock: ((_ clockId: String) -> Void)?
    var onStopClock: ((_ clockId: String) -> Void)?
    var onResetClock: ((_ clockId: String) -> Void)?
    var isClockActive: ((_ clockId: String) -> Bool)?
    var onAttachLabelsToAnchor: AttachLabelsToAnchorCallback?
    var onAttachLabelsToLastStamp: AttachLabelsToLastStampCallback?
    var onAttachLabelsIfTagMatches: AttachLabelsIfTagMatchesCallback?
    var onAttachTimeEventsToAnchor: AttachTimeEventsToAnchorCallback?
    /// Ставит позицию на карте нужному тегу. allowedTagIds=nil — к якорю/крайнему штампу;
    /// непустой набор — только к штампам этих тегов (эксклюзивные партнёры карты).
    var onAttachMapPosition: ((_ fieldId: String, _ normalized: CGPoint, _ allowedTagIds: Set<String>?, _ onDone: (() -> Void)?) -> Void)?

    private init() {}

    // MARK: - Pending selections

    func togglePendingTimeEvent(id: String) {
        var updated = pendingTimeEventIds
        if updated.contains(id) {
            updated.remove(id)
        } else {
            updated.insert(id)
        }
        pendingTimeEventIds = updated
    }

    // MARK: - Activated labels (Cmd+click or binding activation)

    func activateLabel(id: String) {
        if !activatedLabelIds.contains(id) {
            activatedLabelIds.append(id)
        }
    }

    func deactivateLabel(id: String) {
        activatedLabelIds.removeAll { $0 == id }
    }

    func isLabelActivated(_ id: String) -> Bool {
        activatedLabelIds.contains(id)
    }

    func labelsForTagAddition(triggeringLabelId: String? = nil) -> [String] {
        var result = activatedLabelIds
        if let lid = triggeringLabelId, !result.contains(lid) {
            result.append(lid)
        }
        return result
    }

    func takeActivatedLabels(triggeringLabelId: String? = nil) -> [String] {
        let result = labelsForTagAddition(triggeringLabelId: triggeringLabelId)
        activatedLabelIds = []
        return result
    }

    func clearActivatedLabels() {
        activatedLabelIds = []
    }

    func highlightOriginIsLabel() -> Bool {
        highlightOriginButtonKey?.hasPrefix("\(CanvasButtonKind.label.rawValue):") ?? false
    }

    func clearPendingTimeEvents() {
        pendingTimeEventIds = []
    }

    // MARK: - Configuration

    /// Коллекция, под которую сейчас загружены связки. nil — связки не сконфигурированы.
    private(set) var configuredCollectionId: String?

    func configure(layout: TagFreeLayout, collectionId: String? = nil) {
        bindings = layout.bindings
        items = layout.items
        configuredCollectionId = collectionId
        KeyBindingLog.log("configure(collection: \(collectionId ?? "nil")) items=\(items.count) bindings=\(bindings.count)")
        reset()
    }

    /// Уход с коллекции связок. Чистит именно СВЯЗКИ (в отличие от `reset()`, который трогает
    /// только состояние подсветки): движок — синглтон, и без этого связки прошлой коллекции
    /// «протекали» в следующую.
    func clearConfiguration() {
        KeyBindingLog.log("clearConfiguration (было bindings=\(bindings.count), collection=\(configuredCollectionId ?? "nil"))")
        bindings = []
        items = []
        configuredCollectionId = nil
        reset()
        resetRuntimeVisibility()
    }

    /// Гарантирует, что связки ТЕКУЩЕЙ коллекции загружены, и делает это лениво — прямо перед
    /// обработкой нажатия.
    ///
    /// Раньше `configure` вызывался только из `onAppear`/`onChange` вьюх библиотеки тегов. Если
    /// ни один из этих хуков не срабатывал (типовой случай — коллекция только что создана и
    /// подхвачена в уже смонтированном канвасе), `bindings` оставался пустым: холст рисовался,
    /// теги ставились, хоткеи работали, а связки молчали до перезапуска приложения.
    ///
    /// Идемпотентно: для уже загруженной коллекции — no-op (важно, иначе `configure` сбрасывал бы
    /// подсветку посреди цепочки).
    @discardableResult
    func ensureConfiguredForCurrentCollection(playFields: [PlayField] = []) -> Bool {
        let library = TagLibraryManager.shared
        guard case .user(let name) = library.currentCollectionType,
              let info = CollectionsBookmarksManager.shared.loadCollections().first(where: { $0.name == name })
        else {
            KeyBindingLog.log("ensureConfigured: текущая коллекция не пользовательская — пропуск")
            return false
        }

        if configuredCollectionId == info.id { return true }

        guard let stored = TagFreeLayoutStorage.loadLayoutIfExists(
            collectionId: info.id,
            tags: library.tags,
            labels: library.allLabels,
            timeEvents: library.timeEvents,
            playFields: playFields
        ) else {
            KeyBindingLog.log("ensureConfigured: раскладка не найдена для '\(name)' (id \(info.id))")
            return false
        }

        KeyBindingLog.log("ensureConfigured: ленивая загрузка '\(name)'")
        configure(layout: stored, collectionId: info.id)
        return true
    }

    func reset() {
        cancelPendingWork()
        highlightModeActive = false
        highlightedButtonIds = []
        highlightOriginButtonKey = nil
        anchorTagId = nil
        activatedLabelIds = []
        pendingTimeEventIds = []
        highlightHotkeys = [:]
        didCompleteHighlightPair = false
    }

    func resetRuntimeVisibility() {
        runtimeVisibility = [:]
    }

    // MARK: - Exclusive on interval stop (вызывается до завершения записи)

    /// Снимает подсветку, если её источник — этот тег. Нужно для интервального тега,
    /// который при запуске подсветил свои лейблы (связка подсветки тег→лейбл): когда
    /// тег выключают, подсветка должна гаснуть сразу, не дожидаясь нажатия на лейбл.
    func clearHighlightIfOriginatedFromTag(_ tagId: String) {
        let tagKey = "\(CanvasButtonKind.tag.rawValue):\(tagId)"
        guard highlightModeActive,
              highlightOriginButtonKey == tagKey || anchorTagId == tagId else { return }
        clearHighlight()
    }

    // MARK: - Button tap entry point

    @discardableResult
    func handleButtonTap(kind: CanvasButtonKind, elementId: String) -> Bool {
        let buttonKey = "\(kind.rawValue):\(elementId)"
        let triggeringLabelId = kind == .label ? elementId : nil
        didCompleteHighlightPair = false

        KeyBindingLog.log("handleButtonTap \(buttonKey) | всего bindings=\(bindings.count), исходящих=\(bindings.filter { $0.sourceButtonKey == buttonKey }.count)")

        if kind == .tag, isIntervalTagActive?(elementId) == true {
            KeyBindingLog.log("  ↳ тег уже пишется как интервал — связки не применяем")
            return true
        }

        // Счётчик — своя точка входа (старт/стоп + цепочка). Сюда приходит с горячей клавиши подсветки.
        if kind == .clock {
            handleClockTap(clockId: elementId)
            return true
        }

        // Связки «сброс» этой кнопки — в обе стороны (цепочка видит только исходящие).
        applyClockResets(kind: kind, elementId: elementId)

        if tryCompleteHighlightPair(partnerKind: kind, partnerId: elementId) {
            didCompleteHighlightPair = true
            return true
        }

        if highlightModeActive, !highlightedButtonIds.contains(buttonKey) {
            clearHighlight()
        }

        let sourceTagActivating: Bool? = kind == .tag ? true : nil

        var visited = Set<String>()
        applyOutgoingBindings(
            from: buttonKey,
            sourceKind: kind,
            sourceId: elementId,
            sourceTagActivating: sourceTagActivating,
            triggeringLabelId: triggeringLabelId,
            visited: &visited
        )

        // Эксклюзивная связка тег↔тег двунаправленная: применяем её и для входящего направления
        // (когда нажатый тег — цель связки). Прямое направление уже отработало выше.
        if kind == .tag {
            applyIncomingExclusiveBindings(kind: .tag, elementId: elementId)
            // Эксклюзив тег↔лейбл: нажатие тега подсвечивает его эксклюзивные лейблы (выбор партнёра).
            highlightExclusiveLabelPartners(ofTag: elementId)
        }

        return true
    }

    /// Нажатие тега подсвечивает его эксклюзивные лейблы (эксклюзив тег↔лейбл = выбор из набора лейблов).
    /// Якорь — этот тег (он добавляется на таймлайн сразу), нажатие подсвеченного лейбла прикрепит его к тегу.
    private func highlightExclusiveLabelPartners(ofTag tagId: String) {
        var highlighted = highlightedButtonIds
        var didHighlight = false
        for binding in bindings where binding.type == .exclusive && isTagLabelPair(binding) {
            let labelKey: String?
            if binding.sourceKind == .tag, binding.sourceId == tagId, binding.targetKind == .label {
                labelKey = binding.targetButtonKey
            } else if binding.targetKind == .tag, binding.targetId == tagId, binding.sourceKind == .label {
                labelKey = binding.sourceButtonKey
            } else {
                labelKey = nil
            }
            if let labelKey {
                highlighted.insert(labelKey)
                didHighlight = true
            }
        }
        guard didHighlight else { return }
        highlightedButtonIds = highlighted
        anchorTagId = tagId
        highlightOriginButtonKey = "\(CanvasButtonKind.tag.rawValue):\(tagId)"
        highlightModeActive = true
    }

    @discardableResult
    private func tryCompleteHighlightPair(partnerKind: CanvasButtonKind, partnerId: String) -> Bool {
        let partnerKey = "\(partnerKind.rawValue):\(partnerId)"
        guard highlightModeActive,
              highlightedButtonIds.contains(partnerKey),
              let originKey = highlightOriginButtonKey else { return false }

        let originParts = originKey.split(separator: ":", maxSplits: 1)
        guard originParts.count == 2,
              let originKind = CanvasButtonKind(rawValue: String(originParts[0])) else { return false }
        let originId = String(originParts[1])

        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            self.applyRevertVisibilityIfNeeded(for: partnerKey)
            self.clearHighlight()
        }

        switch (originKind, partnerKind) {
        case (.label, .tag):
            let labels = takeActivatedLabels(triggeringLabelId: originId)
            onAddTag?(partnerId, nil, nil, labels, finish)

        case (.tag, .label):
            // Тег-источник уже на таймлайне (добавляется сразу при нажатии). Прикрепляем лейбл к нему.
            var labelIds = takeActivatedLabels()
            if !labelIds.contains(partnerId) {
                labelIds.append(partnerId)
            }
            onAttachLabelsToAnchor?(originId, labelIds, finish)

        default:
            clearHighlight()
            return false
        }

        return true
    }

    // MARK: - Label tap (simple LMB) with highlight chains

    /// Простое ЛКМ по лейблу в режиме связок.
    /// Приоритет привязки лейбла: к тегу, с которым есть связь (якорь цепочки подсветки
    /// или прямая связка лейбл→тег); если связи нет — к крайнему штампу на таймлайне.
    /// Подсветка трактуется как отложенная активация: нажатие подсвеченного лейбла
    /// прикрепляет его и запускает его собственные исходящие связки (продолжение цепочки).
    func handleLabelTap(labelId: String) {
        let buttonKey = "\(CanvasButtonKind.label.rawValue):\(labelId)"
        didCompleteHighlightPair = false
        didActivateTagInChain = false

        // Связки «сброс» этого лейбла — в обе стороны (цепочка видит только исходящие).
        applyClockResets(kind: .label, elementId: labelId)

        // Случай 1: лейбл — подсвеченный партнёр активной цепочки (в т.ч. эксклюзивный лейбл,
        // подсвеченный своим тегом) → прикрепляем к якорю и продолжаем его собственную цепочку.
        if highlightModeActive, highlightedButtonIds.contains(buttonKey) {
            advanceChainWithLabel(labelId: labelId, buttonKey: buttonKey)
            return
        }

        // Эксклюзивный лейбл, нажатый отдельно (не подсвечен): привязывается ТОЛЬКО к своим
        // эксклюзивным тегам — если крайний тег его эксклюзивный партнёр, прикрепляем; иначе ничего.
        let exclusivePartners = exclusiveTagPartners(ofLabel: labelId)
        if !exclusivePartners.isEmpty {
            if highlightModeActive { clearHighlight() }
            onAttachLabelsIfTagMatches?([labelId], exclusivePartners, nil)
            return
        }

        if highlightModeActive {
            clearHighlight()
        }

        // Случай 2: свежее нажатие — применяем исходящие связки лейбла (с каскадом активаций).
        var visited = Set<String>()
        applyOutgoingBindings(
            from: buttonKey, sourceKind: .label, sourceId: labelId,
            sourceTagActivating: nil, triggeringLabelId: labelId, visited: &visited
        )

        // 2a: лейбл запустил собственную подсветку → копим его и ждём партнёра.
        if highlightModeActive, highlightOriginButtonKey == buttonKey {
            activateLabel(id: labelId)
            return
        }

        // 2b: цепочка активаций дошла до тега → лейблы уже забандлены в него.
        if didActivateTagInChain {
            clearActivatedLabels()
            return
        }

        // 2c: тег в цепочке не появился → все накопленные лейблы (цепочка) к крайнему штампу.
        var labels = takeActivatedLabels()
        if !labels.contains(labelId) { labels.append(labelId) }
        onAttachLabelsToLastStamp?(labels, nil)
    }

    // MARK: - Map tap (зона карты)

    /// Клик по зоне карты. Работает как лейбл: ставит позицию нужному тегу и запускает
    /// исходящие связки карты. При эксклюзивных связках карта↔тег — только к этим тегам.
    func handleMapTap(mapId: String, normalized: CGPoint) {
        let buttonKey = "\(CanvasButtonKind.map.rawValue):\(mapId)"

        let exclusivePartners = exclusiveTagPartners(ofMap: mapId)
        if !exclusivePartners.isEmpty {
            if highlightModeActive { clearHighlight() }
            onAttachMapPosition?(mapId, normalized, exclusivePartners, nil)
            return
        }

        // Позиция к якорю/крайнему штампу (как обычный лейбл со всеми тегами).
        onAttachMapPosition?(mapId, normalized, nil, nil)

        // Исходящие связки карты (активация тегов и т.п.).
        var visited = Set<String>()
        applyOutgoingBindings(
            from: buttonKey, sourceKind: .map, sourceId: mapId,
            sourceTagActivating: nil, triggeringLabelId: nil, visited: &visited
        )
    }

    // MARK: - Reset tap (Ctrl + ЛКМ)

    /// Сбрасывает счётчики, связанные с этой кнопкой связкой «сброс».
    ///
    /// Направление стрелки не важно: сброс — это отношение «кнопка ↔ счётчик», и связку рисуют
    /// в обе стороны. Прямое направление (кнопка — источник) отрабатывает и обычной цепочкой
    /// связок, здесь оно продублировано намеренно: сброс идемпотентен, зато жест работает и тогда,
    /// когда обычное действие кнопки мы пропускаем.
    /// Возвращает число сброшенных счётчиков.
    @discardableResult
    func applyClockResets(kind: CanvasButtonKind, elementId: String) -> Int {
        let buttonKey = "\(kind.rawValue):\(elementId)"

        var targets: [(clockId: String, delay: Double)] = []
        for binding in bindings where binding.type == .clockReset {
            if binding.sourceButtonKey == buttonKey, binding.targetKind == .clock {
                targets.append((binding.targetId, binding.delaySeconds ?? 0))
            } else if binding.targetButtonKey == buttonKey, binding.sourceKind == .clock {
                targets.append((binding.sourceId, binding.delaySeconds ?? 0))
            }
        }
        guard !targets.isEmpty else { return 0 }

        KeyBindingLog.log("сброс по связке от \(buttonKey): счётчики \(targets.map(\.clockId)), onResetClock \(onResetClock == nil ? "НЕ ПОДКЛЮЧЁН ❌" : "ok")")
        for target in targets {
            guard target.delay > 0 else {
                onResetClock?(target.clockId)
                continue
            }
            let work = DispatchWorkItem { [weak self] in
                DispatchQueue.main.async { self?.onResetClock?(target.clockId) }
            }
            pendingWork.append(work)
            DispatchQueue.global().asyncAfter(deadline: .now() + target.delay, execute: work)
        }
        return targets.count
    }

    /// Ctrl+ЛКМ (вторичный клик) по кнопке холста: отрабатывают ТОЛЬКО связки «сброс» —
    /// обычное действие кнопки не выполняется (тег на таймлайн не уходит, цепочки не запускаются,
    /// подсветка не трогается). Клик по самому счётчику сбрасывает его всегда, без связок.
    /// Возвращает `false`, если сбрасывать нечего — тогда вызывающий обрабатывает нажатие как обычное.
    @discardableResult
    func handleResetTap(kind: CanvasButtonKind, elementId: String) -> Bool {
        var count = applyClockResets(kind: kind, elementId: elementId)

        // Сам счётчик: вторичный клик по нему — это его сброс.
        if kind == .clock {
            onResetClock?(elementId)
            count += 1
        }

        guard count == 0 else { return true }

        let known = bindings.filter { $0.type == .clockReset }
            .map { "\($0.sourceButtonKey)→\($0.targetButtonKey)" }
        KeyBindingLog.log("handleResetTap \(kind.rawValue):\(elementId): сбрасывать нечего (всего bindings=\(bindings.count), связки сброса: \(known.isEmpty ? "нет" : known.joined(separator: ", ")))")
        return false
    }

    // MARK: - Clock tap (секундомер / таймер)

    /// Клик по счётчику на холсте. Ведёт себя как интервальный тег: активация запускает счётчик
    /// И его цепочку связок; повторное нажатие по идущему счётчику — просто остановка (связки
    /// не отрабатываем, как и у интервального тега, чтобы выключение не «дёргало» партнёров).
    /// Следа на таймлайне счётчик не оставляет — цепочка идёт от него как от обычного источника.
    func handleClockTap(clockId: String) {
        let buttonKey = "\(CanvasButtonKind.clock.rawValue):\(clockId)"
        let wasActive = isClockActive?(clockId) ?? false
        didCompleteHighlightPair = false

        KeyBindingLog.log("handleClockTap \(buttonKey) | активен=\(wasActive), исходящих=\(bindings.filter { $0.sourceButtonKey == buttonKey }.count)")

        // Нажатие счётчика — уход из текущей цепочки подсветки (в т.ч. если счётчик сам подсвечен:
        // пара считается отработанной). Гасим ДО связок — они могут поднять свою подсветку.
        if highlightModeActive { clearHighlight() }

        if wasActive {
            onStopClock?(clockId)
            return
        }

        onStartClock?(clockId)

        // Связки «сброс» этого счётчика на СОСЕДНИЕ счётчики (себя запуском не сбрасываем).
        applyClockResets(kind: .clock, elementId: clockId)

        var visited = Set<String>()
        applyOutgoingBindings(
            from: buttonKey, sourceKind: .clock, sourceId: clockId,
            sourceTagActivating: nil, triggeringLabelId: nil, visited: &visited
        )
        // Эксклюзив двунаправленный: применяем и когда счётчик — цель связки.
        applyIncomingExclusiveBindings(kind: .clock, elementId: clockId)
    }

    /// Теги — эксклюзивные партнёры карты (эксклюзивные связки тег↔карта с участием этой карты).
    func exclusiveTagPartners(ofMap mapId: String) -> Set<String> {
        var result = Set<String>()
        for binding in bindings where binding.type == .exclusive {
            if binding.sourceKind == .map, binding.sourceId == mapId, binding.targetKind == .tag {
                result.insert(binding.targetId)
            } else if binding.targetKind == .map, binding.targetId == mapId, binding.sourceKind == .tag {
                result.insert(binding.sourceId)
            }
        }
        return result
    }

    /// Нажат подсвеченный лейбл. Копим его. Если тег-якорь УЖЕ на таймлайне (не висит сам в подсветке) —
    /// прикрепляем накопленные лейблы к нему сразу. Иначе несём лейблы дальше по цепочке: они забандлятся
    /// в тег при завершении (если цепочка ведёт к тегу) или уйдут на крайний штамп, если цепочка кончилась.
    private func advanceChainWithLabel(labelId: String, buttonKey: String) {
        activateLabel(id: labelId)

        // Якорь «готов» (тег уже на таймлайне), если он задан и сам не висит в подсветке как цель.
        if let anchor = anchorTagId,
           !highlightedButtonIds.contains("\(CanvasButtonKind.tag.rawValue):\(anchor)") {
            onAttachLabelsToAnchor?(anchor, takeActivatedLabels(), nil)
        }

        // Снимаем ВСЕ текущие подсветки (нажатие подсвеченного убирает все), но сохраняем якорь —
        // цепочка продолжается только теми подсветками, что создаст сам нажатый лейбл ниже.
        highlightedButtonIds = []
        highlightHotkeys = [:]
        highlightOriginButtonKey = buttonKey

        var visited = Set<String>()
        applyOutgoingBindings(
            from: buttonKey, sourceKind: .label, sourceId: labelId,
            sourceTagActivating: nil, triggeringLabelId: labelId, visited: &visited
        )

        // Новых подсветок не появилось — цепочка завершена.
        if highlightedButtonIds.isEmpty {
            // Лейблы не ушли в тег (ни в якорь, ни через активацию) — прикрепляем к крайнему штампу.
            if !activatedLabelIds.isEmpty, !didActivateTagInChain {
                onAttachLabelsToLastStamp?(takeActivatedLabels(), nil)
            }
            clearHighlight()
        }
    }

    private func scheduleHighlightClearAfterBindings() {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.clearHighlight() }
        }
        pendingWork.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    func applyOutgoingBindingsAfterSourceAdded(kind: CanvasButtonKind, elementId: String) {
        let buttonKey = "\(kind.rawValue):\(elementId)"
        var visited = Set<String>()
        applyOutgoingBindings(
            from: buttonKey,
            sourceKind: kind,
            sourceId: elementId,
            sourceTagActivating: kind == .tag ? true : nil,
            triggeringLabelId: nil,
            visited: &visited
        )
    }

    // MARK: - Esc

    func resetHighlight() {
        cancelPendingWork()
        highlightModeActive = false
        highlightedButtonIds = []
        highlightHotkeys = [:]
        highlightOriginButtonKey = nil
        anchorTagId = nil
        activatedLabelIds = []
        pendingTimeEventIds = []
        didCompleteHighlightPair = false
    }

    // MARK: - Outgoing bindings (with cascade)

    private func applyOutgoingBindings(
        from sourceButtonKey: String,
        sourceKind: CanvasButtonKind,
        sourceId: String,
        sourceTagActivating: Bool?,
        triggeringLabelId: String?,
        visited: inout Set<String>
    ) {
        guard visited.insert(sourceButtonKey).inserted else { return }

        let outgoing = filteredOutgoingBindings(from: sourceButtonKey, sourceKind: sourceKind, sourceId: sourceId)
        for binding in outgoing {
            scheduleBinding(
                binding,
                sourceTagActivating: sourceTagActivating,
                triggeringLabelId: triggeringLabelId,
                visited: visited
            )
        }
    }

    private func filteredOutgoingBindings(
        from sourceButtonKey: String,
        sourceKind: CanvasButtonKind,
        sourceId: String
    ) -> [KeyBinding] {
        bindings.filter { binding in
            guard binding.sourceButtonKey == sourceButtonKey else { return false }
            return shouldApplyBinding(binding, from: sourceKind, sourceId: sourceId)
        }
    }

    private func shouldApplyBinding(
        _ binding: KeyBinding,
        from sourceKind: CanvasButtonKind,
        sourceId: String
    ) -> Bool {
        // Сами эксклюзивные связки применяются всегда.
        guard binding.type != .exclusive else { return true }
        // Эксклюзивный лейбл блокируется ТОЛЬКО во взаимодействии с ТЕГАМИ (не-эксклюзивная связка
        // лейбл↔тег). Связки эксклюзивного лейбла на лейблы/события работают как обычно.
        if binding.sourceKind == .label, binding.targetKind == .tag,
           labelHasExclusiveBindings(labelId: binding.sourceId) {
            return false
        }
        if binding.sourceKind == .tag, binding.targetKind == .label,
           labelHasExclusiveBindings(labelId: binding.targetId) {
            return false
        }
        return true
    }

    private func labelHasExclusiveBindings(labelId: String) -> Bool {
        bindings.contains { binding in
            binding.type == .exclusive && (
                (binding.sourceKind == .label && binding.sourceId == labelId) ||
                (binding.targetKind == .label && binding.targetId == labelId)
            )
        }
    }

    private func scheduleBinding(
        _ binding: KeyBinding,
        sourceTagActivating: Bool?,
        triggeringLabelId: String?,
        visited: Set<String>
    ) {
        let delay = binding.delaySeconds ?? 0
        if delay <= 0 {
            var mutableVisited = visited
            applyBinding(
                binding,
                sourceTagActivating: sourceTagActivating,
                triggeringLabelId: triggeringLabelId,
                visited: &mutableVisited
            )
            return
        }
        let capturedVisited = visited
        let capturedTrigger = triggeringLabelId
        let capturedActivating = sourceTagActivating
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var mutableVisited = capturedVisited
            DispatchQueue.main.async {
                self.applyBinding(
                    binding,
                    sourceTagActivating: capturedActivating,
                    triggeringLabelId: capturedTrigger,
                    visited: &mutableVisited
                )
            }
        }
        pendingWork.append(work)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func applyBinding(
        _ binding: KeyBinding,
        sourceTagActivating: Bool?,
        triggeringLabelId: String?,
        visited: inout Set<String>
    ) {
        let targetKey = binding.targetButtonKey
        KeyBindingLog.log("  применяю \(binding.type.rawValue): \(binding.sourceButtonKey) → \(targetKey)")
        switch binding.type {

        case .highlight:
            activateHighlight(binding: binding)

        case .activation:
            handleActivation(binding: binding, triggeringLabelId: triggeringLabelId, visited: &visited)

        case .deactivation:
            if binding.targetKind == .tag {
                KeyBindingLog.log("    ↳ deactivation \(binding.targetId): onStopIntervalTag \(onStopIntervalTag == nil ? "НЕ ПОДКЛЮЧЁН ❌" : "ok"), сейчас активен=\(isIntervalTagActive?(binding.targetId) ?? false)")
                onStopIntervalTag?(binding.targetId)
            } else if binding.targetKind == .clock {
                KeyBindingLog.log("    ↳ deactivation счётчика \(binding.targetId): onStopClock \(onStopClock == nil ? "НЕ ПОДКЛЮЧЁН ❌" : "ok")")
                onStopClock?(binding.targetId)
            }

        case .clockReset:
            if binding.targetKind == .clock {
                KeyBindingLog.log("    ↳ сброс счётчика \(binding.targetId): onResetClock \(onResetClock == nil ? "НЕ ПОДКЛЮЧЁН ❌" : "ok")")
                onResetClock?(binding.targetId)
            }

        case .intervalInversion:
            if binding.targetKind == .clock {
                let isActive = isClockActive?(binding.targetId) ?? false
                KeyBindingLog.log("    ↳ инверсия счётчика \(binding.targetId): активен=\(isActive)")
                if isActive {
                    onStopClock?(binding.targetId)
                } else {
                    startClockAndContinueChain(clockId: binding.targetId, visited: &visited)
                }
            } else if binding.targetKind == .tag {
                let isActive = isIntervalTagActive?(binding.targetId) ?? false
                KeyBindingLog.log("    ↳ intervalInversion \(binding.targetId): активен=\(isActive), onStart \(onStartIntervalTag == nil ? "НЕТ ❌" : "ok"), onStop \(onStopIntervalTag == nil ? "НЕТ ❌" : "ok")")
                if isActive {
                    onStopIntervalTag?(binding.targetId)
                } else {
                    // Если интервал запущен нажатием лейбла — лейбл попадёт в запись (bundled).
                    if let tl = triggeringLabelId { activateLabel(id: tl) }
                    didActivateTagInChain = true
                    onStartIntervalTag?(binding.targetId)
                    applyOutgoingBindings(
                        from: targetKey,
                        sourceKind: .tag,
                        sourceId: binding.targetId,
                        sourceTagActivating: true,
                        triggeringLabelId: nil,
                        visited: &visited
                    )
                }
            }

        case .visibility:
            runtimeVisibility[targetKey] = true
            if binding.revertVisibilityAfterPress == true {
                schedulePressRevertVisibility(targetKey: targetKey, revertTo: false)
            }

        case .invisibility:
            runtimeVisibility[targetKey] = false
            if binding.revertVisibilityAfterPress == true {
                schedulePressRevertVisibility(targetKey: targetKey, revertTo: true)
            }

        case .visibilityInversion:
            let current = runtimeVisibility[targetKey] ?? (items.first(where: { $0.id == targetKey })?.isVisible ?? true)
            runtimeVisibility[targetKey] = !current

        case .exclusive:
            if isStatefulKind(binding.sourceKind), isStatefulKind(binding.targetKind) {
                handleExclusiveStateful(binding: binding, sourceActivating: sourceTagActivating ?? true)
            }
            // Эксклюзив тег↔лейбл обрабатывается при простом ЛКМ по лейблу
            // (привязка к крайнему тегу только если он — эксклюзивный партнёр), без подсветки.
        }
    }

    private func isTagLabelPair(_ binding: KeyBinding) -> Bool {
        (binding.sourceKind == .tag && binding.targetKind == .label) ||
        (binding.sourceKind == .label && binding.targetKind == .tag)
    }

    /// Кнопки со «включённым/выключенным» состоянием: интервальный тег и счётчик.
    /// Только между ними эксклюзив означает «активация одного гасит другой».
    private func isStatefulKind(_ kind: CanvasButtonKind) -> Bool {
        kind == .tag || kind == .clock
    }

    private func handleExclusiveStateful(binding: KeyBinding, sourceActivating: Bool) {
        // Эксклюзив гасит партнёра только при АКТИВАЦИИ актора: повторное нажатие по уже
        // активному тегу/счётчику — обычное выключение, партнёра при этом не трогаем.
        guard sourceActivating else { return }
        deactivateExclusivePartner(kind: binding.targetKind, id: binding.targetId)
    }

    /// Эффект эксклюзивной связки тег↔тег (и тег↔счётчик / счётчик↔счётчик): активация одного
    /// гасит другой. Обратного эффекта («выключил один — включился другой») нет намеренно.
    private func deactivateExclusivePartner(kind: CanvasButtonKind, id: String) {
        switch kind {
        case .tag:
            if isIntervalTagActive?(id) == true { onStopIntervalTag?(id) }
        case .clock:
            if isClockActive?(id) == true { onStopClock?(id) }
        default:
            break
        }
    }

    /// Эксклюзивная связка работает в обе стороны: применяем её и когда нажатая кнопка —
    /// ЦЕЛЬ связки (обратное направление). Прямое направление (кнопка-источник) — в applyBinding.
    private func applyIncomingExclusiveBindings(kind: CanvasButtonKind, elementId: String) {
        let buttonKey = "\(kind.rawValue):\(elementId)"
        for binding in bindings where binding.type == .exclusive
            && isStatefulKind(binding.sourceKind) && isStatefulKind(binding.targetKind)
            && binding.targetButtonKey == buttonKey {
            deactivateExclusivePartner(kind: binding.sourceKind, id: binding.sourceId)
        }
    }

    private func activateHighlight(binding: KeyBinding) {
        highlightOriginButtonKey = binding.sourceButtonKey
        if binding.sourceKind == .tag {
            anchorTagId = binding.sourceId
        } else if binding.targetKind == .tag {
            anchorTagId = binding.targetId
        }

        var highlighted = highlightedButtonIds
        highlighted.insert(binding.targetButtonKey)
        highlightedButtonIds = highlighted
        highlightModeActive = true

        if let show = binding.showTargetOnHighlight {
            runtimeVisibility[binding.targetButtonKey] = show
        }

        if let hk = binding.highlightHotkey, !hk.isEmpty {
            highlightHotkeys[hk.lowercased()] = binding.targetButtonKey
        }

        if binding.revertVisibilityAfterPress == true, let show = binding.showTargetOnHighlight {
            schedulePostHighlightVisibilityRevert(targetKey: binding.targetButtonKey, revertTo: !show)
        }
    }

    /// Теги-эксклюзивные партнёры лейбла (эксклюзивные связки тег↔лейбл с участием этого лейбла).
    func exclusiveTagPartners(ofLabel labelId: String) -> Set<String> {
        var result = Set<String>()
        for binding in bindings where binding.type == .exclusive && isTagLabelPair(binding) {
            if binding.sourceKind == .label, binding.sourceId == labelId, binding.targetKind == .tag {
                result.insert(binding.targetId)
            } else if binding.targetKind == .label, binding.targetId == labelId, binding.sourceKind == .tag {
                result.insert(binding.sourceId)
            }
        }
        return result
    }

    private func handleActivation(
        binding: KeyBinding,
        triggeringLabelId: String?,
        visited: inout Set<String>
    ) {
        let targetId = binding.targetId
        let targetKey = binding.targetButtonKey

        // Защита от зацикливания: если целевой тег уже активирован в текущей цепочке
        // (теги связаны активацией в обе стороны — например бросок→нападение→защита и
        // защита→нападение), повторно его не активируем, иначе цепочка зациклится и
        // тег добавится ещё раз. `visited` содержит все теги, отработавшие в этой цепочке.
        if binding.targetKind == .tag, visited.contains(targetKey) {
            KeyBindingLog.log("    ↳ activation пропущена: \(targetKey) уже отработал в этой цепочке")
            return
        }

        // Цепочка активаций: исходный лейбл тоже копится, чтобы попасть в итоговый тег.
        if binding.sourceKind == .label {
            activateLabel(id: binding.sourceId)
        }

        if binding.targetKind == .tag {
            didActivateTagInChain = true
            KeyBindingLog.log("    ↳ activation тега \(targetId): onAddTag \(onAddTag == nil ? "НЕ ПОДКЛЮЧЁН ❌" : "ok")")
            let labels = takeActivatedLabels(triggeringLabelId: triggeringLabelId)
            let capturedVisited = visited
            let capturedTrigger = triggeringLabelId
            onAddTag?(targetId, binding.overrideTimeBefore, binding.overrideTimeAfter, labels) { [weak self] in
                guard let self else { return }
                var mutableVisited = capturedVisited
                self.applyOutgoingBindings(
                    from: targetKey,
                    sourceKind: .tag,
                    sourceId: targetId,
                    sourceTagActivating: true,
                    triggeringLabelId: capturedTrigger,
                    visited: &mutableVisited
                )
                // Лейблы, активированные исходящими связками этого тега (тег→лейбл в цепочке,
                // например лейбл→тег→лейбл), прикрепляем к нему же — иначе они терялись.
                if !self.activatedLabelIds.isEmpty {
                    self.onAttachLabelsToAnchor?(targetId, self.takeActivatedLabels(), nil)
                }
            }
        } else if binding.targetKind == .label {
            activateLabel(id: targetId)
            // Каскад: применяем исходящие связки активированного лейбла (цепочка активаций идёт дальше).
            applyOutgoingBindings(
                from: targetKey,
                sourceKind: .label,
                sourceId: targetId,
                sourceTagActivating: nil,
                triggeringLabelId: triggeringLabelId,
                visited: &visited
            )
        } else if binding.targetKind == .timeEvent {
            var pending = pendingTimeEventIds
            pending.insert(targetId)
            pendingTimeEventIds = pending
        } else if binding.targetKind == .clock {
            KeyBindingLog.log("    ↳ activation счётчика \(targetId): onStartClock \(onStartClock == nil ? "НЕ ПОДКЛЮЧЁН ❌" : "ok")")
            startClockAndContinueChain(clockId: targetId, visited: &visited)
        }
    }

    /// Запускает счётчик и продолжает цепочку его исходящими связками (счётчик как звено).
    /// Уже отработавший в этой цепочке счётчик пропускаем — иначе взаимные связки зациклятся.
    private func startClockAndContinueChain(clockId: String, visited: inout Set<String>) {
        let targetKey = "\(CanvasButtonKind.clock.rawValue):\(clockId)"
        guard !visited.contains(targetKey) else {
            KeyBindingLog.log("    ↳ счётчик \(targetKey) уже отработал в этой цепочке — пропуск")
            return
        }
        onStartClock?(clockId)
        applyOutgoingBindings(
            from: targetKey, sourceKind: .clock, sourceId: clockId,
            sourceTagActivating: nil, triggeringLabelId: nil, visited: &visited
        )
    }

    private func clearHighlight() {
        highlightModeActive = false
        highlightedButtonIds = []
        highlightHotkeys = [:]
        highlightOriginButtonKey = nil
        anchorTagId = nil
    }

    private func cancelPendingWork() {
        pendingWork.forEach { $0.cancel() }
        pendingWork = []
    }

    private var revertOnNextPress: [String: Bool] = [:]

    private func schedulePressRevertVisibility(targetKey: String, revertTo: Bool) {
        revertOnNextPress[targetKey] = revertTo
    }

    private func schedulePostHighlightVisibilityRevert(targetKey: String, revertTo: Bool) {
        revertOnNextPress[targetKey] = revertTo
    }

    func applyRevertVisibilityIfNeeded(for buttonKey: String) {
        if let revert = revertOnNextPress[buttonKey] {
            runtimeVisibility[buttonKey] = revert
            revertOnNextPress.removeValue(forKey: buttonKey)
        }
    }

    // MARK: - Highlight hotkey support

    @discardableResult
    func handleHighlightHotkey(_ hotkey: String) -> Bool {
        guard highlightModeActive,
              let targetKey = highlightHotkeys[hotkey.lowercased()] else {
            return false
        }
        let parts = targetKey.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let kind = CanvasButtonKind(rawValue: String(parts[0])) else {
            return false
        }
        let elementId = String(parts[1])
        return handleButtonTap(kind: kind, elementId: elementId)
    }
}
