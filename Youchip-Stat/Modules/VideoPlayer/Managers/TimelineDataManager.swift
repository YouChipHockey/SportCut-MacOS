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
import UserNotifications

class TimelineDataManager: ObservableObject {
    
    static let shared = TimelineDataManager()
    @Published var lines: [TimelineLine] = []
    @Published var selectedLineID: UUID? = nil
    @Published var selectedStampID: UUID? = nil
    @Published var unlinkedScreenshotPopups: [UnlinkedScreenshotPopup] = []
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
        
        let line = lines[lineIndex]
        
        // Проверяем, является ли это таймлайном рисунков
        let isDrawingsTimeline = line.name.lowercased().contains("рисунок") ||
                                 line.name.lowercased().contains("рисунки") ||
                                 line.name.lowercased().contains("скриншот") ||
                                 line.name.lowercased().contains("screenshot") ||
                                 line.name.lowercased().contains("drawing")
        
        // Если это таймлайн рисунков, удаляем файл скриншота
        if isDrawingsTimeline {
            if let stamp = line.stamps.first(where: { $0.id == stampID }) {
                deleteScreenshotFile(screenshotName: stamp.label)
            }
        }
        
        lines[lineIndex].stamps.removeAll(where: { $0.id == stampID })
        updateTimelines()
        
