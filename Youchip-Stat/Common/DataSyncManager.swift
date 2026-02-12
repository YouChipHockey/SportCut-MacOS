//
//  DataSyncManager.swift
//  Youchip-Stat
//
//  Created on 10.02.2026.
//

import Foundation
import AVFoundation

/// Manages data synchronization between Documents and Application Support directories
class DataSyncManager {
    
    static let shared = DataSyncManager()
    
    private let fileManager = FileManager.default
    
    // Throttling to avoid excessive backups
    private var backupTimer: Timer?
    private var pendingBackup = false
    private let backupDelay: TimeInterval = 2.0
    
    // MARK: - Directories
    
    /// Primary user data directory (Documents)
    private var documentsDirectory: URL {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    /// Backup directory (Application Support)
    private var backupDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("YouChip-Stat-Backup", isDirectory: true)
    }
    
    private var collectionsDirectory: URL {
        return documentsDirectory.appendingPathComponent("YouChip-Stat/Collections", isDirectory: true)
    }
    
    private var backupCollectionsDirectory: URL {
        return backupDirectory.appendingPathComponent("YouChip-Stat/Collections", isDirectory: true)
    }
    
    private var playFieldsDirectory: URL {
        return documentsDirectory.appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
    }
    
    private var backupPlayFieldsDirectory: URL {
        return backupDirectory.appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
    }
    
    // MARK: - UserDefaults Keys
    
    private let lastSyncDateKey = "DataSync_LastSyncDate"
    private let videosDataKey = "videosData"
    private let collectionsBookmarksKey = "collectionsBookmarks"
    
    // MARK: - Orphaned Timelines
    
    /// Structure for storing orphaned timelines (without linked video)
    struct OrphanedTimeline: Codable {
        let videoId: String
        let videoName: String?
        let timelines: [TimelineLine]
        let customName: String?
        let isFavorite: Bool?
        let backupDate: Date
        
        struct TimelineLine: Codable {
            let id: UUID
            let name: String
            let stamps: [TimelineStamp]
            let tagIdForMode: String
            
            struct TimelineStamp: Codable {
                let id: UUID
                let idTag: String
                let primaryID: String?
                let timeStartSeconds: Double
                let timeFinishSeconds: Double
                let colorHex: String
                let label: String
                let isActiveForMapView: Bool?
                let labels: [String]
                let timeEvents: [String]
                let position: CGPoint?
            }
        }
    }
    
    private var timelinesBackupDirectory: URL {
        return backupDirectory.appendingPathComponent("Timelines", isDirectory: true)
    }
    
    // MARK: - Init
    
    private init() {
        createBackupDirectoryIfNeeded()
    }
    
    // MARK: - Public Methods
    
    /// Synchronizes data on app launch
    /// Checks for data in Documents and restores from backup if needed
    func synchronizeOnAppLaunch() {
        print("🔄 DataSync: Starting synchronization on app launch")
        
        // Clean up duplicate collections first
        CollectionsBookmarksManager.shared.cleanupDuplicateCollections()
        
        // Load collections from CollectionsBookmarks.json (this triggers migration if needed)
        // This ensures CollectionsBookmarks.json is populated before restore
        _ = UserDefaults.standard.getCollectionBookmarks()
        
        // Restore collections from backup file if UserDefaults is empty
        restoreCollectionsFromBackup()
        
        let hasDocumentsData = checkDocumentsHasData()
        
        if !hasDocumentsData {
            print("📥 DataSync: No data in Documents, restoring from backup")
            restoreFromBackup()
        } else {
            print("✅ DataSync: Data exists in Documents, checking differences with backup")
            
            if hasBackupDataDifferences() {
                print("⚠️ DataSync: Differences found, restoring newer data from backup")
                restoreFromBackup()
            } else {
                print("✅ DataSync: Data is identical")
            }
        }
        
        backupToApplicationSupport()
    }
    
