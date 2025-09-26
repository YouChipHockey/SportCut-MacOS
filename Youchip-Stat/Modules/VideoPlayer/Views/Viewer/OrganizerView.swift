//
//  OrganizerView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVFoundation

struct OrganizerView: View {
    @ObservedObject var playlistManager: PlaylistManager
    @ObservedObject var videoPlaylistManager: VideoPlaylistManager
    @State private var draggedItem: OrganizerTag?
    @State private var showSavePlaylistSheet = false
    @State private var showPlaylistMenu = false
    @State private var isExporting = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Плейлисты")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Playlist selector
                Menu {
                    // Current playlist (if unsaved)
                    if playlistManager.currentPlaylist == nil && !playlistManager.currentTags.isEmpty {
                        Button(action: {
                            showPlaylistMenu = false
                        }) {
                            HStack {
                                Text("Текущий (не сохранен)")
                                    .foregroundColor(.orange)
                                Spacer()
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    // Saved playlists
                    ForEach(playlistManager.playlists) { playlist in
                        Button(action: {
                            playlistManager.loadPlaylist(playlist)
                            showPlaylistMenu = false
                        }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .foregroundColor(.primary)
                                Text("\(playlist.tagCount) тегов • \(formatDuration(playlist.duration))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if !playlistManager.playlists.isEmpty {
                        Divider()
                    }
                    
                    Button("Новый плейлист") {
                        playlistManager.createNewPlaylist()
                        showPlaylistMenu = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(playlistManager.currentPlaylist?.name ?? "Новый плейлист")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Выбрать плейлист")
                
                // Save button
                if playlistManager.currentPlaylist == nil && !playlistManager.currentTags.isEmpty {
                    Button(action: {
                        showSavePlaylistSheet = true
                    }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Сохранить плейлист")
                }
                
                // Clear button
                        Button(action: {
                            playlistManager.clear()
                            videoPlaylistManager.stopPlayback()
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Очистить плейлист")
                        
                        // Export button
                        if !playlistManager.currentTags.isEmpty {
                            Menu {
                                Button("Экспорт как архив") {
                                    exportPlaylist(mode: .archive)
                                }
                                
                                Button("Экспорт как фильм") {
                                    exportPlaylist(mode: .film)
                                }
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Экспортировать плейлист")
                        }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Playlist controls
            if !playlistManager.currentTags.isEmpty {
                HStack(spacing: 8) {
                    Button(action: {
                        videoPlaylistManager.setPlaylist(playlistManager.currentTags)
                        videoPlaylistManager.playPlaylist()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: videoPlaylistManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text(videoPlaylistManager.isPlaying ? "Пауза" : "Воспроизвести")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(playlistManager.currentTags.count) тегов")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if playlistManager.currentPlaylist == nil {
                            Text("Не сохранен")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            
            Divider()
            
            // Tags list
            if playlistManager.currentTags.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    
                    Text("Плейлист пуст")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("Перетащите теги с таймлайна\nили используйте ПКМ")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(playlistManager.currentTags) { tag in
                        OrganizerTagRow(
                            tag: tag,
                            onPlay: {
                                videoPlaylistManager.playSingleTag(tag)
                            },
                            onRemove: {
                                if let index = playlistManager.currentTags.firstIndex(where: { $0.id == tag.id }) {
                                    playlistManager.removeTag(at: index)
                                    videoPlaylistManager.stopPlayback()
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowBackground(Color.clear)
                    }
                    .onMove(perform: playlistManager.moveTag)
                    .onDelete { indexSet in
                        for index in indexSet {
                            playlistManager.removeTag(at: index)
                        }
                        videoPlaylistManager.stopPlayback()
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .sheet(isPresented: $showSavePlaylistSheet) {
            SavePlaylistSheet(playlistManager: playlistManager)
        }
        .overlay(
            Group {
                if isExporting {
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("Экспорт...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                }
            }
        )
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    // MARK: - Export Functions
    private func exportPlaylist(mode: ViewerExportMode) {
        guard let asset = VideoPlayerManager.shared.player?.currentItem?.asset else {
            print("Asset not found")
            return
        }
        
        let segments = getSegmentsForExport()
        if segments.isEmpty {
            print("Нет сегментов для экспорта")
            return
        }
        
        isExporting = true
        
        if mode == .film {
            exportFilm(segments: segments, asset: asset) { result in
                DispatchQueue.main.async {
                    self.isExporting = false
                    
                    switch result {
                    case .success(let outputURL):
                        let panel = NSSavePanel()
                        panel.allowedFileTypes = ["mp4"]
                        panel.nameFieldStringValue = outputURL.lastPathComponent
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                try FileManager.default.copyItem(at: outputURL, to: url)
                                print("Фильм экспортирован: \(url)")
                            } catch {
                                print("Ошибка сохранения фильма: \(error)")
                            }
                        }
                    case .failure(let error):
                        print("Ошибка экспорта фильма: \(error)")
                    }
                }
            }
        } else {
            exportPlaylistArchive(segments: segments, asset: asset) { result in
                DispatchQueue.main.async {
                    self.isExporting = false
                    
                    switch result {
                    case .success(let zipURL):
                        let panel = NSSavePanel()
                        panel.allowedFileTypes = ["zip"]
                        panel.nameFieldStringValue = "playlist_export.zip"
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                try FileManager.default.copyItem(at: zipURL, to: url)
                                print("Архив экспортирован: \(url)")
                            } catch {
                                print("Ошибка сохранения архива: \(error)")
                            }
                        }
                    case .failure(let error):
                        print("Ошибка экспорта архива: \(error)")
                    }
                }
            }
        }
    }
    
    private func getSegmentsForExport() -> [ExportSegment] {
        var result: [ExportSegment] = []
        let tagLibrary = TagLibraryManager.shared
        
        // Получаем максимальное время видео
        let maxVideoDuration = max(1.0, VideoPlayerManager.shared.videoDuration)
        
        for tag in playlistManager.currentTags {
            guard let correctedTime = correctTimeRange(
                startSeconds: tag.startTime,
                durationSeconds: tag.duration,
                maxVideoDuration: maxVideoDuration
            ) else {
                continue
            }
            
            let start = CMTime(seconds: correctedTime.start, preferredTimescale: 600)
            let duration = CMTime(seconds: correctedTime.duration, preferredTimescale: 600)
            let possibleGroup = tagLibrary.allTagGroups.first(where: { $0.tags.contains(tag.stampID.uuidString) })
            
            result.append(
                ExportSegment(
                    timeRange: CMTimeRange(start: start, duration: duration),
                    lineName: tag.lineName,
                    tagName: tag.tagName,
                    groupName: possibleGroup?.name
                )
            )
        }
        
        return result
    }
    
    private func correctTimeRange(startSeconds: Double, durationSeconds: Double, maxVideoDuration: Double) -> (start: Double, duration: Double)? {
        var correctedStart = startSeconds
        var correctedDuration = durationSeconds
        
        // Корректируем время: начало не может быть меньше 0
        if correctedStart < 0 {
            correctedStart = 0
        }
        
        // Корректируем время: конец не может быть больше максимального времени видео
        let endSeconds = correctedStart + correctedDuration
        if endSeconds > maxVideoDuration {
            let newDuration = maxVideoDuration - correctedStart
            if newDuration > 0 {
                correctedDuration = newDuration
            } else {
                return nil // Сегмент полностью за пределами видео
            }
        }
        
        // Проверяем, что после корректировки у нас есть валидная длительность
        guard correctedDuration > 0 else {
            return nil
        }
        
        return (correctedStart, correctedDuration)
    }
    
    private func exportFilm(segments: [ExportSegment], asset: AVAsset, completion: @escaping (Result<URL, Error>) -> Void) {
        let composition = AVMutableComposition()
        
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(NSError(domain: "Export", code: 0, userInfo: [NSLocalizedDescriptionKey: "Video track not found"])))
            return
        }
        let audioTrack = asset.tracks(withMediaType: .audio).first
        
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(.failure(NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create video track"])))
            return
        }
        var compAudioTrack: AVMutableCompositionTrack? = nil
        if audioTrack != nil {
            compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        
        var currentTime = CMTime.zero
        for segment in segments {
            do {
                try compVideoTrack.insertTimeRange(segment.timeRange, of: videoTrack, at: currentTime)
                if let compAudio = compAudioTrack, let aTrack = audioTrack {
                    try compAudio.insertTimeRange(segment.timeRange, of: aTrack, at: currentTime)
                }
                currentTime = currentTime + segment.timeRange.duration
            } catch {
                completion(.failure(error))
                return
            }
        }
        
        let fileName = "playlist_film.mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: outputURL)
        
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        exportSession?.outputURL = outputURL
        exportSession?.outputFileType = .mp4
        exportSession?.exportAsynchronously {
            if exportSession?.status == .completed {
                completion(.success(outputURL))
            } else {
                completion(.failure(exportSession?.error ?? NSError(domain: "Export", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown export error"])))
            }
        }
    }
    
    private func exportPlaylistArchive(segments: [ExportSegment], asset: AVAsset, completion: @escaping (Result<URL, Error>) -> Void) {
        print("🎬 Starting playlist archive export with \(segments.count) segments")
        
        // Проверяем, что есть сегменты для экспорта
        if segments.isEmpty {
            print("❌ No segments to export")
            completion(.failure(NSError(domain: "Export", code: -1, userInfo: [NSLocalizedDescriptionKey: "No segments to export"])))
            return
        }
        
        print("📊 Exporting \(segments.count) segments")
        
        var exportedURLs: [URL] = []
        let group = DispatchGroup()
        var exportError: Error? = nil
        
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(NSError(domain: "Export", code: 0, userInfo: [NSLocalizedDescriptionKey: "Video track not found"])))
            return
        }
        let audioTrack = asset.tracks(withMediaType: .audio).first
        
        for (index, segment) in segments.enumerated() {
            group.enter()
            
            print("🎬 Processing segment \(index + 1)/\(segments.count): \(segment.lineName) - \(segment.tagName)")
            print("   Time range: \(segment.timeRange.start.seconds)s to \(segment.timeRange.start.seconds + segment.timeRange.duration.seconds)s")
            
            let composition = AVMutableComposition()
            guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video,
                                                                   preferredTrackID: kCMPersistentTrackID_Invalid)
            else {
                print("❌ Failed to create video track for segment \(index + 1)")
                exportError = NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create video track"])
                group.leave()
                continue
            }
            var compAudioTrack: AVMutableCompositionTrack? = nil
            if let aTrack = audioTrack {
                compAudioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid)
                do {
                    print("   🎵 Inserting audio time range: \(segment.timeRange.start.seconds)s to \(segment.timeRange.start.seconds + segment.timeRange.duration.seconds)s")
                    try compAudioTrack?.insertTimeRange(segment.timeRange, of: aTrack, at: .zero)
                    print("   ✅ Audio track inserted successfully")
                } catch {
                    print("   ❌ Failed to insert audio time range: \(error.localizedDescription)")
                    exportError = error
                    group.leave()
                    continue
                }
            }
            
            do {
                print("   📹 Inserting video time range: \(segment.timeRange.start.seconds)s to \(segment.timeRange.start.seconds + segment.timeRange.duration.seconds)s")
                try compVideoTrack.insertTimeRange(segment.timeRange, of: videoTrack, at: .zero)
                print("   ✅ Video track inserted successfully")
            } catch {
                print("   ❌ Failed to insert video time range: \(error.localizedDescription)")
                exportError = error
                group.leave()
                continue
            }
            
            let fileName = "\(segment.lineName)_\(segment.tagName)_\(index + 1).mp4"
            let clipOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: clipOutputURL)
            
            let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
            exportSession?.outputURL = clipOutputURL
            exportSession?.outputFileType = .mp4
            
            exportSession?.exportAsynchronously {
                if exportSession?.status == .completed {
                    print("   ✅ Export completed for segment \(index + 1): \(fileName)")
                    exportedURLs.append(clipOutputURL)
                } else {
                    print("   ❌ Export failed for segment \(index + 1): \(exportSession?.error?.localizedDescription ?? "Unknown error")")
                    exportError = exportSession?.error ?? NSError(domain: "Export", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown export error"])
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            print("🏁 All export tasks completed")
            print("   Exported URLs count: \(exportedURLs.count)")
            print("   Export error: \(exportError?.localizedDescription ?? "None")")
            
            if let error = exportError {
                print("❌ Export failed with error: \(error)")
                completion(.failure(error))
            } else {
                print("✅ All segments exported successfully, compressing files...")
                compressFiles(urls: exportedURLs, completion: completion)
            }
        }
    }
    
    private func compressFiles(urls: [URL], completion: @escaping (Result<URL, Error>) -> Void) {
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("playlist_export.zip")
        try? FileManager.default.removeItem(at: zipURL)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        
        var arguments = ["-j", zipURL.path]
        for fileURL in urls {
            arguments.append(fileURL.path)
        }
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                completion(.success(zipURL))
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: data, encoding: .utf8) ?? "Неизвестная ошибка"
                let error = NSError(domain: "ZIPError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMessage])
                completion(.failure(error))
            }
        } catch {
            completion(.failure(error))
        }
    }
}

// MARK: - Save Playlist Sheet
struct SavePlaylistSheet: View {
    @ObservedObject var playlistManager: PlaylistManager
    @Environment(\.presentationMode) var presentationMode
    @State private var playlistName = ""
    @State private var showingAlert = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Сохранить плейлист")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Название плейлиста")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("Введите название", text: $playlistName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        savePlaylist()
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Информация о плейлисте:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text("Тегов:")
                        .foregroundColor(.secondary)
                    Text("\(playlistManager.currentTags.count)")
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Длительность:")
                        .foregroundColor(.secondary)
                    Text(formatDuration(playlistManager.currentTags.reduce(0) { $0 + $1.duration }))
                        .fontWeight(.medium)
                }
            }
            .padding()
            .cornerRadius(8)
            
            HStack(spacing: 12) {
                Button("Отмена") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button("Сохранить") {
                    savePlaylist()
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
                .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 300)
        .alert("Ошибка", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text("Плейлист с таким названием уже существует")
        }
    }
    
    private func savePlaylist() {
        let trimmedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        // Проверяем, не существует ли уже плейлист с таким именем
        if playlistManager.playlists.contains(where: { $0.name == trimmedName }) {
            showingAlert = true
            return
        }
        
        playlistManager.saveCurrentPlaylist(name: trimmedName)
        presentationMode.wrappedValue.dismiss()
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct OrganizerTagRow: View {
    let tag: OrganizerTag
    let onPlay: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Color indicator
            Circle()
                .fill(Color(hex: tag.color) ?? .gray)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.tagName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                Text(tag.lineName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(formatTime(tag.startTime))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 4) {
                Button(action: onPlay) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Воспроизвести тег")
                
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Удалить из органайзера")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