        NotificationCenter.default.post(name: .stampCountsChanged, object: nil)
    }
    
    private func deleteScreenshotFile(screenshotName: String) {
        guard let currentBookmark = currentBookmark,
              let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.bookmark == currentBookmark }) else {
            print("❌ Не найден filesFile для удаления скриншота")
            return
        }
        
        let screenshotsFolder = filesFile.screenshotsFolder
        let imageFileName = screenshotName.hasSuffix(".png") ? screenshotName : "\(screenshotName).png"
        let imageURL = screenshotsFolder.appendingPathComponent(imageFileName)
        let jsonURL = screenshotsFolder.appendingPathComponent("\(screenshotName).json")
        
        // Удаляем файлы
        do {
            if FileManager.default.fileExists(atPath: imageURL.path) {
                try FileManager.default.removeItem(at: imageURL)
                print("✅ Удален файл изображения: \(imageFileName)")
            }
            
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                try FileManager.default.removeItem(at: jsonURL)
                print("✅ Удален файл метаданных: \(screenshotName).json")
            }
            
            // Удаляем из менеджера скриншотов
            ScreenshotsMetadataManager.shared.removeScreenshot(screenshotName: screenshotName)
        } catch {
            print("❌ Ошибка удаления файлов скриншота: \(error.localizedDescription)")
        }
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
    
    func addStampToSelectedLine(idTag: String, primaryId: String?, name: String, timeStartSeconds: Double, timeFinishSeconds: Double, color: String, labels: [String], position: CGPoint? = nil) {
        if MarkupMode.current == .standard {
            guard let lineID = selectedLineID,
                  let idx = lines.firstIndex(where: { $0.id == lineID }) else { return }
            
            let selectedEvents = Array(TagLibraryManager.shared.selectedTimeEvents)
            
            let stamp = TimelineStamp(
                idTag: idTag,
                primaryID: primaryId,
                timeStartSeconds: timeStartSeconds,
                timeFinishSeconds: timeFinishSeconds,
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
                        timeStartSeconds: timeStartSeconds,
                        timeFinishSeconds: timeFinishSeconds,
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
        
        NotificationCenter.default.post(name: .stampCountsChanged, object: nil)
    }
    
    func updateStampLabels(lineID: UUID, stampID: UUID, newLabels: [String]) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        guard let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else { return }
        lines[lineIndex].stamps[stampIndex].labels = newLabels
        updateTimelines()
    }
    
    func updateStampTimeEvents(lineID: UUID, stampID: UUID, newEvents: [String]) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        guard let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else { return }
        lines[lineIndex].stamps[stampIndex].timeEvents = newEvents
        updateTimelines()
    }
    
    func stampHasOverlaps(lineID: UUID, stampID: UUID) -> Bool {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              let stamp = lines[lineIndex].stamps.first(where: { $0.id == stampID }) else {
            return false
        }
        
        return lines[lineIndex].stamps.contains { otherStamp in
            guard otherStamp.id != stampID else { return false }
            
            let stampStart = stamp.timeStartSeconds
            let stampEnd = stamp.timeFinishSeconds
            let otherStart = otherStamp.timeStartSeconds
            let otherEnd = otherStamp.timeFinishSeconds
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
            let limitedStart = min(newStartTime, stamp.timeFinishSeconds - 0.5)
            stamp.timeStartSeconds = limitedStart
        }
        
        if let newEndTime = newEnd {
            let limitedEnd = max(newEndTime, stamp.timeStartSeconds + 0.5)
            stamp.timeFinishSeconds = limitedEnd
        }
        
        lines[lineIndex].stamps[stampIndex] = stamp
        updateTimelines()
        
        // Check if any screenshots need to be unlinked due to time range change
        checkAndUnlinkScreenshotsOutsideStamp(stampID: stampID, newStart: stamp.timeStartSeconds, newEnd: stamp.timeFinishSeconds)
    }
    
    func updateTimelines() {
        guard let currentBookmark = currentBookmark else { return }
        VideoFilesManager.shared.updateTimelines(for: currentBookmark, with: lines)
    }
    
    @objc private func handleTagUpdated(_ notification: Notification) {
        guard let tagId = notification.userInfo?["tagId"] as? String else { return }
        let newName = notification.userInfo?["newName"] as? String
        
        var updated = false
        
        guard let updatedTag = TagLibraryManager.shared.findTagById(tagId) else { return }
        
        for lineIndex in 0..<lines.count {
            for stampIndex in 0..<lines[lineIndex].stamps.count {
                if lines[lineIndex].stamps[stampIndex].idTag == tagId {
                    lines[lineIndex].stamps[stampIndex].label = newName ?? updatedTag.name
                    updated = true
                }
            }
            
            if lines[lineIndex].tagIdForMode == tagId {
                lines[lineIndex].name = newName ?? updatedTag.name
                updated = true
            }
        }
        
        if updated {
            updateTimelines()
        }
    }
    
    func updateStampTimeRange(lineID: UUID, stampID: UUID, newStartTime: Double, newEndTime: Double) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else { return }
        
        lines[lineIndex].stamps[stampIndex].timeStartSeconds = newStartTime
        lines[lineIndex].stamps[stampIndex].timeFinishSeconds = newEndTime
        
        updateTimelines()
    }
    
    private func checkAndUnlinkScreenshotsOutsideStamp(stampID: UUID, newStart: Double, newEnd: Double) {
        let screenshots = ScreenshotsMetadataManager.shared.screenshots
        
        // Find the stamp to get its name
        var stampName: String = "тега"
        for line in lines {
            if let stamp = line.stamps.first(where: { $0.id == stampID }) {
                if let tag = TagLibraryManager.shared.findTagById(stamp.idTag) {
                    stampName = tag.name
                } else {
                    stampName = stamp.label
                }
                break
            }
        }
        
        for screenshot in screenshots {
            // Check if this screenshot is linked to the modified stamp
            guard screenshot.relatedStampIds.contains(stampID) else {
                continue
            }
            
            // Check if screenshot's videoTime is still within the stamp's time range
            let screenshotTime = screenshot.videoTime
            if screenshotTime < newStart || screenshotTime > newEnd {
                // Screenshot is now outside the stamp range, unlink it
                var updatedStampIds = screenshot.relatedStampIds
                updatedStampIds.removeAll { $0 == stampID }
                
                // Update the screenshot metadata
                ScreenshotsMetadataManager.shared.updateScreenshotRelatedStamps(
                    screenshotName: screenshot.screenshotName,
                    relatedStampIds: updatedStampIds
                )
                
                // Create popup for this unlinked screenshot
                let message = "Рисунок '\(screenshot.screenshotName)' отвязался от тега '\(stampName)' из-за изменения его длины"
                let popup = UnlinkedScreenshotPopup(
                    id: UUID(),
                    screenshotName: screenshot.screenshotName,
                    tagName: stampName,
                    message: message
                )
                
                DispatchQueue.main.async {
                    self.unlinkedScreenshotPopups.append(popup)
                    
                    // Auto-dismiss after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        self.unlinkedScreenshotPopups.removeAll { $0.id == popup.id }
                    }
                }
            }
        }
    }
    
    func dismissPopup(id: UUID) {
        unlinkedScreenshotPopups.removeAll { $0.id == id }
    }
    
}

// MARK: - Unlinked Screenshot Popup Model

struct UnlinkedScreenshotPopup: Identifiable {
    let id: UUID
    let screenshotName: String
    let tagName: String
    let message: String
}
