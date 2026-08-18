//
//  MarkupClipSearchSheet.swift
//  Youchip-Stat
//
//  Поиск по клипам в режиме разметки. Тот же UX, что и в просмотре (ClipSearchResultsList),
//  но данные берутся из TimelineDataManager, а имена тегов/событий — из TagLibraryManager.
//  Выбор применяется к TimelineFilter.searchAllowedStampIDs → на таймлайне остаются только
//  найденные/выбранные клипы (см. FullControlView.displayLines).
//

import SwiftUI

struct MarkupClipSearchSheet: View {
    @ObservedObject var filter: TimelineFilter
    @ObservedObject private var timelineData = TimelineDataManager.shared
    @Environment(\.presentationMode) private var presentationMode

    @State private var searchText: String = ""
    @State private var selectedSearchTagIDs: Set<String> = []

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(^String.Titles.clipSearchTitle)
                    .font(.headline)
                Spacer()
                Button(^String.Titles.reset) {
                    filter.clearFilters()
                    searchText = ""
                    selectedSearchTagIDs = []
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.red)
            }
            .padding(.horizontal)
            .padding(.top)

            Divider()

            searchBar

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isSearching {
                        ClipSearchResultsList(
                            rows: clipSearchRows(),
                            query: searchText,
                            selectedTagIDs: $selectedSearchTagIDs
                        )
                    } else {
                        Text(^String.Titles.clipSearchPrompt)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal)
            }

            Divider()

            HStack {
                Button(^String.Titles.cancelButtonTitle) { presentationMode.wrappedValue.dismiss() }
                    .buttonStyle(PlainButtonStyle())
                Spacer()
                Button(^String.Titles.apply) { presentationMode.wrappedValue.dismiss() }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.blue)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 500, height: 500)
        .onAppear {
            searchText = filter.searchQuery
            let rows = clipSearchRows()
            if let allowed = filter.searchAllowedStampIDs {
                selectedSearchTagIDs = Set(rows.filter { !$0.stampIDs.isDisjoint(with: allowed) }.map(\.id))
            } else {
                selectedSearchTagIDs = Set(rows.map(\.id))
            }
        }
        .onChange(of: searchText) { _ in
            selectedSearchTagIDs = Set(clipSearchRows().map(\.id))
        }
        .onChange(of: selectedSearchTagIDs) { _ in
            applyClipSearch()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField(^String.Titles.search, text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 12))
            if isSearching {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(6)
        .padding(.horizontal)
    }

    private func clipSearchRows() -> [ClipSearchTagRow] {
        guard isSearching else { return [] }
        let tagLib = TagLibraryManager.shared
        var stamps: [TimelineStamp] = []
        var nameByStamp: [UUID: String] = [:]
        var labelsByStamp: [UUID: [String]] = [:]
        var eventsByStamp: [UUID: [String]] = [:]

        for line in timelineData.lines {
            for stamp in line.stamps {
                stamps.append(stamp)
                let tid = stamp.idTag
                nameByStamp[stamp.id] = tagLib.findTagById(tid)?.name ?? stamp.label
                labelsByStamp[stamp.id] = stamp.labels.map { lbl in
                    tagLib.findLabelById(lbl.id)?.name ?? lbl.name
                }
                eventsByStamp[stamp.id] = stamp.timeEvents.compactMap { eid in
                    tagLib.allTimeEvents.first(where: { $0.id == eid })?.name
                }
            }
        }

        return ClipSearch.buildRows(
            stamps: stamps,
            query: searchText,
            tagID: { $0.idTag },
            tagName: { nameByStamp[$0.id] ?? $0.label },
            labelNames: { labelsByStamp[$0.id] ?? [] },
            eventNames: { eventsByStamp[$0.id] ?? [] }
        )
    }

    private func applyClipSearch() {
        guard isSearching else {
            filter.searchQuery = ""
            filter.searchAllowedStampIDs = nil
            filter.isFilterActive = filter.hasActiveFilters()
            return
        }
        let allowed = clipSearchRows()
            .filter { selectedSearchTagIDs.contains($0.id) }
            .reduce(into: Set<UUID>()) { $0.formUnion($1.stampIDs) }
        filter.searchQuery = searchText
        filter.searchAllowedStampIDs = allowed
        filter.isFilterActive = filter.hasActiveFilters()
    }
}
