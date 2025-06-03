//
//  EditorViewModel.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 05.08.2024.
//

import Foundation
import Combine
import SwiftUI

class EditorViewModel: ObservableObject {
    
    @Published var state: EditorState
    @Published var webView: EditorWebView?
    @Published var currentItem: Int = 0 {
        willSet {
            updateImages()
        }
    }
    
    private let filePicker = FilesDocumentPickerHelper()
    
    private var onImageExported: ((String) -> Void)?
    private var currentAction: EditorAction = .close
    
    let action = PassthroughSubject<EditorAction, Never>()
    private var observables: [AnyCancellable] = []
    private var exportImageTimer: DispatchWorkItem?
    
    var endHandler: ((URL) -> Void)?
    
    init(file: URL, screenshotsFolder: URL, endHandler: ((URL) -> Void)? = nil) {
        let fileManager = FileManager.default
        let destinationURL = URL.appTemporaryDirectory.appendingPathComponent(file.lastPathComponent).fixedFile()
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }
        
        let bufferFile: URL
        if (try? fileManager.copyItem(at: file, to: destinationURL)) != nil {
            bufferFile = destinationURL
        } else {
            bufferFile = file
        }
        
        self.state = EditorState(inputFile: file, bufferFile: bufferFile, image: NSImage(contentsOf: file) ?? NSImage(resource: .trialLogo), screenshotsFolder: screenshotsFolder)
        self.endHandler = endHandler
        self.webView = if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            EditorWebView(
                viewModel: EditorWebViewModel(
                    url: url,
                    imageUrl: file,
                    isDrawing: false,
                    onImageExported: { [weak self] base64Image in
                        DispatchQueue.main.async { [weak self] in
                            self?.exportImageTimer?.cancel()
                            self?.state.showHUD = false
                            if base64Image.isEmpty {
                                return
                            }
                            guard self?.makeImage(base64String: base64Image) == true else { return }
                            
                            self?.update()
                            self?.handleActionAfterGetImage()
                        }
                    },
                    onError: { [weak self] error in
                        self?.handleActionAfterGetImageWithError(error: error)
                    }
                )
            )
        } else {
            nil
        }
        
        action
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                self?.handleAction(action)
            }
            .store(in: &observables)
    }
    
    deinit {
        observables.removeAll()
        webView?.webView.stopLoading()
        webView?.webView.navigationDelegate = nil
        webView?.webView.uiDelegate = nil
        webView?.webView.configuration.userContentController.removeScriptMessageHandler(forName: "imageExport")
    }
    
    private func update() {
        updateUI(url: state.bufferFile)
    }
    
    private func updateUI(url: URL) {
        state.bufferFile = url
        if let image = NSImage(contentsOf: url) { state.image = image }
        updateWebView()
    }
    
    private func updateWebView() {
        self.webView?.viewModel.imageUrl = state.bufferFile
    }
    
    private func updateImages() {
        self.currentAction = .changeImage(item: currentItem)
        callExportImageWithTimeout()
    }
    
    private func handleActionAfterGetImage() {
        state.showHUD = false
        
        switch currentAction {
        case .share:
            share()
        case .save:
            saveFile()
        case .changeImage(_):
            break
        case .download:
            downloadFile()
        case .close:
            close()
        default:
            break
        }
    }
    
    private func handleActionAfterGetImageWithError(error: String? = nil) {
        state.showHUD = false
        action.send(.showError(error: error ?? "Что то пошло не так"))
        
        switch currentAction {
        case .close:
            close()
        default:
            break
        }
    }

    private func callExportImageWithTimeout() {
        webView?.callExportImage()

        exportImageTimer = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.handleActionAfterGetImageWithError()
            }
        }

        if let timer = exportImageTimer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timer)
        }
    }

    private func share() {
        state.showPicker.toggle()
    }
    
    private func close() {
        endHandler?(state.bufferFile)
        state.shouldDissmis = true
    }
    
    private func makeImage(base64String: String) -> Bool {
        guard let imageData = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            return false
        }
        
        do {
            try imageData.write(to: state.bufferFile)
            return true
        } catch {
            state.errorTitle = error.localizedDescription
            state.showError = true
            return false
        }
    }
    
    private func handleAction(_ action: EditorAction) {
        currentAction = action
        switch action {
        case .showSuccess(let result):
            state.showSubscriptionsSuccessSheet = result
        case .showError(let error):
            state.errorTitle = error
            state.showError = true
        case .showInfo(let info):
            state.infoTitle = info
            state.showInfo = true
        default:
            state.showHUD = true
            callExportImageWithTimeout()
        }
    }
    
    private func downloadFile() {
        saveFile()
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.nameFieldStringValue = state.bufferFile.lastPathComponent
        savePanel.allowedContentTypes = [.jpeg, .png]
        
        savePanel.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .OK, let url = savePanel.url {
                self.createFileInSystem(file: url)
            }
        }
    }
    
    private func saveFile() {
        let fileManager = FileManager.default
        do {
            guard let image = NSImage(contentsOf: state.bufferFile),
                  let imageData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: imageData),
                  let data = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "EditorError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not get image data"])
            }
            
            try data.write(to: state.inputFile)
            state.image = image
            state.infoTitle = "Файл успешно сохранен"
            state.showInfo = true
        } catch {
            state.errorTitle = error.localizedDescription
            state.showError = true
        }
    }

    private func createFileInSystem(file: URL) {
        let fileManager = FileManager.default
        do {
            try fileManager.copyItem(at: state.bufferFile, to: file)
            self.state.infoTitle = "Файл успешно сохранен"
            self.state.showInfo = true
        } catch {
            self.state.errorTitle = error.localizedDescription
            self.state.showError = true
        }
    }
    
    private func convertImageToBase64(image: NSImage?) -> String? {
        guard let image = image, let imageData = image.tiffRepresentation else {
            return nil
        }
        let base64String = imageData.base64EncodedString(options: [])
        return base64String
    }
    
}

struct ScreenshotNameSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var screenshotName: String = ""
    let onSave: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Название скриншота")
                .font(.headline)
            
            FocusAwareTextField(text: $screenshotName, placeholder: "Введите название")
                .padding()
            
            HStack {
                Button("Отмена") {
                    NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
                    presentationMode.wrappedValue.dismiss()
                }
                
                Button("Сохранить") {
                    if !screenshotName.isEmpty {
                        onSave(screenshotName)
                    } else {
                        onSave("Screenshot_\(Int(Date().timeIntervalSince1970))")
                    }
                    NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(screenshotName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            NotificationCenter.default.post(name: NSNotification.Name("AddLineSheetAppeared"), object: nil)
        }
    }
}
