//
//  DataManagementSheet.swift
//  Youchip-Stat
//
//  Created on 10.02.2026.
//

import SwiftUI
import AppKit

struct DataManagementSheet: View {
    
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var isProcessing = false
    @State private var resultMessage: String?
    @State private var showResult = false
    @State private var showOrphanedTimelinesSheet = false
    @State private var orphanedTimelines: [DataSyncManager.OrphanedTimeline] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "externaldrive.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 24))
                    
                    Text(^String.Titles.dataManagementTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 20))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Info section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 16))
                            Text(^String.Titles.dataManagementBackupSystemInfo)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        
                        Text(^String.Titles.dataManagementBackupSystemDescription)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // Documents button
                            Button(action: {
                                openDocumentsFolder()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 14))
                                        .frame(width: 20)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(^String.Titles.dataManagementDocumentsTitle)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        Text(^String.Titles.dataManagementDocumentsDescription)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 16))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help(^String.Titles.dataManagementDocumentsHelp)
                            
                            // Application Support button
                            Button(action: {
                                openApplicationSupportFolder()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "lock.shield.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 14))
                                        .frame(width: 20)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(^String.Titles.dataManagementApplicationSupportTitle)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        Text(^String.Titles.dataManagementApplicationSupportDescription)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 16))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.green.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help(^String.Titles.dataManagementApplicationSupportHelp)
                        }
                        .padding(.leading, 8)
                        
                        Text(^String.Titles.dataManagementBackupNote)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // Actions section
                    VStack(spacing: 16) {
                        // Restore button
                        Button(action: {
                            showRestoreConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(^String.Titles.dataManagementRestoreFromBackup)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    Text(^String.Titles.dataManagementRestoreFromBackupDescription)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .padding(16)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isProcessing)
                        
                        // Create backup button
                        Button(action: {
                            createBackup()
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.green)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(^String.Titles.dataManagementCreateBackup)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    Text(^String.Titles.dataManagementCreateBackupDescription)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .padding(16)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isProcessing)
                        
                        // Orphaned timelines button
                        Button(action: {
                            checkOrphanedTimelines()
                        }) {
                            HStack {
                                Image(systemName: "film.stack.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.purple)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(^String.Titles.dataManagementCheckOrphanedTimelines)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    Text(^String.Titles.dataManagementCheckOrphanedTimelinesDescription)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .padding(16)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isProcessing)
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Delete button
                        Button(action: {
                            showDeleteConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "trash.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.red)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(^String.Titles.dataManagementDeleteAllData)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.red)
                                    
                                    Text(^String.Titles.dataManagementDeleteAllDataDescription)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 12))
                            }
                            .padding(16)
                            .background(Color.red.opacity(0.05))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isProcessing)
                    }
                    
                    if isProcessing {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(^String.Titles.dataManagementProcessing)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 550, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .alert(^String.Titles.dataManagementRestoreConfirmationTitle, isPresented: $showRestoreConfirmation) {
            Button(^String.Titles.cancelButtonTitle, role: .cancel) {}
            Button(^String.Titles.dataManagementRestoreFromBackup) {
                restoreFromBackup()
            }
        } message: {
            Text(^String.Titles.dataManagementRestoreConfirmationMessage)
        }
        .alert(^String.Titles.dataManagementDeleteConfirmationTitle, isPresented: $showDeleteConfirmation) {
            Button(^String.Titles.cancelButtonTitle, role: .cancel) {}
            Button(^String.Titles.deleteButtonTitle, role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text(^String.Titles.dataManagementDeleteConfirmationMessage)
        }
        .alert(resultMessage ?? "", isPresented: $showResult) {
            Button("OK") {
                if resultMessage?.contains("удалены") == true {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showOrphanedTimelinesSheet) {
            if !orphanedTimelines.isEmpty {
                OrphanedTimelinesRecoveryView(
                    orphanedTimelines: $orphanedTimelines,
                    onComplete: {
                        showOrphanedTimelinesSheet = false
                        orphanedTimelines = []
                    }
                )
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 60))
                    
                    Text(^String.Titles.dataManagementNoOrphanedTimelines)
                        .font(.system(size: 18, weight: .semibold))
                    
                    Text(^String.Titles.dataManagementAllTimelinesLinked)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Button(^String.Titles.closeButtonTitle) {
                        showOrphanedTimelinesSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(40)
                .frame(width: 400, height: 300)
            }
        }
    }
    
    // MARK: - Actions
    
    private func createBackup() {
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            DataSyncManager.shared.backupToApplicationSupport()
            
            DispatchQueue.main.async {
                isProcessing = false
                resultMessage = ^String.Titles.dataManagementBackupCreatedSuccess
                showResult = true
            }
        }
    }
    
    private func restoreFromBackup() {
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            DataSyncManager.shared.restoreFromBackup()
            
            DispatchQueue.main.async {
                isProcessing = false
                resultMessage = ^String.Titles.dataManagementRestoreSuccess
                showResult = true
            }
        }
    }
    
    private func checkOrphanedTimelines() {
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let orphaned = DataSyncManager.shared.detectOrphanedTimelines()
            
            DispatchQueue.main.async {
                isProcessing = false
                orphanedTimelines = orphaned
                showOrphanedTimelinesSheet = true
            }
        }
    }
    
    private func deleteAllData() {
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            DataSyncManager.shared.deleteAllUserData()
            DataSyncManager.shared.deleteAllTimelinesFromBackup()
            
            DispatchQueue.main.async {
                isProcessing = false
                resultMessage = ^String.Titles.dataManagementDeleteSuccess
                showResult = true
            }
        }
    }
    
    // MARK: - Open Folders
    
    private func openDocumentsFolder() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appDocumentsURL = documentsURL.appendingPathComponent("YouChip-Stat", isDirectory: true)
        
        if !fileManager.fileExists(atPath: appDocumentsURL.path) {
            try? fileManager.createDirectory(at: appDocumentsURL, withIntermediateDirectories: true)
        }
        
        NSWorkspace.shared.open(appDocumentsURL)
    }
    
    private func openApplicationSupportFolder() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let backupURL = appSupportURL.appendingPathComponent("YouChip-Stat-Backup", isDirectory: true)
        
        if !fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)
        }
        
        NSWorkspace.shared.open(backupURL)
    }
}

#Preview {
    DataManagementSheet()
}
