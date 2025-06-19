//
//  Untitled.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/14/25.
//

import SwiftUI

struct FieldMapFilterView: View {
    @Binding var filters: FieldMapFilters
    @State private var availableEvents: [TimeEvent] = []
    @State private var availableTagGroups: [TagGroup] = []
    @State private var availableTags: [String: String] = [:] // ID -> Name
    @State private var availableLabelGroups: [LabelGroupData] = []
    @State private var availableLabels: [Label] = []
    
    let stamps: [TimelineStamp]
    let onApply: () -> Void
    let onReset: () -> Void
    let onCancle: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Фильтры")
                    .font(.headline)
                Spacer()
                
                Button(action: {
                    onCancle()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Закрыть без применения")
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Events filter section
                    filterSection(
                        title: "События",
                        items: availableEvents.map { ($0.id, $0.name) },
                        selectedIds: $filters.selectedEvents
                    )
                    
                    // Tag groups filter section
                    filterSection(
                        title: "Группы тегов",
                        items: availableTagGroups.map { ($0.id, $0.name) },
                        selectedIds: $filters.selectedTagGroups
                    )
                    
                    // Tags filter section
                    filterSection(
                        title: "Теги",
                        items: availableTags.map { ($0, $1) },
                        selectedIds: $filters.selectedTags
                    )
                    
                    // Label groups filter section
                    filterSection(
                        title: "Группы лейблов",
                        items: availableLabelGroups.map { ($0.id, $0.name) },
                        selectedIds: $filters.selectedLabelGroups
                    )
                    
                    // Labels filter section
                    filterSection(
                        title: "Лейблы",
                        items: availableLabels.map { ($0.id, $0.name) },
                        selectedIds: $filters.selectedLabels
                    )
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            HStack {
                Button("Сбросить") {
                    resetFilters()
                    onReset()
                }
                
                Spacer()
                
                Button("Применить") {
                    onApply()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
        .frame(width: 300, height: 500)
        .padding()
        .onAppear {
            loadAvailableFilterOptions()
        }
    }
    
    private func filterSection(title: String, items: [(id: String, name: String)], selectedIds: Binding<Set<String>>) -> some View {
        Section(header: Text(title).font(.subheadline).bold()) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.sorted { $0.name < $1.name }, id: \.id) { item in
                    Toggle(item.name, isOn: Binding(
                        get: { selectedIds.wrappedValue.contains(item.id) },
                        set: { newValue in
                            if newValue {
                                selectedIds.wrappedValue.insert(item.id)
                            } else {
                                selectedIds.wrappedValue.remove(item.id)
                            }
                        }
                    ))
                    .toggleStyle(CheckboxToggleStyle())
                }
                
                if items.isEmpty {
                    Text("Нет доступных элементов")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private func loadAvailableFilterOptions() {
        var eventIDs = Set<String>()
        stamps.forEach { stamp in
            stamp.timeEvents.forEach { eventIDs.insert($0) }
        }
        availableEvents = TagLibraryManager.shared.allTimeEvents
            .filter { eventIDs.contains($0.id) }
        
        var tagIDs = Set<String>()
        var tagGroupIDs = Set<String>()
        
        stamps.forEach { stamp in
            tagIDs.insert(stamp.idTag)
            if let group = TagLibraryManager.shared.findTagGroupForTag(stamp.idTag) {
                tagGroupIDs.insert(group.id)
            }
        }
        
        availableTagGroups = TagLibraryManager.shared.allTagGroups
            .filter { tagGroupIDs.contains($0.id) }
        
        availableTags = [:]
        tagIDs.forEach { tagID in
            if let tag = TagLibraryManager.shared.findTagById(tagID) {
                availableTags[tagID] = tag.name
            } else {
                availableTags[tagID] = "Tag #\(tagID)"
            }
        }
        
        var labelIDs = Set<String>()
        var labelGroupIDs = Set<String>()
        
        stamps.forEach { stamp in
            stamp.labels.forEach { labelID in
                labelIDs.insert(labelID)
                for group in TagLibraryManager.shared.allLabelGroups {
                    if group.lables.contains(labelID) {
                        labelGroupIDs.insert(group.id)
                        break
                    }
                }
            }
        }
        
        availableLabelGroups = TagLibraryManager.shared.allLabelGroups
            .filter { labelGroupIDs.contains($0.id) }
        
        availableLabels = []
        labelIDs.forEach { labelID in
            if let label = TagLibraryManager.shared.findLabelById(labelID) {
                availableLabels.append(label)
            }
        }
    }
    
    private func resetFilters() {
        filters.selectedEvents.removeAll()
        filters.selectedTagGroups.removeAll()
        filters.selectedTags.removeAll()
        filters.selectedLabelGroups.removeAll()
        filters.selectedLabels.removeAll()
    }
}
