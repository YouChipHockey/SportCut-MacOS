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
            Text("Переименовать плейлист")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Введите новое имя:")
                TextField("Новое имя", text: $playlistName)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(minWidth: 300)
            
            HStack {
                Button("Отмена") {
                    onCancel()
                }
                Spacer()
                Button("Переименовать") {
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
