//
//  FieldMapVisualizationPicker.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/4/25.
//

import SwiftUI

enum VisualizationMode {
    case byTimeline
    case all
}

struct FieldMapVisualizationPicker: View {
    let onCancel: () -> Void
    let onVisualize: (CollectionBookmark, VisualizationMode, [TimelineStamp]) -> Void
    
    @State private var collections: [CollectionBookmark] = []
    @State private var selectedCollection: CollectionBookmark? = nil
    @State private var selectedMode: VisualizationMode = .all
    @State private var selectedTagIDs: Set<String> = []
    @State private var selectedTimelineIDs: Set<UUID> = []
    /// Id карт, на которых стоят точки, но которых нет (с картинкой) ни в одной коллекции —
    /// зато есть встроенная карта. Считаем один раз на onAppear (грузить все коллекции на каждый
    /// рендер дорого). Наличие таких id = доступна псевдо-коллекция «Импортированное».
    @State private var orphanMapIds: Set<String> = []
    @ObservedObject private var timelineData = TimelineDataManager.shared

    /// Сентинел псевдо-коллекции «Импортированное» (визуализация встроенных карт без коллекции).
    private static let importedCollectionId = "__imported_maps__"

    private var realAvailableCollections: [CollectionBookmark] {
        collections.filter { collection in
            let manager = CustomCollectionManager()
            // Годится ЛЮБАЯ карта коллекции с картинкой, не только playFields.first. В
            // мультикарточных коллекциях размечать могли по не-первой карте (разметка берёт
            // карты, привязанные к тегу — см. usableMapFields), а старый фильтр смотрел лишь на
            // первую и ошибочно выкидывал коллекцию → «Нет коллекций с настроенной картой поля».
            // isVisualizable/collectionTagAndFieldIds ниже уже работают со всеми playFields.
            return manager.loadCollectionFromBookmarks(named: collection.name) &&
                  manager.playFields.contains { $0.imageBookmark != nil }
        }
    }

    private var availableCollections: [CollectionBookmark] {
        var list = realAvailableCollections
        // Псевдо-коллекция для встроенных карт без коллекции-источника — чтобы визуализировать
        // можно было ВСЕГДА, независимо от проблем коллекций.
        if !orphanMapIds.isEmpty {
            list.append(Self.importedCollectionBookmark())
        }
        return list
    }

    private func isImportedCollection(_ collection: CollectionBookmark) -> Bool {
        collection.id == Self.importedCollectionId
    }

    private static func importedCollectionBookmark() -> CollectionBookmark {
        CollectionBookmark(
            id: importedCollectionId,
            name: ^String.Titles.fieldMapImportedGroup,
            tagGroupsBookmark: Data(), tagsBookmark: Data(),
            labelGroupsBookmark: Data(), labelsBookmark: Data(),
            timeEventsBookmark: Data(), playFieldBookmark: nil
        )
    }
    
    var body: some View {
        VStack {
            VStack(spacing: 20) {
                Text(^String.Titles.fieldMapVisualization)
                    .font(.headline)
                
                if availableCollections.isEmpty {
                    Text(^String.Titles.noCollectionsWithFieldMap)
                        .foregroundColor(.secondary)
                } else {
                    collectionSelectionSection
                    
                    if selectedCollection != nil {
                        visualizationModeSection
                        
                        switch selectedMode {
                        case .byTimeline:
                            timelineSelectionSection
                        case .all:
                            allTagsSection
                        }
                    }
                }
                
                HStack {
                    Button(^String.Titles.collectionsButtonCancel) {
                        onCancel()
                    }
                    
                    Spacer()
                        .help(^String.Titles.configureTagsOnFieldMap)
                    
                    Button(^String.Titles.visualize) {
                        if let collection = selectedCollection {
                            let stamps = getSelectedStamps()
                            onVisualize(collection, selectedMode, stamps)
                        }
                    }
                    .disabled(selectedCollection == nil || !canVisualize())
                }
                .padding(.top)
            }
            .frame(width: 500, height: 500)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadCollections()
        }
    }
    
    private var collectionSelectionSection: some View {
        VStack(alignment: .leading) {
            Text("\(^String.Titles.selectCollection):")
                .font(.subheadline)
                .bold()
            
            Picker(selection: $selectedCollection, label: Text(^String.Titles.collection)) {
                Text(^String.Titles.selectCollection).tag(nil as CollectionBookmark?)
                
                ForEach(availableCollections, id: \.name) { collection in
                    Text(collection.name).tag(collection as CollectionBookmark?)
                }
            }
            .onChange(of: selectedCollection) { _ in
                selectedTagIDs.removeAll()
                selectedTimelineIDs.removeAll()
            }
        }
    }
    
