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
}
