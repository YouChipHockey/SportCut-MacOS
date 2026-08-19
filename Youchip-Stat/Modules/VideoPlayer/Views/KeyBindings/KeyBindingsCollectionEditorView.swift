//
//  KeyBindingsCollectionEditorView.swift
//  Youchip-Stat
//
//  Full-screen editor for key-bindings (.free) collections:
//  navigation panel | layout canvas | element settings.
//

import SwiftUI
import AppKit

struct KeyBindingsCollectionEditorView: View {

    @StateObject private var collectionManager: CustomCollectionManager
    @StateObject private var layoutSession = TagFreeLayoutEditorSession()

    @State private var layout: TagFreeLayout
    @State private var isNavCollapsed = false
    @State private var navTab: CollectionNavigationTab = .tags
    @State private var showSaveSuccess = false
    @State private var isEditingCollectionName = false
    /// Элемент, редактируемый в отдельном окне (двойной клик по кнопке в раскладке).
    @State private var elementToEdit: PendingCanvasEdit?
    @State private var showExportSheet = false
    /// Объекты, выбранные на холсте под удаление (ждут подтверждения).
    @State private var pendingDeletion: [CanvasElementRef] = []
    @State private var showDeleteAlert = false
    /// Отмена/возврат правок редактора (⌘Z / ⌘⇧Z).
    @StateObject private var history = CollectionEditorHistory()

    init() {
        let manager = CustomCollectionManager()
        _collectionManager = StateObject(wrappedValue: manager)
        _layout = State(initialValue: TagFreeLayoutStorage.makeDefaultLayout(for: []))
    }

    init(initialDisplayMode: CollectionTagLibraryDisplayMode) {
        let manager = CustomCollectionManager(initialDisplayMode: initialDisplayMode)
        _collectionManager = StateObject(wrappedValue: manager)
        _layout = State(initialValue: TagFreeLayoutStorage.makeDefaultLayout(for: []))
    }

    init(initialDisplayMode: CollectionTagLibraryDisplayMode, template: CollectionTemplate?) {
        let manager = CustomCollectionManager(initialDisplayMode: initialDisplayMode, template: template)
        _collectionManager = StateObject(wrappedValue: manager)
        _layout = State(initialValue: TagFreeLayoutStorage.makeDefaultLayout(for: manager.tags))
    }

