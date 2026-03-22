//
//  SportCutExportSheet.swift
//  Youchip-Stat
//

import SwiftUI
import AVFoundation

struct SportCutExportSheet: View {
    let sessionID: UUID
    @ObservedObject var playerManager: SportCutPlayerManager
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var exportType: SportCutExportType = .clips
    @State private var selectedPlaylistIDs: Set<UUID> = []
    @State private var addWatermark = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    
    private var session: SportCutSession? {
        sessionManager.sessions.first { $0.id == sessionID }
    }
    
    private var allPlaylists: [SportCutPlaylist] {
        session?.playlistGroups.flatMap(\.playlists) ?? []
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(^String.Titles.sportCutExportTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.sportCutExportType)
                            .font(.system(size: 14, weight: .semibold))
                        
                        ForEach(SportCutExportType.allCases, id: \.rawValue) { type in
                            Button(action: { exportType = type }) {
                                HStack {
                                    Image(systemName: exportType == type ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(exportType == type ? .blue : .gray)
                                    Text(type.displayName)
                                        .font(.system(size: 13))
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(^String.Titles.sportCutSelectPlaylists)
                                .font(.system(size: 14, weight: .semibold))
                            
                            Spacer()
                            
                            Button(^String.Titles.sportCutSelectAll) {
                                selectedPlaylistIDs = Set(allPlaylists.map(\.id))
                            }
                            .font(.system(size: 11))
                            .buttonStyle(PlainButtonStyle())
                            .foregroundColor(.blue)
                        }
                        
                        ForEach(allPlaylists) { playlist in
                            Button(action: {
                                if selectedPlaylistIDs.contains(playlist.id) {
                                    selectedPlaylistIDs.remove(playlist.id)
                                } else {
                                    selectedPlaylistIDs.insert(playlist.id)
                                }
                            }) {
                                HStack {
                                    Image(systemName: selectedPlaylistIDs.contains(playlist.id) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(selectedPlaylistIDs.contains(playlist.id) ? .blue : .gray)
                                    Text(playlist.name)
                                        .font(.system(size: 12))
                                    Spacer()
                                    Text(String.Titles.sportCutEventsCount.format(playlist.eventCount))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    Toggle(isOn: $addWatermark) {
                        Text(^String.Titles.sportCutAddWatermark)
                    }
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            
            if isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: exportProgress)
                    Text(String.Titles.sportCutExportProgress.format(Int(exportProgress * 100)))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
            }
            
            Divider()
            
            HStack {
                Button(^String.Titles.cancelButtonTitle) { dismiss() }
                    .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: startExport) {
                    Text(^String.Titles.sportCutExportAction)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedPlaylistIDs.isEmpty || isExporting)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 550)
    }
    
    private func startExport() {
        guard let session = session else { return }
        
        let selectedPlaylists = allPlaylists.filter { selectedPlaylistIDs.contains($0.id) }
        guard !selectedPlaylists.isEmpty else { return }
        
        isExporting = true
        
        let panel = NSSavePanel()
        
        switch exportType {
        case .clips:
            panel.allowedFileTypes = ["zip"]
            panel.nameFieldStringValue = "\(session.name)_clips.zip"
        case .film:
            panel.allowedFileTypes = ["mp4"]
            panel.nameFieldStringValue = "\(session.name)_film.mp4"
        case .filmPerPlaylist:
            panel.canCreateDirectories = true
            panel.allowedFileTypes = ["mp4"]
            panel.nameFieldStringValue = "\(session.name)_playlists"
        }
        
        guard panel.runModal() == .OK, let outputURL = panel.url else {
            isExporting = false
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            exportPlaylists(selectedPlaylists, to: outputURL, session: session)
        }
    }
    
    private func exportPlaylists(_ playlists: [SportCutPlaylist], to outputURL: URL, session: SportCutSession) {
        let totalEvents = playlists.flatMap(\.events).count
        var processedEvents = 0
        
        switch exportType {
        case .clips:
            exportAsClips(playlists: playlists, outputURL: outputURL, session: session, totalEvents: totalEvents, processedEvents: &processedEvents)
        case .film:
            exportAsFilm(playlists: playlists, outputURL: outputURL, session: session, totalEvents: totalEvents)
        case .filmPerPlaylist:
            exportAsFilmPerPlaylist(playlists: playlists, outputURL: outputURL, session: session, totalEvents: totalEvents)
        }
    }
    
    private func exportAsClips(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession, totalEvents: Int, processedEvents: inout Int) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let allEvents = playlists.flatMap(\.events)
        let group = DispatchGroup()
        var processed = 0
        
        for (index, event) in allEvents.enumerated() {
            group.enter()
            
            guard let source = session.sources.first(where: { $0.id == event.sourceID }),
                  let url = source.resolveVideoURL() else {
                group.leave()
                continue
            }
            
            let asset = AVAsset(url: url)
            let composition = AVMutableComposition()
            
            guard let videoTrack = asset.tracks(withMediaType: .video).first,
                  let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                group.leave()
                continue
            }
            
            let audioTrack = asset.tracks(withMediaType: .audio).first
            let compAudio = audioTrack != nil ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) : nil
            
            let startTime = CMTime(seconds: event.startTime, preferredTimescale: 600)
            let duration = CMTime(seconds: event.duration, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, duration: duration)
            
            do {
                try compVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)
                if let compAudio = compAudio, let audio = audioTrack {
                    try compAudio.insertTimeRange(timeRange, of: audio, at: .zero)
                }
            } catch {
                group.leave()
                continue
            }
            
            let clipName = "\(event.tagName)_\(index + 1).mp4"
            let clipURL = tempDir.appendingPathComponent(clipName)
            
            let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
            exportSession?.outputURL = clipURL
            exportSession?.outputFileType = .mp4
            
            exportSession?.exportAsynchronously {
                DispatchQueue.main.async { [self] in
                    processed += 1
                    exportProgress = Double(processed) / Double(totalEvents)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let zipURL = outputURL
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            let filesPaths = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil).map(\.path)) ?? []
            process.arguments = ["-j", zipURL.path] + filesPaths
            try? process.run()
            process.waitUntilExit()
            
            try? FileManager.default.removeItem(at: tempDir)
            isExporting = false
        }
    }
    
