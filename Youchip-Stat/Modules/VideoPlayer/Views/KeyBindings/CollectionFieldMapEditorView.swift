//
//  CollectionFieldMapEditorView.swift
//  Youchip-Stat
//
//  Field map editor for key-bindings collection editor (center pane).
//

import SwiftUI
import AppKit

struct CollectionFieldMapEditorView: View {

    @ObservedObject var collectionManager: CustomCollectionManager

    @State private var showCropSheet = false
    @State private var mapPendingDelete: PlayField?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                mapsSection
                tagsForMapSection
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showCropSheet) {
            if let bookmarkData = UserDefaults.standard.data(forKey: "tempImageBookmark"),
               let tempUrl = resolveBookmark(bookmarkData) {
                CropImageView(imageURL: tempUrl) { cropped in
                    handleCroppedImage(cropped, tempUrl: tempUrl)
                }
            }
        }
        .alert(item: $mapPendingDelete) { field in
            Alert(
                title: Text(^String.Titles.deleteFieldMap),
                message: Text(field.name),
                primaryButton: .destructive(Text(^String.Titles.deleteMap)) {
                    collectionManager.removeFieldImage(id: field.id)
                },
                secondaryButton: .cancel(Text(^String.Titles.collectionsButtonCancel))
            )
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "map.fill").foregroundColor(.purple).font(.title2)
            Text(^String.Titles.fieldMapSettings).font(.title2.weight(.semibold))
            Spacer()
            Button {
                selectNewFieldImage()
            } label: {
                SwiftUI.Label(^String.Titles.uploadFieldMap, systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var mapsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if collectionManager.playFields.isEmpty {
                emptyMapSection
            } else {
                ForEach(collectionManager.playFields, id: \.id) { field in
                    mapCard(field)
                }
            }
        }
    }

    private func mapCard(_ playField: PlayField) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "map").foregroundColor(.purple)
                Text(playField.name).font(.headline)
                Spacer()
                Button(^String.Titles.delete) { mapPendingDelete = playField }
                    .buttonStyle(.bordered)
            }

            if let bookmark = playField.imageBookmark,
               let url = createImageUrl(bookmark),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
            }

            HStack(spacing: 24) {
                dimensionField(
                    title: ^String.Titles.collectionsFieldWidth,
                    value: playField.width,
                    onChange: { collectionManager.updateFieldDimensions(id: playField.id, width: $0, height: playField.height) }
                )
                dimensionField(
                    title: ^String.Titles.collectionsFieldHeight,
                    value: playField.height,
                    onChange: { collectionManager.updateFieldDimensions(id: playField.id, width: playField.width, height: $0) }
                )
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }

    private var emptyMapSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "map").font(.system(size: 48)).foregroundColor(.purple.opacity(0.5))
            Text(^String.Titles.fieldMapNotSet).font(.headline)
            Text(^String.Titles.uploadFieldMapHint).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button {
                selectNewFieldImage()
            } label: {
                SwiftUI.Label(^String.Titles.uploadFieldMap, systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }

    private var tagsForMapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(^String.Titles.collectionsTagsForMap).font(.headline)
                Spacer()
                let enabled = collectionManager.tags.filter { $0.mapEnabled ?? false }.count
                Text(String.Titles.collectionsTagsCount.format(enabled, collectionManager.tags.count))
                    .font(.caption).foregroundColor(.secondary)
            }

            ForEach(collectionManager.tagGroups) { group in
                let groupTags = collectionManager.tags.filter { group.tags.contains($0.id) }
                if !groupTags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.name).font(.subheadline.weight(.semibold))
                        ForEach(groupTags) { tag in
                            HStack {
                                Circle().fill(Color(hex: tag.color)).frame(width: 10, height: 10)
                                Text(tag.name).font(.caption)
                                Spacer()
                                // Выбор карт для тега (мультивыбор): точку нужно поставить
                                // на каждой выбранной карте. Показываем, только если карт несколько.
                                if (tag.mapEnabled ?? false), collectionManager.playFields.count > 1 {
                                    mapMultiSelectMenu(for: tag)
                                }
                                Toggle("", isOn: Binding(
                                    get: { tag.mapEnabled ?? false },
                                    set: { collectionManager.updateTagMapEnabled(id: tag.id, mapEnabled: $0) }
                                ))
                                .labelsHidden()
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                }
            }
        }
    }

    /// Меню мультивыбора карт для тега. Отмеченные карты — те, на которых нужно
    /// поставить точку при разметке (на каждую создаётся отдельный штамп).
    @ViewBuilder
    private func mapMultiSelectMenu(for tag: Tag) -> some View {
        let selectedIds = Set(tag.resolvedMapFieldIds.isEmpty
                              ? [collectionManager.playFields.first?.id].compactMap { $0 }
                              : tag.resolvedMapFieldIds)
        Menu {
            ForEach(collectionManager.playFields, id: \.id) { field in
                Button {
                    collectionManager.toggleTagMapField(id: tag.id, mapFieldId: field.id)
                } label: {
                    HStack {
                        Text(field.name)
                        if selectedIds.contains(field.id) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "map")
                    .font(.system(size: 10))
                Text(mapSelectionSummary(selectedIds: selectedIds))
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(maxWidth: 160, alignment: .trailing)
    }

    /// Короткая подпись для кнопки мультивыбора карт: имя единственной карты или «N карт».
    private func mapSelectionSummary(selectedIds: Set<String>) -> String {
        if selectedIds.count == 1, let only = selectedIds.first,
           let field = collectionManager.playFields.first(where: { $0.id == only }) {
            return field.name
        }
        return String.Titles.collectionsTagsCount.format(selectedIds.count, collectionManager.playFields.count)
    }

    private func dimensionField(title: String, value: Double, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            HStack {
                TextField("", value: Binding(get: { value }, set: onChange), formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                Stepper("", value: Binding(get: { value }, set: onChange), in: 1...1000)
                    .labelsHidden()
            }
        }
    }

    private func selectNewFieldImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["png", "jpg", "jpeg"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let tempUrl = tempDir.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: tempUrl)
            let bookmark = try tempUrl.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.setValue(bookmark, forKey: "tempImageBookmark")
            showCropSheet = true
        } catch {
            print(error)
        }
    }

    private func handleCroppedImage(_ image: NSImage, tempUrl: URL) {
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: tempUrl)
            _ = collectionManager.addFieldImage(from: tempUrl)
        }
        tempUrl.stopAccessingSecurityScopedResource()
        try? FileManager.default.removeItem(at: tempUrl)
    }

    private func createImageUrl(_ bookmark: Data) -> URL? {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            guard url.startAccessingSecurityScopedResource() else { return nil }
            return url
        } catch { return nil }
    }

    private func resolveBookmark(_ bookmark: Data) -> URL? {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            return url.startAccessingSecurityScopedResource() ? url : nil
        } catch { return nil }
    }

}
