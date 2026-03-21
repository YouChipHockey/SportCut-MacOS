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
    
    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }
    
    private var activeSources: [SportCutSource] {
        guard let session = session else { return [] }
        if selectedSourceIndex == -1 {
            return session.sources
        } else if selectedSourceIndex < session.sources.count {
            return [session.sources[selectedSourceIndex]]
        }
        return []
    }
    
    private var availableTags: [Tag] {
        let allTags = activeSources.flatMap(\.tags)
        let usedTagIDs = Set(activeSources.flatMap { source in
            source.timelines.flatMap { line in
                line.stamps.flatMap(\.idTags)
            }
        })
        return allTags.filter { usedTagIDs.contains($0.id) }
    }
    
    private var availableTagGroups: [TagGroup] {
        activeSources.flatMap(\.tagGroups)
    }
    
    private var availableLabels: [Label] {
        let usedLabelIDs = Set(activeSources.flatMap { source in
            source.timelines.flatMap { line in
                line.stamps.flatMap(\.labelIDs)
            }
        })
        return activeSources.flatMap(\.labels).filter { usedLabelIDs.contains($0.id) }
    }
    
    private var availableLabelGroups: [LabelGroupData] {
        activeSources.flatMap(\.labelGroups)
    }
    
    private var availableEvents: [TimeEvent] {
        let usedEventIDs = Set(activeSources.flatMap { source in
            source.timelines.flatMap { line in
                line.stamps.flatMap(\.timeEvents)
            }
        })
        return activeSources.flatMap(\.timeEvents).filter { usedEventIDs.contains($0.id) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Фильтры")
                    .font(.headline)
                
                Spacer()
                
                Button("Сбросить") { filter.clearFilters() }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.red)
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !availableTagGroups.isEmpty {
                        filterSection(title: "Группы тегов") {
                            ForEach(availableTagGroups, id: \.id) { group in
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
                    
                    if !availableTags.isEmpty {
                        filterSection(title: "Теги") {
                            ForEach(availableTags, id: \.id) { tag in
                                tagFilterButton(tag: tag)
                            }
                        }
                    }
                    
                    if !availableLabelGroups.isEmpty {
                        filterSection(title: "Группы лейблов") {
                            ForEach(availableLabelGroups, id: \.id) { group in
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
                    
                    if !availableLabels.isEmpty {
                        filterSection(title: "Лейблы") {
                            ForEach(availableLabels, id: \.id) { label in
                                labelFilterButton(label: label)
                            }
                        }
                    }
                    
                    if !availableEvents.isEmpty {
                        filterSection(title: "Общие события") {
                            ForEach(availableEvents, id: \.id) { event in
                                eventFilterButton(event: event)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            HStack {
                Button("Отмена") { presentationMode.wrappedValue.dismiss() }
                    .buttonStyle(PlainButtonStyle())
                Spacer()
                Button("Применить") { presentationMode.wrappedValue.dismiss() }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.blue)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 500, height: 500)
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
