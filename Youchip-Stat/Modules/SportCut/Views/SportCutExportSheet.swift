//
//  SportCutExportSheet.swift
//  Youchip-Stat
//

import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

struct SportCutExportSheet: View {
    let sessionID: UUID
    @ObservedObject var playerManager: SportCutPlayerManager
    @ObservedObject var sessionManager = SportCutSessionManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var exportType: SportCutExportType = .clips
    @State private var selectedPlaylistIDs: Set<UUID> = []
    @State private var addWatermark = false
    @StateObject private var exportUI = SportCutExportUIState()

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

            if exportUI.isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: exportUI.progress)
                    Text(String.Titles.sportCutExportProgress.format(Int(exportUI.progress * 100)))
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
                .disabled(selectedPlaylistIDs.isEmpty || exportUI.isExporting)
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

        exportUI.isExporting = true
        exportUI.progress = 0

        let panel = NSSavePanel()

        switch exportType {
        case .clips:
            panel.allowedContentTypes = [UTType.zip]
            panel.nameFieldStringValue = "\(session.name)_clips.zip"
        case .film:
            panel.allowedContentTypes = [UTType.mpeg4Movie]
            panel.nameFieldStringValue = "\(session.name)_film.mp4"
        case .filmPerPlaylist:
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [UTType.mpeg4Movie]
            panel.nameFieldStringValue = "\(session.name)_playlists"
        }

        guard panel.runModal() == .OK, let outputURL = panel.url else {
            exportUI.isExporting = false
            return
        }

        let type = exportType
        let ui = exportUI
        DispatchQueue.global(qos: .userInitiated).async {
            let backend = SportCutExportBackend(ui: ui)
            backend.run(playlists: selectedPlaylists, outputURL: outputURL, session: session, type: type)
        }
    }
}

// MARK: - Export UI state (main-thread updates from background)

private final class SportCutExportUIState: ObservableObject {
    @Published var progress: Double = 0
    @Published var isExporting: Bool = false
}

// MARK: - Background export

private final class SportCutExportBackend {
    private let ui: SportCutExportUIState

    init(ui: SportCutExportUIState) {
        self.ui = ui
    }

    func run(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession, type: SportCutExportType) {
        switch type {
        case .clips:
            exportAsClips(playlists: playlists, outputURL: outputURL, session: session)
        case .film:
            exportAsFilm(playlists: playlists, outputURL: outputURL, session: session)
        case .filmPerPlaylist:
            exportAsFilmPerPlaylist(playlists: playlists, outputURL: outputURL, session: session)
        }
    }

    private func resolvedEvent(_ event: SportCutEvent, session: SportCutSession) -> SportCutEvent {
        session.timelineResolvedEvent(for: event)
    }

    private static func bestPreset(for asset: AVAsset) -> String {
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        for candidate in [AVAssetExportPresetHighestQuality, AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720, AVAssetExportPreset960x540, AVAssetExportPresetPassthrough] {
            if presets.contains(candidate) { return candidate }
        }
        return AVAssetExportPresetPassthrough
    }

    private func exportAsClips(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession) {
        let sink = ui
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let allEvents = playlists.flatMap(\.events)
        let total = max(allEvents.count, 1)
        let group = DispatchGroup()
        var processed = 0
        let progressLock = NSLock()

        for (index, rawEvent) in allEvents.enumerated() {
            group.enter()
            let event = resolvedEvent(rawEvent, session: session)

            guard let source = session.sources.first(where: { $0.id == event.sourceID }),
                  let url = source.mediaAccessURL() else {
                group.leave()
                progressLock.lock()
                processed += 1
                let p = processed
                progressLock.unlock()
                DispatchQueue.main.async { sink.progress = Double(p) / Double(total) }
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let asset = AVAsset(url: url)
            let composition = AVMutableComposition()

            guard let videoTrack = asset.tracks(withMediaType: .video).first,
                  let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                group.leave()
                progressLock.lock()
                processed += 1
                let p = processed
                progressLock.unlock()
                DispatchQueue.main.async { sink.progress = Double(p) / Double(total) }
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
                progressLock.lock()
                processed += 1
                let p = processed
                progressLock.unlock()
                DispatchQueue.main.async { sink.progress = Double(p) / Double(total) }
                continue
            }

            let safeTag = event.tagName
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let prefix = String(safeTag.prefix(80))
            let clipName = "\(prefix)_\(index + 1).mp4"
            let clipURL = tempDir.appendingPathComponent(clipName)

            let preset = Self.bestPreset(for: composition)
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
                group.leave()
                progressLock.lock()
                processed += 1
                let p = processed
                progressLock.unlock()
                DispatchQueue.main.async { sink.progress = Double(p) / Double(total) }
                continue
            }

            exportSession.outputURL = clipURL
            exportSession.outputFileType = .mp4

            exportSession.exportAsynchronously {
                progressLock.lock()
                processed += 1
                let p = processed
                progressLock.unlock()
                DispatchQueue.main.async { sink.progress = Double(p) / Double(total) }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let zipURL = outputURL
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            let files = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? []
            let filesPaths = files.map(\.path)
            guard !filesPaths.isEmpty else {
                try? FileManager.default.removeItem(at: tempDir)
                sink.isExporting = false
                return
            }
            process.arguments = ["-j", zipURL.path] + filesPaths
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // ignore; UI still stops
            }

            try? FileManager.default.removeItem(at: tempDir)
            sink.isExporting = false
        }
    }

    private func exportAsFilm(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession) {
        let sink = ui
        let allEvents = playlists.flatMap(\.events).map { resolvedEvent($0, session: session) }
        let composition = AVMutableComposition()

        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { sink.isExporting = false }
            return
        }

        let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var currentTime = CMTime.zero

        for event in allEvents {
            guard let source = session.sources.first(where: { $0.id == event.sourceID }),
                  let url = source.mediaAccessURL() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

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

        let preset = Self.bestPreset(for: composition)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
            DispatchQueue.main.async { sink.isExporting = false }
            return
        }

        try? FileManager.default.removeItem(at: outputURL)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                sink.isExporting = false
            }
        }
    }

    private func exportAsFilmPerPlaylist(playlists: [SportCutPlaylist], outputURL: URL, session: SportCutSession) {
        let sink = ui
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

            for rawEvent in playlist.events {
                let event = resolvedEvent(rawEvent, session: session)
                guard let source = session.sources.first(where: { $0.id == event.sourceID }),
                      let url = source.mediaAccessURL() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

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

            let safePlaylist = playlist.name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let filmURL = parentDir.appendingPathComponent("\(baseName)_\(String(safePlaylist.prefix(120))).mp4")
            try? FileManager.default.removeItem(at: filmURL)

            let preset = Self.bestPreset(for: composition)
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
                group.leave()
                continue
            }

            exportSession.outputURL = filmURL
            exportSession.outputFileType = .mp4

            exportSession.exportAsynchronously {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            sink.isExporting = false
        }
    }
}
