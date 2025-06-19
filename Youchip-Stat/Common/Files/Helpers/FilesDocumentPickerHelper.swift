//
//  FilesDocumentPickerHelper.swift
//  printer
//
//  Created by Сергей Бекезин on 22.08.2024.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Cocoa

enum FileDocumentPickerFileResponse {
    case file(file: URL)
    case fileNotDownloaded(file: URL)
    case fileDownloading
}

enum FileDocumentPickerFilesResponse {
    case files(files: [URL])
    case filesNotDownloaded(files: [URL])
    case filesDownloading
}

class FilesDocumentPickerHelper: NSObject, ObservableObject {
    
    struct Pick: OptionSet {
        
        let rawValue: UInt
        
        static let spreadsheets = Pick(rawValue: 1 << 0)
        static let documents = Pick(rawValue: 1 << 1)
        static let presentations = Pick(rawValue: 1 << 2)
        static let pdf = Pick(rawValue: 1 << 3)
        static let images = Pick(rawValue: 1 << 4)
        static let plainText = Pick(rawValue: 1 << 5)
        static let pages = Pick(rawValue: 1 << 6)
        static let keynote = Pick(rawValue: 1 << 7)
        static let numbers = Pick(rawValue: 1 << 8)
        static let videos = Pick(rawValue: 1 << 9)
        
        static let allFiles: Pick = [spreadsheets, documents, presentations, pdf, images, plainText, pages, keynote, numbers]
        static let convertebleFiles: Pick = [spreadsheets, documents, presentations, pdf, images, plainText]
        static let media: Pick = [images, videos]
        
    }
    
    @Published var selectedURLs: [URL] = []
    @Published var bookmarks: [Data] = []
    var bookmark: Data? = nil
    
    private var completion: CustomTypes.Completion?
    private var multipleFilesCompletion: CustomTypes.MultipleFilesCompletion?
    private var saveCompletion: CustomTypes.CompletionWithResult?
    private var filesManager = VideoFilesManager.shared
    
    func importFile(pick: Pick, completion: @escaping CustomTypes.Completion) {
        self.completion = completion
        presentFilesPicker(pick: pick, allowsMultipleSelection: false)
    }
    
    func importFiles(pick: Pick, multipleFilesCompletion: @escaping CustomTypes.MultipleFilesCompletion) {
        self.multipleFilesCompletion = multipleFilesCompletion
        presentFilesPicker(pick: pick, allowsMultipleSelection: true)
    }
    
    func saveFiles(files: [FilesFile], directoryName: String? = nil, saveCompletion: @escaping CustomTypes.CompletionWithResult) {
        self.saveCompletion = saveCompletion
        presentSavePicker(files: files, directoryName: directoryName)
    }
    
    // MARK: - Helpers
    
    private func presentFilesPicker(pick: Pick, allowsMultipleSelection: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = pick.contentTypes
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.showsResizeIndicator = true
        panel.begin { response in
            if response == .OK {
                self.documentPicker(panel.urls)
            } else {
                self.documentPickerWasCancelled()
            }
        }
    }
    
    private func presentSavePicker(files: [FilesFile], directoryName: String?) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        
        openPanel.begin { [weak self] (result) -> Void in
            if result == NSApplication.ModalResponse.OK {
                if let directoryURL = openPanel.url {
                    do {
                        var newDirectoryUrl = directoryURL
                        if let newDirectoryName = directoryName {
                            try FileManager.default.createDirectory(at: directoryURL.appendingPathComponent(newDirectoryName), withIntermediateDirectories: true, attributes: nil)
                            newDirectoryUrl = directoryURL.appendingPathComponent(newDirectoryName)
                        }
                        for file in files {
                            guard let url = file.url else { continue }
                            let fileURL = newDirectoryUrl.appendingPathComponent(file.lastPathComponent).fixedFile()
                            try FileManager.default.copyItem(at: url, to: fileURL)
                            self?.saveCompletion?(.success(fileURL))
                        }
                    } catch {
                        self?.saveCompletion?(.failure(error))
                    }
                }
            }
        }
    }
    
    private func documentPicker(_ urls: [URL]) {
        if let completion, let url = urls.first {
            if let status = url.ubiquitousStatus, status != .current {
                if url.isDownloading {
                    completion(.fileDownloading)
                } else {
                    completion(.fileNotDownloaded(file: url))
                }
            } else {
                completion(.file(file: url))
            }
        }
        if let multipleFilesCompletion, !urls.isEmpty {
            let notDownloadedFiles = urls.filter { $0.ubiquitousStatus != .current && $0.ubiquitousStatus != nil }
            if notDownloadedFiles.isEmpty {
                multipleFilesCompletion(.files(files: urls))
            } else {
                let notDownloadingFiles = notDownloadedFiles.filter { !$0.isDownloading }
                
                if notDownloadingFiles.isEmpty {
                    multipleFilesCompletion(.filesDownloading)
                } else {
                    multipleFilesCompletion(.filesNotDownloaded(files: notDownloadedFiles))
                }
            }
        }
        
        finishPicking()
    }
    
    private func documentPickerWasCancelled() {
        finishPicking()
    }
    
    private func finishPicking() {
        completion = nil
        multipleFilesCompletion = nil
    }
    
}

@available(macOS 11.0, *)
extension FilesDocumentPickerHelper.Pick {
    
    var contentTypes: [UTType] {
        var contentTypes: [UTType] = []
        if contains(.spreadsheets) {
            contentTypes.append(.spreadsheet)
        }
        if contains(.documents) {
            let types = [UTType(filenameExtension: "doc"), UTType(filenameExtension: "docx")].compactMap { $0 }
            contentTypes.append(contentsOf: types)
        }
        if contains(.presentations) {
            contentTypes.append(.presentation)
        }
        if contains(.pdf) {
            contentTypes.append(.pdf)
        }
        if contains(.images) {
            contentTypes.append(.image)
        }
        if contains(.plainText) {
            contentTypes.append(.plainText)
        }
        if contains(.pages) {
            contentTypes.append(UTType(filenameExtension: "pages")!)
        }
        if contains(.keynote) {
            contentTypes.append(UTType(filenameExtension: "key")!)
        }
        if contains(.numbers) {
            contentTypes.append(UTType(filenameExtension: "numbers")!)
        }
        if contains(.videos) {
            contentTypes.append(.movie)
        }
        return contentTypes
    }
}
