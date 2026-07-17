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

    init(existingCollection: CollectionBookmark) {
        let manager = CustomCollectionManager(withBookmark: existingCollection)
        _collectionManager = StateObject(wrappedValue: manager)
        let stored = TagFreeLayoutStorage.loadLayoutIfExists(
            collectionId: manager.collectionID,
            tags: manager.tags,
            labels: manager.labels,
            timeEvents: manager.timeEvents
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
                        pane: .settings,
                        showsModePicker: false
                    )
                    .frame(width: 340)
                }
            }
        }
        .onAppear {
            normalizeLayoutFromManager()
        }
        .onChange(of: collectionManager.tags) { _ in normalizeLayoutFromManager() }
        .onChange(of: collectionManager.labels) { _ in normalizeLayoutFromManager() }
        .onChange(of: collectionManager.timeEvents) { _ in normalizeLayoutFromManager() }
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
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: 16) {
            Text(^String.Titles.freeLayoutTitle)
                .font(.headline)

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

            Button(^String.Titles.sportCutReset) {
                layout = TagFreeLayoutStorage.makeDefaultLayout(for: collectionManager.tags)
                layoutSession.resetSelection()
            }
            .buttonStyle(.bordered)
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
                pane: .canvas,
                showsModePicker: true,
                onEditElement: requestElementEdit
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
            timeEvents: collectionManager.timeEvents
        )
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
        if let url = collectionManager.exportCollection() {
            print("Collection exported to: \(url.path)")
        }
    }
}
