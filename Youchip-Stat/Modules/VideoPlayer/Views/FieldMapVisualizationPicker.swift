//
//  FieldMapVisualizationPicker.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/4/25.
//

import SwiftUI

enum VisualizationMode {
    case byTags
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
    @ObservedObject private var timelineData = TimelineDataManager.shared
    
    private var availableCollections: [CollectionBookmark] {
        collections.filter { collection in
            let manager = CustomCollectionManager()
            return manager.loadCollectionFromBookmarks(named: collection.name) &&
                  manager.playField != nil &&
                  manager.playField?.imageBookmark != nil
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Визуализация карты поля")
                .font(.headline)
            
            if availableCollections.isEmpty {
                Text("Нет коллекций с настроенной картой поля")
                    .foregroundColor(.secondary)
            } else {
                collectionSelectionSection
                
                if selectedCollection != nil {
                    visualizationModeSection
                    
                    switch selectedMode {
                    case .byTags:
                        tagSelectionSection
                    case .byTimeline:
                        timelineSelectionSection
                    case .all:
                        allTagsSection
                    }
                }
            }
            
            HStack {
                Button("Отмена") {
                    onCancel()
                }
                
                Spacer()
                .help("Настроить отображение тегов на карте поля")
                
                Button("Визуализировать") {
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
        .onAppear {
            loadCollections()
        }
    }
    
    private var collectionSelectionSection: some View {
        VStack(alignment: .leading) {
            Text("Выберите коллекцию:")
                .font(.subheadline)
                .bold()
            
            Picker(selection: $selectedCollection, label: Text("Коллекция")) {
                Text("Выберите коллекцию").tag(nil as CollectionBookmark?)
                
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
            Text("Режим визуализации:")
                .font(.subheadline)
                .bold()
            
            Picker("", selection: $selectedMode) {
                Text("По тегам").tag(VisualizationMode.byTags)
                Text("По таймлайнам").tag(VisualizationMode.byTimeline)
                Text("Все теги").tag(VisualizationMode.all)
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedMode) { _ in
                // Reset selections when mode changes
                selectedTagIDs.removeAll()
                selectedTimelineIDs.removeAll()
            }
        }
    }
    
    private var tagSelectionSection: some View {
        VStack(alignment: .leading) {
            Text("Выберите теги:")
                .font(.subheadline)
                .bold()
            
            if availableTagsForCollection().isEmpty {
                Text("Нет доступных тегов с позицией для данной коллекции")
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
            Text("Выберите таймлайны:")
                .font(.subheadline)
                .bold()
            
            if availableTimelinesForCollection().isEmpty {
                Text("Нет доступных таймлайнов с тегами с позицией для данной коллекции")
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
                                
                                Text("\(countPositionedStampsInTimeline(timeline)) тегов")
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
            Text("Все теги:")
                .font(.subheadline)
                .bold()
            
            let tagCount = allPositionedStampsForCollection().count
            
            if tagCount == 0 {
                Text("Нет тегов с позицией для этой коллекции")
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            } else {
                Text("Будет отображено \(tagCount) тегов с заданной позицией")
                    .padding(.vertical, 5)
            }
        }
    }
    
    private func loadCollections() {
        collections = UserDefaults.standard.getCollectionBookmarks()
    }
    
    private func availableTagsForCollection() -> [TimelineStamp] {
        guard let collection = selectedCollection else { return [] }
        
        let allTags = timelineData.lines.flatMap { line in
            line.stamps.filter { stamp in
                stamp.position != nil &&
                isTagFromCollection(stamp.idTag, collection: collection) &&
                (stamp.isActiveForMapView == true)
            }
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
        
        return timelineData.lines.filter { line in
            line.stamps.contains { stamp in
                stamp.position != nil &&
                isTagFromCollection(stamp.idTag, collection: collection) &&
                (stamp.isActiveForMapView == true)
            }
        }
    }
    
    private func countPositionedStampsInTimeline(_ timeline: TimelineLine) -> Int {
        guard let collection = selectedCollection else { return 0 }
        
        return timeline.stamps.filter { stamp in
            stamp.position != nil &&
            isTagFromCollection(stamp.idTag, collection: collection) &&
            (stamp.isActiveForMapView == true)
        }.count
    }
    
    private func allPositionedStampsForCollection() -> [TimelineStamp] {
        guard let collection = selectedCollection else { return [] }
        
        return timelineData.lines.flatMap { line in
            line.stamps.filter { stamp in
                stamp.position != nil &&
                isTagFromCollection(stamp.idTag, collection: collection) &&
                (stamp.isActiveForMapView == true)
            }
        }
    }
    
    private func isTagFromCollection(_ tagId: String, collection: CollectionBookmark) -> Bool {
        let collectionManager = CustomCollectionManager()
        guard collectionManager.loadCollectionFromBookmarks(named: collection.name) else {
            return false
        }
        
        return collectionManager.tags.contains { $0.id == tagId }
    }
    
    private func getSelectedStamps() -> [TimelineStamp] {
        guard let collection = selectedCollection else { return [] }
        
        switch selectedMode {
        case .byTags:
            return timelineData.lines.flatMap { line in
                line.stamps.filter { stamp in
                    stamp.position != nil &&
                    selectedTagIDs.contains(stamp.idTag) &&
                    isTagFromCollection(stamp.idTag, collection: collection)
                }
            }
            
        case .byTimeline:
            return timelineData.lines.filter { line in
                selectedTimelineIDs.contains(line.id)
            }.flatMap { line in
                line.stamps.filter { stamp in
                    stamp.position != nil &&
                    isTagFromCollection(stamp.idTag, collection: collection) &&
                    (stamp.isActiveForMapView == true)
                }
            }
            
        case .all:
            return allPositionedStampsForCollection()
        }
    }
    
    private func canVisualize() -> Bool {
        guard let collection = selectedCollection else { return false }
        
        switch selectedMode {
        case .byTags:
            return !selectedTagIDs.isEmpty
        case .byTimeline:
            return !selectedTimelineIDs.isEmpty
        case .all:
            return !allPositionedStampsForCollection().isEmpty
        }
    }
}
