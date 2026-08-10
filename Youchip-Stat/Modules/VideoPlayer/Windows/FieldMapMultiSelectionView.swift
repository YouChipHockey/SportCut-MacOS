//
//  FieldMapMultiSelectionView.swift
//  Youchip-Stat
//
//  Разметка тега, привязанного к нескольким картам: карты показываются стопкой
//  одна под другой, точку нужно поставить на каждой, и только потом можно продолжить.
//  На каждую карту создаётся отдельный штамп (см. TagLibraryView).
//

import SwiftUI
import Cocoa

/// Одна карта в мультивыборе: id соответствует `PlayField.id` (= `Tag.mapFieldIds`).
struct FieldMapSelectionItem: Identifiable {
    let id: String
    let name: String
    let imageBookmark: Data
}

struct FieldMapMultiSelectionView: View {

    let tag: Tag
    let items: [FieldMapSelectionItem]
    /// Возвращает нормализованные координаты (0...1) для каждой карты по её id.
    let onSave: ([String: CGPoint]) -> Void

    @State private var normalizedByField: [String: CGPoint] = [:]

    private var allMarked: Bool {
        items.allSatisfy { normalizedByField[$0.id] != nil }
    }

    private var markedCount: Int {
        items.reduce(0) { $0 + (normalizedByField[$1.id] != nil ? 1 : 0) }
    }

    /// Кол-во колонок сетки: в столбце максимум 2 карты (columns = ceil(count/2)).
    /// Окно открывается сразу во всю высоту экрана (см. `FieldMapMultiSelectionWindowController`).
    static func columnCount(for count: Int) -> Int {
        max(1, Int(ceil(Double(count) / 2.0)))
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top),
              count: Self.columnCount(for: items.count))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            // ScrollView остаётся как страховка, если экран меньше нужного размера сетки.
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 20) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        FieldMapSelectionRow(
                            index: index,
                            item: item,
                            tagColorHex: tag.color,
                            normalized: normalizedByField[item.id],
                            onPick: { normalizedByField[item.id] = $0 }
                        )
                    }
                }
                .padding()
            }

            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: tag.color)).frame(width: 12, height: 12)
            Text("\(^String.Titles.selectMapPositionForTag) \(tag.name)")
                .font(.headline)
            Spacer()
            Text(String.Titles.collectionsTagsCount.format(markedCount, items.count))
                .font(.caption)
                .foregroundColor(allMarked ? .green : .secondary)
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button(^String.Titles.collectionsButtonCancel) {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if !allMarked {
                Text(^String.Titles.fieldMapMarkAllHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(^String.Titles.saveButtonTitle) {
                onSave(normalizedByField)
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!allMarked)
        }
        .padding()
    }
}

/// Одна карта в стопке: изображение + отметка точки по тапу.
private struct FieldMapSelectionRow: View {

    let index: Int
    let item: FieldMapSelectionItem
    let tagColorHex: String
    let normalized: CGPoint?
    let onPick: (CGPoint) -> Void

    @State private var fieldImage: NSImage? = nil
    @State private var imageSize: CGSize = .zero

    private var selectedPoint: CGPoint? {
        guard let normalized, imageSize.width > 0, imageSize.height > 0 else { return nil }
        return CGPoint(x: normalized.x * imageSize.width, y: normalized.y * imageSize.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: normalized != nil ? "checkmark.circle.fill" : "\(index + 1).circle")
                    .foregroundColor(normalized != nil ? .green : .secondary)
                Text(item.name)
                    .font(.subheadline.weight(.medium))
            }

            if let image = fieldImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { imageSize = geo.size }
                                .onChange(of: geo.size) { imageSize = $0 }
                        }
                    )
                    .overlay(
                        Group {
                            if let point = selectedPoint {
                                Circle()
                                    .fill(Color(hex: tagColorHex))
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    .position(point)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard imageSize.width > 0, imageSize.height > 0,
                                      value.location.x >= 0, value.location.x <= imageSize.width,
                                      value.location.y >= 0, value.location.y <= imageSize.height else { return }
                                onPick(CGPoint(x: value.location.x / imageSize.width,
                                               y: value.location.y / imageSize.height))
                            }
                    )
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(8)
            } else {
                Text(^String.Titles.failedToLoadFieldMap)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .onAppear(perform: loadFieldImage)
    }

    private func loadFieldImage() {
        guard fieldImage == nil else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: item.imageBookmark, options: .withSecurityScope,
                              relativeTo: nil, bookmarkDataIsStale: &isStale)
            if url.startAccessingSecurityScopedResource() {
                fieldImage = NSImage(contentsOf: url)
                url.stopAccessingSecurityScopedResource()
            }
        } catch {
            print(error)
        }
    }
}
