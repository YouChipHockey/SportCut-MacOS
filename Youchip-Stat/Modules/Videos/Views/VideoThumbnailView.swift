//
//  VideoThumbnailView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import SwiftUI

struct VideoThumbnailView: View {
    
    let file: FilesFile
    let viewModel: VideosViewModel
    
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Color.black
                
                if let image = viewModel.filesPreviewManager.getThumbnail(for: file.url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 100)
                        .background(Color.black)
                }
            }
            .frame(width: 150, height: 100)
            .cornerRadius(10)
            
            Text(file.name)
                .font(.caption)
                .frame(width: 150, height: 40)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
        }
        .frame(width: 150)
        .onTapGesture {
            viewModel.action.send(.openVideo(file: file))
        }
        .contextMenu {
            Button(role: .destructive) {
                viewModel.action.send(.deleteFile(file: file))
            } label: {
                Label(^String.ButtonTitles.deleteButtonTitle, systemImage: AppImage.sfTrash.rawValue)
            }
        }
    }
}
