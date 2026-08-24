//
//  SportCutClipSearch.swift
//  Youchip-Stat
//
//  Инлайн-поиск по клипам в просмотре (SportCut): поле прямо в баре, результаты появляются по мере
//  ввода панелью под баром (без отдельного окна). Логику строк/применения держим здесь — её делят
//  таймлайн и таблица. Тот же движок строк, что в разметке (ClipSearch.buildRows), и то же
//  применение через TimelineFilter.searchAllowedStampIDs, что в SportCutFilterSheet.
//

import SwiftUI

enum SportCutClipSearch {

    /// Источники области поиска для сессии и выбранной вкладки источника (как в SportCutFilterSheet).
    static func scopeSources(sessionID: UUID, selectedSourceIndex: Int) -> [SportCutSource] {
        guard let session = SportCutSessionManager.shared.sessions.first(where: { $0.id == sessionID })
        else { return [] }
        if selectedSourceIndex < 0 { return session.sources }
        if selectedSourceIndex < session.sources.count { return [session.sources[selectedSourceIndex]] }
        return []
    }

    /// Строки-теги по запросу: имена резолвим из источника (или библиотеки), лейблы/события — из штампа.
    static func rows(sources: [SportCutSource], query: String) -> [ClipSearchTagRow] {
        let tagLib = TagLibraryManager.shared
        var stamps: [TimelineStamp] = []
        var nameByStamp: [UUID: String] = [:]
        var labelsByStamp: [UUID: [String]] = [:]
        var eventsByStamp: [UUID: [String]] = [:]

        for source in sources {
            for line in source.timelines where !line.isClocksTimeline {
                for stamp in line.stamps {
                    stamps.append(stamp)
                    let tid = stamp.idTag
                    let srcName = source.tags.first(where: { $0.id == tid })?.name
                    let libName = tagLib.findTagById(tid)?.name
                    nameByStamp[stamp.id] = srcName ?? libName ?? stamp.label
                    labelsByStamp[stamp.id] = stamp.labels.map(\.name)
                    eventsByStamp[stamp.id] = stamp.timeEvents.compactMap { eid -> String? in
                        if let e = source.timeEvents.first(where: { $0.id == eid }) { return e.name }
                        return tagLib.allTimeEvents.first(where: { $0.id == eid })?.name
                    }
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

    /// Применяет поиск к фильтру: остаются ВСЕ штампы, совпавшие с запросом (без промежуточной панели
    /// выбора). Пустой запрос — снимает поиск, не трогая категориальные фильтры.
    static func apply(to filter: TimelineFilter, query: String, sources: [SportCutSource]) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            filter.searchQuery = ""
            filter.searchAllowedStampIDs = nil
            filter.isFilterActive = filter.hasActiveFilters()
            return
        }
        let allowed = rows(sources: sources, query: query).reduce(into: Set<UUID>()) { $0.formUnion($1.stampIDs) }
        filter.searchQuery = query
        filter.searchAllowedStampIDs = allowed
        filter.isFilterActive = filter.hasActiveFilters()
    }
}

/// Инлайн-строка поиска для бара просмотра: компактное поле. Применение (сразу фильтрует по
/// совпадениям, без панели) делает родитель по `onChange(searchText)` через `SportCutClipSearch.apply`.
struct SportCutInlineSearchField: View {
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
    }
}
