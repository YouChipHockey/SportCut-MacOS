//
//  OverlayItem.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 18.12.2025.
//

import AVKit

struct ExportWatermarkOptions {
    var showEpisodeNumbering: Bool = true
    var showTagAndLabels: Bool = true
    var showComment: Bool = true

    static let `default` = ExportWatermarkOptions()
}

struct OverlayItem {
    let tag: Tag
    let stamp: TimelineStamp
    let selectedLabelGroups: [OverlayLabelGroupItem]
    let start: CMTime
    let duration: CMTime
    let videoSize: CGSize?
    /// When set, this ordinal is used directly (e.g. playlist position in viewer mode)
    /// instead of computing it from the timeline stamps.
    let playlistIndex: Int?
    let watermarkOptions: ExportWatermarkOptions

    init(
        tag: Tag,
        stamp: TimelineStamp,
        selectedLabelGroups: [OverlayLabelGroupItem],
        start: CMTime,
        duration: CMTime,
        videoSize: CGSize?,
        playlistIndex: Int? = nil,
        watermarkOptions: ExportWatermarkOptions = .default
    ) {
        self.tag = tag
        self.stamp = stamp
        self.selectedLabelGroups = selectedLabelGroups
        self.start = start
        self.duration = duration
        self.videoSize = videoSize
        self.playlistIndex = playlistIndex
        self.watermarkOptions = watermarkOptions
    }
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
