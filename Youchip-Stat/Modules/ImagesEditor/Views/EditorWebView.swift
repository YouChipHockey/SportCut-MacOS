//
//  EditorWebView.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 05.08.2024.
//

import SwiftUI
import WebKit

class EditorWebViewModel: ObservableObject {
    @Published var imageUrl: URL
    let url: URL
    let isDrawing: Bool
    var onError: ((String) -> Void)?
    var onImageExported: ((String) -> Void)?
    
    init(url: URL, imageUrl: URL, isDrawing: Bool, onImageExported: ((String) -> Void)? = nil, onError: ((String) -> Void)? = nil) {
        self.url = url
        self.imageUrl = imageUrl
        self.isDrawing = isDrawing
        self.onImageExported = onImageExported
    }
}

struct EditorWebView: NSViewRepresentable {
    
    @ObservedObject var viewModel: EditorWebViewModel
    let webView: WKWebView
    
    init(viewModel: EditorWebViewModel) {
        self.viewModel = viewModel
        self.webView = WKWebView()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, onImageExported: viewModel.onImageExported, onError: viewModel.onError)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "imageExport")
        webView.configuration.userContentController.add(context.coordinator, name: "imageExport")
        let request = URLRequest(url: viewModel.url)
        webView.load(request)
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        let request = URLRequest(url: viewModel.url)
        nsView.load(request)
        
        context.coordinator.updateImageUrl(viewModel.imageUrl)
    }
    
    func callExportImage() {
        let javascript = """
            document.getElementById('exportButton').click();
        """
        webView.evaluateJavaScript(javascript, completionHandler: { (result, error) in
            if let error = error {
                print("JavaScript evaluation error: \(error)")
            }
        })
    }
    
    class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EditorWebView
        var onImageExported: ((String) -> Void)?
        var onError: ((String) -> Void)?
        var imageUrl: URL
        var isDrawing: Bool
        
        init(_ parent: EditorWebView, onImageExported: ((String) -> Void)?, onError: ((String) -> Void)?) {
            self.parent = parent
            self.onImageExported = onImageExported
            self.onError = onError
            self.imageUrl = parent.viewModel.imageUrl
            self.isDrawing = parent.viewModel.isDrawing
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let task = URLSession.shared.dataTask(with: imageUrl) { data, response, error in
                guard let data = data, error == nil else {
                    self.onError?(error?.localizedDescription ?? "Unknown error")
                    print("Error loading image data: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }

                let base64String = data.base64EncodedString()
                let javascript = """
                    window.postMessage({ type: 'initEditor', imageBase64: 'data:image/png;base64,\(base64String)', isDraw: \(self.isDrawing) }, '*');
                """

                DispatchQueue.main.async {
                    webView.evaluateJavaScript(javascript) { [weak self] (result, error) in
                        if let error = error {
                            self?.onError?(error.localizedDescription)
                            print("JavaScript evaluation error: \(error.localizedDescription)")
                        }
                    }
                }
            }

            task.resume()
        }
        
        func updateImageUrl(_ newUrl: URL) {
            self.imageUrl = newUrl
            parent.webView.reload()
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "imageExport", let body = message.body as? String {
                onImageExported?(body)
            }
        }
        
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.begin { (result) in
                if result == .OK {
                    completionHandler(openPanel.urls)
                } else {
                    completionHandler(nil)
                }
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            return navigationAction.shouldPerformDownload ? decisionHandler(.download, preferences) : decisionHandler(.allow, preferences)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            navigationResponse.canShowMIMEType ? decisionHandler(.allow) : decisionHandler(.download)
        }
    }
}

extension EditorWebView.Coordinator: WKDownloadDelegate {
    
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.nameFieldStringValue = "result.png"
        savePanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.modalPanelWindow)))
        savePanel.begin { (result) in
            if result.rawValue == NSApplication.ModalResponse.OK.rawValue {
                if let url = savePanel.url {
                    completionHandler(url)
                } else {
                    completionHandler(nil)
                }
            } else {
                completionHandler(nil)
            }
        }
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        print("downloaded")
    }
    
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        print("\(error.localizedDescription)")
    }
}
