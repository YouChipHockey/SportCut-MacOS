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
    /// Режим выбора проектов для объединения.
    @State private var isMergeSelectionMode = false
    /// Id выбранных проектов в порядке выбора — этот порядок и станет порядком склейки.
    @State private var mergeSelection: [String] = []
    @State private var showMergeSheet = false
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
    
    /// Выбранные проекты в порядке выбора.
    private var mergeSources: [ProjectMergeSource] {
        mergeSelection.compactMap { id in
            viewModel.state.files.first(where: { $0.videoData.id == id }).map(ProjectMergeSource.init(file:))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if isMergeSelectionMode {
                mergeSelectionBar
            }

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
        .sheet(isPresented: $viewModel.state.showLiveSourceSelection) {
            LiveSourceSelectionView(
                isAppendMode: viewModel.state.appendVideoFile != nil,
                onConfigure: { _, _, _, preloadedURL, saveFolderURL in
                    LiveStreamManager.shared.setSaveCopyFolder(saveFolderURL)
                    viewModel.action.send(.liveSourceConfigured(preloadedURL: preloadedURL))
                },
                onCancel: {
                    viewModel.action.send(.cancelLiveSetup)
                }
            )
        }
        .sheet(isPresented: $viewModel.state.showLiveMetadataSheet, onDismiss: {
            if viewModel.state.isLiveSessionConfigured {
                // User dismissed without saving - cleanup
                viewModel.action.send(.cancelLiveSetup)
            }
        }) {
            liveMetadataSheet
        }
        .sheet(isPresented: $showDataManagementSheet) {
            DataManagementSheet()
        }
        .sheet(isPresented: $showMergeSheet) {
            ProjectMergeView(
                sources: mergeSources,
                onFinished: { _ in
                    showMergeSheet = false
                    exitMergeSelectionMode()
                },
                onCancel: {
                    showMergeSheet = false
                }
            )
            .environmentObject(viewModel)
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
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))

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

                addMenu
                importMenu
                mergeButton
                settingsMenu
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            HStack(spacing: 8) {
                ForEach(VideoFilter.allCases, id: \.self) { filter in
                    Button(action: {
                        selectedFilter = filter
                    }) {
                        Text(filter.localizedTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(selectedFilter == filter ? .white : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(selectedFilter == filter ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                            )
                            .overlay(
                                Capsule().stroke(selectedFilter == filter ? Color.clear : Color(NSColor.separatorColor), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                licenseBadge
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }

    /// Основное акцентное действие — «Добавить» (файл / по ссылке / запись трансляции).
    private var addMenu: some View {
        Menu {
            Button {
                viewModel.action.send(.openFiles)
            } label: {
                SwiftUI.Label(^String.Titles.videosAddFromFile, systemImage: "folder")
            }
            Button {
                viewModel.action.send(.showDownloadFromURLSheet)
            } label: {
                SwiftUI.Label(^String.Titles.addVideoFromURL, systemImage: "link")
            }
            Button {
                viewModel.action.send(.showLiveSourceSelection)
            } label: {
                SwiftUI.Label(^String.Titles.recordVideo, systemImage: "record.circle")
            }
        } label: {
            primaryHeaderLabel(icon: "plus", text: ^String.Titles.videosAddMenuTitle)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Импорт проекта / коллекции.
    private var importMenu: some View {
        Menu {
            Button {
                viewModel.action.send(.importProject)
            } label: {
                SwiftUI.Label(^String.Titles.projectImportTitle, systemImage: "square.and.arrow.down")
            }
            Button {
                showImportCollectionSheet = true
            } label: {
                SwiftUI.Label(^String.Titles.importCollection, systemImage: "tray.and.arrow.down")
            }
        } label: {
            secondaryHeaderLabel(icon: "square.and.arrow.down", text: ^String.Titles.videosImportMenuTitle, showsChevron: true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Вход в режим выбора проектов для объединения.
    private var mergeButton: some View {
        Button(action: {
            if isMergeSelectionMode {
                exitMergeSelectionMode()
            } else {
                isMergeSelectionMode = true
            }
        }) {
            secondaryHeaderLabel(
                icon: "arrow.triangle.merge",
                text: isMergeSelectionMode ? ^String.Titles.mergeProjectsExitSelection : ^String.Titles.mergeProjectsButton
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help(^String.Titles.mergeProjectsHelp)
    }

    /// Панель под шапкой: сколько выбрано и кнопка перехода к объединению.
    private var mergeSelectionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .foregroundColor(.accentColor)

            Text(String(format: ^String.Titles.mergeProjectsSelectedCount, mergeSelection.count))
                .font(.system(size: 13, weight: .medium))

            Text(^String.Titles.mergeProjectsSelectionHint)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()

            Button(^String.Titles.cancelButtonTitle) {
                exitMergeSelectionMode()
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.secondary)

            Button(action: { showMergeSheet = true }) {
                Text(^String.Titles.mergeProjectsStartButton)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(mergeSelection.count >= 2 ? Color.accentColor : Color.gray))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(mergeSelection.count < 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
    }

    private func toggleMergeSelection(for file: FilesFile) {
        let id = file.videoData.id
        if let index = mergeSelection.firstIndex(of: id) {
            mergeSelection.remove(at: index)
        } else {
            mergeSelection.append(id)
        }
    }

    private func exitMergeSelectionMode() {
        isMergeSelectionMode = false
        mergeSelection.removeAll()
    }

    private var settingsMenu: some View {
        Menu {
            Button {
                viewModel.action.send(.openGuide)
            } label: {
                SwiftUI.Label(^String.Titles.videosViewButtonGuides, systemImage: "book")
            }
            Button {
                viewModel.action.send(.showAuthSheet)
            } label: {
                SwiftUI.Label(
                    viewModel.authManager.isAuthValid ? ^String.Titles.renewLicense : ^String.Titles.buyLicense,
                    systemImage: viewModel.authManager.isAuthValid ? "checkmark.shield" : "exclamationmark.shield"
                )
            }
            Divider()
            Button {
                WindowsManager.shared.openSettingsWindow()
            } label: {
                SwiftUI.Label(^String.Titles.settingsMenuItem, systemImage: "slider.horizontal.3")
            }
            Button {
                showDataManagementSheet = true
            } label: {
                SwiftUI.Label(^String.Titles.dataManagementTitle, systemImage: "externaldrive.fill")
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .frame(width: 34, height: 34)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(^String.Titles.settings)
    }

    /// Лицензия: если активна — просто «Лицензия активна» (лимитов нет); иначе показываем лимиты
    /// разметки И режима просмотра (отдельными строками).
    @ViewBuilder
    private var licenseBadge: some View {
        let active = viewModel.authManager.isAuthValid
        HStack(spacing: 6) {
            Image(systemName: active ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(active ? .green : .orange)
                .font(.system(size: 12))
            if active {
                Text(^String.Titles.licenseActive)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.state.limitInfoText)
                    if let viewingText = viewModel.state.viewingLimitInfoText {
                        Text(viewingText)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((active ? Color.green : Color.orange).opacity(0.12))
        .cornerRadius(20)
    }

    private func primaryHeaderLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
            Text(text)
                .font(.system(size: 14, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .opacity(0.85)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor)
        .cornerRadius(8)
    }

    private func secondaryHeaderLabel(icon: String, text: String, showsChevron: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(text)
                .font(.system(size: 14, weight: .medium))
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.6)
            }
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
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
                ForEach(filteredFiles, id: \.videoData.id) { file in
                    VideoThumbnailView(
                        file: file,
                        viewModel: viewModel,
                        isSelectionMode: isMergeSelectionMode,
                        selectionOrder: mergeSelection.firstIndex(of: file.videoData.id).map { $0 + 1 },
                        onToggleSelection: { toggleMergeSelection(for: file) }
                    )
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
    
    // MARK: - Live Metadata Sheet
    
    @State private var liveTeam1Name: String = ""
    @State private var liveTeam2Name: String = ""
    @State private var liveScore: String = ""
    @State private var liveSelectedDate: Date = Date()
    
    private var liveMetadataSheet: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "record.circle")
                        .foregroundColor(.red)
                        .font(.system(size: 20))
                    
                    Text(^String.Titles.liveStreamMatchInfo)
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
                        
                        TextField(^String.Titles.enterTeam1Name, text: $liveTeam1Name)
                            .textFieldStyle(ModernTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.videosViewFieldTeam2)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        TextField(^String.Titles.enterTeam2Name, text: $liveTeam2Name)
                            .textFieldStyle(ModernTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.videosViewFieldScore)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        TextField(^String.Titles.enterScore, text: $liveScore)
                            .textFieldStyle(ModernTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.videosViewFieldDateTime)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        DatePicker("",
                                   selection: $liveSelectedDate,
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
                        viewModel.action.send(.cancelLiveSetup)
                        liveTeam1Name = ""
                        liveTeam2Name = ""
                        liveScore = ""
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
                        viewModel.action.send(.startLiveWithMetadata(
                            team1: liveTeam1Name,
                            team2: liveTeam2Name,
                            score: liveScore,
                            dateTime: liveSelectedDate
                        ))
                        liveTeam1Name = ""
                        liveTeam2Name = ""
                        liveScore = ""
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "record.circle")
                                .font(.system(size: 14, weight: .medium))
                            Text(^String.Titles.liveStreamStartRecording)
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(8)
                        .shadow(color: .red.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(liveTeam1Name.isEmpty || liveTeam2Name.isEmpty)
                    .opacity(liveTeam1Name.isEmpty || liveTeam2Name.isEmpty ? 0.6 : 1.0)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 450, maxWidth: 450, minHeight: 420, maxHeight: 600)
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
                // Сразу подхватываем импортированную коллекцию в общий пул — иначе она не
                // открывается из списка до перезапуска (обсервер пулов вешается только редактором).
                TagLibraryManager.shared.refreshGlobalPools()
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
