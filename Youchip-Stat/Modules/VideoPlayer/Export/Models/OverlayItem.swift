//
//  OverlayItem.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 18.12.2025.
//

import AVKit

struct OverlayItem {
    let tag: Tag
    let stamp: TimelineStamp
    let selectedLabelGroups: [OverlayLabelGroupItem]
    let start: CMTime
    let duration: CMTime
    let videoSize: CGSize?
}

struct OverlayLabelGroupItem: Hashable {
    let group: LabelGroupData
    var selectedLabels: [Label]
    
    static func labelGroupItems(forLabels labelIds: [String]) -> [OverlayLabelGroupItem] {
        let tagLibrary = TagLibraryManager.shared
        var selectedLabelGroups: [OverlayLabelGroupItem] = []
        let stampLabels = labelIds.compactMap { labelID in
            tagLibrary.allLabels.first(where: { $0.id == labelID })
        }
        stampLabels.forEach { label in
            guard let labelGroup = tagLibrary.allLabelGroups.first(where: { $0.lables.contains(label.id) }) else { return }
            if let index = selectedLabelGroups.firstIndex(where: { $0.group.id == labelGroup.id }) {
                selectedLabelGroups[index].selectedLabels.append(label)
            } else {
                let groupItem = OverlayLabelGroupItem(group: labelGroup, selectedLabels: [label])
                selectedLabelGroups.append(groupItem)
            }
        }
        return selectedLabelGroups
    }
}

extension Array where Element == OverlayLabelGroupItem {
    
    var sortedByGroupName: [OverlayLabelGroupItem] {
        self.sorted { $0.group.name < $1.group.name }
    }
}
