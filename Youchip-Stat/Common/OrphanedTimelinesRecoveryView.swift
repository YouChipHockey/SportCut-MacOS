//
//  OrphanedTimelinesRecoveryView.swift
//  Youchip-Stat
//
//  Created on 10.02.2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct OrphanedTimelinesRecoveryView: View {
    
    @Binding var orphanedTimelines: [DataSyncManager.OrphanedTimeline]
    let onComplete: () -> Void
    
    @State private var selectedVideoURLs: [String: URL] = [:]
    @State private var isProcessing = false
    @State private var processedCount = 0
    @State private var showSuccess = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 28))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(^String.Titles.orphanedTimelinesTitle)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text(String.Titles.orphanedTimelinesFound.format(orphanedTimelines.count))
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                Text(^String.Titles.orphanedTimelinesInstructions)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // List of orphaned timelines
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(orphanedTimelines, id: \.videoId) { orphaned in
                        OrphanedTimelineRow(
                            orphaned: orphaned,
                            selectedURL: Binding(
                                get: { selectedVideoURLs[orphaned.videoId] },
                                set: { selectedVideoURLs[orphaned.videoId] = $0 }
                            ),
                            onDelete: {
                                deleteTimeline(orphaned)
                            }
                        )
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            HStack(spacing: 12) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(String.Titles.orphanedTimelinesRestoring.format(processedCount, orphanedTimelines.count))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                } else {
                    Spacer()
                    
                    Button(^String.Titles.orphanedTimelinesSkipAll) {
                        dismiss()
                        onComplete()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.secondary)
                    
                    Button(^String.Titles.orphanedTimelinesRestoreSelected) {
                        restoreSelectedTimelines()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedVideoURLs.isEmpty)
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 700, height: 600)
        .background(Color(NSColor.controlBackgroundColor))
        .alert(^String.Titles.orphanedTimelinesRestoreSuccess, isPresented: $showSuccess) {
            Button(^String.Titles.alertsOkTitle) {
                dismiss()
                onComplete()
            }
        } message: {
            Text(String.Titles.orphanedTimelinesRestoreSuccessMessage.format(processedCount))
        }
    }
    
    // MARK: - Actions
    
    private func restoreSelectedTimelines() {
        isProcessing = true
        processedCount = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            for (videoId, videoURL) in selectedVideoURLs {
                guard let orphaned = orphanedTimelines.first(where: { $0.videoId == videoId }) else {
                    continue
                }
                
                guard let bookmark = videoURL.makeBookmark() else {
                    print("❌ Failed to create bookmark for \(videoURL.lastPathComponent)")
                    continue
                }
                
                // Check if video already exists in VideoFilesManager
                let existingFile = VideoFilesManager.shared.files.first { file in
                    do {
                        var isStale = false
                        let fileURL = try URL(resolvingBookmarkData: file.videoData.bookmark,
                                            options: .withSecurityScope,
                                            relativeTo: nil,
                                            bookmarkDataIsStale: &isStale)
                        return fileURL == videoURL
                    } catch {
                        return false
                    }
                }
                
                let newVideoId: String
                if let existing = existingFile {
                    // Use existing video ID
                    newVideoId = existing.videoData.id
                    print("📹 Using existing video ID: \(newVideoId)")
                } else {
                    // Import file first to create entry and get ID
                    if let importedFile = VideoFilesManager.shared.importFile(url: videoURL) {
                        newVideoId = importedFile.videoData.id
                        print("📹 Created new video entry with ID: \(newVideoId)")
                    } else {
                        print("❌ Failed to import video file")
                        continue
                    }
                }
                
                if DataSyncManager.shared.restoreTimelineToVideo(
                    orphanedTimeline: orphaned,
                    newVideoBookmark: bookmark,
                    newVideoId: newVideoId
                ) {
                    DispatchQueue.main.async {
                        processedCount += 1
                    }
                } else {
                    print("❌ Failed to restore timeline for video \(videoURL.lastPathComponent)")
                }
            }
            
            DispatchQueue.main.async {
                isProcessing = false
                showSuccess = processedCount > 0
                
                VideoFilesManager.shared.refreshFiles()
                updateOrphanedTimelinesList()
            }
        }
    }
    
    private func deleteTimeline(_ orphaned: DataSyncManager.OrphanedTimeline) {
        DataSyncManager.shared.deleteOrphanedTimeline(orphaned)
        orphanedTimelines.removeAll { $0.videoId == orphaned.videoId }
        selectedVideoURLs.removeValue(forKey: orphaned.videoId)
        
        if orphanedTimelines.isEmpty {
            dismiss()
            onComplete()
        }
    }
    
    private func updateOrphanedTimelinesList() {
        let remaining = orphanedTimelines.filter { orphaned in
            !selectedVideoURLs.keys.contains(orphaned.videoId)
        }
        orphanedTimelines = remaining
        selectedVideoURLs.removeAll()
    }
}

