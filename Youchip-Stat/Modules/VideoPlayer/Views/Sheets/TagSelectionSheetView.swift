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
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Выберите тег для экспорта")
                .font(.headline)
            
            List {
                ForEach(tagGroupsWithTags(), id: \.name) { groupInfo in
                    Section(header: Text(groupInfo.name).font(.subheadline).bold()) {
                        ForEach(groupInfo.tags) { tag in
                            Button(tag.name) {
                                onSelect(tag)
                            }
                        }
                    }
                }
            }
            .frame(width: 300)
            
            Button("Отмена") {
                presentationMode.wrappedValue.dismiss()
            }
            .padding(.top, 10)
        }
        .padding()
    }
    
    private func tagGroupsWithTags() -> [TagGroupWithTags] {
        let allGroups = tagLibrary.allTagGroups
        var groupsWithTags: [String: (name: String, tags: [Tag])] = [:]
        groupsWithTags["uncategorized"] = ("Без группы", [])
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
