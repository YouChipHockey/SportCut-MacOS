//
//  CollectionEditorHistory.swift
//  Youchip-Stat
//
//  Отмена/возврат в редакторе коллекции со связками клавиш (⌘Z / ⌘⇧Z).
//
//  История снимковая: правок в редакторе десятки (перетащили кнопку, сменили цвет, добавили
//  тег в панели слева, удалили объект, нарисовали связку) и живут они в двух местах сразу —
//  в раскладке холста и в самой коллекции. Ловить каждую мутацию отдельно нереально, поэтому
//  состояние снимается целиком и с задержкой: серия правок одного жеста (drag, набор цвета)
//  схлопывается в одну запись истории.
//

import Foundation

/// Полное состояние редактора на момент снимка.
struct CollectionEditorSnapshot {
    var layout: TagFreeLayout
    var tags: [Tag]
    var tagGroups: [TagGroup]
    var labels: [Label]
    var labelGroups: [LabelGroupData]
    var timeEvents: [TimeEvent]
    var clocks: [ClockEntity]
    var playFields: [PlayField]

    /// Отпечаток для сравнения снимков: модели редактора не `Equatable`, зато все `Codable`.
    var fingerprint: Data {
        let dto = Fingerprint(
            layout: layout,
            tags: tags,
            tagGroups: tagGroups,
            labels: labels,
            labelGroups: labelGroups,
            timeEvents: timeEvents,
            clocks: clocks,
            playFields: playFields
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(dto)) ?? Data()
    }

    private struct Fingerprint: Encodable {
        let layout: TagFreeLayout
        let tags: [Tag]
        let tagGroups: [TagGroup]
        let labels: [Label]
        let labelGroups: [LabelGroupData]
        let timeEvents: [TimeEvent]
        let clocks: [ClockEntity]
        let playFields: [PlayField]
    }
}

final class CollectionEditorHistory: ObservableObject {

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// Сколько шагов помним. Снимок — это вся коллекция, поэтому глубину держим разумной.
    private let limit = 40
    /// Серия правок одного действия (перетаскивание, ввод в поле) должна стать одной записью.
    private let debounceInterval: TimeInterval = 0.5

    private var undoStack: [CollectionEditorSnapshot] = []
    private var redoStack: [CollectionEditorSnapshot] = []
    private var current: (snapshot: CollectionEditorSnapshot, fingerprint: Data)?
    private var pendingCapture: DispatchWorkItem?

    /// Стартовое состояние редактора — точка, до которой можно откатиться.
    func reset(to snapshot: CollectionEditorSnapshot) {
        pendingCapture?.cancel()
        pendingCapture = nil
        undoStack = []
        redoStack = []
        current = (snapshot, snapshot.fingerprint)
        refreshFlags()
    }

    /// Снять состояние чуть позже — если правки продолжатся, запись схлопнется в одну.
    func scheduleCapture(_ capture: @escaping () -> CollectionEditorSnapshot) {
        pendingCapture?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.record(capture())
        }
        pendingCapture = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    func undo() -> CollectionEditorSnapshot? {
        guard let currentState = current, let previous = undoStack.popLast() else { return nil }
        redoStack.append(currentState.snapshot)
        current = (previous, previous.fingerprint)
        cancelPendingCapture()
        refreshFlags()
        return previous
    }

    func redo() -> CollectionEditorSnapshot? {
        guard let currentState = current, let next = redoStack.popLast() else { return nil }
        undoStack.append(currentState.snapshot)
        current = (next, next.fingerprint)
        cancelPendingCapture()
        refreshFlags()
        return next
    }

    private func record(_ snapshot: CollectionEditorSnapshot) {
        pendingCapture = nil
        let fingerprint = snapshot.fingerprint
        guard let currentState = current else {
            current = (snapshot, fingerprint)
            refreshFlags()
            return
        }
        // Ничего не изменилось (например, снимок после отмены) — историю не трогаем.
        guard fingerprint != currentState.fingerprint else { return }
        undoStack.append(currentState.snapshot)
        if undoStack.count > limit { undoStack.removeFirst() }
        redoStack.removeAll()
        current = (snapshot, fingerprint)
        refreshFlags()
    }

    /// Отложенный снимок после применения отмены/возврата не нужен: состояние уже известно.
    private func cancelPendingCapture() {
        pendingCapture?.cancel()
        pendingCapture = nil
    }

    private func refreshFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
