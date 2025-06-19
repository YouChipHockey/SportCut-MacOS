//
//  SyncMetadata.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import Foundation
import Combine
import FirebaseAppCheck

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