    private func exportAsFilm(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession, totalEvents: Int) {
        let allEvents = playlists.flatMap(\.events)
        let composition = AVMutableComposition()
        
        guard let firstEvent = allEvents.first,
              let firstSource = session.sources.first(where: { $0.id == firstEvent.sourceID }),
              let firstURL = firstSource.resolveVideoURL() else {
            DispatchQueue.main.async { isExporting = false }
            return
        }
        
        let firstAsset = AVAsset(url: firstURL)
        guard let videoTrack = firstAsset.tracks(withMediaType: .video).first,
              let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { isExporting = false }
            return
        }
        
        let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var currentTime = CMTime.zero
        
        for event in allEvents {
            guard let source = session.sources.first(where: { $0.id == event.sourceID }),
                  let url = source.resolveVideoURL() else { continue }
            
            let asset = AVAsset(url: url)
            guard let vTrack = asset.tracks(withMediaType: .video).first else { continue }
            let aTrack = asset.tracks(withMediaType: .audio).first
            
            let startTime = CMTime(seconds: event.startTime, preferredTimescale: 600)
            let duration = CMTime(seconds: event.duration, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, duration: duration)
            
            do {
                try compVideo.insertTimeRange(timeRange, of: vTrack, at: currentTime)
                if let compAudio = compAudio, let aTrack = aTrack {
                    try compAudio.insertTimeRange(timeRange, of: aTrack, at: currentTime)
                }
                currentTime = currentTime + duration
            } catch { continue }
        }
        
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        try? FileManager.default.removeItem(at: outputURL)
        exportSession?.outputURL = outputURL
        exportSession?.outputFileType = .mp4
        
        exportSession?.exportAsynchronously {
            DispatchQueue.main.async { isExporting = false }
        }
    }
    
    private func exportAsFilmPerPlaylist(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession, totalEvents: Int) {
        let parentDir = outputURL.deletingLastPathComponent()
        let baseName = outputURL.deletingPathExtension().lastPathComponent
        
        let group = DispatchGroup()
        
        for playlist in playlists {
            group.enter()
            
            let composition = AVMutableComposition()
            guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                group.leave()
                continue
            }
            let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            
            var currentTime = CMTime.zero
            
            for event in playlist.events {
                guard let source = session.sources.first(where: { $0.id == event.sourceID }),
                      let url = source.resolveVideoURL() else { continue }
                
                let asset = AVAsset(url: url)
                guard let vTrack = asset.tracks(withMediaType: .video).first else { continue }
                let aTrack = asset.tracks(withMediaType: .audio).first
                
                let startTime = CMTime(seconds: event.startTime, preferredTimescale: 600)
                let duration = CMTime(seconds: event.duration, preferredTimescale: 600)
                let timeRange = CMTimeRange(start: startTime, duration: duration)
                
                do {
                    try compVideo.insertTimeRange(timeRange, of: vTrack, at: currentTime)
                    if let compAudio = compAudio, let aTrack = aTrack {
                        try compAudio.insertTimeRange(timeRange, of: aTrack, at: currentTime)
                    }
                    currentTime = currentTime + duration
                } catch { continue }
            }
            
            let filmURL = parentDir.appendingPathComponent("\(baseName)_\(playlist.name).mp4")
            try? FileManager.default.removeItem(at: filmURL)
            
            let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
            exportSession?.outputURL = filmURL
            exportSession?.outputFileType = .mp4
            
            exportSession?.exportAsynchronously { group.leave() }
        }
        
        group.notify(queue: .main) {
            isExporting = false
        }
    }
}
