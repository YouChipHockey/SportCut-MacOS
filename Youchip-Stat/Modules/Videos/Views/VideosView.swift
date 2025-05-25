//
//  VideosView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import SwiftUI

struct VideosView: View {
    
    @EnvironmentObject private var viewModel: VideosViewModel
    
    @State private var team1Name: String = ""
    @State private var team2Name: String = ""
    @State private var score: String = ""
    @State private var selectedDate: Date = Date()
    
    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150), spacing: 20, alignment: .top)
                ],
                spacing: 20
            ) {
                ForEach(viewModel.state.files, id: \.videoData.bookmark) { file in
                    VideoThumbnailView(file: file, id: file.videoData.id, viewModel: viewModel)
                }
            }
            .padding()
        }
        .frame(minWidth: 650, minHeight: 600)
        .background(Color.appSystemGray)
        .navigationTitle(^String.Titles.rootVideosTitle)
        .overlay(loadingOverlay)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Text(viewModel.state.limitInfoText)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                ViewsFactory.whiteBarButton(title: "Гайды") {
                    viewModel.action.send(.openGuide)
                }
                ViewsFactory.whiteBarButton(title: ^String.Titles.addVideoTitle) {
                    viewModel.action.send(.openFiles)
                }
                
                ViewsFactory.whiteBarButton(title: viewModel.authManager.isAuthValid ? "Продлить лицензию" : "Купить лицензию") {
                    viewModel.action.send(.showAuthSheet)
                }
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
        .onReceive(viewModel.authManager.$isAuthValid) { isValid in
            viewModel.action.send(.updateLimitInfo)
        }
    }
    
    // MARK: - Вспомогательные представления
    
    private var loadingOverlay: some View {
        Group {
            if viewModel.state.showHUD {
                ViewsFactory.customHUD()
                    .transition(.opacity)
            }
        }
    }
    
    private var videoMetadataSheet: some View {
        VStack(spacing: 20) {
            Text("Информация о матче")
                .font(.headline)
                .padding(.top)
            
            Form {
                TextField("Команда 1", text: $team1Name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                TextField("Команда 2", text: $team2Name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                TextField("Счёт (например: 2-1)", text: $score)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                DatePicker("Дата и время матча",
                           selection: $selectedDate,
                           displayedComponents: [.date, .hourAndMinute]
                )
                .padding(.horizontal)
            }
            
            HStack {
                Button("Отмена") {
                    viewModel.state.showMetadataSheet = false
                }
                
                Button("Сохранить") {
                    if let url = viewModel.state.videoMetadata.url {
                        viewModel.action.send(.saveVideoMetadata(
                            url: url,
                            team1: team1Name,
                            team2: team2Name,
                            score: score,
                            dateTime: selectedDate
                        ))
                    }
                }
                .disabled(team1Name.isEmpty || team2Name.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
        .onAppear {
            team1Name = viewModel.state.videoMetadata.team1
            team2Name = viewModel.state.videoMetadata.team2
            score = viewModel.state.videoMetadata.score
            selectedDate = viewModel.state.videoMetadata.dateTime
        }
    }
    
    private var videoRenameSheet: some View {
        VStack(spacing: 20) {
            Text("Переименовать видео")
                .font(.headline)
                .padding(.top)
            
            Form {
                TextField("Имя файла", text: $viewModel.state.newFileName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
            }
            
            HStack {
                Button("Отмена") {
                    viewModel.state.showRenameSheet = false
                }
                
                Button("Сохранить") {
                    if let file = viewModel.state.fileToRename {
                        viewModel.action.send(.renameSimpleVideo(
                            file: file,
                            newName: viewModel.state.newFileName
                        ))
                    }
                }
                .disabled(viewModel.state.newFileName.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 200)
    }
}
