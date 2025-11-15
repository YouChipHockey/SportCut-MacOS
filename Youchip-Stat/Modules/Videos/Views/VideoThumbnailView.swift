//
//  VideoThumbnailView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import SwiftUI

struct VideoThumbnailView: View {
    let file: FilesFile
    let id: String
    let viewModel: VideosViewModel
    
    @State private var isHovered = false
    @State private var isFavorite: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(
                        color: isHovered ? Color.black.opacity(0.15) : Color.black.opacity(0.08),
                        radius: isHovered ? 8 : 4,
                        x: 0,
                        y: isHovered ? 4 : 2
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isHovered ? Color.blue.opacity(0.3) : Color.clear,
                                lineWidth: 2
                            )
                    )
                
                VStack(spacing: 0) {
                    ZStack {
                        if file.isBroken {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.red.opacity(0.3),
                                            Color.red.opacity(0.1)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: 120)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(.orange)
                                        Text(^String.Titles.videoUnavailable)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                )
                        } else if let image = viewModel.filesPreviewManager.getThumbnail(for: file.url) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 120)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.gray.opacity(0.3),
                                            Color.gray.opacity(0.1)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: 120)
                        }
                        
                        ZStack {
                            Rectangle()
                                .fill(Color.black.opacity(0.3))
                                .opacity(isHovered ? 1 : 0)
                                .animation(.easeInOut(duration: 0.2), value: isHovered)
                            
                            Button(action: {
                                if file.isBroken {
                                    viewModel.action.send(.showRebindAlert(file: file))
                                } else {
                                    viewModel.action.send(.openVideo(id: id))
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.9))
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                    
                                    Image(systemName: file.isBroken ? "arrow.triangle.2.circlepath" : "play.fill")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(file.isBroken ? .orange : .blue)
                                        .offset(x: file.isBroken ? 0 : 2)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .scaleEffect(isHovered ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: isHovered)
                        }
                    }
                    .clipShape(
                        RoundedRectangle(cornerRadius: 12)
                    )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(file.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            if isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.yellow)
                                    .shadow(color: .orange.opacity(0.3), radius: 1, x: 0, y: 0)
                            }
                        }
                        
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                
                                Text(formatDate(file.dateOpened))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if let url = file.url {
                                Text(formatFileSize(url))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .frame(width: 200)
            .onHover { hovering in
                isHovered = hovering
            }
            .contextMenu {
                contextMenuContent
            }
            .onAppear {
                updateFavoriteState()
            }
            .onChange(of: viewModel.state.files) { _ in
                updateFavoriteState()
            }
        }
    }
    
    private var contextMenuContent: some View {
        Group {
            if file.isBroken {
                Button(action: {
                    viewModel.action.send(.showRebindAlert(file: file))
                }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                        Text(^String.Titles.rebindVideo)
                    }
                }
            } else {
                Button(action: {
                    viewModel.action.send(.openVideo(id: id))
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                            .foregroundColor(.blue)
                        Text(^String.Titles.openButtonTitle)
                    }
                }
            }
            
            Divider()
            
            Button(action: {
                viewModel.action.send(.toggleFavorite(file: file))
            }) {
                HStack {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundColor(.yellow)
                    Text(isFavorite ? ^String.Titles.removeFromFavorites : ^String.Titles.addToFavorites)
                }
            }
            
            Divider()
            
            Button(action: {
                viewModel.action.send(.showRenameSheet(file: file))
            }) {
                HStack {
                    Image(systemName: "pencil")
                        .foregroundColor(.orange)
                    Text(^String.Titles.renameButtonTitle)
                }
            }
            
            Divider()
            
            Button(action: {
                viewModel.action.send(.exportProject(file: file))
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.green)
                    Text(^String.Titles.exportProject)
                }
            }
            
            Divider()
            
            Button(action: {
                viewModel.action.send(.deleteFile(file: file))
            }) {
                HStack {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                    Text(^String.Titles.delete)
                }
            }
        }
    }
    
    private func updateFavoriteState() {
        if let updatedFile = viewModel.state.files.first(where: { $0.id == file.id }) {
            let newFavoriteState = viewModel.filesManager.isFavorite(updatedFile)
            if isFavorite != newFavoriteState {
                print("Updating favorite state for \(file.name): \(isFavorite) -> \(newFavoriteState)")
                isFavorite = newFavoriteState
            }
        } else {
            let newFavoriteState = viewModel.filesManager.isFavorite(file)
            if isFavorite != newFavoriteState {
                print("Updating favorite state for \(file.name) (fallback): \(isFavorite) -> \(newFavoriteState)")
                isFavorite = newFavoriteState
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: date)
    }
    
    private func formatFileSize(_ url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
        } catch {
             
        }
        return ""
    }
}