// MARK: - Orphaned Timeline Row

struct OrphanedTimelineRow: View {
    
    let orphaned: DataSyncManager.OrphanedTimeline
    @Binding var selectedURL: URL?
    let onDelete: () -> Void
    
    @State private var showFilePicker = false
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            timelineInfoView
            HStack(spacing: 12) {
                selectVideoButton
                deleteButton
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(overlayBorder)
        .alert(^String.Titles.orphanedTimelinesDeleteConfirmationTitle, isPresented: $showDeleteConfirmation) {
            Button(^String.Titles.cancelButtonTitle, role: .cancel) {}
            Button(^String.Titles.deleteButtonTitle, role: .destructive) {
                onDelete()
            }
        } message: {
            Text(^String.Titles.orphanedTimelinesDeleteConfirmationMessage)
        }
    }
    
    // MARK: - Subviews
    
    private var timelineInfoView: some View {
        HStack(spacing: 12) {
            filmIcon
            timelineDetails
            Spacer()
            selectedVideoStatus
        }
    }
    
    private var filmIcon: some View {
        Image(systemName: "film.fill")
            .foregroundColor(.blue)
            .font(.system(size: 24))
            .frame(width: 40, height: 40)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
    }
    
    private var timelineDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(videoDisplayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            
            timelineStats
        }
    }
    
    private var videoDisplayName: String {
        orphaned.customName ?? orphaned.videoName ?? ^String.Titles.orphanedTimelinesUnknownVideo
    }
    
    private var timelineStats: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12))
                Text(timelinesCountText)
                    .font(.system(size: 12))
            }
            .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 12))
                Text(stampsCountText)
                    .font(.system(size: 12))
            }
            .foregroundColor(.secondary)
            
            Text(String.Titles.orphanedTimelinesSaved.format(formattedDate))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    
    private var timelinesCountText: String {
        let count = orphaned.timelines.count
        if count == 1 {
            return ^String.Titles.orphanedTimelinesTimelineSingular
        } else if count >= 2 && count <= 4 {
            return String.Titles.orphanedTimelinesTimelinePlural24.format(count)
        } else {
            return String.Titles.orphanedTimelinesTimelinePlural5Plus.format(count)
        }
    }
    
    private var stampsCountText: String {
        let count = totalStamps
        if count == 1 {
            return ^String.Titles.orphanedTimelinesStampsSingular
        } else if count >= 2 && count <= 4 {
            return String.Titles.orphanedTimelinesStampsPlural24.format(count)
        } else {
            return String.Titles.orphanedTimelinesStampsPlural5Plus.format(count)
        }
    }
    
    @ViewBuilder
    private var selectedVideoStatus: some View {
        if let url = selectedURL {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(url.lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 150)
            }
        }
    }
    
    private var selectVideoButton: some View {
        Button(action: {
            showFilePicker = true
        }) {
            buttonContent
        }
        .buttonStyle(PlainButtonStyle())
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            handleFilePickerResult(result)
        }
    }
    
    private var buttonContent: some View {
        HStack {
            Image(systemName: buttonIconName)
                .font(.system(size: 14))
            Text(buttonTitle)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(buttonGradient)
        .cornerRadius(6)
    }
    
    private var buttonIconName: String {
        selectedURL == nil ? "folder.badge.plus" : "arrow.triangle.2.circlepath"
    }
    
    private var buttonTitle: String {
        selectedURL == nil ? ^String.Titles.orphanedTimelinesSelectVideo : ^String.Titles.orphanedTimelinesChangeVideo
    }
    
    private var buttonGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var overlayBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(borderColor, lineWidth: 2)
    }
    
    private var borderColor: Color {
        selectedURL != nil ? Color.blue.opacity(0.3) : Color.clear
    }
    
    // MARK: - Helpers
    
    private var deleteButton: some View {
        Button(action: {
            showDeleteConfirmation = true
        }) {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                Text(^String.Titles.orphanedTimelinesDelete)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help(^String.Titles.orphanedTimelinesDeleteHelp)
    }
    
    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedURL = url
            }
        case .failure(let error):
            print("Ошибка выбора файла: \(error.localizedDescription)")
        }
    }
    
    private var totalStamps: Int {
        orphaned.timelines.reduce(0) { $0 + $1.stamps.count }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: orphaned.backupDate)
    }
}

#Preview {
    OrphanedTimelinesRecoveryView(
        orphanedTimelines: .constant([]),
        onComplete: {}
    )
}
