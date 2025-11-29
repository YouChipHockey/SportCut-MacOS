//
//  ProjectImportView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import SwiftUI
import AppKit

struct ProjectImportView: View {
    @ObservedObject var viewModel: VideosViewModel
    @State private var selectedVideoURL: URL? = nil
    @State private var videoBookmark: Data? = nil
    @State private var projectName: String = ""
    
    let projectData: ProjectImportModel
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(^String.Titles.projectImportTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(projectData.projectName)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(^String.Titles.projectImportTeam1)
                        .fontWeight(.medium)
                    Text(projectData.videoMetadata.team1)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text(^String.Titles.projectImportTeam2)
                        .fontWeight(.medium)
                    Text(projectData.videoMetadata.team2)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text(^String.Titles.projectImportScore)
                        .fontWeight(.medium)
                    Text(projectData.videoMetadata.score)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text(^String.Titles.projectImportCreationDate)
                        .fontWeight(.medium)
                    Text(projectData.videoMetadata.dateTime, style: .date)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text(^String.Titles.projectImportTimelinesCount)
                        .fontWeight(.medium)
                    Text("\(projectData.timelines.count)")
                        .foregroundColor(.secondary)
                }
                
                if let customName = projectData.customName {
                    HStack {
                        Text(^String.Titles.projectImportCustomName)
                            .fontWeight(.medium)
                        Text(customName)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 12) {
                Text(^String.Titles.projectImportVideoBinding)
                    .font(.headline)
                
                if let videoURL = selectedVideoURL {
                    HStack {
                        Image(systemName: "video.fill")
                            .foregroundColor(.blue)
                        Text(videoURL.lastPathComponent)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(^String.Titles.projectImportChangeVideo) {
                            selectVideoFile()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 12) {
                        Text(^String.Titles.projectImportSelectVideoPrompt)
                            .foregroundColor(.secondary)
                        
                        Button(^String.Titles.projectImportSelectVideo) {
                            selectVideoFile()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(^String.Titles.projectImportCreateWithoutVideo) {
                            createProjectWithoutVideo()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            
            HStack(spacing: 12) {
                Button(^String.Titles.cancelButtonTitle) {
                    viewModel.action.send(.showProjectImportSheet(projectData: projectData))
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if selectedVideoURL != nil {
                    Button(^String.Titles.projectImportCreateProject) {
                        createProjectWithVideo()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 500, height: 600)
    }
    
    private func createProjectWithVideo() {
        guard let videoBookmark = videoBookmark else { return }
        viewModel.action.send(.createProjectFromImport(projectData: projectData, videoBookmark: videoBookmark))
    }
    
    private func createProjectWithoutVideo() {
        viewModel.action.send(.createProjectFromImport(projectData: projectData, videoBookmark: nil))
    }
    
    private func selectVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                selectedVideoURL = url
                videoBookmark = url.makeBookmark()
            }
        }
    }
}

#Preview {
    let sampleProjectData = ProjectImportModel(
        version: "1.0",
        exportDate: Date(),
        projectName: "Sample Project",
        videoMetadata: VideoMetadata(
            team1: "Team A",
            team2: "Team B",
            score: "2-1",
            url: nil,
            dateTime: Date()
        ),
        timelines: [],
        customName: "Custom Name",
        isFavorite: false,
        projectId: "sample-id",
        customCollection: nil
    )
    
    ProjectImportView(
        viewModel: VideosViewModel(),
        projectData: sampleProjectData
    )
}
