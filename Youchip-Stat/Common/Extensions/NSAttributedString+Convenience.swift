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
        let labelNameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.white
        ]
        let labelGroupAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
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
                attributedString.append(NSAttributedString(string: " • ", attributes: tagNameAttributes))
                let timeEventsString = timeEvents.enumerated().map { index, event in
                    event.name + (index < timeEvents.count - 1 ? ", " : "")
                }.joined()
                attributedString.append(NSAttributedString(string: timeEventsString, attributes: timeEventAttributes))
            }
            let hasLabels = options.showTagAndLabels && !overlayItem.selectedLabelGroups.isEmpty
            let comment = (overlayItem.stamp.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hasComment = options.showComment && !comment.isEmpty
            if hasLabels || hasComment {
                attributedString.append(NSAttributedString(string: "\n", attributes: tagNameAttributes))
            }
        }

        // Line 2: all label groups in one row: "Group A: L1, L2 • Group B: L3"
        if options.showTagAndLabels {
            let groups = overlayItem.selectedLabelGroups.sortedByGroupName
            for (groupIndex, labelGroupItem) in groups.enumerated() {
                let labelsJoined = labelGroupItem.selectedLabels.map(\.name).joined(separator: ", ")
                attributedString.append(
                    NSAttributedString(
                        string: "\(labelGroupItem.group.name):",
                        attributes: labelGroupAttributes
                    )
                )
                attributedString.append(
                    NSAttributedString(
                        string: " \(labelsJoined)",
                        attributes: labelNameAttributes
                    )
                )
                if groupIndex < groups.count - 1 {
                    attributedString.append(NSAttributedString(string: " • ", attributes: labelNameAttributes))
                }
            }
            let comment = (overlayItem.stamp.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if options.showComment && !comment.isEmpty {
                attributedString.append(NSAttributedString(string: "\n", attributes: labelNameAttributes))
            }
        }

        // Last line: comment (only when comment is enabled)
        if options.showComment {
            let comment = (overlayItem.stamp.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !comment.isEmpty else {
                return attributedString.length > 0 ? attributedString : nil
            }
            let commentAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: NSColor.white
            ]
            attributedString.append(NSAttributedString(string: comment, attributes: commentAttributes))
        }

        return attributedString.length > 0 ? attributedString : nil
    }
    
}
