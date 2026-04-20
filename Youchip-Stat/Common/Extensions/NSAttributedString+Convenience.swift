//
//  NSAttributedString+Convenience.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 20.12.2025.
//

import AppKit

extension NSAttributedString {
    
    static func attributedStringForTagInfo(overlayItem: OverlayItem) -> NSAttributedString? {
        let options = overlayItem.watermarkOptions
        guard options.showEpisodeNumbering || options.showTagAndLabels || options.showComment else {
            return nil
        }

        let attributedString = NSMutableAttributedString(string: "")
        let timelineManager = TimelineDataManager.shared
        let tagLibrary = TagLibraryManager.shared

        let tagName = overlayItem.tag.name
        let timeEvents = tagLibrary.allTimeEvents.filter { overlayItem.stamp.timeEvents.contains($0.id) }

        // Resolve ordinal: use playlist index when provided (viewer/organizer mode),
        // otherwise compute position among same-tag stamps (markup mode).
        let ordinal: Int
        if let playlistIndex = overlayItem.playlistIndex {
            ordinal = playlistIndex
        } else {
            let allStamps: [TimelineStamp] = timelineManager.lines.flatMap { $0.stamps }.sortedByStartTime
            let allStampsInfo: [(id: UUID, tagIds: [String], name: String)] = allStamps.map { ($0.id, $0.idTags, $0.label) }
            let stampsOfSingleType = allStampsInfo.filter { $0.tagIds.contains(overlayItem.tag.id) }
            guard let tagIndex = stampsOfSingleType.firstIndex(where: { $0.id == overlayItem.stamp.id }) else { return nil }
            ordinal = tagIndex + 1
        }

        let fontSize: CGFloat
        if let videoSize = overlayItem.videoSize {
            let baseHeight: CGFloat = 360
            let baseFontSize: CGFloat = 13
            fontSize = (videoSize.height / baseHeight) * baseFontSize
        } else {
            fontSize = 13
        }
        let timeEventAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.systemOrange
        ]
        let tagNameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.systemGreen
        ]
        let labelGroupNameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let labelNameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.white
        ]

        // Line 1: [ordinal prefix if enabled] + [tag name if either flag is on] + [time events if tagAndLabels enabled]
        if options.showEpisodeNumbering || options.showTagAndLabels {
            var lineStart = ""
            if options.showEpisodeNumbering {
                lineStart += "\(ordinal). "
            }
            lineStart += tagName
            attributedString.append(NSAttributedString(string: lineStart, attributes: tagNameAttributes))

            if options.showTagAndLabels && !timeEvents.isEmpty {
                attributedString.append(NSAttributedString(string: ", ", attributes: tagNameAttributes))
                let timeEventsString = timeEvents.enumerated().map { index, event in
                    event.name + (index < timeEvents.count - 1 ? ", " : "")
                }.joined() + "\n"
                attributedString.append(NSAttributedString(string: timeEventsString, attributes: timeEventAttributes))
            } else {
                attributedString.append(NSAttributedString(string: "\n", attributes: tagNameAttributes))
            }
        }

        // Lines 2…N: one line per label group (only when tagAndLabels is enabled)
        if options.showTagAndLabels {
            overlayItem.selectedLabelGroups.sortedByGroupName.forEach { labelGroupItem in
                labelGroupItem.selectedLabels.forEach { label in
                    let isLast = label == labelGroupItem.selectedLabels.last
                    let separator = isLast ? "\n" : ", "
                    attributedString.append(NSAttributedString(string: label.name + separator, attributes: labelNameAttributes))
                }
            }
        }

        // Last line: comment (only when comment is enabled)
        if options.showComment, let comment = overlayItem.stamp.comment, !comment.isEmpty {
            let commentAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: NSColor.white
            ]
            attributedString.append(NSAttributedString(string: comment, attributes: commentAttributes))
        }

        return attributedString.length > 0 ? attributedString : nil
    }
    
}
