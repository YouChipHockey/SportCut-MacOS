//
//  NSAttributedString+Convenience.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 20.12.2025.
//

import AppKit

extension NSAttributedString {
    
    static func attributedStringForTagInfo(overlayItem: OverlayItem) -> NSAttributedString? {
        let attributedString = NSMutableAttributedString(string: "")
        let timelineManager = TimelineDataManager.shared
        let tagLibrary = TagLibraryManager.shared
        
        let tagName = overlayItem.tag.name
        let tagGroupName = (tagLibrary.allTagGroups.first { $0.tags.contains(overlayItem.tag.id) }?.name ?? "Group").uppercased()
        let timeEvents = tagLibrary.allTimeEvents.filter { overlayItem.stamp.timeEvents.contains($0.id) }
        
        let allStamps: [TimelineStamp] = timelineManager.lines.flatMap { $0.stamps }.sortedByStartTime
        let allStampsInfo: [(id: UUID, tagId: String, name: String)] = allStamps.map { ($0.id, $0.idTag, $0.label) }
        let stampsOfSingleType = allStampsInfo.filter { $0.tagId == overlayItem.tag.id }
        guard let tagIndex = stampsOfSingleType.firstIndex(where: { $0.id == overlayItem.stamp.id } ) else { return nil }
        
        let timeEventAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.systemOrange
        ]
        let tagNameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.systemGreen
        ]
        let labelGroupNameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let labelNameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.white
        ]
        
        var tagGroupAndNameString = tagIndex == 0 ? "\(tagName)" : "\(tagName)_\(tagIndex)"
        tagGroupAndNameString = tagGroupName + ": " + tagGroupAndNameString
        tagGroupAndNameString += timeEvents.isEmpty ? "" : ", "
        let timeEventsString = timeEvents.enumerated().map { index, event in
            event.name + (index < timeEvents.count - 1 ? ", " : "")
        }.joined() + "\n"
        
        let tagGroupAndNameAttributedString = NSAttributedString(string: tagGroupAndNameString, attributes: tagNameAttributes)
        let timeEventsAttributedstring = NSAttributedString(string: timeEventsString, attributes: timeEventAttributes)
        let descriptionAttributedString = NSMutableAttributedString()
        
        overlayItem.selectedLabelGroups.forEach { labelGroupItem in
            let labelGroupNameAttributedString = NSAttributedString(string: labelGroupItem.group.name.uppercased() + ": ", attributes: labelGroupNameAttributes)
            descriptionAttributedString.append(labelGroupNameAttributedString)
            
            labelGroupItem.selectedLabels.forEach { label in
                let separator = label == labelGroupItem.selectedLabels.last ? " " : ", "
                let labelAttributedString = NSMutableAttributedString(string: label.name + separator, attributes: labelNameAttributes)
                descriptionAttributedString.append(labelAttributedString)
            }
        }
        attributedString.append(tagGroupAndNameAttributedString)
        attributedString.append(timeEventsAttributedstring)
        attributedString.append(descriptionAttributedString)
        
        return attributedString
    }
    
}
