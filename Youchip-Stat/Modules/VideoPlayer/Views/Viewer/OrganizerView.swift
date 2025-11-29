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
    @State private var showDeleteAlert = false
    @State private var playlistToDelete: SavedPlaylist?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            playlistControlsView
            Divider()
            tagsListView
        }
        .sheet(isPresented: $showSavePlaylistSheet) {
            SavePlaylistSheet(playlistManager: playlistManager)
        }
        .alert(^String.Titles.deletePlaylistQuestion, isPresented: $showDeleteAlert) {
            Button(^String.Titles.cancelButtonTitle, role: .cancel) {
                playlistToDelete = nil
            }
            Button(^String.Titles.deleteButtonTitle, role: .destructive) {
                if let playlist = playlistToDelete {
                    playlistManager.deletePlaylist(playlist)
                    playlistToDelete = nil
                }
            }
        } message: {
            if let playlist = playlistToDelete {
                Text(String(format: ^String.Titles.confirmDeletePlaylist, playlist.name))
            }
        }
        .overlay(exportOverlayView)
    }
    
    private var headerView: some View {
        HStack {
            Text(^String.Titles.playlists)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            playlistSelectorMenu
            saveButton
            clearButton
            exportButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var playlistSelectorMenu: some View {
        Menu {
            if playlistManager.currentPlaylist == nil && !playlistManager.currentTags.isEmpty {
                Button(action: {
                    showPlaylistMenu = false
                }) {
                    HStack {
                        Text(^String.Titles.currentUnsaved)
                            .foregroundColor(.orange)
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    }
                }
            }
            
            ForEach(playlistManager.playlists) { playlist in
                Menu {
                    Button(^String.Titles.load) {
                        playlistManager.loadPlaylist(playlist)
                        showPlaylistMenu = false
                    }
                    
                    Divider()
                    
                    Button(^String.Titles.deleteButtonTitle, role: .destructive) {
                        playlistToDelete = playlist
                        showDeleteAlert = true
                        showPlaylistMenu = false
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.name)
                            .foregroundColor(.primary)
                        Text("\(playlist.tagCount) \(^String.Titles.tagsCountNew) • \(formatDuration(playlist.duration))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if !playlistManager.playlists.isEmpty {
                Divider()
            }
            
            Button(^String.Titles.newPlaylist) {
                playlistManager.createNewPlaylist()
                showPlaylistMenu = false
            }
        } label: {
            HStack(spacing: 4) {
                Text(playlistManager.currentPlaylist?.name ?? ^String.Titles.newPlaylist)
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
        .help(^String.Titles.selectPlaylist)
    }
    
    @ViewBuilder
    private var saveButton: some View {
        if (!playlistManager.currentTags.isEmpty && playlistManager.currentPlaylist == nil) || playlistManager.isPlaylistModified {
            Button(action: {
                if playlistManager.currentPlaylist != nil {
                    playlistManager.updateCurrentPlaylist()
                } else {
                    showSavePlaylistSheet = true
                }
            }) {
                Image(systemName: playlistManager.currentPlaylist != nil ? "arrow.down.circle" : "plus.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            }
            .buttonStyle(PlainButtonStyle())
            .help(playlistManager.currentPlaylist != nil ? ^String.Titles.collectionsButtonSaveChanges : ^String.Titles.savePlaylist)
        }
    }
    
    private var clearButton: some View {
        Button(action: {
            playlistManager.clear()
        }) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.red)
        }
        .buttonStyle(PlainButtonStyle())
        .help(^String.Titles.clearPlaylist)
    }
    
    @ViewBuilder
    private var exportButton: some View {
        if !playlistManager.currentTags.isEmpty {
            Menu {
                Button(^String.Titles.exportAsArchive) {
                    exportPlaylist(mode: .archive)
                }
                
                Button(^String.Titles.exportAsFilm) {
                    exportPlaylist(mode: .film)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .help(^String.Titles.exportPlaylist)
        }
    }
    
    @ViewBuilder
    private var playlistControlsView: some View {
        if !playlistManager.currentTags.isEmpty {
            HStack(spacing: 8) {
                Button(action: {
                    videoPlaylistManager.setPlaylist(playlistManager.currentTags)
                    videoPlaylistManager.playPlaylist()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: videoPlaylistManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                        Text(videoPlaylistManager.isPlaying ? ^String.Titles.pause : ^String.Titles.play)
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
                    Text("\(playlistManager.currentTags.count) \(^String.Titles.tagsCountNew)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if playlistManager.currentPlaylist == nil {
                        Text(^String.Titles.unsaved)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
    
    private var tagsListView: some View {
        Group {
            if playlistManager.currentTags.isEmpty {
                emptyPlaylistView
            } else {
                tagsListContent
            }
        }
    }
    
    private var emptyPlaylistView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.gray)
            
            Text(^String.Titles.playlistEmpty)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(^String.Titles.dragTagsFromTimeline)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.05))
        .onDrop(of: ["public.data", "com.youchip.organizerTag"], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }
    
    private var tagsListContent: some View {
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
        .background(Color.clear)
        .onDrop(of: ["public.data", "com.youchip.organizerTag"], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }
    
    @ViewBuilder
    private var exportOverlayView: some View {
        if isExporting {
            VStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                Text(^String.Titles.exporting)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(8)
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("com.youchip.organizerTags") {
                provider.loadDataRepresentation(forTypeIdentifier: "com.youchip.organizerTags") { data, error in
                    if let error = error {
                        return
                    }
                    
                    if let data = data,
                       let tags = try? JSONDecoder().decode([OrganizerTag].self, from: data) {
                        DispatchQueue.main.async {
                            for tag in tags {
                                self.playlistManager.addTag(tag)
                            }
                        }
                    }
                }
            }
            else if provider.hasItemConformingToTypeIdentifier("com.youchip.organizerTag") {
                provider.loadDataRepresentation(forTypeIdentifier: "com.youchip.organizerTag") { data, error in
                    if let error = error {
                        return
                    }
                    
                    if let data = data,
                       let tag = try? JSONDecoder().decode(OrganizerTag.self, from: data) {
                        DispatchQueue.main.async {
                            self.playlistManager.addTag(tag)
                        }
                    }
                }
            }
            else if provider.hasItemConformingToTypeIdentifier("public.data") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.data") { data, error in
                    if let error = error {
                        return
                    }
                    
                    if let data = data {
                        if let tags = try? JSONDecoder().decode([OrganizerTag].self, from: data) {
                            DispatchQueue.main.async {
                                for tag in tags {
                                    self.playlistManager.addTag(tag)
                                }
                            }
                        }
                        else if let tag = try? JSONDecoder().decode(OrganizerTag.self, from: data) {
                            DispatchQueue.main.async {
                                self.playlistManager.addTag(tag)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    private func exportPlaylist(mode: ViewerExportMode) {
        guard let asset = VideoPlayerManager.shared.player?.currentItem?.asset else {
            return
        }
        
        let segments = getSegmentsForExport()
        if segments.isEmpty {
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
                            } catch {
                                print(error.localizedDescription)
                            }
                        }
                    case .failure(let error):
                        print(error.localizedDescription)
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
                            } catch {
                                print(error.localizedDescription)
                            }
                        }
                    case .failure(let error):
                        print(error.localizedDescription)
                    }
                }
            }
        }
    }
    
    private func getSegmentsForExport() -> [ExportSegmentOrganaizer] {
        var result: [ExportSegmentOrganaizer] = []
        let tagLibrary = TagLibraryManager.shared
        
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
            
            let labels = tag.labelIDs.compactMap { labelID in
                tagLibrary.findLabelById(labelID)
            }
            
            result.append(
                ExportSegmentOrganaizer(
                    timeRange: CMTimeRange(start: start, duration: duration),
                    tagName: tag.tagName,
                    groupName: tag.tagGroupName ?? "",
                    labels: labels.isEmpty ? [] : labels,
                )
            )
        }
        
        return result
    }
    
    private func correctTimeRange(startSeconds: Double, durationSeconds: Double, maxVideoDuration: Double) -> (start: Double, duration: Double)? {
        var correctedStart = startSeconds
        var correctedDuration = durationSeconds
        
        if correctedStart < 0 {
            correctedStart = 0
        }
        
        let endSeconds = correctedStart + correctedDuration
        if endSeconds > maxVideoDuration {
            let newDuration = maxVideoDuration - correctedStart
            if newDuration > 0 {
                correctedDuration = newDuration
            } else {
                return nil
            }
        }
        
        guard correctedDuration > 0 else {
            return nil
        }
        
        return (correctedStart, correctedDuration)
    }
    
    private func exportFilm(segments: [ExportSegmentOrganaizer], asset: AVAsset, completion: @escaping (Result<URL, Error>) -> Void) {
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
    
    private func exportPlaylistArchive(segments: [ExportSegmentOrganaizer], asset: AVAsset, completion: @escaping (Result<URL, Error>) -> Void) {
        if segments.isEmpty {
            completion(.failure(NSError(domain: "Export", code: -1, userInfo: [NSLocalizedDescriptionKey: "No segments to export"])))
            return
        }
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
            

            let composition = AVMutableComposition()
            guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video,
                                                                   preferredTrackID: kCMPersistentTrackID_Invalid)
            else {
                exportError = NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create video track"])
                group.leave()
                continue
            }
            var compAudioTrack: AVMutableCompositionTrack? = nil
            if let aTrack = audioTrack {
                compAudioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid)
                do {
                    try compAudioTrack?.insertTimeRange(segment.timeRange, of: aTrack, at: .zero)
                } catch {
                    exportError = error
                    group.leave()
                    continue
                }
            }
            
            do {
                try compVideoTrack.insertTimeRange(segment.timeRange, of: videoTrack, at: .zero)
            } catch {
                exportError = error
                group.leave()
                continue
            }
            
            let fileName: String
            var nameParts: [String] = []
            
            nameParts.append(segment.tagName)
            
            if !segment.groupName.isEmpty {
                nameParts.append(segment.groupName)
            }
            
            if !segment.labels.isEmpty {
                for label in segment.labels {
                    nameParts.append(label.name)
                }
            }
            
            fileName = "\(nameParts.joined(separator: "_")).mp4"
            let clipOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: clipOutputURL)
            
            let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
            exportSession?.outputURL = clipOutputURL
            exportSession?.outputFileType = .mp4
            
            exportSession?.exportAsynchronously {
                if exportSession?.status == .completed {
                    exportedURLs.append(clipOutputURL)
                } else {
                    exportError = exportSession?.error ?? NSError(domain: "Export", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown export error"])
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if let error = exportError {
                completion(.failure(error))
            } else {
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
                let errorMessage = String(data: data, encoding: .utf8) ?? ^String.Titles.unknownError
                let error = NSError(domain: "ZIPError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMessage])
                completion(.failure(error))
            }
        } catch {
            completion(.failure(error))
        }
    }
    
}

struct SavePlaylistSheet: View {
    @ObservedObject var playlistManager: PlaylistManager
    @Environment(\.presentationMode) var presentationMode
    @State private var playlistName = ""
    @State private var showingAlert = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text(^String.Titles.savePlaylistTitle)
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.playlistName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField(^String.Titles.enterName, text: $playlistName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        savePlaylist()
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(^String.Titles.playlistInfo)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text(^String.Titles.tags)
                        .foregroundColor(.secondary)
                    Text("\(playlistManager.currentTags.count)")
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text(^String.Titles.duration)
                        .foregroundColor(.secondary)
                    Text(formatDuration(playlistManager.currentTags.reduce(0) { $0 + $1.duration }))
                        .fontWeight(.medium)
                }
            }
            .padding()
            .cornerRadius(8)
            
            HStack(spacing: 12) {
                Button(^String.Titles.cancel) {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(^String.Titles.save) {
                    savePlaylist()
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
                .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 300)
        .alert(^String.Titles.error, isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(^String.Titles.playlistAlreadyExists)
        }
    }
    
    private func savePlaylist() {
        let trimmedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
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
    
    private var labels: [Label] {
        tag.labelIDs.compactMap { labelID in
            TagLibraryManager.shared.findLabelById(labelID)
        }
    }
    
    private var events: [TimeEvent] {
        tag.eventIDs.compactMap { eventID in
            TagLibraryManager.shared.allTimeEvents.first { $0.id == eventID }
        }
    }
    
    private var tagTitle: String {
        if let groupName = tag.tagGroupName {
            return "\(tag.tagName) (\(groupName))"
        } else {
            return tag.tagName
        }
    }
    
    private var labelsText: String {
        if labels.isEmpty {
            return ^String.Titles.labelsNone
        } else {
            let labelNames = labels.map { $0.name }.joined(separator: ", ")
            return String(format: ^String.Titles.labelsPrefix, labelNames)
        }
    }
    
    private var eventsText: String {
        if events.isEmpty {
            return ^String.Titles.eventsNone
        } else {
            let eventNames = events.map { $0.name }.joined(separator: ", ")
            return String(format: ^String.Titles.eventsPrefix, eventNames)
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: tag.color) ?? .gray)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tagTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                Text(labelsText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(eventsText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text(String(format: ^String.Titles.timeAndMoment, formatTime(tag.duration), formatTime(tag.startTime)))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Button(action: onPlay) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help(^String.Titles.playTag)
                
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                .help(^String.Titles.removeFromOrganizer)
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

