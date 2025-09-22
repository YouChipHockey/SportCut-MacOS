//
//  ImageDocument.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }

    var image: NSImage

    init(image: NSImage) {
        self.image = image
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let image = NSImage(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.image = image
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let imageData = image.pngData() else {
            throw CocoaError(.fileWriteUnknownError)
        }
        return FileWrapper(regularFileWithContents: imageData)
    }
}
