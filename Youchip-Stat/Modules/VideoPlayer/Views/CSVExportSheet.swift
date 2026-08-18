//
//  CSVExportSheet.swift
//  Youchip-Stat
//
//  Диалог CSV-экспорта разметки: выбор формата (по таймлайнам / по тегам)
//  и конкретных таймлайнов или тегов (либо все сразу).
//

import SwiftUI
import AppKit

struct CSVExportSheet: View {

    let lines: [TimelineLine]
    let resolver: CSVNameResolver
    let defaultFileName: String
    let onClose: () -> Void

    enum Mode: Hashable { case timelines, tags }

    @State private var mode: Mode = .timelines
    @State private var selectedLineIDs: Set<UUID> = []
    @State private var selectedTagIDs: Set<String> = []
    @State private var allTimelines = true
    @State private var allTags = true

    private var timelineOptions: [(id: UUID, name: String)] {
        lines.filter { !$0.isServiceTimeline }.map { ($0.id, $0.name) }
    }

    private var tagOptions: [(id: String, name: String)] {
        var order: [String] = []
        var seen = Set<String>()
        for line in lines where !line.isServiceTimeline {
            for stamp in line.stamps where seen.insert(stamp.idTag).inserted {
                order.append(stamp.idTag)
            }
        }
        return order.map { ($0, resolver.tagName($0)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "tablecells").foregroundColor(.green)
                Text(^String.Titles.csvExportTitle).font(.headline)
                Spacer()
                Button(^String.Titles.collectionsButtonCancel) { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()

            Picker("", selection: $mode) {
                Text(^String.Titles.csvExportByTimelines).tag(Mode.timelines)
                Text(^String.Titles.csvExportByTags).tag(Mode.tags)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 20).padding(.top, 14)

            Text(mode == .timelines ? ^String.Titles.csvExportTimelinesHint : ^String.Titles.csvExportTagsHint)
                .font(.system(size: 11)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 6)

            selectionList
                .padding(.horizontal, 12).padding(.top, 8)

            Divider()
            HStack {
                Spacer()
                Button(^String.Titles.csvExportButton) { exportCSV() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canExport)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 460, height: 540)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var canExport: Bool {
        if mode == .timelines { return allTimelines || !selectedLineIDs.isEmpty }
        return allTags || !selectedTagIDs.isEmpty
    }

    @ViewBuilder
    private var selectionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if mode == .timelines {
                    checkRow(title: ^String.Titles.csvExportAll, isOn: allTimelines) {
                        allTimelines.toggle()
                        if allTimelines { selectedLineIDs.removeAll() }
                    }
                    Divider()
                    ForEach(timelineOptions, id: \.id) { option in
                        checkRow(title: option.name, isOn: !allTimelines && selectedLineIDs.contains(option.id)) {
                            allTimelines = false
                            toggle(&selectedLineIDs, option.id)
                        }
                    }
                } else {
                    checkRow(title: ^String.Titles.csvExportAll, isOn: allTags) {
                        allTags.toggle()
                        if allTags { selectedTagIDs.removeAll() }
                    }
                    Divider()
                    ForEach(tagOptions, id: \.id) { option in
                        checkRow(title: option.name, isOn: !allTags && selectedTagIDs.contains(option.id)) {
                            allTags = false
                            toggle(&selectedTagIDs, option.id)
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.05)))
    }

    private func checkRow(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundColor(isOn ? .green : .secondary)
                Text(title).font(.system(size: 13)).foregroundColor(.primary).lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3).padding(.horizontal, 6)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func exportCSV() {
        let csv: String
        if mode == .timelines {
            csv = MarkupCSVExporter.timelinesCSV(lines: lines, selectedLineIDs: allTimelines ? nil : selectedLineIDs, resolver: resolver)
        } else {
            csv = MarkupCSVExporter.tagsCSV(lines: lines, selectedTagIDs: allTags ? nil : selectedTagIDs, resolver: resolver)
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let suffix = mode == .timelines ? "timelines" : "tags"
        panel.nameFieldStringValue = "\(defaultFileName)_\(suffix).csv"
        panel.title = ^String.Titles.csvExportTitle
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.data(using: .utf8)?.write(to: url)
            onClose()
        }
    }
}
