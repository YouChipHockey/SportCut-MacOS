//
//  SportCutCreateSessionView.swift
//  Youchip-Stat
//

import SwiftUI
import UniformTypeIdentifiers

struct SportCutCreateSessionView: View {
    let onCreated: (SportCutSession) -> Void
    let onCancel: () -> Void
    
    @State private var sessionName = ""
    @State private var selectedProjects: [FilesFile] = []
    @State private var selectedVideoURLs: [URL] = []
    @State private var showProjectPicker = false
    @State private var showLimitAlert = false
    private var filesManager: VideoFilesManager { VideoFilesManager.shared }
    
    private var availableFiles: [FilesFile] {
        filesManager.files.filter { file in
            !selectedProjects.contains(where: { $0.videoData.id == file.videoData.id })
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 20))
                    
                    Text(^String.Titles.sportCutCreateSession)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                
                Text(^String.Titles.sportCutAddProjectsDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.sportCutSessionName)
                            .font(.system(size: 14, weight: .medium))
                        
                        TextField(^String.Titles.sportCutEnterName, text: $sessionName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(^String.Titles.sportCutMarkupProjects)
                                .font(.system(size: 14, weight: .semibold))
                            
                            Spacer()
                            
                            Button(action: { showProjectPicker = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text(^String.Titles.sportCutAddProject)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(availableFiles.isEmpty)
                        }
                        
                        if selectedProjects.isEmpty {
                            Text(^String.Titles.sportCutNoAddedProjects)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(selectedProjects, id: \.videoData.id) { file in
                                HStack {
                                    Image(systemName: "film")
                                        .foregroundColor(.blue)
                                    Text(file.name)
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    let stampCount = file.timelines.flatMap(\.stamps).count
                                    Text(String.Titles.sportCutEventsCount.format(stampCount))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    
                                    Button(action: {
                                        selectedProjects.removeAll { $0.videoData.id == file.videoData.id }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(^String.Titles.sportCutVideoFiles)
                                .font(.system(size: 14, weight: .semibold))
                            
                            Spacer()
                            
                            Button(action: addVideoFiles) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text(^String.Titles.sportCutAddVideo)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        if selectedVideoURLs.isEmpty {
                            Text(^String.Titles.sportCutNoAddedVideos)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(selectedVideoURLs, id: \.absoluteString) { url in
                                HStack {
                                    Image(systemName: "video")
                                        .foregroundColor(.green)
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        selectedVideoURLs.removeAll { $0 == url }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            
            Divider()
            
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text(^String.Titles.cancelButtonTitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: createSession) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                        Text(^String.Titles.sportCutCreate)
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(sessionName.isEmpty && selectedProjects.isEmpty && selectedVideoURLs.isEmpty)
                .opacity(sessionName.isEmpty && selectedProjects.isEmpty && selectedVideoURLs.isEmpty ? 0.6 : 1.0)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 600, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showProjectPicker) {
            ProjectPickerSheet(
                availableFiles: availableFiles,
                onAdd: { files in
                    for file in files {
                        if !selectedProjects.contains(where: { $0.videoData.id == file.videoData.id }) {
                            selectedProjects.append(file)
                        }
                    }
                    showProjectPicker = false
                },
                onCancel: { showProjectPicker = false }
            )
        }
        .alert(^String.Titles.viewingLimitReachedTitle, isPresented: $showLimitAlert) {
            Button(^String.Titles.alertsOkTitle, role: .cancel) { }
        } message: {
            Text(^String.Titles.viewingLimitReachedMessage)
        }
    }
    
    private func addVideoFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.title = ^String.Titles.sportCutSelectVideoFiles
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                if !selectedVideoURLs.contains(url) {
                    selectedVideoURLs.append(url)
                }
            }
        }
    }
    
    private func createSession() {
        // Лимит режима просмотра: без активной лицензии нельзя создавать новые сессии сверх лимита.
        guard LicenseLimitsManager.shared.canCreateViewingSession else {
            showLimitAlert = true
            return
        }
        let name = sessionName.isEmpty ? String.Titles.sportCutSessionPrefix.format(Date().formatted(.dateTime.day().month().hour().minute())) : sessionName
        var session = SportCutSessionManager.shared.createSession(name: name)
        
        for file in selectedProjects {
            SportCutSessionManager.shared.addProjectSource(to: &session, file: file)
        }
        
        for url in selectedVideoURLs {
            SportCutSessionManager.shared.addVideoSource(to: &session, url: url)
        }
        
        if session.playlistGroups.isEmpty {
            SportCutSessionManager.shared.addPlaylistGroup(to: &session, name: ^String.Titles.sportCutDefaultGroupName)
        }
        
        onCreated(session)
    }
}

// MARK: - Project Picker Sheet

struct ProjectPickerSheet: View {
    let availableFiles: [FilesFile]
    let onAdd: ([FilesFile]) -> Void
    let onCancel: () -> Void
    // Выбор ведём по уникальному id проекта, а НЕ по bookmark: у разных проектов
    // с одним и тем же видеофайлом bookmark совпадает, и по нему выделялись сразу все.
    @State private var selectedProjectIDs: Set<String> = []
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(^String.Titles.sportCutSelectProjects)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            Divider()
            
            if availableFiles.isEmpty {
                VStack(spacing: 8) {
                    Text(^String.Titles.sportCutNoAvailableProjects)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(availableFiles, id: \.videoData.id) { file in
                            let isSelected = selectedProjectIDs.contains(file.videoData.id)
                            HStack {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isSelected ? .blue : .gray)
                                    .font(.system(size: 16))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                        .font(.system(size: 13, weight: .medium))
                                    let count = file.timelines.flatMap(\.stamps).count
                                    Text(String.Titles.sportCutTimelinesAndEvents.format(file.timelines.count, count))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelected {
                                    selectedProjectIDs.remove(file.videoData.id)
                                } else {
                                    selectedProjectIDs.insert(file.videoData.id)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
            
            Divider()
            
            HStack {
                Button(^String.Titles.cancelButtonTitle) { onCancel() }
                    .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(String.Titles.sportCutAddCount.format(selectedProjectIDs.count)) {
                    let selected = availableFiles.filter { selectedProjectIDs.contains($0.videoData.id) }
                    onAdd(selected)
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
                .disabled(selectedProjectIDs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 450, height: 400)
    }
}
