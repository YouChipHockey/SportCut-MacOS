//
//  ExportSheet.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ExportSheet: View {
    let image: NSImage
    @Environment(\.presentationMode) var presentationMode
    @State private var showSavePanel = false

    var body: some View {
        VStack(spacing: 20) {
            Text(^String.Titles.exportImage)
                .font(.headline)

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 500, maxHeight: 500)
                .border(Color.gray, width: 1)

            HStack {
                Button(^String.Titles.cancel) {
                    presentationMode.wrappedValue.dismiss()
                }

                Button(^String.Titles.save) {
                    showSavePanel = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .fileExporter(
            isPresented: $showSavePanel,
            document: ImageDocument(image: image),
            contentType: .png,
            defaultFilename: "polygon_export_\(Int(Date().timeIntervalSince1970)).png"
        ) { result in
            switch result {
            case .success(let url):
                print(url)
            case .failure(let error):
                print(error)
            }
            presentationMode.wrappedValue.dismiss()
        }
    }
}