    init(existingCollection: CollectionBookmark) {
        let manager = CustomCollectionManager(withBookmark: existingCollection)
        _collectionManager = StateObject(wrappedValue: manager)
        let stored = TagFreeLayoutStorage.loadLayoutIfExists(
            collectionId: manager.collectionID,
            tags: manager.tags,
            labels: manager.labels,
            timeEvents: manager.timeEvents,
            playFields: manager.playFields
        )
        _layout = State(initialValue: stored ?? TagFreeLayoutStorage.makeDefaultLayout(for: manager.tags))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarView
            Divider()

            HStack(spacing: 0) {
                if isNavCollapsed {
                    collapsedNavStrip
                } else {
                    CollectionNavigationPanel(
                        collectionManager: collectionManager,
                        layout: $layout,
                        selectedTab: $navTab,
                        isEditingCollectionName: $isEditingCollectionName,
                        onCollapse: { withAnimation { isNavCollapsed = true } }
                    )
                    .frame(minWidth: 300, maxWidth: 360)

                    Divider()
                }

                centerPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if navTab != .map {
                    Divider()

                    TagFreeLayoutEditorContent(
                        session: layoutSession,
                        layout: $layout,
                        tags: collectionManager.tags,
                        labels: collectionManager.labels,
                        timeEvents: collectionManager.timeEvents,
                        playFields: collectionManager.playFields,
                        clocks: collectionManager.clocks,
                        pane: .settings,
                        showsModePicker: false,
                        onSetTagsColor: setTagsColor,
                        onDuplicateElement: duplicateElement,
                        onCreatePlayFieldFromURL: createPlayFieldFromURL,
                        onDeleteElements: requestDeleteElements
                    )
                    .frame(width: 340)
                }
            }
        }
        .onAppear {
            normalizeLayoutFromManager()
            history.reset(to: currentSnapshot())
        }
        // История: снимок состояния после любой правки — раскладки или самой коллекции.
        // `CollectionEditorHistory` схлопывает серию правок одного действия в одну запись.
        .onChange(of: layoutHistorySignature) { _ in scheduleHistoryCapture() }
        .onReceive(collectionManager.objectWillChange) { _ in scheduleHistoryCapture() }
        .onChange(of: collectionManager.tags) { _ in normalizeLayoutFromManager() }
        .onChange(of: collectionManager.labels) { _ in normalizeLayoutFromManager() }
        .onChange(of: collectionManager.timeEvents) { _ in normalizeLayoutFromManager() }
        .onChange(of: collectionManager.playFields.map { $0.id }) { _ in normalizeLayoutFromManager() }
        .onDisappear {
            NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
        }
        .sheet(item: $elementToEdit) { target in
            CanvasElementEditSheet(
                collectionManager: collectionManager,
                layout: $layout,
                target: target,
                onDismiss: { elementToEdit = nil }
            )
        }
        .sheet(isPresented: $showExportSheet) {
            CollectionExportSheet(collectionManager: collectionManager, layout: layout,
                                  onDone: { showExportSheet = false })
        }
        .alert(^String.Titles.alertsAreYouSure, isPresented: $showDeleteAlert) {
            Button(^String.Titles.cancelButtonTitle, role: .cancel) { pendingDeletion = [] }
            Button(^String.Titles.deleteButtonTitle, role: .destructive) { performPendingDeletion() }
        } message: {
            Text(String(format: ^String.Titles.canvasDeleteConfirmMessage, pendingDeletion.count))
        }
    }

    // MARK: - История правок (⌘Z / ⌘⇧Z)

    /// Слепок раскладки для отслеживания правок холста: позиции, размеры, вид кнопок и связки.
    private var layoutHistorySignature: String {
        let items = layout.items
            .map { "\($0.id)|\(Int($0.center.x))|\(Int($0.center.y))|\(Int($0.size.width))|\(Int($0.size.height))|\(Int($0.rotation))|\($0.isVisible)|\($0.shape.rawValue)|\($0.fillOpacity)|\($0.strokeColor ?? "")|\($0.textColor ?? "")|\($0.fontSize)|\($0.showLabel)" }
            .joined(separator: ";")
        let bindings = layout.bindings
            .map { "\($0.sourceButtonKey)>\($0.targetButtonKey)" }
            .joined(separator: ";")
        return items + "#" + bindings
    }

    private func currentSnapshot() -> CollectionEditorSnapshot {
        CollectionEditorSnapshot(
            layout: layout,
            tags: collectionManager.tags,
            tagGroups: collectionManager.tagGroups,
            labels: collectionManager.labels,
            labelGroups: collectionManager.labelGroups,
            timeEvents: collectionManager.timeEvents,
            clocks: collectionManager.clocks,
            playFields: collectionManager.playFields
        )
    }

    private func scheduleHistoryCapture() {
        history.scheduleCapture { currentSnapshot() }
    }

    private func apply(_ snapshot: CollectionEditorSnapshot) {
        collectionManager.tags = snapshot.tags
        collectionManager.tagGroups = snapshot.tagGroups
        collectionManager.labels = snapshot.labels
        collectionManager.labelGroups = snapshot.labelGroups
        collectionManager.timeEvents = snapshot.timeEvents
        collectionManager.clocks = snapshot.clocks
        collectionManager.playFields = snapshot.playFields
        // Раскладку ставим последней: изменения пулов дёргают нормализацию, и она должна
        // работать уже по восстановленной раскладке.
        layout = snapshot.layout
        layoutSession.resetSelection()
    }

    private func undo() {
        guard let snapshot = history.undo() else { return }
        apply(snapshot)
    }

    private func redo() {
        guard let snapshot = history.redo() else { return }
        apply(snapshot)
    }

    // MARK: - Удаление объектов с холста

    /// Кнопку тега с холста убрать нельзя — нормализация раскладки вернёт её обратно, поэтому
    /// «удалить» на холсте редактора означает удалить сам объект коллекции. Спрашиваем подтверждение.
    private func requestDeleteElements(_ targets: [CanvasElementRef]) {
        guard !targets.isEmpty else { return }
        pendingDeletion = targets
        showDeleteAlert = true
    }

    private func performPendingDeletion() {
        let targets = pendingDeletion
        pendingDeletion = []
        guard !targets.isEmpty else { return }

        for target in targets {
            switch target.kind {
            case .tag:       collectionManager.deleteTag(id: target.elementId)
            case .label:     collectionManager.deleteLabel(id: target.elementId)
            case .timeEvent: collectionManager.removeTimeEvent(id: target.elementId)
            case .clock:     collectionManager.removeClock(id: target.elementId)
            case .map:       collectionManager.removeFieldImage(id: target.elementId)
            }
        }

        let ids = Set(targets.map { $0.id })
        layout.items.removeAll { ids.contains($0.id) }
        layout.bindings.removeAll { ids.contains($0.sourceButtonKey) || ids.contains($0.targetButtonKey) }
        layoutSession.resetSelection()
        normalizeLayoutFromManager()
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: 16) {
            Text(^String.Titles.freeLayoutTitle)
                .font(.headline)

            HStack(spacing: 6) {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(!history.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .help(^String.Titles.editorUndo)

                Button(action: redo) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.bordered)
                .disabled(!history.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help(^String.Titles.editorRedo)
            }

            Spacer()

            Button(action: saveAll) {
                HStack(spacing: 8) {
                    Image(systemName: showSaveSuccess ? "checkmark.circle.fill" : (collectionManager.isEditingExisting ? "arrow.clockwise" : "square.and.arrow.down"))
                    Text(collectionManager.isEditingExisting ? ^String.Titles.updateCollection : ^String.Titles.saveCollection)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(showSaveSuccess)

            Button(action: exportCollection) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text(^String.Titles.fieldMapButtonExport)
                }
            }
            .buttonStyle(.bordered)

            Menu {
                Button(^String.Titles.keyBindingsResetBindingsOnly) {
                    // Только связки — кнопки (их расположение) остаются на месте.
                    layout.bindings.removeAll()
                    layoutSession.resetSelection()
                }
                Button(^String.Titles.keyBindingsResetAll, role: .destructive) {
                    layout = TagFreeLayoutStorage.makeDefaultLayout(for: collectionManager.tags)
                    layoutSession.resetSelection()
                }
            } label: {
                Text(^String.Titles.sportCutReset)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var collapsedNavStrip: some View {
        VStack {
            Button(action: { withAnimation { isNavCollapsed = false } }) {
                Image(systemName: "sidebar.left")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(^String.Titles.keyBindingsShowNavigation)
            Spacer()
        }
        .frame(width: 36)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var centerPane: some View {
        if navTab == .map {
            CollectionFieldMapEditorView(collectionManager: collectionManager)
        } else {
            TagFreeLayoutEditorContent(
                session: layoutSession,
                layout: $layout,
                tags: collectionManager.tags,
                labels: collectionManager.labels,
                timeEvents: collectionManager.timeEvents,
                playFields: collectionManager.playFields,
                clocks: collectionManager.clocks,
                pane: .canvas,
                showsModePicker: true,
                onEditElement: requestElementEdit,
                onSetTagsColor: setTagsColor,
                onDuplicateElement: duplicateElement,
                onCreatePlayFieldFromURL: createPlayFieldFromURL,
                onExportSelected: { ids in _ = collectionManager.exportSelectedCanvasItems(ids, layout: layout) },
                onDeleteElements: requestDeleteElements
            )
        }
    }

    /// Двойной клик по элементу раскладки — открыть окно редактирования с двумя вкладками.
    private func requestElementEdit(kind: CanvasButtonKind, elementId: String) {
        elementToEdit = PendingCanvasEdit(kind: kind, elementId: elementId)
    }

    // MARK: - Actions

    private func normalizeLayoutFromManager() {
        layout = TagFreeLayoutStorage.normalizeLayout(
            layout,
            tags: collectionManager.tags,
            labels: collectionManager.labels,
            timeEvents: collectionManager.timeEvents,
            playFields: collectionManager.playFields,
            clocks: collectionManager.clocks,
            poolsAreAuthoritative: true
        )
    }

    /// Батч-смена цвета самих тегов (для выделенных кнопок-тегов на холсте).
    private func setTagsColor(_ tagIds: [String], hex: String) {
        for tagId in tagIds {
            guard let tag = collectionManager.tags.first(where: { $0.id == tagId }) else { continue }
            _ = collectionManager.updateTag(
                id: tag.id, primaryID: tag.primaryID, name: tag.name, description: tag.description,
                color: hex, defaultTimeBefore: tag.defaultTimeBefore, defaultTimeAfter: tag.defaultTimeAfter,
                labelGroupIDs: tag.lablesGroup, hotkey: tag.hotkey, labelHotkeys: tag.labelHotkeys ?? [:],
                isInterval: tag.isInterval ?? false, mapEnabled: tag.mapEnabled ?? false
            )
        }
    }

    /// Дублирует сущность (тег/лейбл/событие) в коллекции — для копипаста кнопок холста.
    /// Имя копии = «Оригинал (копия)». Возвращает id новой сущности.
    private func duplicateElement(kind: CanvasButtonKind, sourceElementId: String) -> String? {
        let suffix = " " + (^String.Titles.collectionsCopySuffix)
        switch kind {
        case .tag:
            guard let tag = collectionManager.tags.first(where: { $0.id == sourceElementId }) else { return nil }
            let groupId = collectionManager.tagGroups.first(where: { $0.tags.contains(tag.id) })?.id
                ?? collectionManager.tagGroups.first?.id ?? ""
            let new = collectionManager.createTag(
                name: tag.name + suffix, description: tag.description, color: tag.color,
                defaultTimeBefore: tag.defaultTimeBefore, defaultTimeAfter: tag.defaultTimeAfter,
                inGroup: groupId, hotkey: nil, isInterval: tag.isInterval ?? false
            )
            return new.id
        case .label:
            guard let label = collectionManager.labels.first(where: { $0.id == sourceElementId }) else { return nil }
            let groupId = collectionManager.labelGroups.first(where: { $0.lables.contains(label.id) })?.id
                ?? collectionManager.labelGroups.first?.id ?? ""
            let new = collectionManager.createLabel(name: label.name + suffix, description: label.description, inGroup: groupId)
            return new.id
        case .timeEvent:
            guard let event = collectionManager.timeEvents.first(where: { $0.id == sourceElementId }) else { return nil }
            let new = collectionManager.createTimeEvent(name: event.name + suffix)
            return new.id
        case .map:
            // Карты (изображения) не дублируем при копипасте кнопок.
            return nil
        case .clock:
            return collectionManager.duplicateClock(id: sourceElementId, nameSuffix: suffix)?.id
        }
    }

    /// Создаёт PlayField из файла (перетаскивание карты из Finder на холст).
    private func createPlayFieldFromURL(_ url: URL) -> PlayField? {
        guard let id = collectionManager.addFieldImage(from: url) else { return nil }
        normalizeLayoutFromManager()
        return collectionManager.playFields.first(where: { $0.id == id })
    }

    private func saveAll() {
        if collectionManager.saveCollectionToFiles() {
            TagFreeLayoutStorage.saveLayout(layout, collectionId: collectionManager.collectionID)
            showSaveSuccess = true
            isEditingCollectionName = false
            NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showSaveSuccess = false
            }
        }
    }

    private func exportCollection() {
        showExportSheet = true
    }
}

/// Диалог экспорта: всё или часть (галочками) с сохранением связок/позиций для попавших в экспорт.
struct CollectionExportSheet: View {
    @ObservedObject var collectionManager: CustomCollectionManager
    let layout: TagFreeLayout
    var onDone: () -> Void

    @State private var partial = false
    @State private var checkedTags: Set<String> = []
    @State private var checkedLabels: Set<String> = []
    @State private var checkedEvents: Set<String> = []
    @State private var checkedMaps: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(^String.Titles.exportCollectionTitle).font(.headline)
                Spacer()
            }.padding()
            Divider()

            Picker("", selection: $partial) {
                Text(^String.Titles.keyBindingsExportAll).tag(false)
                Text(^String.Titles.keyBindingsExportPart).tag(true)
            }
            .pickerStyle(.segmented)
            .padding()

            if partial {
                Text(^String.Titles.keyBindingsExportChoosePart)
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        checkSection(^String.Titles.tags, items: collectionManager.tags.map { ($0.id, $0.name) }, checked: $checkedTags)
                        checkSection(^String.Titles.labels, items: collectionManager.labels.map { ($0.id, $0.name) }, checked: $checkedLabels)
                        checkSection(^String.Titles.commonEvents, items: collectionManager.timeEvents.map { ($0.id, $0.name) }, checked: $checkedEvents)
                        if !collectionManager.playFields.isEmpty {
                            checkSection(^String.Titles.keyBindingsLoadedMaps, items: collectionManager.playFields.map { ($0.id, $0.name) }, checked: $checkedMaps)
                        }
                    }.padding()
                }.frame(maxHeight: 380)
            }

            Divider()
            HStack {
                Button(^String.Titles.collectionsButtonCancel) { onDone() }
                Spacer()
                Button(^String.Titles.fieldMapButtonExport) {
                    if partial {
                        _ = collectionManager.exportFiltered(tagIds: checkedTags, labelIds: checkedLabels,
                                                             eventIds: checkedEvents, mapIds: checkedMaps, layout: layout)
                    } else {
                        _ = collectionManager.exportCollection()
                    }
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .disabled(partial && checkedTags.isEmpty && checkedLabels.isEmpty && checkedEvents.isEmpty && checkedMaps.isEmpty)
            }.padding()
        }
        .frame(width: 460)
    }

    private func checkSection(_ title: String, items: [(String, String)], checked: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !items.isEmpty {
                Text(title).font(.subheadline).fontWeight(.semibold)
                ForEach(items, id: \.0) { id, name in
                    Toggle(isOn: Binding(
                        get: { checked.wrappedValue.contains(id) },
                        set: { on in if on { checked.wrappedValue.insert(id) } else { checked.wrappedValue.remove(id) } }
                    )) {
                        Text(name.isEmpty ? id : name).font(.caption)
                    }
                }
            }
        }
    }
}
