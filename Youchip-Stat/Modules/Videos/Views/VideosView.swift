//
//  VideosView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideosView: View {
    
    @EnvironmentObject private var viewModel: VideosViewModel
    
    @State private var team1Name: String = ""
    @State private var team2Name: String = ""
    @State private var score: String = ""
    @State private var selectedDate: Date = Date()
    @State private var searchText: String = ""
    @State private var selectedFilter: VideoFilter = .all
    @State private var showImportCollectionSheet = false
    @State private var showDataManagementSheet = false
    @StateObject private var importManager = CollectionImportManager()
    
    enum VideoFilter: String, CaseIterable {
        case all = "all"
        case recent = "recent"
        case favorites = "favorites"
        
        var localizedTitle: String {
            switch self {
            case .all:
                return ^String.Titles.all
            case .recent:
                return ^String.Titles.recent
            case .favorites:
                return ^String.Titles.favorites
            }
        }
    }
    
    var filteredFiles: [FilesFile] {
        var files = viewModel.state.files
        
        if !searchText.isEmpty {
            files = files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        switch selectedFilter {
        case .all:
            break
        case .recent:
            files = files.sorted { $0.dateOpened > $1.dateOpened }
        case .favorites:
            files = files.filter { viewModel.filesManager.isFavorite($0) }
        }
        
        return files
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            if filteredFiles.isEmpty {
                emptyStateView
            } else {
                videosGridView
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.controlBackgroundColor))
        .navigationTitle(^String.Titles.video)
        .overlay(loadingOverlay)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                modernToolbarContent
            }
        }
        .infoAlert(
            title: ^String.Titles.alertsErrorTitle,
            message: viewModel.state.errorTitle,
            show: $viewModel.state.showError
        )
        .cloudFilesAlerts(
            showFilesDownloadAlert: $viewModel.state.showFilesDownloadAlert,
            showFilesDownloadingAlert: $viewModel.state.showFilesDownloadingAlert,
            downloadFiles: {
                viewModel.action.send(.downloadFiles)
            }
        )
        .sheet(isPresented: $viewModel.state.showMetadataSheet, onDismiss: {
            team1Name = ""
            team2Name = ""
            score = ""
        }) {
            videoMetadataSheet
        }
        .sheet(isPresented: $viewModel.state.showRenameSheet) {
            videoRenameSheet
        }
        .sheet(isPresented: $viewModel.state.showAuthSheet, onDismiss: {
            viewModel.action.send(.updateLimitInfo)
        }) {
            AuthKeyView()
                .environmentObject(viewModel.authManager)
        }
        .sheet(isPresented: $showImportCollectionSheet) {
            importCollectionSheet
        }
        .sheet(isPresented: $viewModel.state.showProjectImportSheet) {
            if let projectData = viewModel.state.importedProjectData {
                ProjectImportView(viewModel: viewModel, projectData: projectData)
            }
        }
        .sheet(isPresented: $viewModel.state.showDownloadFromURLSheet) {
            VideoDownloadFromURLView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showDataManagementSheet) {
            DataManagementSheet()
        }
        .alert(^String.Titles.videoUnavailable, isPresented: $viewModel.state.showRebindAlert) {
            Button(^String.Titles.cancelButtonTitle, role: .cancel) {
                viewModel.state.fileToRebind = nil
            }
            Button(^String.Titles.selectNewVideo) {
                selectNewVideoForRebind()
            }
        } message: {
            if let file = viewModel.state.fileToRebind {
                Text(String(format: ^String.Titles.videoUnavailableMessage, file.name))
            }
        }
        .onReceive(viewModel.authManager.$isAuthValid) { isValid in
            viewModel.action.send(.updateLimitInfo)
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                    
                    TextField(^String.Titles.searchVideos, text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                
                Button(action: {
                    viewModel.action.send(.openFiles)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                        Text(^String.Titles.addVideoTitle)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: .blue.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    viewModel.action.send(.showDownloadFromURLSheet)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 14, weight: .medium))
                        Text(^String.Titles.addVideoFromURL)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: .green.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            HStack {
                ForEach(VideoFilter.allCases, id: \.self) { filter in
                    Button(action: {
                        selectedFilter = filter
                    }) {
                        Text(filter.localizedTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(selectedFilter == filter ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                selectedFilter == filter 
                                    ? Color.blue 
                                    : Color(NSColor.controlBackgroundColor)
                            )
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        selectedFilter == filter 
                                            ? Color.clear 
                                            : Color(NSColor.separatorColor), 
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: viewModel.authManager.isAuthValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(viewModel.authManager.isAuthValid ? .green : .orange)
                        .font(.system(size: 12))
                    
                    Text(viewModel.state.limitInfoText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
    
    private var videosGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 200), spacing: 20, alignment: .top)
                ],
                spacing: 20
            ) {
                ForEach(filteredFiles, id: \.videoData.bookmark) { file in
                    VideoThumbnailView(file: file, id: file.videoData.id, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(^String.Titles.noVideos)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(searchText.isEmpty ? ^String.Titles.addFirstVideo : ^String.Titles.nothingFound)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if searchText.isEmpty {
                Button(action: {
                    viewModel.action.send(.openFiles)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text(^String.Titles.addVideoTitle)
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
                    .cornerRadius(10)
                    .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var modernToolbarContent: some View {
        HStack(spacing: 12) {
            Button(action: {
                viewModel.action.send(.importProject)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14))
                    Text(^String.Titles.projectImportTitle)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(6)
                .shadow(color: .green.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                showImportCollectionSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14))
                    Text(^String.Titles.importCollection)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.purple, Color.purple.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(6)
                .shadow(color: .purple.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                viewModel.action.send(.openGuide)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "book")
                        .font(.system(size: 14))
                    Text(^String.Titles.videosViewButtonGuides)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                viewModel.action.send(.showAuthSheet)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.authManager.isAuthValid ? "checkmark.shield" : "exclamationmark.shield")
                        .font(.system(size: 14))
                    Text(viewModel.authManager.isAuthValid ? ^String.Titles.renewLicense : ^String.Titles.buyLicense)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(viewModel.authManager.isAuthValid ? .green : .orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    viewModel.authManager.isAuthValid 
                        ? Color.green.opacity(0.1) 
                        : Color.orange.opacity(0.1)
                )
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            viewModel.authManager.isAuthValid 
                                ? Color.green.opacity(0.3) 
                                : Color.orange.opacity(0.3), 
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                showDataManagementSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 14))
                    Text(^String.Titles.dataManagementTitle)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var loadingOverlay: some View {
        Group {
            if viewModel.state.showHUD {
                ViewsFactory.customHUD()
                    .transition(.opacity)
            }
        }
    }
    
    private var videoMetadataSheet: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 20))
                    
                    Text(^String.Titles.videosViewTitleMatchInfo)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                
                Text(^String.Titles.fillMatchInfo)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.videosViewFieldTeam1)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        TextField(^String.Titles.enterTeam1Name, text: $team1Name)
                            .textFieldStyle(ModernTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.videosViewFieldTeam2)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        TextField(^String.Titles.enterTeam2Name, text: $team2Name)
                            .textFieldStyle(ModernTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.videosViewFieldScore)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        TextField(^String.Titles.enterScore, text: $score)
                            .textFieldStyle(ModernTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.videosViewFieldDateTime)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        DatePicker("",
                                   selection: $selectedDate,
                                   displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(CompactDatePickerStyle())
                        .labelsHidden()
                    }
                }
                .padding(.horizontal, 24)
            }
            
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.state.showMetadataSheet = false
                    }) {
                        Text(^String.Titles.collectionsButtonCancel)
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
                    
                    Button(action: {
                        if let url = viewModel.state.videoMetadata.url {
                            viewModel.action.send(.saveVideoMetadata(
                                url: url,
                                team1: team1Name,
                                team2: team2Name,
                                score: score,
                                dateTime: selectedDate
                            ))
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .medium))
                            Text(^String.Titles.saveButtonTitle)
                                .font(.system(size: 16, weight: .medium))
                        }
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
                        .shadow(color: .blue.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(team1Name.isEmpty || team2Name.isEmpty)
                    .opacity(team1Name.isEmpty || team2Name.isEmpty ? 0.6 : 1.0)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 450, maxWidth: 450, minHeight: 420, maxHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            team1Name = viewModel.state.videoMetadata.team1
            team2Name = viewModel.state.videoMetadata.team2
            score = viewModel.state.videoMetadata.score
            selectedDate = viewModel.state.videoMetadata.dateTime
        }
    }
    
    private var videoRenameSheet: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 20))
                    
                    Text(^String.Titles.videosViewDialogRenameVideo)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                
                Text(^String.Titles.enterNewVideoName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.videosViewFieldFileName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    TextField(^String.Titles.enterNewName, text: $viewModel.state.newFileName)
                        .textFieldStyle(ModernTextFieldStyle())
                }
                .padding(.horizontal, 24)
            }
            
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.state.showRenameSheet = false
                    }) {
                        Text(^String.Titles.collectionsButtonCancel)
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
                    
                    Button(action: {
                        if let file = viewModel.state.fileToRename {
                            viewModel.action.send(.renameSimpleVideo(
                                file: file,
                                newName: viewModel.state.newFileName
                            ))
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .medium))
                            Text(^String.Titles.saveButtonTitle)
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.orange, Color.orange.opacity(0.8)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(8)
                        .shadow(color: .orange.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(viewModel.state.newFileName.isEmpty)
                    .opacity(viewModel.state.newFileName.isEmpty ? 0.6 : 1.0)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 400, maxWidth: 400, minHeight: 220, maxHeight: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var importCollectionSheet: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(.purple)
                        .font(.title)
                    
                    Text(^String.Titles.importCollection)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                
                Text(^String.Titles.selectCollectionFilePrompt)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            ScrollView {
                VStack(spacing: 20) {
                    if importManager.isImporting {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            
                            Text(^String.Titles.importingCollection)
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 60))
                                .foregroundColor(.purple.opacity(0.6))
                            
                            Text(^String.Titles.selectCollectionFileButton)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            if let error = importManager.importError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                }
            }
            
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 12) {
                    Button(action: {
                        showImportCollectionSheet = false
                        importManager.importError = nil
                    }) {
                        Text(^String.Titles.collectionsButtonCancel)
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
                    .disabled(importManager.isImporting)
                    
                    Spacer()
                    
                    Button(action: {
                        selectCollectionFile()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.system(size: 14, weight: .medium))
                            Text(^String.Titles.selectFile)
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.purple, Color.purple.opacity(0.8)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(8)
                        .shadow(color: .purple.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(importManager.isImporting)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 500, maxWidth: 500, minHeight: 400, maxHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func selectCollectionFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.title = ^String.Titles.selectCollectionFile
        panel.message = ^String.Titles.selectCollectionFileMessage
        
        if panel.runModal() == .OK, let url = panel.url {
            if let importedManager = importManager.importCollection(from: url) {
                _ = importedManager.saveCollectionToFiles()
                NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                
                showImportCollectionSheet = false
                importManager.importError = nil
            }
        }
    }
    
    private func selectNewVideoForRebind() {
        guard let file = viewModel.state.fileToRebind else { return }
        
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.title = ^String.Titles.selectVideoFile
        panel.message = String(format: ^String.Titles.selectNewVideoFileMessage, file.name)
        
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.action.send(.rebindVideo(file: file, newURL: url))
        } else {
            viewModel.state.showRebindAlert = false
            viewModel.state.fileToRebind = nil
        }
    }
}

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .font(.system(size: 14))
    }
}
