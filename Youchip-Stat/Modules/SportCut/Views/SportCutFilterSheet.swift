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
                
                Button(^String.Titles.reset) { filter.clearFilters() }
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
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if filterProjectTab == -1 {
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
        VStack(alignment: .leading, spacing: 16) {
            if showSourceHeader {
                Text(source.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            let tagGroups = availableTagGroups(for: source, used: usedTagIDs)
            let tags = availableTags(for: source, used: usedTagIDs)
            let labelGroups = availableLabelGroups(for: source, used: usedLabelIDs)
            let labels = availableLabels(for: source, used: usedLabelIDs)
            let events = availableEvents(for: source, usedEventIDs: usedEventIDs)

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
                                let allSelected = groupLabels.allSatisfy { filter.selectedLabels.contains($0) }
                                
                                Button(action: {
                                    if allSelected {
                                        groupLabels.forEach { filter.selectedLabels.remove($0) }
                                    } else {
                                        groupLabels.forEach { filter.selectedLabels.insert($0) }
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
    
    private func labelFilterButton(label: Label) -> some View {
        let isSelected = filter.selectedLabels.contains(label.id)
        return Button(action: {
            if isSelected {
                filter.selectedLabels.remove(label.id)
            } else {
                filter.selectedLabels.insert(label.id)
            }
            filter.isFilterActive = filter.hasActiveFilters()
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
