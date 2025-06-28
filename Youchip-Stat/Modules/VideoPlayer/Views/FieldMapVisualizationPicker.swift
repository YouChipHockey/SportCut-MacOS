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
        switch selectedMode {
        case .byTimeline:
            return !selectedTimelineIDs.isEmpty
        case .all:
            return !allPositionedStampsForCollection().isEmpty
        }
    }
}