    private var visualizationModeSection: some View {
        VStack(alignment: .leading) {
            Text(^String.Titles.visualizationMode)
                .font(.subheadline)
                .bold()
            
            Picker("", selection: $selectedMode) {
                Text(^String.Titles.byTimelines).tag(VisualizationMode.byTimeline)
                Text(^String.Titles.allTags).tag(VisualizationMode.all)
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedMode) { _ in
                selectedTagIDs.removeAll()
                selectedTimelineIDs.removeAll()
            }
        }
    }
    
    private var tagSelectionSection: some View {
        VStack(alignment: .leading) {
            Text(^String.Titles.selectTags)
                .font(.subheadline)
                .bold()
            
            if availableTagsForCollection().isEmpty {
                Text(^String.Titles.noTagsWithPositionAvailable)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(availableTagsForCollection(), id: \.id) { tag in
                            HStack {
                                Rectangle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 12, height: 12)
                                
                                Text(tag.label)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                
                                Spacer()
                                
                                Toggle("", isOn: Binding(
                                    get: { selectedTagIDs.contains(tag.idTag) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedTagIDs.insert(tag.idTag)
                                        } else {
                                            selectedTagIDs.remove(tag.idTag)
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                            .padding(6)
                            .background(selectedTagIDs.contains(tag.idTag) ? Color.blue.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                        }
                    }
                    .padding(5)
                }
                .frame(height: 200)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    private var timelineSelectionSection: some View {
        VStack(alignment: .leading) {
            Text(^String.Titles.fieldMapPickerLabelSelectTimelines)
                .font(.subheadline)
                .bold()
            
            if availableTimelinesForCollection().isEmpty {
                Text(^String.Titles.fieldMapPickerNoTimelines)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(availableTimelinesForCollection(), id: \.id) { timeline in
                            HStack {
                                Text(timeline.name)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                
                                Spacer()
                                
                                Text("\(countPositionedStampsInTimeline(timeline)) \(^String.Titles.fieldMapPickerTagsCount)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Toggle("", isOn: Binding(
                                    get: { selectedTimelineIDs.contains(timeline.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedTimelineIDs.insert(timeline.id)
                                        } else {
                                            selectedTimelineIDs.remove(timeline.id)
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                            .padding(6)
                            .background(selectedTimelineIDs.contains(timeline.id) ? Color.blue.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                        }
                    }
                    .padding(5)
                }
                .frame(height: 200)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    private var allTagsSection: some View {
        VStack(alignment: .leading) {
            Text(^String.Titles.fieldMapPickerLabelAllTags)
                .font(.subheadline)
                .bold()
            
            let tagCount = allPositionedStampsForCollection().count
            
            if tagCount == 0 {
                Text(^String.Titles.fieldMapPickerNoPositionTags)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            } else {
                Text(String(format: ^String.Titles.fieldMapPickerTagsDisplayCount, tagCount))
                    .padding(.vertical, 5)
            }
        }
    }
    
    private func loadCollections() {
        collections = UserDefaults.standard.getCollectionBookmarks()
        recomputeOrphanMapIds()
    }

    /// Карты, на которых стоят точки, но которых нет (с картинкой) ни в одной коллекции, зато есть
    /// встроенная карта. Тяжёлый проход (грузит коллекции) — делаем один раз здесь, кэшируем.
    private func recomputeOrphanMapIds() {
        // id карт, реально использованных точками штампов.
        var referenced = Set<String>()
        for line in timelineData.lines {
            for stamp in line.stamps {
                for mp in stamp.mapPositions { if let id = mp.mapFieldId { referenced.insert(id) } }
            }
        }
        guard !referenced.isEmpty else { orphanMapIds = []; return }

        // id карт, которые коллекции могут показать (есть картинка).
        var provided = Set<String>()
        for c in collections {
            let m = CustomCollectionManager()
            guard m.loadCollectionFromBookmarks(named: c.name) else { continue }
            for f in m.playFields where f.imageBookmark != nil { provided.insert(f.id) }
        }

        orphanMapIds = referenced.subtracting(provided).filter { EmbeddedMapsStore.shared.contains(id: $0) }
    }

    /// Штампы, стоящие на «осиротевших» картах (только встроенные, без коллекции-источника).
    private func orphanStamps() -> [TimelineStamp] {
        guard !orphanMapIds.isEmpty else { return [] }
        return timelineData.lines.flatMap { line in
            line.stamps.filter { stamp in
                stamp.isActiveForMapView == true &&
                stamp.mapPositions.contains { mp in mp.mapFieldId.map { orphanMapIds.contains($0) } ?? false }
            }
        }
    }

    /// Id тегов и id карт (PlayField) выбранной коллекции — считаем один раз за проход. Для
    /// псевдо-коллекции «Импортированное» — теги/карты «осиротевших» штампов.
    private func collectionTagAndFieldIds(_ collection: CollectionBookmark) -> (tags: Set<String>, fields: Set<String>) {
        if isImportedCollection(collection) {
            let stamps = orphanStamps()
            let tags = Set(stamps.flatMap { $0.idTags })
            return (tags, orphanMapIds)
        }
        let manager = CustomCollectionManager()
        guard manager.loadCollectionFromBookmarks(named: collection.name) else { return ([], []) }
        return (Set(manager.tags.map { $0.id }), Set(manager.playFields.map { $0.id }))
    }

    /// Эффективный набор: карты коллекции + «осиротевшие» встроенные (для реальной коллекции), чтобы
    /// «Импортированное» показывалось вместе с картами коллекции. Для псевдо-коллекции — только orphan.
    private func effectiveTagAndFieldIds(_ collection: CollectionBookmark) -> (tags: Set<String>, fields: Set<String>) {
        let base = collectionTagAndFieldIds(collection)
        guard !isImportedCollection(collection), !orphanMapIds.isEmpty else { return base }
        let orphanTags = orphanStamps().flatMap { $0.idTags }
        return (base.tags.union(orphanTags), base.fields.union(orphanMapIds))
    }

    /// Штамп можно визуализировать, только если его тег в коллекции И карта, на которой стоит
    /// позиция, есть в этой коллекции. Иначе рисовать негде — не учитываем.
    private func isVisualizable(_ stamp: TimelineStamp, tagIds: Set<String>, fieldIds: Set<String>) -> Bool {
        guard !stamp.mapPositions.isEmpty, stamp.isActiveForMapView == true else { return false }
        guard stamp.idTags.contains(where: { tagIds.contains($0) }) else { return false }
        // Хотя бы одна точка попадает в карту этой коллекции (или legacy-точка без карты → первая карта).
        return stamp.mapPositions.contains { mp in
            if let mid = mp.mapFieldId { return fieldIds.contains(mid) }
            return !fieldIds.isEmpty
        }
    }

    private func availableTagsForCollection() -> [TimelineStamp] {
        guard let collection = selectedCollection else { return [] }
        let ids = effectiveTagAndFieldIds(collection)

        let allTags = timelineData.lines.flatMap { line in
            line.stamps.filter { isVisualizable($0, tagIds: ids.tags, fieldIds: ids.fields) }
        }

        var uniqueTags: [String: TimelineStamp] = [:]
        for tag in allTags {
            if uniqueTags[tag.idTag] == nil {
                uniqueTags[tag.idTag] = tag
            }
        }
        return uniqueTags.values.sorted { $0.label < $1.label }
    }

    private func availableTimelinesForCollection() -> [TimelineLine] {
        guard let collection = selectedCollection else { return [] }
        let ids = effectiveTagAndFieldIds(collection)
        return timelineData.lines.filter { line in
            line.stamps.contains { isVisualizable($0, tagIds: ids.tags, fieldIds: ids.fields) }
        }
    }

    private func countPositionedStampsInTimeline(_ timeline: TimelineLine) -> Int {
        guard let collection = selectedCollection else { return 0 }
        let ids = effectiveTagAndFieldIds(collection)
        return timeline.stamps.filter { isVisualizable($0, tagIds: ids.tags, fieldIds: ids.fields) }.count
    }

    private func allPositionedStampsForCollection() -> [TimelineStamp] {
        guard let collection = selectedCollection else { return [] }
        let ids = effectiveTagAndFieldIds(collection)
        return timelineData.lines.flatMap { line in
            line.stamps.filter { isVisualizable($0, tagIds: ids.tags, fieldIds: ids.fields) }
        }
    }

    private func getSelectedStamps() -> [TimelineStamp] {
        guard let collection = selectedCollection else { return [] }

        switch selectedMode {
        case .byTimeline:
            let ids = effectiveTagAndFieldIds(collection)
            return timelineData.lines.filter { line in
                selectedTimelineIDs.contains(line.id)
            }.flatMap { line in
                line.stamps.filter { isVisualizable($0, tagIds: ids.tags, fieldIds: ids.fields) }
            }

        case .all:
            return allPositionedStampsForCollection()
        }
    }
    
    private func canVisualize() -> Bool {        
        switch selectedMode {
        case .byTimeline:
            return !selectedTimelineIDs.isEmpty
        case .all:
            return !allPositionedStampsForCollection().isEmpty
        }
    }
}
