//
//  TagSelectionSheetView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct TagGroupWithTags {
    let name: String
    let tags: [Tag]
}

struct TagSelectionSheetView: View {
    
    let uniqueTags: [Tag]
    let onSelect: (Tag) -> Void
    let onSelectWithLabels: (Tag) -> Void
    /// В оконном режиме закрывает окно шага; в режиме листа (nil) — через `presentationMode`.
    var onCancel: (() -> Void)? = nil
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            Text(^String.Titles.selectTagForExport)
                .font(.headline)
            
            List {
                ForEach(tagGroupsWithTags(), id: \.name) { groupInfo in
                    Section(header: Text(groupInfo.name).font(.subheadline).bold()) {
                        ForEach(groupInfo.tags) { tag in
                            HStack {
                                Text(tag.name)
                                Spacer()
                                
                                if hasLabelsForTag(tag) {
                                    Button(action: {
                                        onSelectWithLabels(tag)
                                    }) {
                                        Image(systemName: "ellipsis.circle")
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .help(^String.Titles.selectLabelsForThisTag)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(tag)
                            }
                        }
                    }
                }
            }
            
            HStack {
                Button(^String.Titles.collectionsButtonCancel) {
                    if let onCancel { onCancel() } else { presentationMode.wrappedValue.dismiss() }
                }
                
                Spacer()
                
                Text(^String.Titles.clickTagToExport)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)
        }
        .padding()
    }
    
    private func hasLabelsForTag(_ tag: Tag) -> Bool {
        let timelineData = TimelineDataManager.shared
        return timelineData.lines.contains { line in
            line.stamps.contains { stamp in
                stamp.idTags.contains(tag.id) && !stamp.labelIDs.isEmpty
            }
        }
    }
    
    private func tagGroupsWithTags() -> [TagGroupWithTags] {
        let allGroups = tagLibrary.allTagGroups
        var groupsWithTags: [String: (name: String, tags: [Tag])] = [:]
        groupsWithTags["uncategorized"] = (^String.Titles.fieldMapDetailNoGroup, [])
        for tag in uniqueTags {
            var foundGroup = false
            
            for group in allGroups {
                if group.tags.contains(tag.id) {
                    if groupsWithTags[group.id] == nil {
                        groupsWithTags[group.id] = (group.name, [])
                    }
                    groupsWithTags[group.id]?.tags.append(tag)
                    foundGroup = true
                    break
                }
            }
            
            if !foundGroup {
                groupsWithTags["uncategorized"]?.tags.append(tag)
            }
        }
        
        return groupsWithTags.values
            .filter { !$0.tags.isEmpty }
            .map { TagGroupWithTags(name: $0.name, tags: $0.tags) }
            .sorted { $0.name < $1.name }
    }
}