    /// Restores collections from backup file if UserDefaults is empty
    private func restoreCollectionsFromBackup() {
        // CollectionsBookmarks.json is now the single source of truth
        // Collections are loaded from file system based on CollectionsBookmarks.json
        // No need to restore from old backup system
        print("✅ DataSync: Collections loaded from CollectionsBookmarks.json")
    }
    
    /// Creates backup from Documents to Application Support with throttling
    func backupToApplicationSupport() {
        backupTimer?.invalidate()
        pendingBackup = true
        
        backupTimer = Timer.scheduledTimer(withTimeInterval: backupDelay, repeats: false) { [weak self] _ in
            self?.performBackup()
        }
    }
    
    /// Immediate backup creation without throttling
    func backupToApplicationSupportImmediate() {
        backupTimer?.invalidate()
        performBackup()
    }
    
    private func performBackup() {
        guard pendingBackup else { return }
        pendingBackup = false
        
        print("💾 DataSync: Creating data backup")
        
        createBackupDirectoryIfNeeded()
        backupCollections()
        backupPlayFields()
        backupTimelines()
        backupCollectionsBackup()
        backupUserDefaults()
        
        UserDefaults.standard.set(Date(), forKey: lastSyncDateKey)
        print("✅ DataSync: Backup created successfully")
    }
    
    /// Restores data from Application Support to Documents
    func restoreFromBackup() {
        print("📥 DataSync: Restoring data from backup")
        
        restoreCollections()
        restorePlayFields()
        restoreTimelines()
        restoreCollectionsBackup()
        restoreUserDefaults()
        
        // Restore collections from backup file to UserDefaults
        restoreCollectionsFromBackup()
        
        // Clean up and sync collections after restore
        CollectionsBookmarksManager.shared.cleanupDuplicateCollections()
        
        print("✅ DataSync: Data restored from backup")
    }
    
    /// Deletes all user data from both directories
    /// Used only for manual deletion by user
    func deleteAllUserData() {
        print("🗑️ DataSync: Deleting all user data")
        
        deleteFromDocuments()
        deleteFromApplicationSupport()
        clearUserDefaults()
        
        print("✅ DataSync: All user data deleted")
    }
    
    // MARK: - Orphaned Timelines Detection
    
