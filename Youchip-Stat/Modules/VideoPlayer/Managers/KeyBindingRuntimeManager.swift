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
    private(set) var highlightOriginButtonKey: String?
    @Published private(set) var activatedLabelIds: [String] = []
    @Published private(set) var pendingTimeEventIds: Set<String> = []
    private(set) var didCompleteHighlightPair: Bool = false
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

    func labelOutgoingActivatesTag(labelId: String) -> Bool {
        let buttonKey = "\(CanvasButtonKind.label.rawValue):\(labelId)"
        return filteredOutgoingBindings(from: buttonKey, sourceKind: .label, sourceId: labelId).contains {
            $0.type == .activation && $0.targetKind == .tag
        }
    }

    func highlightOriginIsLabel() -> Bool {
        highlightOriginButtonKey?.hasPrefix("\(CanvasButtonKind.label.rawValue):") ?? false
    }

    func highlightOriginIsTag() -> Bool {
        highlightOriginButtonKey?.hasPrefix("\(CanvasButtonKind.tag.rawValue):") ?? false
    }

    /// Тег подсветил партнёра (лейбл) — ждём второе нажатие, тег на таймлайн пока не добавляем.
    func isWaitingForTagLabelPartner() -> Bool {
        highlightModeActive && highlightOriginIsTag()
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

    func applyExclusiveOnTagDeactivation(tagId: String) {
        let buttonKey = "\(CanvasButtonKind.tag.rawValue):\(tagId)"
        let outgoing = filteredOutgoingBindings(from: buttonKey, sourceKind: .tag, sourceId: tagId)
        for binding in outgoing where binding.type == .exclusive {
            if binding.sourceKind == .tag, binding.targetKind == .tag {
                handleExclusiveTagTag(binding: binding, sourceActivating: false)
            }
        }
    }

    // MARK: - Button tap entry point

    @discardableResult
    func handleButtonTap(kind: CanvasButtonKind, elementId: String) -> Bool {
        let buttonKey = "\(kind.rawValue):\(elementId)"
        let triggeringLabelId = kind == .label ? elementId : nil
        didCompleteHighlightPair = false

        if kind == .tag, isIntervalTagActive?(elementId) == true {
            return true
        }

        if tryCompleteHighlightPair(partnerKind: kind, partnerId: elementId) {
            didCompleteHighlightPair = true
            return true
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

        if !highlightModeActive {
            applyIncomingTagLabelExclusiveBindings(
                clickedKind: kind,
                clickedId: elementId,
                clickedButtonKey: buttonKey
            )
        }

        return true
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
            var labelIds = takeActivatedLabels()
            if !labelIds.contains(partnerId) {
                labelIds.append(partnerId)
            }
            onAddTag?(originId, nil, nil, labelIds, finish)

        default:
            clearHighlight()
            return false
        }

        return true
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
        if sourceKind == .label, labelHasExclusiveBindings(labelId: sourceId) {
            return binding.type == .exclusive
        }
        if binding.targetKind == .label, labelHasExclusiveBindings(labelId: binding.targetId) {
            return binding.type == .exclusive
        }
        if binding.sourceKind == .label, labelHasExclusiveBindings(labelId: binding.sourceId) {
            return binding.type == .exclusive
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
        switch binding.type {

        case .highlight:
            activateHighlight(binding: binding)

        case .activation:
            handleActivation(binding: binding, triggeringLabelId: triggeringLabelId, visited: &visited)

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
            if binding.sourceKind == .tag, binding.targetKind == .tag {
                handleExclusiveTagTag(binding: binding, sourceActivating: sourceTagActivating ?? true)
            } else if isTagLabelPair(binding) {
                activateExclusiveHighlight(binding: binding)
            }
        }
    }

    private func isTagLabelPair(_ binding: KeyBinding) -> Bool {
        (binding.sourceKind == .tag && binding.targetKind == .label) ||
        (binding.sourceKind == .label && binding.targetKind == .tag)
    }

    private func handleExclusiveTagTag(binding: KeyBinding, sourceActivating: Bool) {
        guard binding.sourceKind == .tag, binding.targetKind == .tag else { return }
        if sourceActivating {
            if isIntervalTagActive?(binding.targetId) == true {
                onStopIntervalTag?(binding.targetId)
            }
        } else {
            if isIntervalTagActive?(binding.targetId) != true {
                onStartIntervalTag?(binding.targetId)
            }
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

    private func activateExclusiveHighlight(binding: KeyBinding) {
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
    }

    /// Эксклюзивная связка тег↔лейбл срабатывает и при нажатии цели (например, лейбл при связке тег→лейбл).
    private func applyIncomingTagLabelExclusiveBindings(
        clickedKind: CanvasButtonKind,
        clickedId: String,
        clickedButtonKey: String
    ) {
        for binding in bindings where (binding.type == .exclusive || binding.type == .highlight) && isTagLabelPair(binding) {
            let isIncomingTarget = binding.targetKind == clickedKind && binding.targetId == clickedId
            let isIncomingSource = binding.sourceKind == clickedKind && binding.sourceId == clickedId
            guard isIncomingTarget || isIncomingSource else { continue }
            guard shouldApplyBinding(binding, from: clickedKind, sourceId: clickedId) else { continue }

            let partnerKey: String
            if binding.targetButtonKey == clickedButtonKey {
                partnerKey = binding.sourceButtonKey
            } else {
                partnerKey = binding.targetButtonKey
            }

            highlightOriginButtonKey = clickedButtonKey
            if binding.sourceKind == .tag {
                anchorTagId = binding.sourceId
            } else if binding.targetKind == .tag {
                anchorTagId = binding.targetId
            }

            var highlighted = highlightedButtonIds
            highlighted.insert(partnerKey)
            highlightedButtonIds = highlighted
            highlightModeActive = true
            break
        }
    }

    private func handleActivation(
        binding: KeyBinding,
        triggeringLabelId: String?,
        visited: inout Set<String>
    ) {
        let targetId = binding.targetId
        let targetKey = binding.targetButtonKey

        if binding.targetKind == .tag {
            let labels = labelsForTagAddition(triggeringLabelId: triggeringLabelId)
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
            }
        } else if binding.targetKind == .label {
            activateLabel(id: targetId)
        } else if binding.targetKind == .timeEvent {
            var pending = pendingTimeEventIds
            pending.insert(targetId)
            pendingTimeEventIds = pending
        }
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
