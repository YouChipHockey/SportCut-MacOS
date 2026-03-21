//
//  SportCutSessionManager.swift
//  Youchip-Stat
//

import Foundation
import Combine
import AVFoundation

class SportCutSessionManager: ObservableObject {
    static let shared = SportCutSessionManager()
    
    @Published var sessions: [SportCutSession] = []
    @Published var currentSession: SportCutSession?
    
    private let sessionsKey = "SportCutSessions_v1"
    
    private init() {
        loadSessions()
    }
    
    // MARK: - CRUD
    
    func createSession(name: String) -> SportCutSession {
        let session = SportCutSession(name: name)
        sessions.append(session)
        saveSessions()
        return session
    }
    
    func deleteSession(_ session: SportCutSession) {
        sessions.removeAll { $0.id == session.id }
        if currentSession?.id == session.id {
            currentSession = nil
        }
        saveSessions()
    }
    
    func updateSession(_ session: SportCutSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
            if currentSession?.id == session.id {
                currentSession = session
            }
            saveSessions()
        }
    }
    
    // MARK: - Source management
    
    func addProjectSource(to session: inout SportCutSession, file: FilesFile) {
        guard let url = file.url else { return }
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        
        let timelines = file.timelines
        let tagLibrary = TagLibraryManager.shared
        
        let source = SportCutSource(
            name: file.name,
            videoBookmark: bookmark,
            timelines: timelines,
            isStandaloneVideo: false,
            projectID: file.id,
            tags: tagLibrary.allTags,
            tagGroups: tagLibrary.allTagGroups,
            labels: tagLibrary.allLabels,
            labelGroups: tagLibrary.allLabelGroups,
            timeEvents: tagLibrary.allTimeEvents
        )
        
        session.sources.append(source)
        updateSession(session)
    }
    
    func addVideoSource(to session: inout SportCutSession, url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        
        let videoName = url.deletingPathExtension().lastPathComponent
        let tagID = UUID().uuidString
        let lineID = UUID()
        
        let fakeTag = Tag(
            id: tagID,
            primaryID: nil,
            name: videoName,
            description: "",
            color: "4A90D9",
            defaultTimeBefore: 0,
            defaultTimeAfter: 0,
            collection: nil,
            lablesGroup: [],
            hotkey: nil,
            labelHotkeys: nil,
            mapEnabled: nil,
            isInterval: nil
        )
        
        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        
        let stamp = TimelineStamp(
            id: UUID(),
            tagRefs: [StampTagRef(id: tagID, tagGroupId: "")],
            primaryID: nil,
            timeStartSeconds: 0,
            timeFinishSeconds: duration > 0 ? duration : 3600,
            colorHex: "4A90D9",
            label: videoName,
            labels: [],
            timeEvents: []
        )
        
        let timeline = TimelineLine(
            id: lineID,
            name: videoName,
            stamps: [stamp],
            tagIdForMode: tagID
        )
        
        let source = SportCutSource(
            name: videoName,
            videoBookmark: bookmark,
            timelines: [timeline],
            isStandaloneVideo: true,
            tags: [fakeTag],
            tagGroups: [],
            labels: [],
            labelGroups: [],
            timeEvents: []
        )
        
        session.sources.append(source)
        updateSession(session)
    }
    
    func removeSource(from session: inout SportCutSession, sourceID: UUID) {
        session.sources.removeAll { $0.id == sourceID }
        updateSession(session)
    }
    
    // MARK: - Playlist management
    
    func addPlaylistGroup(to session: inout SportCutSession, name: String) {
        let group = SportCutPlaylistGroup(name: name)
        session.playlistGroups.append(group)
        updateSession(session)
    }
    
    func addPlaylist(to session: inout SportCutSession, groupIndex: Int, name: String?) {
        guard groupIndex < session.playlistGroups.count else { return }
        let playlistCount = session.playlistGroups[groupIndex].playlists.count
        let playlistName = name ?? "\(playlistCount + 1)"
        let playlist = SportCutPlaylist(name: playlistName)
        session.playlistGroups[groupIndex].playlists.append(playlist)
        updateSession(session)
    }
    
    func duplicatePlaylist(in session: inout SportCutSession, groupIndex: Int, playlistIndex: Int) {
        guard groupIndex < session.playlistGroups.count,
              playlistIndex < session.playlistGroups[groupIndex].playlists.count else { return }
        
        let original = session.playlistGroups[groupIndex].playlists[playlistIndex]
        let copy = SportCutPlaylist(
            name: "\(original.name) (копия)",
            events: original.events
        )
        session.playlistGroups[groupIndex].playlists.insert(copy, after: playlistIndex)
        updateSession(session)
    }
    
    // MARK: - Persistence
    
    private func saveSessions() {
        do {
            let data = try JSONEncoder().encode(sessions)
            UserDefaults.standard.set(data, forKey: sessionsKey)
        } catch {
            print("SportCutSessionManager: Failed to save sessions: \(error)")
        }
    }
    
    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey) else { return }
        do {
            sessions = try JSONDecoder().decode([SportCutSession].self, from: data)
        } catch {
            sessions = []
            print("SportCutSessionManager: Failed to load sessions: \(error)")
        }
    }
}

private extension Array {
    mutating func insert(_ element: Element, after index: Int) {
        if index + 1 >= count {
            append(element)
        } else {
            insert(element, at: index + 1)
        }
    }
}
