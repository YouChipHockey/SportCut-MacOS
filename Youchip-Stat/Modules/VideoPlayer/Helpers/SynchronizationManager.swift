//
//  SynchronizationManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import Foundation
import Combine
import FirebaseAppCheck

enum SyncConflictResolution {
    case useLocal
    case useRemote
    case merge
    case askUser
}

enum SyncError: Error {
    case networkError(Error)
    case conflictError(String)
    case serverError(Int, String?)
    case decodingError(Error)
    case invalidData
    case unauthorized
    case mergeConflict([TimelineLine], [TimelineLine])
    case uploadFailed
    case noLocalData
    case noRemoteData
    
    var description: String {
        switch self {
        case .networkError(let error):
            return "Ошибка сети: \(error.localizedDescription)"
        case .conflictError(let message):
            return "Конфликт при синхронизации: \(message)"
        case .serverError(let code, let message):
            return "Ошибка сервера \(code): \(message ?? "Неизвестная ошибка")"
        case .decodingError(let error):
            return "Ошибка обработки данных: \(error.localizedDescription)"
        case .invalidData:
            return "Некорректные данные для синхронизации"
        case .unauthorized:
            return "Нет доступа к серверу"
        case .mergeConflict:
            return "Обнаружены конфликты данных, требующие разрешения"
        case .uploadFailed:
            return "Не удалось загрузить данные на сервер"
        case .noLocalData:
            return "Отсутствуют локальные данные для синхронизации"
        case .noRemoteData:
            return "Отсутствуют данные на сервере"
        }
    }
}

struct SyncMetadata: Codable {
    var lastSyncTimestamp: Date
    var lastLocalModification: Date
    var syncVersion: Int
    var videoId: String
    var videoHash: String?
    var conflictResolutionStrategy: String
    
    init(videoId: String) {
        self.videoId = videoId
        self.lastSyncTimestamp = Date(timeIntervalSince1970: 0)
        self.lastLocalModification = Date()
        self.syncVersion = 1
        self.videoHash = nil
        self.conflictResolutionStrategy = "prioritizeLocal"
    }
}

class SynchronizationManager {
    static let shared = SynchronizationManager()
    
    private var cancellables = Set<AnyCancellable>()
    private var apiService: MarkersAPIService
    private var pendingSyncs: [String: Bool] = [:]
    private var autoSyncTimer: Timer?
    private var syncQueue = DispatchQueue(label: "com.youchip.syncQueue", qos: .utility)
    
    // Current state
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var syncStatus: String?
    @Published private(set) var syncProgress: Double = 0
    @Published private(set) var conflictDetected = false
    @Published private(set) var syncErrors: [SyncError] = []
    
    // Configuration
    private var conflictResolutionStrategy: SyncConflictResolution = .useLocal
    private var autoSyncEnabled = true
    private var autoSyncInterval: TimeInterval = 60 * 5 // 5 minutes
    private var retryCount = 3
    private var syncTimeout: TimeInterval = 30
    
    // Cached data to avoid unnecessary network requests
    private var metadataCache: [String: SyncMetadata] = [:]
    private var remoteDataCache: [String: [FullTimelineLine]] = [:]
    
    private init() {
        self.apiService = MarkersAPIService.shared
        setupAutoSync()
        
        // Load user preferences
        loadSyncPreferences()
        
        // Listen for timeline changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTimelineDataChanged),
            name: NSNotification.Name("TimelineDataChanged"),
            object: nil
        )
        
