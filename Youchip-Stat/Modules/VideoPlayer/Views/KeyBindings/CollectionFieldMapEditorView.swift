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
    @State private var activeAlert: FieldMapAlert?
    @State private var activeTagsOnTimelines = 0

    private enum FieldMapAlert: Identifiable {
        case fieldChange
        case fieldDelete
        var id: Self { self }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                if let playField = collectionManager.playField {
                    existingMapSection(playField)
                } else {
                    emptyMapSection
                }
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
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .fieldChange:
                return Alert(
                    title: Text(^String.Titles.fieldMapChange),
                    message: Text(String(format: ^String.Titles.fieldMapChangeWarning, String(activeTagsOnTimelines))),
                    primaryButton: .default(Text(^String.Titles.resetPositions)) {
                        resetTagPositionsOnTimelines()
                        selectNewFieldImage()
                    },
                    secondaryButton: .destructive(Text(^String.Titles.savePositions)) {
                        selectNewFieldImage()
                    }
                )
            case .fieldDelete:
                return Alert(
                    title: Text(^String.Titles.deleteFieldMap),
                    message: Text(String(format: ^String.Titles.fieldMapChangeWarning, String(activeTagsOnTimelines))),
                    primaryButton: .destructive(Text(^String.Titles.deleteMap)) {
                        collectionManager.deleteFieldImage()
                        resetTagPositionsOnTimelines()
                    },
                    secondaryButton: .cancel(Text(^String.Titles.collectionsButtonCancel))
                )
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "map.fill").foregroundColor(.purple).font(.title2)
            Text(^String.Titles.fieldMapSettings).font(.title2.weight(.semibold))
            Spacer()
        }
    }

    private func existingMapSection(_ playField: PlayField) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button(^String.Titles.replace) {
                    activeTagsOnTimelines = countActiveMapTagsOnTimelines()
                    if activeTagsOnTimelines > 0 { activeAlert = .fieldChange }
                    else { selectNewFieldImage() }
                }
                .buttonStyle(.bordered)
                Button(^String.Titles.delete) {
                    activeTagsOnTimelines = countActiveMapTagsOnTimelines()
                    if activeTagsOnTimelines > 0 { activeAlert = .fieldDelete }
                    else { collectionManager.deleteFieldImage() }
                }
                .buttonStyle(.bordered)
            }

            if let bookmark = playField.imageBookmark,
               let url = createImageUrl(bookmark),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
                    .cornerRadius(12)
            }

            HStack(spacing: 24) {
                dimensionField(
                    title: ^String.Titles.collectionsFieldWidth,
                    value: playField.width,
                    onChange: { collectionManager.updateFieldDimensions(width: $0, height: playField.height) }
                )
                dimensionField(
                    title: ^String.Titles.collectionsFieldHeight,
                    value: playField.height,
                    onChange: { collectionManager.updateFieldDimensions(width: playField.width, height: $0) }
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
            _ = collectionManager.setFieldImage(from: tempUrl)
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

    private func countActiveMapTagsOnTimelines() -> Int {
        TimelineDataManager.shared.lines.flatMap(\.stamps).filter { stamp in
            guard collectionManager.tags.contains(where: { stamp.idTags.contains($0.id) }) else { return false }
            return stamp.position != nil && (stamp.isActiveForMapView ?? false)
        }.count
    }

    private func resetTagPositionsOnTimelines() {
        let timeline = TimelineDataManager.shared
        for i in timeline.lines.indices {
            for j in timeline.lines[i].stamps.indices {
                let stamp = timeline.lines[i].stamps[j]
                if collectionManager.tags.contains(where: { stamp.idTags.contains($0.id) }) {
                    timeline.lines[i].stamps[j].isActiveForMapView = false
                }
            }
        }
        timeline.updateTimelines()
    }
}
