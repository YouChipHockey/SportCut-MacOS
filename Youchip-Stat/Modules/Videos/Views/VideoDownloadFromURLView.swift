//
//  VideoDownloadFromURLView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 22.01.2026.
//

import SwiftUI

struct VideoDownloadFromURLView: View {
    
    @EnvironmentObject var viewModel: VideosViewModel
    @StateObject private var downloadManager = VideoDownloadManager.shared
    @StateObject private var permissionManager = DownloadsFolderPermissionManager.shared
    
    @State private var videoURL: String = ""
    @State private var selectedQuality: VideoQuality?
    @State private var useServerVideoName: Bool = false
    
    private let selectedFormat = "mp4" // Всегда используем mp4
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            ScrollView {
                VStack(spacing: 20) {
                    contentView
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            
            footerView
        }
        .frame(minWidth: 550, maxWidth: 550, minHeight: 450, maxHeight: 650)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            _ = permissionManager.checkDownloadsAccess()
            NotificationCenter.default.post(name: NSNotification.Name("AddLineSheetAppeared"), object: nil)
        }
        .onDisappear {
            NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "link.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 20))
                
                Text(^String.Titles.downloadVideoFromURL)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            Text(^String.Titles.downloadVideoFromURLDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            permissionStatusBanner
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }
    
    private var permissionStatusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: permissionManager.hasDownloadsAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(permissionManager.hasDownloadsAccess ? .green : .orange)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(permissionManager.hasDownloadsAccess 
                     ? ^String.Titles.downloadsFolderAccessGranted 
                     : ^String.Titles.downloadsFolderAccessRequired)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                if !permissionManager.hasDownloadsAccess {
                    Text(^String.Titles.downloadsFolderAccessDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if !permissionManager.hasDownloadsAccess {
                Button(action: {
                    permissionManager.openSystemPreferences()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                        Text(^String.Titles.openSystemSettings)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    _ = permissionManager.checkDownloadsAccess()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(12)
        .background(
            permissionManager.hasDownloadsAccess 
                ? Color.green.opacity(0.1) 
                : Color.orange.opacity(0.1)
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    permissionManager.hasDownloadsAccess 
                        ? Color.green.opacity(0.3) 
                        : Color.orange.opacity(0.3), 
                    lineWidth: 1
                )
        )
        .padding(.top, 12)
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch downloadManager.downloadState {
        case .idle, .fetchingFormats:
            urlInputView
            
        case .selectingQuality:
            qualitySelectionView
            
        case .downloading(let progress):
            downloadingView(progress: progress)
            
        case .completed:
            completedView
            
        case .error(let message):
            errorView(message: message)
        }
    }
    
    private var urlInputView: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.videoURL)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                TextField(^String.Titles.enterVideoURL, text: $videoURL)
                    .textFieldStyle(ModernTextFieldStyle())
                    .disabled(downloadManager.downloadState == .fetchingFormats)
            }
            
            if downloadManager.downloadState == .fetchingFormats {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text(^String.Titles.fetchingVideoInfo)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
    }
    
    private var qualitySelectionView: some View {
        VStack(spacing: 16) {
            if let title = downloadManager.videoTitle {
                VStack(alignment: .leading, spacing: 4) {
                    Text(^String.Titles.videoTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $useServerVideoName) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(^String.Titles.useServerVideoName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text(^String.Titles.useServerVideoNameDescription)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(CheckboxToggleStyle())
            }
            .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.selectQuality)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                VStack(spacing: 8) {
                    ForEach(downloadManager.availableQualities) { quality in
                        Button(action: {
                            selectedQuality = quality
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(quality.displayName)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    Text(quality.displaySize)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if selectedQuality?.id == quality.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 18))
                                }
                            }
                            .padding(12)
                            .background(
                                selectedQuality?.id == quality.id
                                    ? Color.blue.opacity(0.1)
                                    : Color(NSColor.controlBackgroundColor)
                            )
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        selectedQuality?.id == quality.id
                                            ? Color.blue
                                            : Color(NSColor.separatorColor),
                                        lineWidth: selectedQuality?.id == quality.id ? 2 : 1
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
    
    private func downloadingView(progress: Double) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            VStack(spacing: 8) {
                Text(^String.Titles.downloadingVideo)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
            
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var completedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            VStack(spacing: 8) {
                Text(^String.Titles.videoDownloaded)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(^String.Titles.videoDownloadedDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            VStack(spacing: 8) {
                Text(^String.Titles.error)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var footerView: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                Button(action: {
                    handleCancel()
                }) {
                    Text(cancelButtonTitle)
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
                    handlePrimaryAction()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: primaryButtonIcon)
                            .font(.system(size: 14, weight: .medium))
                        Text(primaryButtonTitle)
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [primaryButtonColor, primaryButtonColor.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: primaryButtonColor.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!isPrimaryButtonEnabled)
                .opacity(isPrimaryButtonEnabled ? 1.0 : 0.6)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var cancelButtonTitle: String {
        switch downloadManager.downloadState {
        case .downloading:
            return ^String.Titles.cancelButtonTitle
        default:
            return ^String.Titles.closeButtonTitle
        }
    }
    
    private var primaryButtonTitle: String {
        switch downloadManager.downloadState {
        case .idle, .fetchingFormats:
            return ^String.Titles.fetchFormats
        case .selectingQuality:
            return ^String.Titles.downloadButtonTitle
        case .downloading:
            return ^String.Titles.downloadingVideo
        case .completed:
            return ^String.Titles.continueButtonTitle
        case .error:
            return ^String.Titles.tryAgain
        }
    }
    
    private var primaryButtonIcon: String {
        switch downloadManager.downloadState {
        case .idle, .fetchingFormats:
            return "info.circle"
        case .selectingQuality, .downloading:
            return "arrow.down.circle"
        case .completed:
            return "arrow.right.circle"
        case .error:
            return "arrow.clockwise"
        }
    }
    
    private var primaryButtonColor: Color {
        switch downloadManager.downloadState {
        case .completed:
            return .green
        case .error:
            return .orange
        default:
            return .blue
        }
    }
    
    private var isPrimaryButtonEnabled: Bool {
        switch downloadManager.downloadState {
        case .idle:
            return !videoURL.isEmpty && permissionManager.hasDownloadsAccess
        case .fetchingFormats, .downloading:
            return false
        case .selectingQuality:
            return selectedQuality != nil && permissionManager.hasDownloadsAccess
        case .completed, .error:
            return true
        }
    }
    
    private func handleCancel() {
        switch downloadManager.downloadState {
        case .downloading:
            viewModel.action.send(.cancelVideoDownload)
        default:
            downloadManager.reset()
            viewModel.state.showDownloadFromURLSheet = false
        }
    }
    
    private func handlePrimaryAction() {
        switch downloadManager.downloadState {
        case .idle, .fetchingFormats:
            viewModel.action.send(.fetchVideoFormats(urlString: videoURL, ext: selectedFormat))
            
        case .selectingQuality:
            if let quality = selectedQuality {
                viewModel.action.send(.downloadVideoFromURL(quality: quality))
            }
            
        case .completed:
            if let url = viewModel.state.downloadedVideoURL {
                viewModel.state.showDownloadFromURLSheet = false
                
                if useServerVideoName {
                    viewModel.action.send(.addDownloadedVideoWithServerName(url: url, serverTitle: downloadManager.videoTitle))
                } else {
                    viewModel.state.videoMetadata = VideoMetadata(url: url)
                    viewModel.state.showMetadataSheet = true
                }
                
                viewModel.state.downloadedVideoURL = nil
                downloadManager.reset()
            }
            
        case .error:
            downloadManager.reset()
            
        case .downloading:
            break
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .blue : .secondary)
                .font(.system(size: 20))
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            
            configuration.label
        }
        .contentShape(Rectangle())
        .onTapGesture {
            configuration.isOn.toggle()
        }
    }
}