    /// Detects orphaned timelines and returns their list
    func detectOrphanedTimelines() -> [OrphanedTimeline] {
        guard fileManager.fileExists(atPath: timelinesBackupDirectory.path) else {
            return []
        }
        
        var currentVideoIds = Set<String>()
        if let data = UserDefaults.standard.data(forKey: videosDataKey) {
            do {
                let decoder = JSONDecoder()
                let videosData = try decoder.decode([VideosData].self, from: data)
                currentVideoIds = Set(videosData.map { $0.id })
            } catch {
                print("❌ DataSync: Error reading current videos - \(error.localizedDescription)")
            }
        }
        
        var orphanedTimelines: [OrphanedTimeline] = []
        
        do {
            let timelineFiles = try fileManager.contentsOfDirectory(at: timelinesBackupDirectory, 
                                                                    includingPropertiesForKeys: nil)
            
            for fileURL in timelineFiles where fileURL.pathExtension == "json" {
                let videoId = fileURL.deletingPathExtension().lastPathComponent
                
                if !currentVideoIds.contains(videoId) {
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let decoder = JSONDecoder()
                        let orphaned = try decoder.decode(OrphanedTimeline.self, from: data)
                        orphanedTimelines.append(orphaned)
                    } catch {
                        print("⚠️ DataSync: Error reading timeline \(videoId) - \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            print("❌ DataSync: Error reading timelines directory - \(error.localizedDescription)")
        }
        
        if !orphanedTimelines.isEmpty {
            print("🔍 DataSync: Found orphaned timelines: \(orphanedTimelines.count)")
        }
        
        return orphanedTimelines
    }
    
    /// Restores link between video and timeline
    func restoreTimelineToVideo(orphanedTimeline: OrphanedTimeline, newVideoBookmark: Data, newVideoId: String) -> Bool {
        print("🔗 DataSync: Restoring timeline link to video")
        
        // Get video duration from bookmark
        var newVideoDuration: Double = 0
        do {
            var isStale = false
            let videoURL = try URL(resolvingBookmarkData: newVideoBookmark,
                                   options: .withSecurityScope,
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &isStale)
            
            let asset = AVAsset(url: videoURL)
            // Use synchronous method to get duration
            let duration = asset.duration
            newVideoDuration = CMTimeGetSeconds(duration)
            
            guard newVideoDuration > 0 && !duration.isIndefinite else {
                print("❌ DataSync: Invalid video duration: \(newVideoDuration)")
                return false
            }
            
            print("📹 DataSync: Video duration: \(newVideoDuration) seconds")
        } catch {
            print("❌ DataSync: Error getting video duration - \(error.localizedDescription)")
            return false
        }
        
        guard let data = UserDefaults.standard.data(forKey: videosDataKey) else {
            print("❌ DataSync: No video data")
            return false
        }
        
        do {
            let decoder = JSONDecoder()
            var videosData = try decoder.decode([VideosData].self, from: data)
            
            // Filter stamps that are outside video duration
            let restoredTimelines: [TimelineLine] = orphanedTimeline.timelines.compactMap { timeline in
                let filteredStamps = timeline.stamps.compactMap { stamp -> TimelineStamp? in
                    // Check if stamp is within video duration
                    if stamp.timeStartSeconds >= newVideoDuration {
                        print("⚠️ DataSync: Skipping stamp \(stamp.id) - start time \(stamp.timeStartSeconds) exceeds video duration \(newVideoDuration)")
                        return nil
                    }
                    
                    // Clamp finish time to video duration
                    let clampedFinishTime = min(stamp.timeFinishSeconds, newVideoDuration)
                    
                    // Ensure start time is before finish time
                    let clampedStartTime = min(stamp.timeStartSeconds, clampedFinishTime - 0.1)
                    
                    guard clampedStartTime >= 0 && clampedFinishTime > clampedStartTime else {
                        print("⚠️ DataSync: Skipping stamp \(stamp.id) - invalid time range after clamping")
                        return nil
                    }
                    
                    return TimelineStamp(
                        id: stamp.id,
                        idTag: stamp.idTag,
                        primaryID: stamp.primaryID,
                        timeStartSeconds: clampedStartTime,
                        timeFinishSeconds: clampedFinishTime,
                        colorHex: stamp.colorHex,
                        label: stamp.label,
                        labels: stamp.labels,
                        timeEvents: stamp.timeEvents,
                        position: stamp.position,
                        isActiveForMapView: stamp.isActiveForMapView
                    )
                }
                
                // Only include timeline if it has stamps
                guard !filteredStamps.isEmpty else {
                    print("⚠️ DataSync: Skipping timeline \(timeline.name) - no valid stamps after filtering")
                    return nil
                }
                
                return TimelineLine(
                    id: timeline.id,
                    name: timeline.name,
                    stamps: filteredStamps,
                    tagIdForMode: timeline.tagIdForMode
                )
            }
            
            guard !restoredTimelines.isEmpty else {
                print("❌ DataSync: No valid timelines after filtering for video duration")
                return false
            }
            
            if let index = videosData.firstIndex(where: { $0.id == newVideoId }) {
                // Update video metadata
                if let customName = orphanedTimeline.customName {
                    videosData[index].customName = customName
                }
                if let isFavorite = orphanedTimeline.isFavorite {
                    videosData[index].isFavorite = isFavorite
                }
                // Save timelines to file
                VideoFilesManager.shared.saveTimelines(restoredTimelines, for: newVideoId)
            } else {
                let newVideoData = VideosData(
                    bookmark: newVideoBookmark,
                    id: newVideoId,
                    customName: orphanedTimeline.customName,
                    isFavorite: orphanedTimeline.isFavorite
                )
                videosData.append(newVideoData)
                // Save timelines to file
                VideoFilesManager.shared.saveTimelines(restoredTimelines, for: newVideoId)
            }
            
            let encoder = JSONEncoder()
            let updatedData = try encoder.encode(videosData)
            UserDefaults.standard.set(updatedData, forKey: videosDataKey)
            
            // IMPORTANT: Update orphaned timeline file with new videoId for future backups
            // This ensures that if video is deleted again, backup will use correct videoId
            let oldTimelineFile = timelinesBackupDirectory.appendingPathComponent("\(orphanedTimeline.videoId).json")
            let newTimelineFile = timelinesBackupDirectory.appendingPathComponent("\(newVideoId).json")
            
            // Create updated orphaned timeline with new videoId
            var updatedOrphaned = orphanedTimeline
            let updatedTimelines = restoredTimelines.map { timeline in
                OrphanedTimeline.TimelineLine(
                    id: timeline.id,
                    name: timeline.name,
                    stamps: timeline.stamps.map { stamp in
                        OrphanedTimeline.TimelineLine.TimelineStamp(
                            id: stamp.id,
                            idTag: stamp.idTag,
                            primaryID: stamp.primaryID,
                            timeStartSeconds: stamp.timeStartSeconds,
                            timeFinishSeconds: stamp.timeFinishSeconds,
                            colorHex: stamp.colorHex,
                            label: stamp.label,
                            isActiveForMapView: stamp.isActiveForMapView,
                            labels: stamp.labels,
                            timeEvents: stamp.timeEvents,
                            position: stamp.position
                        )
                    },
                    tagIdForMode: timeline.tagIdForMode
                )
            }
            
            // Update with new videoId and filtered timelines
            let updatedOrphanedTimeline = OrphanedTimeline(
                videoId: newVideoId,
                videoName: updatedOrphaned.videoName,
                timelines: updatedTimelines,
                customName: updatedOrphaned.customName,
                isFavorite: updatedOrphaned.isFavorite,
                backupDate: Date()
            )
            
            // Save updated timeline with new videoId
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let timelineData = try encoder.encode(updatedOrphanedTimeline)
                try timelineData.write(to: newTimelineFile)
                
                // Remove old timeline file
                if fileManager.fileExists(atPath: oldTimelineFile.path) {
                    try? fileManager.removeItem(at: oldTimelineFile)
                }
            } catch {
                print("⚠️ DataSync: Error updating timeline backup file - \(error.localizedDescription)")
            }
            
            print("✅ DataSync: Timeline restored successfully (filtered \(orphanedTimeline.timelines.reduce(0) { $0 + $1.stamps.count } - restoredTimelines.reduce(0) { $0 + $1.stamps.count }) stamps)")
            backupToApplicationSupportImmediate()
            
            return true
        } catch {
            print("❌ DataSync: Error restoring timeline - \(error.localizedDescription)")
            return false
        }
    }
    
    /// Deletes orphaned timeline from backup
    func deleteOrphanedTimeline(_ orphaned: OrphanedTimeline) {
        let timelineFile = timelinesBackupDirectory.appendingPathComponent("\(orphaned.videoId).json")
        try? fileManager.removeItem(at: timelineFile)
        print("🗑️ DataSync: Orphaned timeline deleted from backup")
    }
    
    /// Deletes data only from Documents (backup remains)
    func deleteFromDocumentsOnly() {
        print("🗑️ DataSync: Deleting data from Documents")
        deleteFromDocuments()
        clearUserDefaults()
        print("✅ DataSync: Data deleted from Documents, backup preserved")
    }
    
    // MARK: - Private Methods - Backup
    
    private func createBackupDirectoryIfNeeded() {
        fileManager.createDirectoryIfNeeded(url: backupDirectory)
        fileManager.createDirectoryIfNeeded(url: backupCollectionsDirectory)
        fileManager.createDirectoryIfNeeded(url: backupPlayFieldsDirectory)
        fileManager.createDirectoryIfNeeded(url: timelinesBackupDirectory)
    }
    
    private func backupCollections() {
        guard fileManager.fileExists(atPath: collectionsDirectory.path) else {
            print("⚠️ DataSync: Collections directory in Documents does not exist")
            return
        }
        
        do {
            if fileManager.fileExists(atPath: backupCollectionsDirectory.path) {
                try fileManager.removeItem(at: backupCollectionsDirectory)
            }
            
            try fileManager.copyItem(at: collectionsDirectory, to: backupCollectionsDirectory)
            print("✅ DataSync: Collections backed up")
        } catch {
            print("❌ DataSync: Error backing up collections - \(error.localizedDescription)")
        }
    }
    
    private func backupPlayFields() {
        guard fileManager.fileExists(atPath: playFieldsDirectory.path) else {
            print("⚠️ DataSync: PlayFields directory in Documents does not exist")
            return
        }
        
        do {
            if fileManager.fileExists(atPath: backupPlayFieldsDirectory.path) {
                try fileManager.removeItem(at: backupPlayFieldsDirectory)
            }
            
            try fileManager.copyItem(at: playFieldsDirectory, to: backupPlayFieldsDirectory)
            print("✅ DataSync: PlayFields backed up")
        } catch {
            print("❌ DataSync: Error backing up PlayFields - \(error.localizedDescription)")
        }
    }
    
    private var timelinesDirectory: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("YouChip-Stat/Timelines", isDirectory: true)
    }
    
    private func backupTimelines() {
        guard let data = UserDefaults.standard.data(forKey: videosDataKey) else {
            print("⚠️ DataSync: No video data for timeline backup")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let videosData = try decoder.decode([VideosData].self, from: data)
            
            // IMPORTANT: We do NOT delete existing timeline files during backup
            // This allows preserving timelines even after video deletion
            
            var backedUpCount = 0
            
            for videoData in videosData {
                // Load timelines from file
                let timelines = VideoFilesManager.shared.loadTimelines(for: videoData.id)
                guard !timelines.isEmpty else { continue }
                
                var videoName: String?
                do {
                    var isStale = false
                    let url = try URL(resolvingBookmarkData: videoData.bookmark, 
                                     options: .withSecurityScope, 
                                     relativeTo: nil, 
                                     bookmarkDataIsStale: &isStale)
                    videoName = url.lastPathComponent
                } catch {
                    videoName = nil
                }
                let orphanedTimelines = timelines.map { timeline in
                    OrphanedTimeline.TimelineLine(
                        id: timeline.id,
                        name: timeline.name,
                        stamps: timeline.stamps.map { stamp in
                            OrphanedTimeline.TimelineLine.TimelineStamp(
                                id: stamp.id,
                                idTag: stamp.idTag,
                                primaryID: stamp.primaryID,
                                timeStartSeconds: stamp.timeStartSeconds,
                                timeFinishSeconds: stamp.timeFinishSeconds,
                                colorHex: stamp.colorHex,
                                label: stamp.label,
                                isActiveForMapView: stamp.isActiveForMapView,
                                labels: stamp.labels,
                                timeEvents: stamp.timeEvents,
                                position: stamp.position
                            )
                        },
                        tagIdForMode: timeline.tagIdForMode
                    )
                }
                
                let orphaned = OrphanedTimeline(
                    videoId: videoData.id,
                    videoName: videoName,
                    timelines: orphanedTimelines,
                    customName: videoData.customName,
                    isFavorite: videoData.isFavorite,
                    backupDate: Date()
                )
                
                let timelineFile = timelinesBackupDirectory.appendingPathComponent("\(videoData.id).json")
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let timelineData = try encoder.encode(orphaned)
                try timelineData.write(to: timelineFile)
                
                backedUpCount += 1
            }
            
            // Also backup timeline files directory
            if fileManager.fileExists(atPath: timelinesDirectory.path) {
                let backupTimelinesDir = backupDirectory.appendingPathComponent("Timelines", isDirectory: true)
                if fileManager.fileExists(atPath: backupTimelinesDir.path) {
                    try? fileManager.removeItem(at: backupTimelinesDir)
                }
                try? fileManager.copyItem(at: timelinesDirectory, to: backupTimelinesDir)
            }
            
            if backedUpCount > 0 {
                print("✅ DataSync: Video timelines backed up (\(backedUpCount) files)")
            }
        } catch {
            print("❌ DataSync: Error backing up timelines - \(error.localizedDescription)")
        }
    }
    
    /// Structure for compatibility with backupTimelinesForVideo
    struct VideosDataWithTimelines {
        let bookmark: Data
        let id: String
        let timelines: [TimelineLine]
        let customName: String?
        let isFavorite: Bool?
    }
    
    /// Saves timeline for specific video to backup
    /// Used when deleting video to preserve timeline before deletion
    func backupTimelinesForVideo(_ videoData: VideosDataWithTimelines) {
        guard !videoData.timelines.isEmpty else {
            return
        }
        
        createBackupDirectoryIfNeeded()
        
        do {
            var videoName: String?
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: videoData.bookmark, 
                                 options: .withSecurityScope, 
                                 relativeTo: nil, 
                                 bookmarkDataIsStale: &isStale)
                videoName = url.lastPathComponent
            } catch {
                videoName = nil
            }
            let orphanedTimelines = videoData.timelines.map { timeline in
                OrphanedTimeline.TimelineLine(
                    id: timeline.id,
                    name: timeline.name,
                    stamps: timeline.stamps.map { stamp in
                        OrphanedTimeline.TimelineLine.TimelineStamp(
                            id: stamp.id,
                            idTag: stamp.idTag,
                            primaryID: stamp.primaryID,
                            timeStartSeconds: stamp.timeStartSeconds,
                            timeFinishSeconds: stamp.timeFinishSeconds,
                            colorHex: stamp.colorHex,
                            label: stamp.label,
                            isActiveForMapView: stamp.isActiveForMapView,
                            labels: stamp.labels,
                            timeEvents: stamp.timeEvents,
                            position: stamp.position
                        )
                    },
                    tagIdForMode: timeline.tagIdForMode
                )
            }
            
            let orphaned = OrphanedTimeline(
                videoId: videoData.id,
                videoName: videoName,
                timelines: orphanedTimelines,
                customName: videoData.customName,
                isFavorite: videoData.isFavorite,
                backupDate: Date()
            )
            
            let timelineFile = timelinesBackupDirectory.appendingPathComponent("\(videoData.id).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let timelineData = try encoder.encode(orphaned)
            try timelineData.write(to: timelineFile)
            
            print("💾 DataSync: Video timeline \(videoData.id) saved to backup before deletion")
        } catch {
            print("❌ DataSync: Error saving timeline before deletion - \(error.localizedDescription)")
        }
    }
    
