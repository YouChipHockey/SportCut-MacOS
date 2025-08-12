//
//  SyncView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import Foundation
import Combine
import FirebaseAppCheck
import SwiftUI

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
                        interval: syncInterval * 60,
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
