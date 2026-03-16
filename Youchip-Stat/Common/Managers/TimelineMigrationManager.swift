import Foundation

final class TimelineMigrationManager {
    
    static let shared = TimelineMigrationManager()
    
    private let fileManager = FileManager.default
    private let migrationVersionKey = "TimelineMigration_Version"
    private let currentMigrationVersion = 4
    
    private init() {}
    
    func migrateIfNeeded() {
        let lastVersion = UserDefaults.standard.integer(forKey: migrationVersionKey)
        guard lastVersion < currentMigrationVersion else { return }
        
        print("🔄 TimelineMigration: Starting migration from v\(lastVersion) to v\(currentMigrationVersion)")
        
        migrateTimelinesInUserDefaults()
        migrateTimelinesOnDisk()
        migrateOrphanedBackups()
        
        UserDefaults.standard.set(currentMigrationVersion, forKey: migrationVersionKey)
        print("✅ TimelineMigration: Migration complete")
    }
    
    // MARK: - UserDefaults Timelines
    
    private func migrateTimelinesInUserDefaults() {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("timeline_") }
        var migratedCount = 0
        
        for key in keys {
            guard let data = UserDefaults.standard.data(forKey: key) else { continue }
            
            if needsMigration(data: data) {
                if let migrated = migrateTimelineData(data) {
                    UserDefaults.standard.set(migrated, forKey: key)
                    migratedCount += 1
                }
            }
        }
        
        if migratedCount > 0 {
            print("🔄 TimelineMigration: Migrated \(migratedCount) timelines in UserDefaults")
        }
    }
    
    // MARK: - Disk Timelines
    
    private func migrateTimelinesOnDisk() {
        let timelinesDirectory = getTimelinesDirectory()
        guard fileManager.fileExists(atPath: timelinesDirectory.path) else { return }
        
        var migratedCount = 0
        
        guard let files = try? fileManager.contentsOfDirectory(at: timelinesDirectory, includingPropertiesForKeys: nil) else { return }
        
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file) else { continue }
            
            if needsMigration(data: data) {
                if let migrated = migrateTimelineData(data) {
                    try? migrated.write(to: file)
                    migratedCount += 1
                }
            }
        }
        
        if migratedCount > 0 {
            print("🔄 TimelineMigration: Migrated \(migratedCount) timeline files on disk")
        }
    }
    
    // MARK: - Orphaned Backups
    
    private func migrateOrphanedBackups() {
        let backupDir = getBackupTimelinesDirectory()
        guard fileManager.fileExists(atPath: backupDir.path) else { return }
        
        var migratedCount = 0
        
        guard let files = try? fileManager.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil) else { return }
        
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file) else { continue }
            
            if needsMigration(data: data) {
                if let migrated = migrateOrphanedTimelineData(data) {
                    try? migrated.write(to: file)
                    migratedCount += 1
                }
            }
        }
        
        if migratedCount > 0 {
            print("🔄 TimelineMigration: Migrated \(migratedCount) orphaned backup files")
        }
    }
    
    // MARK: - Migration Logic
    
    private func needsMigration(data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            if let orphanedJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let timelines = orphanedJson["timelines"] as? [[String: Any]] {
                return timelinesNeedMigration(timelines)
            }
            return false
        }
        return timelinesNeedMigration(json)
    }
    
    private func timelinesNeedMigration(_ timelines: [[String: Any]]) -> Bool {
        for timeline in timelines {
            guard let stamps = timeline["stamps"] as? [[String: Any]] else { continue }
            for stamp in stamps {
                if let labels = stamp["labels"] as? [String], !labels.isEmpty {
                    return true
                }
                if stamp["tagRefs"] == nil {
                    return true
                }
            }
        }
        return false
    }
    
    private func migrateTimelineData(_ data: Data) -> Data? {
        guard var timelines = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        
        var changed = false
        for i in timelines.indices {
            guard var stamps = timelines[i]["stamps"] as? [[String: Any]] else { continue }
            for j in stamps.indices {
                if migrateStamp(&stamps[j]) {
                    changed = true
                }
            }
            timelines[i]["stamps"] = stamps
        }
        
        guard changed else { return nil }
        return try? JSONSerialization.data(withJSONObject: timelines)
    }
    
    private func migrateOrphanedTimelineData(_ data: Data) -> Data? {
        guard var orphaned = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var timelines = orphaned["timelines"] as? [[String: Any]] else { return nil }
        
        var changed = false
        for i in timelines.indices {
            guard var stamps = timelines[i]["stamps"] as? [[String: Any]] else { continue }
            for j in stamps.indices {
                if migrateStamp(&stamps[j]) {
                    changed = true
                }
            }
            timelines[i]["stamps"] = stamps
        }
        
        guard changed else { return nil }
        orphaned["timelines"] = timelines
        return try? JSONSerialization.data(withJSONObject: orphaned)
    }
    
    @discardableResult
    private func migrateStamp(_ stamp: inout [String: Any]) -> Bool {
        var changed = false
        
        if let labelStrings = stamp["labels"] as? [String] {
            let migratedLabels: [[String: Any]] = labelStrings.map { labelID in
                [
                    "id": labelID,
                    "name": "",
                    "description": "",
                    "lableGroupId": ""
                ]
            }
            stamp["labels"] = migratedLabels
            changed = true
        }
        
        if stamp["tagRefs"] == nil {
            let groupId = (stamp["tagGroupId"] as? String) ?? ""
            
            if let tagArray = stamp["idTags"] as? [String] {
                stamp["tagRefs"] = tagArray.map { ["id": $0, "tagGroupId": groupId] }
                stamp.removeValue(forKey: "idTags")
                changed = true
            } else if let singleTag = stamp["idTag"] as? String {
                stamp["tagRefs"] = [["id": singleTag, "tagGroupId": groupId]]
                stamp.removeValue(forKey: "idTag")
                changed = true
            }
            
            stamp.removeValue(forKey: "tagGroupId")
        }
        
        return changed
    }
    
    // MARK: - Directories
    
    private func getTimelinesDirectory() -> URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("YouChip-Stat/Timelines", isDirectory: true)
    }
    
    private func getBackupTimelinesDirectory() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("YouChip-Stat-Backup/Timelines", isDirectory: true)
    }
}