        // Listen for network status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNetworkStatusChanged),
            name: NSNotification.Name("NetworkStatusChanged"),
            object: nil
        )
        
        // Listen for application entering background/foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: NSNotification.Name("NSApplicationWillResignActiveNotification"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSNotification.Name("NSApplicationDidBecomeActiveNotification"),
            object: nil
        )
    }
    
    deinit {
        autoSyncTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public API
    
    /// Synchronize timeline data for the specified video
    func synchronizeTimelines(for videoId: String) -> AnyPublisher<Void, SyncError> {
        guard !isSyncing else {
            return Fail(error: .conflictError("Синхронизация уже выполняется")).eraseToAnyPublisher()
        }
        
        // Check if we have local data
        guard let localData = VideoFilesManager.shared.getTimelines(for: videoId) else {
            return Fail(error: .noLocalData).eraseToAnyPublisher()
        }
        
        isSyncing = true
        syncStatus = "Начало синхронизации..."
        syncProgress = 0.0
        
        let syncPublisher = syncTimelines(videoId: videoId, localData: localData)
            .handleEvents(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    self.isSyncing = false
                    
                    switch completion {
                    case .failure(let error):
                        self.syncStatus = "Ошибка синхронизации: \(error.description)"
                        self.syncErrors.append(error)
                        
                        print("Sync error for video \(videoId): \(error.description)")
                        
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SyncFailed"),
                            object: nil,
                            userInfo: ["videoId": videoId, "error": error]
                        )
                        
                    case .finished:
                        self.syncStatus = "Синхронизация завершена"
                        self.lastSyncTime = Date()
                        self.syncProgress = 1.0
                        
                        if var metadata = self.getSyncMetadata(for: videoId) {
                            metadata.lastSyncTimestamp = Date()
                            self.saveSyncMetadata(metadata, for: videoId)
                        }
                        
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SyncCompleted"),
                            object: nil,
                            userInfo: ["videoId": videoId]
                        )
                    }
                }
            )
            .eraseToAnyPublisher()
        
        return syncPublisher
    }
    
    func forceUploadLocalChanges(for videoId: String) -> AnyPublisher<Void, SyncError> {
        guard !isSyncing else {
            return Fail(error: .conflictError("Синхронизация уже выполняется")).eraseToAnyPublisher()
        }
        
        guard let localData = VideoFilesManager.shared.getTimelines(for: videoId) else {
            return Fail(error: .noLocalData).eraseToAnyPublisher()
        }
        
        isSyncing = true
        syncStatus = "Загрузка локальных изменений..."
        syncProgress = 0.0
        
        let fullLocalData = transformToFullTimelineLines(localData)
        
        return uploadTimelineData(videoId: videoId, data: fullLocalData)
            .handleEvents(
                receiveSubscription: { [weak self] _ in
                    self?.syncProgress = 0.3
                },
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    self.isSyncing = false
                    
                    switch completion {
                    case .failure(let error):
                        self.syncStatus = "Ошибка загрузки: \(error.description)"
                        self.syncErrors.append(error)
                    case .finished:
                        self.syncStatus = "Загрузка завершена"
                        self.syncProgress = 1.0
                        self.lastSyncTime = Date()
                        
                        if var metadata = self.getSyncMetadata(for: videoId) {
                            metadata.lastSyncTimestamp = Date()
                            metadata.syncVersion += 1
                            self.saveSyncMetadata(metadata, for: videoId)
                        } else {
                            var newMetadata = SyncMetadata(videoId: videoId)
                            newMetadata.lastSyncTimestamp = Date()
                            self.saveSyncMetadata(newMetadata, for: videoId)
                        }
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    func forceDownloadRemoteChanges(for videoId: String) -> AnyPublisher<Void, SyncError> {
        guard !isSyncing else {
            return Fail(error: .conflictError("Синхронизация уже выполняется")).eraseToAnyPublisher()
        }
        
        isSyncing = true
        syncStatus = "Загрузка данных с сервера..."
        syncProgress = 0.0
        
        return fetchTimelineData(for: videoId)
            .flatMap { [weak self] remoteData -> AnyPublisher<Void, SyncError> in
                guard let self = self else {
                    return Fail(error: .invalidData).eraseToAnyPublisher()
                }
                
                let timelineData = self.convertFromFullTimelineLines(remoteData)
                
                VideoFilesManager.shared.updateTimelines(for: videoId, with: timelineData)
                
                self.remoteDataCache[videoId] = remoteData
                
                if var metadata = self.getSyncMetadata(for: videoId) {
                    metadata.lastSyncTimestamp = Date()
                    self.saveSyncMetadata(metadata, for: videoId)
                } else {
                    var newMetadata = SyncMetadata(videoId: videoId)
                    newMetadata.lastSyncTimestamp = Date()
                    self.saveSyncMetadata(newMetadata, for: videoId)
                }
                
                if TimelineDataManager.shared.currentBookmark != nil,
                   let currentVideoId = VideoFilesManager.shared.getCurrentVideoId(),
                   currentVideoId == videoId {
                    TimelineDataManager.shared.lines = timelineData
                }
                
                return Just(()).setFailureType(to: SyncError.self).eraseToAnyPublisher()
            }
            .handleEvents(
                receiveSubscription: { [weak self] _ in
                    self?.syncProgress = 0.3
                },
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    self.isSyncing = false
                    
                    switch completion {
                    case .failure(let error):
                        self.syncStatus = "Ошибка получения данных: \(error.description)"
                        self.syncErrors.append(error)
                    case .finished:
                        self.syncStatus = "Получение данных завершено"
                        self.syncProgress = 1.0
                        self.lastSyncTime = Date()
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    /// Configure synchronization behavior
    func configureSynchronization(
        autoSync: Bool? = nil,
        interval: TimeInterval? = nil,
        conflictStrategy: SyncConflictResolution? = nil,
        retryCount: Int? = nil
    ) {
        if let autoSync = autoSync {
            self.autoSyncEnabled = autoSync
        }
        
        if let interval = interval {
            self.autoSyncInterval = interval
        }
        
        if let strategy = conflictStrategy {
            self.conflictResolutionStrategy = strategy
        }
        
        if let retryCount = retryCount {
            self.retryCount = retryCount
        }
        
        // Update auto-sync timer if needed
        if autoSyncEnabled {
            setupAutoSync()
        } else {
            autoSyncTimer?.invalidate()
            autoSyncTimer = nil
        }
        
        // Save preferences
        saveSyncPreferences()
    }
    
    /// Get the last sync status for a video
    func getSyncStatus(for videoId: String) -> (lastSync: Date?, status: String?) {
        let metadata = getSyncMetadata(for: videoId)
        return (metadata?.lastSyncTimestamp, syncStatus)
    }
    
    /// Clear sync errors
    func clearSyncErrors() {
        syncErrors.removeAll()
    }
    
    /// Resolve conflict manually
    func resolveConflict(for videoId: String, resolution: SyncConflictResolution) -> AnyPublisher<Void, SyncError> {
        guard conflictDetected else {
            return Just(()).setFailureType(to: SyncError.self).eraseToAnyPublisher()
        }
        
        guard let localData = VideoFilesManager.shared.getTimelines(for: videoId),
              let remoteData = remoteDataCache[videoId] else {
            return Fail(error: .invalidData).eraseToAnyPublisher()
        }
        
        isSyncing = true
        syncStatus = "Разрешение конфликтов..."
        syncProgress = 0.0
        
        let resolvePublisher: AnyPublisher<Void, SyncError>
        
        switch resolution {
        case .useLocal:
            // Upload local data to server
            let fullLocalData = transformToFullTimelineLines(localData)
            resolvePublisher = uploadTimelineData(videoId: videoId, data: fullLocalData)
            
        case .useRemote:
            // Apply remote data locally
            let timelineData = convertFromFullTimelineLines(remoteData)
            VideoFilesManager.shared.updateTimelines(for: videoId, with: timelineData)
            
            // Update TimelineDataManager if it's the current video
            if TimelineDataManager.shared.currentBookmark != nil,
               let currentVideoId = VideoFilesManager.shared.getCurrentVideoId(),
               currentVideoId == videoId {
                TimelineDataManager.shared.lines = timelineData
            }
            
            resolvePublisher = Just(()).setFailureType(to: SyncError.self).eraseToAnyPublisher()
            
        case .merge:
            let mergedData = performIntelligentMerge(local: localData, remote: remoteData)
            
            VideoFilesManager.shared.updateTimelines(for: videoId, with: mergedData)
            
            if TimelineDataManager.shared.currentBookmark != nil,
               let currentVideoId = VideoFilesManager.shared.getCurrentVideoId(),
               currentVideoId == videoId {
                TimelineDataManager.shared.lines = mergedData
            }
            
            let fullMergedData = transformToFullTimelineLines(mergedData)
            resolvePublisher = uploadTimelineData(videoId: videoId, data: fullMergedData)
            
        case .askUser:
            resolvePublisher = Fail(error: .conflictError("Требуется ручное разрешение конфликтов")).eraseToAnyPublisher()
        }
        
        return resolvePublisher
            .handleEvents(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    self.isSyncing = false
                    
                    switch completion {
                    case .failure(let error):
                        self.syncStatus = "Ошибка разрешения конфликтов: \(error.description)"
                        self.syncErrors.append(error)
                    case .finished:
                        self.syncStatus = "Конфликты разрешены"
                        self.syncProgress = 1.0
                        self.lastSyncTime = Date()
                        self.conflictDetected = false
                        
                        if var metadata = self.getSyncMetadata(for: videoId) {
                            metadata.lastSyncTimestamp = Date()
                            metadata.syncVersion += 1
                            self.saveSyncMetadata(metadata, for: videoId)
                        }
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func syncTimelines(videoId: String, localData: [TimelineLine]) -> AnyPublisher<Void, SyncError> {
        syncProgress = 0.1
        syncStatus = "Проверка данных на сервере..."
        
        let metadata = getSyncMetadata(for: videoId)
        
        return fetchTimelineData(for: videoId)
            .flatMap { [weak self] remoteData -> AnyPublisher<Void, SyncError> in
                guard let self = self else {
                    return Fail(error: .invalidData).eraseToAnyPublisher()
                }
                
                self.syncProgress = 0.3
                self.syncStatus = "Анализ изменений..."
                
                self.remoteDataCache[videoId] = remoteData
                
                if remoteData.isEmpty {
                    self.syncStatus = "Загрузка локальных данных на сервер..."
                    let fullLocalData = self.transformToFullTimelineLines(localData)
                    return self.uploadTimelineData(videoId: videoId, data: fullLocalData)
                }
                
                let convertedRemoteData = self.convertFromFullTimelineLines(remoteData)
                let hasConflicts = self.detectConflicts(local: localData, remote: convertedRemoteData)
                
                if hasConflicts {
                    self.syncStatus = "Обнаружены конфликты..."
                    self.conflictDetected = true
                    
                    switch self.conflictResolutionStrategy {
                    case .useLocal:
                        self.syncStatus = "Приоритет локальных данных..."
                        let fullLocalData = self.transformToFullTimelineLines(localData)
                        return self.uploadTimelineData(videoId: videoId, data: fullLocalData)
                        
                    case .useRemote:
                        self.syncStatus = "Применение данных с сервера..."
                        VideoFilesManager.shared.updateTimelines(for: videoId, with: convertedRemoteData)
                        
                        if TimelineDataManager.shared.currentBookmark != nil,
                           let currentVideoId = VideoFilesManager.shared.getCurrentVideoId(),
                           currentVideoId == videoId {
                            TimelineDataManager.shared.lines = convertedRemoteData
                        }
                        
                        return Just(()).setFailureType(to: SyncError.self).eraseToAnyPublisher()
                        
                    case .merge:
                        self.syncStatus = "Интеллектуальное объединение данных..."
                        let mergedData = self.performIntelligentMerge(local: localData, remote: convertedRemoteData)
                        
                        VideoFilesManager.shared.updateTimelines(for: videoId, with: mergedData)
                        
                        if TimelineDataManager.shared.currentBookmark != nil,
                           let currentVideoId = VideoFilesManager.shared.getCurrentVideoId(),
                           currentVideoId == videoId {
                            TimelineDataManager.shared.lines = mergedData
                        }
                        
                        let fullMergedData = self.transformToFullTimelineLines(mergedData)
                        return self.uploadTimelineData(videoId: videoId, data: fullMergedData)
                        
                    case .askUser:
                        return Fail(error: .mergeConflict(localData, convertedRemoteData)).eraseToAnyPublisher()
                    }
                } else {
                    if let meta = metadata {
                        if meta.lastLocalModification > meta.lastSyncTimestamp {
                            self.syncStatus = "Загрузка локальных данных на сервер..."
                            let fullLocalData = self.transformToFullTimelineLines(localData)
                            return self.uploadTimelineData(videoId: videoId, data: fullLocalData)
                        } else {
                            self.syncStatus = "Применение данных с сервера..."
                            VideoFilesManager.shared.updateTimelines(for: videoId, with: convertedRemoteData)
                            
                            if TimelineDataManager.shared.currentBookmark != nil,
                               let currentVideoId = VideoFilesManager.shared.getCurrentVideoId(),
                               currentVideoId == videoId {
                                TimelineDataManager.shared.lines = convertedRemoteData
                            }
                            
                            return Just(()).setFailureType(to: SyncError.self).eraseToAnyPublisher()
                        }
                    } else {
                        self.syncStatus = "Загрузка локальных данных на сервер..."
                        let fullLocalData = self.transformToFullTimelineLines(localData)
                        return self.uploadTimelineData(videoId: videoId, data: fullLocalData)
                    }
                }
            }
            .eraseToAnyPublisher()
    }
    
    private func fetchTimelineData(for videoId: String) -> AnyPublisher<[FullTimelineLine], SyncError> {
        return apiService.getMarkersPublisher(for: videoId)
            .mapError { error -> SyncError in
                switch error {
                case .networkError(let err):
                    return .networkError(err)
                case .decodingError(let err):
                    return .decodingError(err)
                case .serverError(let code, let message):
                    return .serverError(code, message)
                case .unauthorized:
                    return .unauthorized
                default:
                    return .networkError(error)
                }
            }
            .flatMap { [weak self] timelineData -> AnyPublisher<[FullTimelineLine], SyncError> in
                guard let self = self else {
                    return Fail(error: .invalidData).eraseToAnyPublisher()
                }
                
                // Try to interpret data as FullTimelineLines directly or convert from TimelineLines
                if let fullData = timelineData as? [FullTimelineLine] {
                    return Just(fullData).setFailureType(to: SyncError.self).eraseToAnyPublisher()
                } else {
                    let fullData = self.transformToFullTimelineLines(timelineData)
                    return Just(fullData).setFailureType(to: SyncError.self).eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }
    
    private func uploadTimelineData(videoId: String, data: [FullTimelineLine]) -> AnyPublisher<Void, SyncError> {
        return apiService.uploadMarkersPublisher(for: videoId, markersData: convertFromFullTimelineLines(data))
            .mapError { error -> SyncError in
                switch error {
                case .networkError(let err):
                    return .networkError(err)
                case .serverError(let code, let message):
                    return .serverError(code, message)
                case .unauthorized:
                    return .unauthorized
                default:
                    return .uploadFailed
                }
            }
            .eraseToAnyPublisher()
    }
    
    private func detectConflicts(local: [TimelineLine], remote: [TimelineLine]) -> Bool {
        if local.isEmpty || remote.isEmpty {
            return false
        }
        
        if local.count != remote.count {
            return true
        }
        
        let localDict = Dictionary(grouping: local, by: { $0.id.uuidString })
        let remoteDict = Dictionary(grouping: remote, by: { $0.id.uuidString })
        
        for (id, lines) in localDict {
            if remoteDict[id] == nil {
                return true
            }
        }
        
        for (id, lines) in remoteDict {
            if localDict[id] == nil {
                return true
            }
        }
        
        for (id, localLines) in localDict {
            guard let remoteLines = remoteDict[id],
                  let localLine = localLines.first,
                  let remoteLine = remoteLines.first else {
                continue
            }
            
            if localLine.stamps.count != remoteLine.stamps.count {
                return true
            }
            
            let localStampDict = Dictionary(grouping: localLine.stamps, by: { $0.id.uuidString })
            let remoteStampDict = Dictionary(grouping: remoteLine.stamps, by: { $0.id.uuidString })
            
            for (stampId, _) in localStampDict {
                if remoteStampDict[stampId] == nil {
                    return true
                }
            }
            
            for (stampId, _) in remoteStampDict {
                if localStampDict[stampId] == nil {
                    return true
                }
            }
            
            for (stampId, localStamps) in localStampDict {
                guard let remoteStamps = remoteStampDict[stampId],
                      let localStamp = localStamps.first,
                      let remoteStamp = remoteStamps.first else {
                    continue
                }
                
                if localStamp.timeStart != remoteStamp.timeStart ||
                   localStamp.timeFinish != remoteStamp.timeFinish ||
                   localStamp.idTag != remoteStamp.idTag ||
                   localStamp.labels != remoteStamp.labels ||
                   localStamp.timeEvents != remoteStamp.timeEvents {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func performIntelligentMerge(local: [TimelineLine], remote: [TimelineLine]) -> [TimelineLine] {
        var mergedLines: [TimelineLine] = []
        
        let localDict = Dictionary(grouping: local, by: { $0.id.uuidString })
        let remoteDict = Dictionary(grouping: remote, by: { $0.id.uuidString })
        
        let allLineIds = Set(localDict.keys).union(Set(remoteDict.keys))
        
        for lineId in allLineIds {
            let localLine = localDict[lineId]?.first
            let remoteLine = remoteDict[lineId]?.first
            
            if let localLine = localLine, remoteLine == nil {
                mergedLines.append(localLine)
            } else if localLine == nil, let remoteLine = remoteLine {
                mergedLines.append(remoteLine)
            } else if let localLine = localLine, let remoteLine = remoteLine {
                let mergedLine = mergeLine(local: localLine, remote: remoteLine)
                mergedLines.append(mergedLine)
            }
        }
        
        return mergedLines
    }
    
    private func mergeLine(local: TimelineLine, remote: TimelineLine) -> TimelineLine {
        var mergedLine = TimelineLine(id: local.id, name: local.name, tagIdForMode: local.tagIdForMode)
        
        let localStampDict = Dictionary(grouping: local.stamps, by: { $0.id.uuidString })
        let remoteStampDict = Dictionary(grouping: remote.stamps, by: { $0.id.uuidString })
        
        // Process all stamp IDs from both datasets
        let allStampIds = Set(localStampDict.keys).union(Set(remoteStampDict.keys))
        
        var mergedStamps: [TimelineStamp] = []
        
        for stampId in allStampIds {
            let localStamp = localStampDict[stampId]?.first
            let remoteStamp = remoteStampDict[stampId]?.first
            
            if let localStamp = localStamp, remoteStamp == nil {
                mergedStamps.append(localStamp)
            } else if localStamp == nil, let remoteStamp = remoteStamp {
                mergedStamps.append(remoteStamp)
            } else if let localStamp = localStamp, let remoteStamp = remoteStamp {
                let mergedStamp = mergeStamp(local: localStamp, remote: remoteStamp)
                mergedStamps.append(mergedStamp)
            }
        }
        
        mergedStamps.sort { $0.startSeconds < $1.startSeconds }
        mergedLine.stamps = mergedStamps
        
        return mergedLine
    }
    
    private func mergeStamp(local: TimelineStamp, remote: TimelineStamp) -> TimelineStamp {
        let allLabels = Set(local.labels).union(Set(remote.labels))
        let allTimeEvents = Set(local.timeEvents).union(Set(remote.timeEvents))
        
        return TimelineStamp(
            id: local.id,
            idTag: local.idTag,
            primaryID: local.primaryID,
            timeStart: local.timeStart,
            timeFinish: local.timeFinish,
            colorHex: local.colorHex,
            label: local.label,
            labels: Array(allLabels),
            timeEvents: Array(allTimeEvents),
            position: local.position,
            isActiveForMapView: local.isActiveForMapView
        )
    }
    
    private func getSyncMetadata(for videoId: String) -> SyncMetadata? {
        if let cachedMetadata = metadataCache[videoId] {
            return cachedMetadata
        }
        
        let key = "syncMetadata_\(videoId)"
        if let data = UserDefaults.standard.data(forKey: key) {
            do {
                let metadata = try JSONDecoder().decode(SyncMetadata.self, from: data)
                metadataCache[videoId] = metadata
                return metadata
            } catch {
                print("Failed to decode sync metadata for video \(videoId): \(error)")
                return nil
            }
        }
        
        return nil
    }
    
    private func saveSyncMetadata(_ metadata: SyncMetadata, for videoId: String) {
        metadataCache[videoId] = metadata
        
        let key = "syncMetadata_\(videoId)"
        do {
            let data = try JSONEncoder().encode(metadata)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Failed to encode sync metadata for video \(videoId): \(error)")
        }
    }
    
    private func setupAutoSync() {
        autoSyncTimer?.invalidate()
        
        if autoSyncEnabled {
            autoSyncTimer = Timer.scheduledTimer(
                withTimeInterval: autoSyncInterval,
                repeats: true
            ) { [weak self] _ in
                self?.performAutoSync()
            }
        }
    }
    
    private func performAutoSync() {
        guard autoSyncEnabled, !isSyncing else { return }
        
        let videosToSync = VideoFilesManager.shared.getAllVideoIds()
        
        for videoId in videosToSync {
            if pendingSyncs[videoId] == true {
                continue
            }
            
            pendingSyncs[videoId] = true
            
            guard let localData = VideoFilesManager.shared.getTimelines(for: videoId) else {
                pendingSyncs[videoId] = nil
                continue
            }
            
            syncQueue.async { [weak self] in
                guard let self = self else { return }
                
                self.synchronizeTimelines(for: videoId)
                    .sink(
                        receiveCompletion: { _ in
                            self.pendingSyncs[videoId] = nil
                        },
                        receiveValue: { _ in }
                    )
                    .store(in: &self.cancellables)
            }
        }
    }
    
    private func loadSyncPreferences() {
        autoSyncEnabled = UserDefaults.standard.bool(forKey: "syncAutoSyncEnabled")
        autoSyncInterval = UserDefaults.standard.double(forKey: "syncAutoSyncInterval")
        retryCount = UserDefaults.standard.integer(forKey: "syncRetryCount")
        
        let strategyString = UserDefaults.standard.string(forKey: "syncConflictStrategy") ?? "useLocal"
        switch strategyString {
        case "useLocal":
            conflictResolutionStrategy = .useLocal
        case "useRemote":
            conflictResolutionStrategy = .useRemote
        case "merge":
            conflictResolutionStrategy = .merge
        case "askUser":
            conflictResolutionStrategy = .askUser
        default:
            conflictResolutionStrategy = .useLocal
        }
        
        if autoSyncInterval == 0 {
            autoSyncInterval = 60 * 5
        }
        
        if retryCount == 0 {
            retryCount = 3
        }
    }
    
    private func saveSyncPreferences() {
        UserDefaults.standard.set(autoSyncEnabled, forKey: "syncAutoSyncEnabled")
        UserDefaults.standard.set(autoSyncInterval, forKey: "syncAutoSyncInterval")
        UserDefaults.standard.set(retryCount, forKey: "syncRetryCount")
        
        let strategyString: String
        switch conflictResolutionStrategy {
        case .useLocal:
            strategyString = "useLocal"
        case .useRemote:
            strategyString = "useRemote"
        case .merge:
            strategyString = "merge"
        case .askUser:
            strategyString = "askUser"
        }
        UserDefaults.standard.set(strategyString, forKey: "syncConflictStrategy")
    }
    
    @objc private func handleTimelineDataChanged() {
        guard let videoId = VideoFilesManager.shared.getCurrentVideoId() else { return }
        
        if var metadata = getSyncMetadata(for: videoId) {
            metadata.lastLocalModification = Date()
            saveSyncMetadata(metadata, for: videoId)
        } else {
            var newMetadata = SyncMetadata(videoId: videoId)
            saveSyncMetadata(newMetadata, for: videoId)
        }
        
        if autoSyncEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                if let videoId = VideoFilesManager.shared.getCurrentVideoId() {
                    self?.synchronizeTimelines(for: videoId)
                        .sink(
                            receiveCompletion: { _ in },
                            receiveValue: { _ in }
                        )
                        .store(in: &self!.cancellables)
                }
            }
        }
    }
    
    @objc private func handleNetworkStatusChanged() {
        if let isConnected = NetworkMonitor.shared.isConnected, isConnected {
            performAutoSync()
        }
    }
    
    @objc private func handleAppWillResignActive() {
        if let videoId = VideoFilesManager.shared.getCurrentVideoId() {
            synchronizeTimelines(for: videoId)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { _ in }
                )
                .store(in: &cancellables)
        }
    }
    
    @objc private func handleAppDidBecomeActive() {
        if let videoId = VideoFilesManager.shared.getCurrentVideoId() {
            synchronizeTimelines(for: videoId)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { _ in }
                )
                .store(in: &cancellables)
        }
    }
    
    // MARK: - Helper Methods for Timeline Conversion
    
    private func transformToFullTimelineLines(_ lines: [TimelineLine]) -> [FullTimelineLine] {
        let tagLibrary = TagLibraryManager.shared
        
        return lines.map { line in
            let fullStamps = line.stamps.map { stamp -> FullTimelineStamp in
                let tag = tagLibrary.findTagById(stamp.idTag)
                var tagGroup: TagGroupInfo? = nil
                if let tagID = tag?.id {
                    for group in tagLibrary.allTagGroups {
                        if group.tags.contains(tagID) {
                            tagGroup = TagGroupInfo(id: group.id, name: group.name)
                            break
                        }
                    }
                }
                
                let fullTag = FullTagWithGroup(
                    id: tag?.id ?? "",
                    primaryID: tag?.primaryID,
                    name: tag?.name ?? stamp.label,
                    description: tag?.description ?? "",
                    color: tag?.color ?? "FFFFFF",
                    defaultTimeBefore: tag?.defaultTimeBefore ?? 0,
                    defaultTimeAfter: tag?.defaultTimeAfter ?? 0,
                    collection: tag?.collection ?? "",
                    hotkey: tag?.hotkey,
                    labelHotkeys: tag?.labelHotkeys,
                    group: tagGroup
                )
                
                let fullLabels = stamp.labels.compactMap { labelID -> FullLabelWithGroup? in
                    guard let label = tagLibrary.findLabelById(labelID) else { return nil }
                    
                    var labelGroup: LabelGroupInfo? = nil
                    for group in tagLibrary.allLabelGroups {
                        if group.lables.contains(labelID) {
                            labelGroup = LabelGroupInfo(id: group.id, name: group.name)
                            break
                        }
                    }
                    
                    return FullLabelWithGroup(
                        id: label.id,
                        name: label.name,
                        description: label.description,
                        group: labelGroup
                    )
                }
                
                let fullTimeEvents = stamp.timeEvents.compactMap { eventID in
                    tagLibrary.allTimeEvents.first(where: { $0.id == eventID })
                }
                
                return FullTimelineStamp(
                    id: stamp.id,
                    timeStart: stamp.timeStart,
                    timeFinish: stamp.timeFinish,
                    tag: fullTag,
                    labels: fullLabels,
                    timeEvents: fullTimeEvents,
                    position: stamp.position
                )
            }
            
            return FullTimelineLine(id: line.id, name: line.name, stamps: fullStamps)
        }
    }
    
    private func convertFromFullTimelineLines(_ fullLines: [FullTimelineLine]) -> [TimelineLine] {
        return fullLines.map { fullLine in
            let stamps = fullLine.stamps.map { fullStamp -> TimelineStamp in
                let position = fullStamp.position
                let isActiveForMapView = position != nil
                
                return TimelineStamp(
                    id: fullStamp.id,
                    idTag: fullStamp.tag.id,
                    primaryID: fullStamp.tag.primaryID,
                    timeStart: fullStamp.timeStart,
                    timeFinish: fullStamp.timeFinish,
                    colorHex: fullStamp.tag.color,
                    label: fullStamp.tag.name,
                    labels: fullStamp.labels.map { $0.id },
                    timeEvents: fullStamp.timeEvents.map { $0.id },
                    position: position,
                    isActiveForMapView: isActiveForMapView
                )
            }
            
            return TimelineLine(id: fullLine.id, name: fullLine.name, stamps: stamps)
        }
    }
}

// MARK: - Network Monitoring Class

class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    @Published var isConnected: Bool? = nil
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        isConnected = true
        
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                let connected = Double.random(in: 0...1) < 0.95
                
                if self?.isConnected != connected {
                    self?.isConnected = connected
                    
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NetworkStatusChanged"),
                        object: nil,
                        userInfo: ["isConnected": connected]
                    )
                }
            }
            .store(in: &cancellables)
    }
}

struct SyncStatusView: View {
    @ObservedObject var syncManager: SynchronizationManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Статус синхронизации")
                    .font(.headline)
                
                Spacer()
                
                if syncManager.isSyncing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 4)
                }
            }
            
            if let status = syncManager.syncStatus {
                Text(status)
                    .font(.subheadline)
            }
            
            if syncManager.isSyncing {
                ProgressView(value: syncManager.syncProgress)
                    .progressViewStyle(LinearProgressViewStyle())
            }
            
            if let lastSync = syncManager.lastSyncTime {
                Text("Последняя синхронизация: \(formattedDate(lastSync))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !syncManager.syncErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ошибки:")
                        .font(.caption)
                        .foregroundColor(.red)
                    
                    ForEach(0..<min(syncManager.syncErrors.count, 3), id: \.self) { index in
                        Text(syncManager.syncErrors[index].description)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                    
                    if syncManager.syncErrors.count > 3 {
                        Text("... и еще \(syncManager.syncErrors.count - 3)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Button("Очистить") {
                        syncManager.clearSyncErrors()
                    }
                    .font(.caption)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct SyncSettingsView: View {
    @ObservedObject var syncManager: SynchronizationManager
    
    @State private var autoSyncEnabled: Bool = true
    @State private var syncInterval: Double = 5
    @State private var conflictStrategy: SyncConflictResolution = .useLocal
    @State private var retryCount: Int = 3
    
    var body: some View {
        Form {
            Section(header: Text("Настройки синхронизации")) {
                Toggle("Автоматическая синхронизация", isOn: $autoSyncEnabled)
                
                if autoSyncEnabled {
                    HStack {
                        Text("Интервал:")
                        Slider(value: $syncInterval, in: 1...30, step: 1)
                        Text("\(Int(syncInterval)) мин")
                    }
                }
                
                Picker("Стратегия при конфликтах", selection: $conflictStrategy) {
                    Text("Приоритет локальных данных").tag(SyncConflictResolution.useLocal)
                    Text("Приоритет данных с сервера").tag(SyncConflictResolution.useRemote)
                    Text("Интеллектуальное объединение").tag(SyncConflictResolution.merge)
                    Text("Спрашивать").tag(SyncConflictResolution.askUser)
                }
                
                Stepper("Количество попыток: \(retryCount)", value: $retryCount, in: 1...10)
            }
            
            Section {
                Button("Применить настройки") {
                    syncManager.configureSynchronization(
                        autoSync: autoSyncEnabled,
                        interval: syncInterval * 60, // Convert to seconds
                        conflictStrategy: conflictStrategy,
                        retryCount: retryCount
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
    }
}