    private func backupUserDefaults() {
        var backupData: [String: Any] = [:]
        
        if let videosData = UserDefaults.standard.data(forKey: videosDataKey) {
            backupData[videosDataKey] = videosData
        }
        
        if let collectionsData = UserDefaults.standard.data(forKey: collectionsBookmarksKey) {
            backupData[collectionsBookmarksKey] = collectionsData
        }
        
        let backupFile = backupDirectory.appendingPathComponent("UserDefaultsBackup.plist")
        
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: backupData, format: .binary, options: 0)
            try data.write(to: backupFile)
            print("✅ DataSync: UserDefaults backed up")
        } catch {
            print("❌ DataSync: Error saving UserDefaults - \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods - Restore
    
    private func restoreCollections() {
        guard fileManager.fileExists(atPath: backupCollectionsDirectory.path) else {
            print("⚠️ DataSync: Collections backup not found")
            return
        }
        
        do {
            let parentDir = collectionsDirectory.deletingLastPathComponent()
            fileManager.createDirectoryIfNeeded(url: parentDir)
            
            if fileManager.fileExists(atPath: collectionsDirectory.path) {
                try fileManager.removeItem(at: collectionsDirectory)
            }
            
            try fileManager.copyItem(at: backupCollectionsDirectory, to: collectionsDirectory)
            print("✅ DataSync: Collections restored from backup")
        } catch {
            print("❌ DataSync: Error restoring collections - \(error.localizedDescription)")
        }
    }
    
    private func restoreTimelines() {
        let backupTimelinesDir = backupDirectory.appendingPathComponent("Timelines", isDirectory: true)
        
        guard fileManager.fileExists(atPath: backupTimelinesDir.path) else {
            print("⚠️ DataSync: Timelines backup not found")
            return
        }
        
        do {
            let parentDir = timelinesDirectory.deletingLastPathComponent()
            fileManager.createDirectoryIfNeeded(url: parentDir)
            
            if fileManager.fileExists(atPath: timelinesDirectory.path) {
                try fileManager.removeItem(at: timelinesDirectory)
            }
            
            try fileManager.copyItem(at: backupTimelinesDir, to: timelinesDirectory)
            print("✅ DataSync: Timelines restored from backup")
        } catch {
            print("❌ DataSync: Error restoring timelines - \(error.localizedDescription)")
        }
    }
    
    private var collectionsBookmarksFile: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("YouChip-Stat/CollectionsBookmarks.json")
    }
    
    private func backupCollectionsBackup() {
        guard fileManager.fileExists(atPath: collectionsBookmarksFile.path) else {
            print("⚠️ DataSync: CollectionsBookmarks.json does not exist")
            return
        }
        
        do {
            let backupFile = backupDirectory.appendingPathComponent("CollectionsBookmarks.json")
            if fileManager.fileExists(atPath: backupFile.path) {
                try fileManager.removeItem(at: backupFile)
            }
            
            try fileManager.copyItem(at: collectionsBookmarksFile, to: backupFile)
            print("✅ DataSync: CollectionsBookmarks.json backed up")
        } catch {
            print("❌ DataSync: Error backing up CollectionsBookmarks.json - \(error.localizedDescription)")
        }
    }
    
    private func restoreCollectionsBackup() {
        let backupFile = backupDirectory.appendingPathComponent("CollectionsBookmarks.json")
        
        guard fileManager.fileExists(atPath: backupFile.path) else {
            print("⚠️ DataSync: CollectionsBookmarks.json not found in backup")
            return
        }
        
        do {
            let parentDir = collectionsBookmarksFile.deletingLastPathComponent()
            fileManager.createDirectoryIfNeeded(url: parentDir)
            
            if fileManager.fileExists(atPath: collectionsBookmarksFile.path) {
                try fileManager.removeItem(at: collectionsBookmarksFile)
            }
            
            try fileManager.copyItem(at: backupFile, to: collectionsBookmarksFile)
            print("✅ DataSync: CollectionsBookmarks.json restored from backup")
        } catch {
            print("❌ DataSync: Error restoring CollectionsBookmarks.json - \(error.localizedDescription)")
        }
    }
    
    private func restorePlayFields() {
        guard fileManager.fileExists(atPath: backupPlayFieldsDirectory.path) else {
            print("⚠️ DataSync: PlayFields backup not found")
            return
        }
        
        do {
            let parentDir = playFieldsDirectory.deletingLastPathComponent()
            fileManager.createDirectoryIfNeeded(url: parentDir)
            
            if fileManager.fileExists(atPath: playFieldsDirectory.path) {
                try fileManager.removeItem(at: playFieldsDirectory)
            }
            
            try fileManager.copyItem(at: backupPlayFieldsDirectory, to: playFieldsDirectory)
            print("✅ DataSync: PlayFields restored from backup")
        } catch {
            print("❌ DataSync: Error restoring PlayFields - \(error.localizedDescription)")
        }
    }
    
    private func restoreUserDefaults() {
        let backupFile = backupDirectory.appendingPathComponent("UserDefaultsBackup.plist")
        
        guard fileManager.fileExists(atPath: backupFile.path) else {
            print("⚠️ DataSync: UserDefaults backup not found")
            return
        }
        
        do {
            let data = try Data(contentsOf: backupFile)
            if let backupData = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                
                if let videosData = backupData[videosDataKey] as? Data {
                    UserDefaults.standard.set(videosData, forKey: videosDataKey)
                }
                
                if let collectionsData = backupData[collectionsBookmarksKey] as? Data {
                    UserDefaults.standard.set(collectionsData, forKey: collectionsBookmarksKey)
                }
                
                print("✅ DataSync: UserDefaults restored from backup")
            }
        } catch {
            print("❌ DataSync: Error restoring UserDefaults - \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods - Check
    
    private func checkDocumentsHasData() -> Bool {
        let hasCollections = fileManager.fileExists(atPath: collectionsDirectory.path)
        let hasUserDefaultsData = UserDefaults.standard.data(forKey: videosDataKey) != nil ||
                                  UserDefaults.standard.data(forKey: collectionsBookmarksKey) != nil
        
        return hasCollections || hasUserDefaultsData
    }
    
    private func hasBackupDataDifferences() -> Bool {
        guard fileManager.fileExists(atPath: backupDirectory.path) else {
            return false
        }
        
        let backupFile = backupDirectory.appendingPathComponent("UserDefaultsBackup.plist")
        
        guard fileManager.fileExists(atPath: backupFile.path) else {
            return false
        }
        
        do {
            let backupAttributes = try fileManager.attributesOfItem(atPath: backupFile.path)
            let backupModificationDate = backupAttributes[.modificationDate] as? Date ?? Date.distantPast
            
            let lastSyncDate = UserDefaults.standard.object(forKey: lastSyncDateKey) as? Date ?? Date.distantPast
            
            return backupModificationDate > lastSyncDate
        } catch {
            print("❌ DataSync: Error checking differences - \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Private Methods - Delete
    
    private func deleteFromDocuments() {
        if fileManager.fileExists(atPath: collectionsDirectory.path) {
            try? fileManager.removeItem(at: collectionsDirectory)
            print("✅ DataSync: Collections deleted from Documents")
        }
        
        if fileManager.fileExists(atPath: playFieldsDirectory.path) {
            try? fileManager.removeItem(at: playFieldsDirectory)
            print("✅ DataSync: PlayFields deleted from Documents")
        }
        
        if fileManager.fileExists(atPath: timelinesDirectory.path) {
            try? fileManager.removeItem(at: timelinesDirectory)
            print("✅ DataSync: Timelines deleted from Documents")
        }
    }
    
    private func deleteFromApplicationSupport() {
        if fileManager.fileExists(atPath: backupDirectory.path) {
            try? fileManager.removeItem(at: backupDirectory)
            print("✅ DataSync: Backup deleted from Application Support")
        }
    }
    
    /// Deletes timelines from backup for specific video
    /// Used only for manual deletion by user
    func deleteTimelinesFromBackup(forVideoId videoId: String) {
        let timelineFile = timelinesBackupDirectory.appendingPathComponent("\(videoId).json")
        
        if fileManager.fileExists(atPath: timelineFile.path) {
            try? fileManager.removeItem(at: timelineFile)
            print("🗑️ DataSync: Timelines for video \(videoId) deleted from backup")
        }
    }
    
    /// Deletes all timelines from backup
    /// Used only for manual deletion of all user data
    func deleteAllTimelinesFromBackup() {
        if fileManager.fileExists(atPath: timelinesBackupDirectory.path) {
            try? fileManager.removeItem(at: timelinesBackupDirectory)
            fileManager.createDirectoryIfNeeded(url: timelinesBackupDirectory)
            print("🗑️ DataSync: All timelines deleted from backup")
        }
    }
    
    private func clearUserDefaults() {
        UserDefaults.standard.removeObject(forKey: videosDataKey)
        UserDefaults.standard.removeObject(forKey: collectionsBookmarksKey)
        UserDefaults.standard.removeObject(forKey: lastSyncDateKey)
        
        // Clear CollectionsBookmarks.json
        if fileManager.fileExists(atPath: collectionsBookmarksFile.path) {
            try? fileManager.removeItem(at: collectionsBookmarksFile)
            print("✅ DataSync: CollectionsBookmarks.json cleared")
        }
        
        print("✅ DataSync: UserDefaults cleared")
    }
}
