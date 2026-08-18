//
//  SportCutFilterSheet.swift
//  Youchip-Stat
//

import SwiftUI

struct SportCutFilterSheet: View {
    let sessionID: UUID
    @ObservedObject var filter: TimelineFilter
    let selectedSourceIndex: Int
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    @Environment(\.presentationMode) var presentationMode
    /// -1 = показать все проекты секциями; иначе индекс `session.sources` — только этот проект.
    @State private var filterProjectTab: Int = -1
    @State private var searchText: String = ""
    /// Выбранные теги в результатах поиска по клипам (по умолчанию — все совпавшие).
    @State private var selectedSearchTagIDs: Set<String> = []
    
    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }
    
    private var activeSources: [SportCutSource] {
        guard let session = session else { return [] }
        if selectedSourceIndex < 0 {
            return session.sources
        } else if selectedSourceIndex < session.sources.count {
            return [session.sources[selectedSourceIndex]]
        }
        return []
    }

    private func usedTagIDs(in sources: [SportCutSource]) -> Set<String> {
        Set(sources.flatMap { source in
            source.timelines.flatMap { line in
                line.stamps.flatMap(\.idTags)
            }
        })
    }

    private func usedLabelIDs(in sources: [SportCutSource]) -> Set<String> {
        Set(sources.flatMap { source in
            source.timelines.flatMap { line in
                line.stamps.flatMap(\.labelIDs)
            }
        })
    }

    private func availableTags(for source: SportCutSource, used: Set<String>) -> [Tag] {
        let fromSource = source.tags.filter { used.contains($0.id) }
        if !fromSource.isEmpty { return fromSource }
        // Fallback 1: check TagLibrary
        let tagLib = TagLibraryManager.shared
        let fromLib = used.compactMap { tagLib.findTagById($0) }
        if !fromLib.isEmpty { return fromLib.sorted { $0.name < $1.name } }
        // Fallback 2: build synthetic tags directly from stamp data
        var seen = Set<String>()
        var result: [Tag] = []
        for line in source.timelines {
            for stamp in line.stamps {
                for tagId in stamp.idTags where used.contains(tagId) && seen.insert(tagId).inserted {
                    result.append(Tag(
                        id: tagId,
                        primaryID: stamp.primaryID,
                        name: stamp.label,
                        description: "",
                        color: stamp.colorHex,
                        defaultTimeBefore: 5,
                        defaultTimeAfter: 3,
                        collection: nil,
                        lablesGroup: [],
                        hotkey: nil,
                        labelHotkeys: nil,
                        mapEnabled: false,
                        isInterval: true
                    ))
                }
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    private func availableTagGroups(for source: SportCutSource, used: Set<String>) -> [TagGroup] {
        let fromSource = source.tagGroups.filter { group in
            group.tags.contains { used.contains($0) }
        }
        if !fromSource.isEmpty { return fromSource }
        let tagLib = TagLibraryManager.shared
        return tagLib.tagGroups.filter { group in
            group.tags.contains { used.contains($0) }
        }
    }

    private func availableLabels(for source: SportCutSource, used: Set<String>) -> [Label] {
        let fromSource = source.labels.filter { used.contains($0.id) }
        if !fromSource.isEmpty { return fromSource }
        // Fallback: build labels from stamp data
        var seen = Set<String>()
        var result: [Label] = []
        for line in source.timelines {
            for stamp in line.stamps {
                for lbl in stamp.labels where used.contains(lbl.id) && seen.insert(lbl.id).inserted {
                    result.append(Label(id: lbl.id, name: lbl.name, description: lbl.description))
                }
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    /// Группа лейблов имеет настоящее имя, если оно непустое и не равно её id.
    /// У экспортируемых/импортированных видео своих групп лейблов нет — их имя не резолвится,
    /// поэтому такие группы (без имени) в фильтре не показываем.
    private func hasResolvedName(_ name: String, id: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != id
    }

    private func availableLabelGroups(for source: SportCutSource, used: Set<String>) -> [LabelGroupData] {
        let fromSource = source.labelGroups.filter { group in
            group.lables.contains { used.contains($0) } && hasResolvedName(group.name, id: group.id)
        }
        if !fromSource.isEmpty { return fromSource }
        // Fallback: build label groups from stamp data — только группы с настоящим именем из библиотеки.
        var groupMap: [String: Set<String>] = [:] // groupId -> label IDs
        var groupNames: [String: String] = [:]
        for line in source.timelines {
            for stamp in line.stamps {
                for lbl in stamp.labels where used.contains(lbl.id) {
                    let gid = lbl.lableGroupId
                    guard !gid.isEmpty else { continue }
                    // Имя берём только из библиотеки. Если группа не резолвится в имя — не показываем её (id как имя не используем).
                    guard let lg = TagLibraryManager.shared.allLabelGroups.first(where: { $0.id == gid }),
                          hasResolvedName(lg.name, id: gid) else { continue }
                    groupMap[gid, default: []].insert(lbl.id)
                    groupNames[gid] = lg.name
                }
            }
        }
        return groupMap.compactMap { gid, labelIds -> LabelGroupData? in
            guard let name = groupNames[gid] else { return nil }
            return LabelGroupData(id: gid, name: name, lables: Array(labelIds))
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Сопоставление лейблов между проектами
    //
    // Один и тот же лейбл в разных проектах может иметь разные id: у каждого проекта своя копия
    // коллекции, id разводятся при импорте дублей, а у разметки из сторонних инструментов лейблы
    // вообще синтетические. Из-за этого отметка лейбла в секции одного проекта отсекала все
    // события второго — фильтр выглядел как «И» между проектами. Поэтому выбор лейбла
    // распространяем на все одноимённые лейблы всех проектов сессии; само сопоставление
    // штампа остаётся «ИЛИ» (`TimelineFilter.matches`).

    /// Индекс лейблов сессии: id → нормализованное имя и нормализованное имя → все его id.
    private struct LabelNameIndex {
        var keyByID: [String: String] = [:]
        var idsByKey: [String: Set<String>] = [:]

        /// Сам id плюс его одноимённые «двойники» из других проектов, и ключи их имён.
        func equivalents(of id: String) -> (ids: Set<String>, keys: Set<String>) {
            guard let key = keyByID[id] else { return ([id], []) }
            return ((idsByKey[key] ?? []).union([id]), [key])
        }

        func equivalents(of ids: [String]) -> (ids: Set<String>, keys: Set<String>) {
            var allIDs = Set<String>()
            var allKeys = Set<String>()
            for id in ids {
                let equivalent = equivalents(of: id)
                allIDs.formUnion(equivalent.ids)
                allKeys.formUnion(equivalent.keys)
            }
            return (allIDs, allKeys)
        }
    }

    private static func labelKey(_ name: String) -> String {
        TimelineFilter.labelKey(name)
    }

    /// Строится по клику (не на каждый рендер) — один проход по всем штампам сессии.
    private func labelNameIndex() -> LabelNameIndex {
        var index = LabelNameIndex()
        func add(id: String, name: String) {
            let key = Self.labelKey(name)
            // Безымянные лейблы (легаси-разметка хранит только id) сопоставлять не по чему.
            guard !key.isEmpty else { return }
            index.keyByID[id] = key
            index.idsByKey[key, default: []].insert(id)
        }
        for source in session?.sources ?? [] {
            for label in source.labels {
                add(id: label.id, name: label.name)
            }
            for line in source.timelines {
                for stamp in line.stamps {
                    for label in stamp.labels {
                        add(id: label.id, name: label.name)
                    }
                }
            }
        }
        return index
    }

    /// Выбор лейбла применяется сразу ко всем его id и к его имени: id покрывают уже загруженные
    /// проекты (чтобы чекбоксы одноимённых лейблов в секциях проектов были согласованы),
    /// имя — те, что добавят в сессию позже.
    private func setLabelsSelected(_ selection: (ids: Set<String>, keys: Set<String>), selected: Bool) {
        if selected {
            filter.selectedLabels.formUnion(selection.ids)
            filter.selectedLabelNames.formUnion(selection.keys)
        } else {
            filter.selectedLabels.subtract(selection.ids)
            filter.selectedLabelNames.subtract(selection.keys)
        }
        filter.isFilterActive = filter.hasActiveFilters()
    }

    private func availableEvents(for source: SportCutSource, usedEventIDs: Set<String>) -> [TimeEvent] {
        let fromSource = source.timeEvents.filter { usedEventIDs.contains($0.id) }
        if !fromSource.isEmpty { return fromSource }
        // Fallback: find events from TagLibrary
        let tagLib = TagLibraryManager.shared
        return usedEventIDs.compactMap { id in tagLib.allTimeEvents.first { $0.id == id } }
            .sorted { $0.name < $1.name }
    }

    private func usedEventIDs(in sources: [SportCutSource]) -> Set<String> {
        Set(sources.flatMap { source in
            source.timelines.flatMap { line in
                line.stamps.flatMap(\.timeEvents)
            }
        })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(^String.Titles.sportCutFilters)
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

            if let session = session, activeSources.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterProjectTabButton(title: ^String.Titles.sportCutAllTab, index: -1)
                        ForEach(Array(activeSources.enumerated()), id: \.element.id) { index, source in
                            filterProjectTabButton(title: source.name, index: index)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 6)
                Divider()
            }

            searchBar

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isSearching {
                        // Поиск по клипам: строки-теги с подсветкой; выбор → id штампов фильтра.
                        ClipSearchResultsList(
                            rows: clipSearchRows(),
                            query: searchText,
                            selectedTagIDs: $selectedSearchTagIDs
                        )
                    } else if filterProjectTab == -1 {
                        ForEach(activeSources, id: \.id) { source in
                            let usedTags = usedTagIDs(in: [source])
                            let usedLabels = usedLabelIDs(in: [source])
                            let usedEv = usedEventIDs(in: [source])
                            sourceFilterSections(
                                source: source,
                                usedTagIDs: usedTags,
                                usedLabelIDs: usedLabels,
                                usedEventIDs: usedEv,
                                showSourceHeader: activeSources.count > 1
                            )
                        }
                    } else if filterProjectTab >= 0, filterProjectTab < activeSources.count {
                        let source = activeSources[filterProjectTab]
                        let usedTags = usedTagIDs(in: [source])
                        let usedLabels = usedLabelIDs(in: [source])
                        let usedEv = usedEventIDs(in: [source])
                        sourceFilterSections(
                            source: source,
                            usedTagIDs: usedTags,
                            usedLabelIDs: usedLabels,
                            usedEventIDs: usedEv,
                            showSourceHeader: false
                        )
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
        .onChange(of: searchText) { _ in
            // Новый запрос — по умолчанию выбраны все совпавшие теги.
            selectedSearchTagIDs = Set(clipSearchRows().map(\.id))
        }
        .onChange(of: selectedSearchTagIDs) { _ in
            applyClipSearch()
        }
    }

    // MARK: - Поиск по фильтрам

    /// Поиск сужает списки тегов/лейблов/событий по подстроке имени; найденное можно отметить
    /// поштучно или целиком кнопкой «Выбрать все».
    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isSearching: Bool { !normalizedQuery.isEmpty }

    private func matchesSearch(_ name: String) -> Bool {
        guard isSearching else { return true }
        return name.lowercased().contains(normalizedQuery)
    }

    /// Источники, по которым сейчас идёт поиск: все проекты или выбранная вкладка.
    private var searchScopeSources: [SportCutSource] {
        if filterProjectTab == -1 { return activeSources }
        if filterProjectTab >= 0, filterProjectTab < activeSources.count { return [activeSources[filterProjectTab]] }
        return []
    }

    // MARK: - Поиск по клипам (строки-теги)

    /// Строит строки-теги по текущему запросу: тег попадает, если текст встречается в его имени,
    /// лейбле или общем событии любого из его штампов (в области поиска). Имена резолвим из
    /// источника (или библиотеки), лейблы берём из штампа.
    private func clipSearchRows() -> [ClipSearchTagRow] {
        guard isSearching else { return [] }
        let tagLib = TagLibraryManager.shared
        var stamps: [TimelineStamp] = []
        var nameByStamp: [UUID: String] = [:]
        var labelsByStamp: [UUID: [String]] = [:]
        var eventsByStamp: [UUID: [String]] = [:]

        for source in searchScopeSources {
            for line in source.timelines {
                for stamp in line.stamps {
                    stamps.append(stamp)
                    let tid = stamp.idTag
                    nameByStamp[stamp.id] = source.tags.first(where: { $0.id == tid })?.name
                        ?? tagLib.findTagById(tid)?.name
                        ?? stamp.label
                    labelsByStamp[stamp.id] = stamp.labels.map(\.name)
                    eventsByStamp[stamp.id] = stamp.timeEvents.compactMap { eid in
                        source.timeEvents.first(where: { $0.id == eid })?.name
                            ?? tagLib.allTimeEvents.first(where: { $0.id == eid })?.name
                    }
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

    /// Применяет выбор поиска по клипам к фильтру (набор id штампов выбранных тегов).
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

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        }
        .padding(.horizontal)
    }

    private func filterProjectTabButton(title: String, index: Int) -> some View {
        Button(action: { filterProjectTab = index }) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(filterProjectTab == index ? Color.blue : Color.gray.opacity(0.15))
                .foregroundColor(filterProjectTab == index ? .white : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func sourceFilterSections(
        source: SportCutSource,
        usedTagIDs: Set<String>,
        usedLabelIDs: Set<String>,
        usedEventIDs: Set<String>,
        showSourceHeader: Bool
    ) -> some View {
        // При поиске остаются только совпавшие по имени элементы; проект без совпадений скрываем целиком.
        let tagGroups = availableTagGroups(for: source, used: usedTagIDs).filter { matchesSearch($0.name) }
        let tags = availableTags(for: source, used: usedTagIDs).filter { matchesSearch($0.name) }
        let labelGroups = availableLabelGroups(for: source, used: usedLabelIDs).filter { matchesSearch($0.name) }
        let labels = availableLabels(for: source, used: usedLabelIDs).filter { matchesSearch($0.name) }
        let events = availableEvents(for: source, usedEventIDs: usedEventIDs).filter { matchesSearch($0.name) }
        let isEmpty = tagGroups.isEmpty && tags.isEmpty && labelGroups.isEmpty && labels.isEmpty && events.isEmpty

        if !isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                if showSourceHeader {
                    Text(source.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }

                    if !tagGroups.isEmpty {
                        filterSection(title: ^String.Titles.sportCutTagGroups) {
                            ForEach(tagGroups, id: \.id) { group in
                                let groupTags = group.tags
                                let allSelected = groupTags.allSatisfy { filter.selectedTags.contains($0) }
                                
                                Button(action: {
                                    if allSelected {
                                        groupTags.forEach { filter.selectedTags.remove($0) }
                                    } else {
                                        groupTags.forEach { filter.selectedTags.insert($0) }
                                    }
                                    filter.isFilterActive = filter.hasActiveFilters()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                                            .foregroundColor(allSelected ? .blue : .gray)
                                        Text(group.name)
                                            .font(.system(size: 12))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(allSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    
                    if !tags.isEmpty {
                        filterSection(title: ^String.Titles.sportCutTags) {
                            ForEach(tags, id: \.id) { tag in
                                tagFilterButton(tag: tag)
                            }
                        }
                    }
                    
                    if !labelGroups.isEmpty {
                        filterSection(title: ^String.Titles.sportCutLabelGroups) {
                            ForEach(labelGroups, id: \.id) { group in
                                let groupLabels = group.lables
                                let allSelected = groupLabels.allSatisfy { isLabelSelected(id: $0, in: source) }

                                Button(action: {
                                    setLabelsSelected(labelNameIndex().equivalents(of: groupLabels), selected: !allSelected)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                                            .foregroundColor(allSelected ? .blue : .gray)
                                        Text(group.name)
                                            .font(.system(size: 12))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(allSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    
                    if !labels.isEmpty {
                        filterSection(title: ^String.Titles.sportCutLabels) {
                            ForEach(labels, id: \.id) { label in
                                labelFilterButton(label: label)
                            }
                        }
                    }
                    
                    if !events.isEmpty {
                        filterSection(title: ^String.Titles.sportCutCommonEvents) {
                            ForEach(events, id: \.id) { event in
                                eventFilterButton(event: event)
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func filterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                content()
            }
        }
    }
    
    private func tagFilterButton(tag: Tag) -> some View {
        let isSelected = filter.selectedTags.contains(tag.id)
        return Button(action: {
            if isSelected {
                filter.selectedTags.remove(tag.id)
            } else {
                filter.selectedTags.insert(tag.id)
            }
            filter.isFilterActive = filter.hasActiveFilters()
        }) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .gray)
                Circle()
                    .fill(Color(hex: tag.color))
                    .frame(width: 6, height: 6)
                Text(tag.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    /// Лейбл считается выбранным и по id, и по имени: тот же лейбл в другом проекте может иметь другой id.
    private func isLabelSelected(id: String, name: String) -> Bool {
        filter.selectedLabels.contains(id) || filter.selectedLabelNames.contains(Self.labelKey(name))
    }

    /// Тот же признак для id из группы лейблов — имя резолвим через библиотеку проекта.
    private func isLabelSelected(id: String, in source: SportCutSource) -> Bool {
        if filter.selectedLabels.contains(id) { return true }
        guard let name = source.labels.first(where: { $0.id == id })?.name else { return false }
        return filter.selectedLabelNames.contains(Self.labelKey(name))
    }

    private func labelFilterButton(label: Label) -> some View {
        let isSelected = isLabelSelected(id: label.id, name: label.name)
        return Button(action: {
            setLabelsSelected(labelNameIndex().equivalents(of: label.id), selected: !isSelected)
        }) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .gray)
                Text(label.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func eventFilterButton(event: TimeEvent) -> some View {
        let isSelected = filter.selectedEvents.contains(event.id)
        return Button(action: {
            if isSelected {
                filter.selectedEvents.remove(event.id)
            } else {
                filter.selectedEvents.insert(event.id)
            }
            filter.isFilterActive = filter.hasActiveFilters()
        }) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .gray)
                Text(event.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
