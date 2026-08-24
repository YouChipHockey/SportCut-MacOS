//
//  MarkupInlineClipSearch.swift
//  Youchip-Stat
//
//  Инлайн-поиск по клипам в разметке: поле прямо в баре, результаты появляются панелью под баром
//  (без отдельного окна) — как в просмотре (SportCut). Раньше был отдельный лист
//  `MarkupClipSearchSheet`. Движок строк — общий `ClipSearch.buildRows`, применение — через
//  `TimelineFilter.searchAllowedStampIDs` (см. `FullControlView.displayLines`).
//

import SwiftUI

enum MarkupClipSearch {

    /// Строки-теги по запросу: имена тегов/лейблов/событий резолвим из библиотеки, лейблы — из штампа.
    static func rows(query: String) -> [ClipSearchTagRow] {
        let tagLib = TagLibraryManager.shared
        let timelineData = TimelineDataManager.shared
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
            query: query,
            tagID: { $0.idTag },
            tagName: { nameByStamp[$0.id] ?? $0.label },
            labelNames: { labelsByStamp[$0.id] ?? [] },
            eventNames: { eventsByStamp[$0.id] ?? [] }
        )
    }

    /// Применяет поиск к фильтру: на таймлайне остаются ВСЕ штампы, совпавшие с запросом (без
    /// промежуточной панели выбора). Пустой запрос — снимает поиск, не трогая категориальные фильтры.
    static func apply(to filter: TimelineFilter, query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            filter.searchQuery = ""
            filter.searchAllowedStampIDs = nil
            filter.isFilterActive = filter.hasActiveFilters()
            return
        }
        let allowed = rows(query: query).reduce(into: Set<UUID>()) { $0.formUnion($1.stampIDs) }
        filter.searchQuery = query
        filter.searchAllowedStampIDs = allowed
        filter.isFilterActive = filter.hasActiveFilters()
    }
}

/// Инлайн-строка поиска для бара разметки: компактное поле. Держит фокус (панель результатов —
/// обычный сосед в разметке родителя, не попап), поэтому запрос можно спокойно печатать.
struct MarkupInlineSearchField: View {
    @Binding var searchText: String

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField(^String.Titles.search, text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 12))
                .frame(width: 150)
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
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(6)
        .help(^String.Titles.clipSearchTitle)
    }
}
