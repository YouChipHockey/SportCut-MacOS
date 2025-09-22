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
            // Карточка с превью
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
                    // Превью видео
                    ZStack {
                        if let image = viewModel.filesPreviewManager.getThumbnail(for: file.url) {
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
                        
                        // Overlay с кнопкой воспроизведения
                        ZStack {
                            // Полупрозрачный фон
                            Rectangle()
                                .fill(Color.black.opacity(0.3))
                                .opacity(isHovered ? 1 : 0)
                                .animation(.easeInOut(duration: 0.2), value: isHovered)
                            
                            // Кнопка воспроизведения
                            Button(action: {
                                viewModel.action.send(.openVideo(id: id))
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.9))
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                    
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.blue)
                                        .offset(x: 2) // Небольшое смещение для визуального центрирования
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
                    
                    // Информация о видео
                    VStack(alignment: .leading, spacing: 8) {
                        // Название файла с звездочкой избранного
                        HStack {
                            Text(file.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            // Звездочка избранного
                            if isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.yellow)
                                    .shadow(color: .orange.opacity(0.3), radius: 1, x: 0, y: 0)
                            }
                        }
                        
                        // Метаданные
                        HStack {
                            // Дата
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                
                                Text(formatDate(file.dateOpened))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Размер файла (если доступен)
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
    
    // MARK: - Context Menu
    private var contextMenuContent: some View {
        Group {
            Button(action: {
                viewModel.action.send(.openVideo(id: id))
            }) {
                HStack {
                    Image(systemName: "play.fill")
                        .foregroundColor(.blue)
                    Text(^String.Titles.openButtonTitle)
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
    
    // MARK: - Helper Functions
    private func updateFavoriteState() {
        // Находим обновленный файл в списке
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
            // Игнорируем ошибки
        }
        return ""
    }
}
