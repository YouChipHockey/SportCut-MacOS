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
    /// Наносить ли логотип клуба (настраивается в настройках приложения).
    var showClubLogo: Bool = false

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

    /// Same as `labelGroupItems(forLabels:)` but resolves each label (and its group) from
    /// the pool first, falling back to the data embedded in the stamp's `labels`. This lets
    /// imported markup — whose labels/groups aren't in the local collection — still render
    /// in the burned-in export overlay. Additive: pooled entries always win.
    static func labelGroupItems(forStamp stamp: TimelineStamp) -> [OverlayLabelGroupItem] {
        let tagLibrary = TagLibraryManager.shared
        var selectedLabelGroups: [OverlayLabelGroupItem] = []
        for item in stamp.labels {
            let label: Label
            if let pooled = tagLibrary.findLabelById(item.id) {
                label = pooled
            } else if !item.name.isEmpty {
                label = Label(id: item.id, name: item.name, description: item.description)
            } else {
                continue
            }

            let group: LabelGroupData
            if let pooledGroup = tagLibrary.allLabelGroups.first(where: { $0.lables.contains(item.id) }) {
                group = pooledGroup
            } else if !item.lableGroupId.isEmpty {
                group = LabelGroupData(id: item.lableGroupId, name: ^String.Titles.sportCutLabels, lables: [item.id])
            } else {
                continue
            }

            if let index = selectedLabelGroups.firstIndex(where: { $0.group.id == group.id }) {
                selectedLabelGroups[index].selectedLabels.append(label)
            } else {
                selectedLabelGroups.append(OverlayLabelGroupItem(group: group, selectedLabels: [label]))
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
