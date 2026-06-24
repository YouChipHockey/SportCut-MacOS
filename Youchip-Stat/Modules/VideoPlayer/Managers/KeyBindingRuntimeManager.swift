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
typealias AttachTimeEventsToAnchorCallback = (
    _ anchorTagId: String,
    _ timeEventIds: [String],
    _ onDone: (() -> Void)?
) -> Void

// MARK: - Manager

final class KeyBindingRuntimeManager: ObservableObject {

    static let shared = KeyBindingRuntimeManager()

    // MARK: - Published state

    @Published private(set) var highlightModeActive: Bool = false
    @Published private(set) var highlightedButtonIds: Set<String> = []
    @Published var runtimeVisibility: [String: Bool] = [:]

    // MARK: - Internal state

    private(set) var anchorTagId: String?
    @Published private(set) var pendingLabelIds: [String] = []
    @Published private(set) var pendingTimeEventIds: Set<String> = []
    private var bindings: [KeyBinding] = []
    private var items: [TagFreeLayoutItem] = []
    private(set) var highlightHotkeys: [String: String] = [:]
    private var pendingWork: [DispatchWorkItem] = []

    // MARK: - Callbacks (set by TagLibraryView)

    var onAddTag: AddTagCallback?
    var onStartIntervalTag: IntervalTagCallback?
    var onStopIntervalTag: StopIntervalTagCallback?
    var isIntervalTagActive: IsIntervalActiveCallback?
    var onAttachLabelsToAnchor: AttachLabelsToAnchorCallback?
    var onAttachTimeEventsToAnchor: AttachTimeEventsToAnchorCallback?

    private init() {}

    // MARK: - Pending selections

    func togglePendingTimeEvent(id: String) {
        if pendingTimeEventIds.contains(id) {
            pendingTimeEventIds.remove(id)
        } else {
            pendingTimeEventIds.insert(id)
        }
    }

    func togglePendingLabel(id: String) {
        if let index = pendingLabelIds.firstIndex(of: id) {
            pendingLabelIds.remove(at: index)
        } else {
            pendingLabelIds.append(id)
        }
    }

    func clearPendingTimeEvents() {
        pendingTimeEventIds = []
    }

    // MARK: - Configuration

    func configure(layout: TagFreeLayout) {
        bindings = layout.bindings
        items = layout.items
        reset()
    }

    func reset() {
        cancelPendingWork()
        highlightModeActive = false
        highlightedButtonIds = []
        anchorTagId = nil
        pendingLabelIds = []
        pendingTimeEventIds = []
        highlightHotkeys = [:]
    }

    func resetRuntimeVisibility() {
        runtimeVisibility = [:]
    }

    // MARK: - Button tap entry point

    @discardableResult
    func handleButtonTap(kind: CanvasButtonKind, elementId: String) -> Bool {
        let buttonKey = "\(kind.rawValue):\(elementId)"

        if highlightModeActive && !highlightedButtonIds.contains(buttonKey) {
            return false
        }

        // Повторное нажатие интервального тега завершает запись — исходящие связки не выполняем.
        if kind == .tag, isIntervalTagActive?(elementId) == true {
            return true
        }

        let isHighlightedSubPress = highlightModeActive && highlightedButtonIds.contains(buttonKey)
        let outgoing = bindings.filter { $0.sourceButtonKey == buttonKey }

        if kind == .label, isHighlightedSubPress, anchorTagId != nil {
            if !pendingLabelIds.contains(elementId) {
                pendingLabelIds.append(elementId)
            }
        }

        if kind == .timeEvent, isHighlightedSubPress, anchorTagId != nil {
            pendingTimeEventIds.insert(elementId)
        }

        var visited = Set<String>()
        applyOutgoingBindings(from: buttonKey, visited: &visited)

        if isHighlightedSubPress {
            finishHighlightedSubPress(
                kind: kind,
                elementId: elementId,
                buttonKey: buttonKey,
                outgoing: outgoing
            )
        }

        return true
    }

    /// Завершить нажатие подсвеченной суб-кнопки: активировать её или привязать лейблы к якорному тегу.
    private func finishHighlightedSubPress(
        kind: CanvasButtonKind,
        elementId: String,
        buttonKey: String,
        outgoing: [KeyBinding]
    ) {
        let hasActivationAction = outgoing.contains { $0.type == .activation }

        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            self.applyRevertVisibilityIfNeeded(for: buttonKey)
            self.clearHighlight()
        }

