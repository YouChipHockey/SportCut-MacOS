//
//  CollectionsMenuView.swift
//  Youchip-Stat
//
//  Меню коллекций на главном экране: список, создание, операции с карточками.
//

import SwiftUI

struct CollectionsMenuView: View {

    @State private var collections: [CollectionInfo] = []
    @State private var showCreateTypeSheet = false
    @State private var selectedDisplayMode: CollectionTagLibraryDisplayMode = .grouped
    @State private var collectionToDelete: CollectionInfo?
    @State private var collectionToRename: CollectionInfo?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if collections.isEmpty {
                emptyState
            } else {
                collectionsGrid
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear(perform: reloadCollections)
        .onReceive(NotificationCenter.default.publisher(for: .collectionDataChanged)) { _ in
            reloadCollections()
        }
        .sheet(isPresented: $showCreateTypeSheet) {
            createCollectionTypeSheet
        }
        .alert(
            ^String.Titles.deleteCollection,
            isPresented: Binding(
                get: { collectionToDelete != nil },
                set: { if !$0 { collectionToDelete = nil } }
            )
        ) {
            Button(^String.Titles.cancelButtonTitle, role: .cancel) {
                collectionToDelete = nil
            }
            Button(^String.Titles.deleteCollection, role: .destructive) {
                if let item = collectionToDelete {
                    CollectionsBookmarksManager.shared.deleteCollectionCompletely(id: item.id)
                    collectionToDelete = nil
                    reloadCollections()
                }
            }
        } message: {
            if let item = collectionToDelete {
                Text(String(format: ^String.Titles.collectionsDeleteConfirmFormat, item.name))
            }
        }
        .alert(^String.Titles.rename, isPresented: Binding(
            get: { collectionToRename != nil },
            set: { if !$0 { collectionToRename = nil } }
        )) {
            TextField(^String.Titles.collectionName, text: $renameText)
            Button(^String.Titles.cancelButtonTitle, role: .cancel) {
                collectionToRename = nil
            }
            Button(^String.Titles.saveButtonTitle) {
                if let item = collectionToRename {
                    _ = CollectionsBookmarksManager.shared.renameCollection(id: item.id, newName: renameText)
                    collectionToRename = nil
                    reloadCollections()
                }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(^String.Titles.collectionsMenuTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(^String.Titles.collectionsMenuSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { showCreateTypeSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text(^String.Titles.createNewCollection)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Grid

    private var collectionsGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200), spacing: 16)],
                spacing: 16
            ) {
                ForEach(collections, id: \.id) { info in
                    collectionCard(info)
                }
            }
            .padding(20)
        }
    }

    private func collectionCard(_ info: CollectionInfo) -> some View {
        ZStack(alignment: .topTrailing) {
            Button(action: { openCollectionEditor(info) }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: info.displayMode == .free ? "keyboard" : "folder.fill")
                            .font(.system(size: 28))
                            .foregroundColor(info.displayMode == .free ? .orange : .blue)
                        Spacer()
                    }

                    Text(info.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(info.displayMode == .free
                         ? ^String.Titles.collectionTypeKeyBindings
                         : ^String.Titles.collectionTypeStandard)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(^String.Titles.rename) {
                    collectionToRename = info
                    renameText = info.name
                }
                Button(^String.Titles.sportCutDuplicate) {
                    _ = CollectionsBookmarksManager.shared.duplicateCollection(id: info.id)
                    reloadCollections()
                }
                Button(^String.Titles.exportCollectionTitle) {
                    exportCollection(info)
                }
                Divider()
                Button(^String.Titles.deleteCollection, role: .destructive) {
                    collectionToDelete = info
                }
            }

            Button(action: { collectionToDelete = info }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
            }
            .buttonStyle(.plain)
            .padding(8)
            .help(^String.Titles.deleteCollection)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(^String.Titles.collectionsMenuEmpty)
                .font(.headline)
                .foregroundColor(.secondary)
            Button(action: { showCreateTypeSheet = true }) {
                Text(^String.Titles.createNewCollection)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Create type sheet

    private var createCollectionTypeSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(^String.Titles.collectionTypePickerTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(^String.Titles.collectionTypePickerHint)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker(^String.Titles.collectionTypePickerTitle, selection: $selectedDisplayMode) {
                Text(^String.Titles.collectionTypeStandard).tag(CollectionTagLibraryDisplayMode.grouped)
                Text(^String.Titles.collectionTypeKeyBindings).tag(CollectionTagLibraryDisplayMode.free)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: selectedDisplayMode == .free ? "keyboard" : "rectangle.grid.2x2")
                        .foregroundColor(selectedDisplayMode == .free ? .orange : .blue)
                    Text(selectedDisplayMode == .free
                         ? ^String.Titles.collectionTypeKeyBindingsDescription
                         : ^String.Titles.collectionTypeStandardDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Spacer()

            HStack {
                Spacer()
                Button(^String.Titles.cancelButtonTitle) {
                    showCreateTypeSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button(^String.Titles.createNewCollection) {
                    showCreateTypeSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        WindowsManager.shared.openCustomCollectionsWindow(initialDisplayMode: selectedDisplayMode)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440, height: 280)
    }

    // MARK: - Actions

    private func reloadCollections() {
        collections = CollectionsBookmarksManager.shared.loadCollections()
    }

    private func openCollectionEditor(_ info: CollectionInfo) {
        guard let bookmark = CollectionsBookmarksManager.shared.collectionBookmark(for: info.id) else { return }
        WindowsManager.shared.openCustomCollectionsWindow(withExistingCollection: bookmark)
    }

    private func exportCollection(_ info: CollectionInfo) {
        let manager = CustomCollectionManager()
        guard manager.loadCollectionFromBookmarks(named: info.name) else { return }
        _ = manager.exportCollection()
    }
}
