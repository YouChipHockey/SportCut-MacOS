//
//  OrphanedTimelinesManager.swift
//  Youchip-Stat
//
//  Created on 10.02.2026.
//

import Foundation
import SwiftUI

class OrphanedTimelinesManager: ObservableObject {
    
    static let shared = OrphanedTimelinesManager()
    
    @Published var orphanedTimelines: [DataSyncManager.OrphanedTimeline] = []
    @Published var showRecoveryView = false
    
    private init() {}
    
    /// Проверяет наличие осиротевших разметок при запуске приложения
    func checkForOrphanedTimelinesOnLaunch() {
        DispatchQueue.global(qos: .userInitiated).async {
            let orphaned = DataSyncManager.shared.detectOrphanedTimelines()
            
            DispatchQueue.main.async {
                self.orphanedTimelines = orphaned
                
                if !orphaned.isEmpty {
                    // Показываем recovery view только если есть осиротевшие разметки
                    self.showRecoveryView = true
                    print("🔍 OrphanedTimelinesManager: Обнаружено \(orphaned.count) осиротевших разметок")
                }
            }
        }
    }
    
    /// Сбрасывает состояние после восстановления
    func resetAfterRecovery() {
        orphanedTimelines = []
        showRecoveryView = false
    }
}
