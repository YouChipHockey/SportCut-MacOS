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
    
    var body: some View {
        VStack {
            ZStack {
                if let image = viewModel.filesPreviewManager.getThumbnail(for: file.url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 150, height: 100)
                        .cornerRadius(8)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 150, height: 100)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    viewModel.action.send(.openVideo(id: id))
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 0)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .contextMenu {
                Button(action: {
                    viewModel.action.send(.openVideo(id: id))
                }) {
                    HStack {
                        Image(systemName: "play")
                        Text("Открыть")
                    }
                }
                
                Button(action: {
                    viewModel.action.send(.showRenameSheet(file: file))
                }) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Переименовать")
                    }
                }
                
                Button(action: {
                    viewModel.action.send(.deleteFile(file: file))
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Удалить")
                    }
                }
                .foregroundColor(.red)
            }
            
            Text(file.name)
                .font(.caption)
                .lineLimit(2)
                .frame(width: 150)
                .multilineTextAlignment(.center)
        }
    }
}
