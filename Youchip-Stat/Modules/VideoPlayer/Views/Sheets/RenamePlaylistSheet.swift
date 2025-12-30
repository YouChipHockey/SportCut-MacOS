//
//  RenamePlaylistSheet.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 30.12.2025.
//

import SwiftUI

struct RenamePlaylistSheet: View {
    @State var playlistName: String = ""
    let onCancel: () -> Void
    let onRename: (String) -> Void
    
    init(onCancel: @escaping () -> Void, onRename: @escaping (String) -> Void) {
        self.onCancel = onCancel
        self.onRename = onRename
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(^String.Titles.renamePlaylist)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text(^String.Titles.enterName)
                TextField(^String.Titles.newName, text: $playlistName)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(minWidth: 300)
            
            HStack {
                Button(^String.Titles.cancel) {
                    onCancel()
                }
                Spacer()
                Button(^String.Titles.rename) {
                    onRename(playlistName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(playlistName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 350, height: 180)
    }
}
