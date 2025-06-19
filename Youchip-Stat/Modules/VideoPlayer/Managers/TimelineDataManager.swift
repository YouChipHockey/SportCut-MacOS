//
//  TimelineDataManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

class TimelineDataManager: ObservableObject {
    
    static let shared = TimelineDataManager()
    @Published var lines: [TimelineLine] = []
    @Published var selectedLineID: UUID? = nil
    @Published var selectedStampID: UUID? = nil
    var currentBookmark: Data?
    
    init() {
        lines = []
        if let first = lines.first {
            selectedLineID = first.id
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTagUpdated),
            name: .tagUpdated,
            object: nil
        )
    }
    
    func selectLine(_ lineID: UUID) {
        if MarkupMode.current == .standard {
            selectedLineID = lineID
        }
    }
    func selectStamp(stampID: UUID?) {
        selectedStampID = stampID
    }
    func removeStamp(lineID: UUID, stampID: UUID) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        lines[lineIndex].stamps.removeAll(where: { $0.id == stampID })
        updateTimelines()
    }
    
    func addLine(name: String) {
        guard MarkupMode.current == .standard else { return }
        
        let newLine = TimelineLine(name: name)
        lines.append(newLine)
        selectedLineID = newLine.id
        updateTimelines()
    }
    
    func findOrCreateTimelineForTag(tag: Tag) -> UUID {
        if let existingLine = lines.first(where: { $0.tagIdForMode == tag.id }) {
            return existingLine.id
        }
        let newLine = TimelineLine(name: tag.name, tagIdForMode: tag.id)
        lines.append(newLine)
        return newLine.id
    }
    
    func updateTagReferences(originalID: String, newID: String) {
        var updated = false
        
        for lineIndex in 0..<lines.count {
            for stampIndex in 0..<lines[lineIndex].stamps.count {
                if lines[lineIndex].stamps[stampIndex].idTag == originalID {
                    lines[lineIndex].stamps[stampIndex].idTag = newID
                    updated = true
                }
            }
            
            if lines[lineIndex].tagIdForMode == originalID {
                lines[lineIndex].tagIdForMode = newID
                updated = true
            }
        }
        
        if updated {
            updateTimelines()
        }
    }
    
    func addStampToSelectedLine(idTag: String, primaryId: String?, name: String, timeStart: String, timeFinish: String, color: String, labels: [String], position: CGPoint? = nil) {
        if MarkupMode.current == .standard {
            guard let lineID = selectedLineID,
                  let idx = lines.firstIndex(where: { $0.id == lineID }) else { return }
            
            let selectedEvents = Array(TagLibraryManager.shared.selectedTimeEvents)
            
            let stamp = TimelineStamp(
                idTag: idTag,
                primaryID: primaryId,
                timeStart: timeStart,
                timeFinish: timeFinish,
                colorHex: color,
                label: name,
                labels: labels,
                timeEvents: selectedEvents,
                position: position,
                isActiveForMapView: position != nil
            )
            lines[idx].stamps.append(stamp)
            
        } else {
            if let tag = TagLibraryManager.shared.findTagById(idTag) {
                let lineID = findOrCreateTimelineForTag(tag: tag)
                
                if let idx = lines.firstIndex(where: { $0.id == lineID }) {
                    let selectedEvents = Array(TagLibraryManager.shared.selectedTimeEvents)
                    
                    let stamp = TimelineStamp(
                        idTag: idTag,
                        primaryID: primaryId,
                        timeStart: timeStart,
                        timeFinish: timeFinish,
                        colorHex: color,
                        label: name,
                        labels: labels,
                        timeEvents: selectedEvents,
                        position: position,
                        isActiveForMapView: position != nil
                    )
                    lines[idx].stamps.append(stamp)
                }
            }
        }
        
        updateTimelines()
    }
    
    func updateStampLabels(lineID: UUID, stampID: UUID, newLabels: [String]) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        guard let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else { return }
        lines[lineIndex].stamps[stampIndex].labels = newLabels
        updateTimelines()
    }
    
    func stampHasOverlaps(lineID: UUID, stampID: UUID) -> Bool {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              let stamp = lines[lineIndex].stamps.first(where: { $0.id == stampID }) else {
            return false
        }
        
        return lines[lineIndex].stamps.contains { otherStamp in
            guard otherStamp.id != stampID else { return false }
            
            let stampStart = stamp.startSeconds
            let stampEnd = stamp.finishSeconds
            let otherStart = otherStamp.startSeconds
            let otherEnd = otherStamp.finishSeconds
            return (stampStart < otherEnd && otherStart < stampEnd)
        }
    }
    
    func updateStampTime(lineID: UUID, stampID: UUID, newStart: Double? = nil, newEnd: Double? = nil) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else {
            return
        }
        
        var stamp = lines[lineIndex].stamps[stampIndex]
        
        if let newStartTime = newStart {
            let limitedStart = min(newStartTime, stamp.finishSeconds - 0.5)
            stamp.timeStart = secondsToTimeString(limitedStart)
        }
        
        if let newEndTime = newEnd {
            let limitedEnd = max(newEndTime, stamp.startSeconds + 0.5)
            stamp.timeFinish = secondsToTimeString(limitedEnd)
        }
        
        lines[lineIndex].stamps[stampIndex] = stamp
        updateTimelines()
    }
    
    func updateTimelines() {
        guard let currentBookmark = currentBookmark else { return }
        VideoFilesManager.shared.updateTimelines(for: currentBookmark, with: lines)
    }
    
    @objc private func handleTagUpdated(_ notification: Notification) {
        guard let originalID = notification.userInfo?["originalID"] as? String,
              let newID = notification.userInfo?["newID"] as? String else {
            return
        }
        
        var updated = false
        
        guard let updatedTag = TagLibraryManager.shared.findTagById(newID) else { return }
        
        for lineIndex in 0..<lines.count {
            for stampIndex in 0..<lines[lineIndex].stamps.count {
                if lines[lineIndex].stamps[stampIndex].idTag == originalID {
                    lines[lineIndex].stamps[stampIndex].idTag = newID
                    lines[lineIndex].stamps[stampIndex].label = updatedTag.name
                    updated = true
                }
            }
            
            if lines[lineIndex].tagIdForMode == originalID {
                lines[lineIndex].tagIdForMode = newID
                if lines[lineIndex].name == lines[lineIndex].tagIdForMode {
                    lines[lineIndex].name = updatedTag.name
                }
                
                updated = true
            }
        }
        
        if updated {
            updateTimelines()
        }
    }
    
}