        switch kind {
        case .label:
            guard !hasActivationAction, let anchorTagId else {
                if hasActivationAction {
                    scheduleHighlightClearAfterBindings()
                } else {
                    finish()
                }
                return
            }
            let labelIds = pendingLabelIds
            pendingLabelIds = []
            onAttachLabelsToAnchor?(anchorTagId, labelIds, finish)

        case .timeEvent:
            guard !hasActivationAction, let anchorTagId else {
                if hasActivationAction {
                    scheduleHighlightClearAfterBindings()
                } else {
                    finish()
                }
                return
            }
            let eventIds = Array(pendingTimeEventIds)
            onAttachTimeEventsToAnchor?(anchorTagId, eventIds, finish)

        case .tag:
            let labels = pendingLabelIds
            pendingLabelIds = []

            // Если исходящая activation уже добавила этот же тег — не дублируем.
            let selfActivatedByBinding = outgoing.contains {
                $0.type == .activation && $0.targetKind == .tag && $0.targetId == elementId
            }

            if selfActivatedByBinding {
                scheduleHighlightClearAfterBindings()
            } else {
                onAddTag?(elementId, nil, nil, labels, finish)
            }
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

    /// Применить исходящие связки после того, как тег-источник уже добавлен (например, после выбора на карте).
    func applyOutgoingBindingsAfterSourceAdded(kind: CanvasButtonKind, elementId: String) {
        let buttonKey = "\(kind.rawValue):\(elementId)"
        var visited = Set<String>()
        applyOutgoingBindings(from: buttonKey, visited: &visited)
    }

    // MARK: - Esc

    func resetHighlight() {
        cancelPendingWork()
        highlightModeActive = false
        highlightedButtonIds = []
        highlightHotkeys = [:]
        anchorTagId = nil
        pendingLabelIds = []
        pendingTimeEventIds = []
    }

    // MARK: - Outgoing bindings (with cascade)

    /// Применить все исходящие связки от кнопки. При активации тега-цели каскадно
    /// отрабатывают и его исходящие связки (1→2→3).
    private func applyOutgoingBindings(from sourceButtonKey: String, visited: inout Set<String>) {
        guard visited.insert(sourceButtonKey).inserted else { return }

        let outgoing = bindings.filter { $0.sourceButtonKey == sourceButtonKey }
        for binding in outgoing {
            scheduleBinding(binding, visited: visited)
        }
    }

    private func scheduleBinding(_ binding: KeyBinding, visited: Set<String>) {
        let delay = binding.delaySeconds ?? 0
        if delay <= 0 {
            var mutableVisited = visited
            applyBinding(binding, visited: &mutableVisited)
            return
        }
        let capturedVisited = visited
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var mutableVisited = capturedVisited
            DispatchQueue.main.async {
                self.applyBinding(binding, visited: &mutableVisited)
            }
        }
        pendingWork.append(work)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func applyBinding(_ binding: KeyBinding, visited: inout Set<String>) {
        let targetKey = binding.targetButtonKey
        switch binding.type {

        case .highlight:
            activateHighlight(binding: binding)

        case .activation:
            handleActivation(binding: binding, visited: &visited)

        case .deactivation:
            if binding.targetKind == .tag {
                onStopIntervalTag?(binding.targetId)
            }

        case .intervalInversion:
            if binding.targetKind == .tag {
                let isActive = isIntervalTagActive?(binding.targetId) ?? false
                if isActive {
                    onStopIntervalTag?(binding.targetId)
                } else {
                    onStartIntervalTag?(binding.targetId)
                    applyOutgoingBindings(from: targetKey, visited: &visited)
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
        }
    }

    private func activateHighlight(binding: KeyBinding) {
        if binding.sourceKind == .tag {
            anchorTagId = binding.sourceId
        }

        highlightedButtonIds.insert(binding.targetButtonKey)
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

    private func handleActivation(binding: KeyBinding, visited: inout Set<String>) {
        let targetId = binding.targetId
        let targetKey = binding.targetButtonKey

        if binding.targetKind == .tag {
            let labels = pendingLabelIds
            pendingLabelIds = []
            let capturedVisited = visited
            onAddTag?(targetId, binding.overrideTimeBefore, binding.overrideTimeAfter, labels) { [weak self] in
                guard let self else { return }
                var mutableVisited = capturedVisited
                self.applyOutgoingBindings(from: targetKey, visited: &mutableVisited)
            }
        } else if binding.targetKind == .label {
            if !pendingLabelIds.contains(targetId) {
                pendingLabelIds.append(targetId)
            }
        } else if binding.targetKind == .timeEvent {
            pendingTimeEventIds.insert(targetId)
        }
    }

    private func clearHighlight() {
        highlightModeActive = false
        highlightedButtonIds = []
        highlightHotkeys = [:]
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
