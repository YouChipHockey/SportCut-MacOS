//
//  ReportWindow.swift
//  Youchip-Stat
//
//  Created by AI Assistant on 22/09/25.
//

import SwiftUI
import WebKit
import Cocoa

struct WebViewWrapper: NSViewRepresentable {
    let htmlString: String
    
    func makeNSView(context: Context) -> WKWebView {
        let webViewConfig = WKWebViewConfiguration()
        webViewConfig.suppressesIncrementalRendering = true
        webViewConfig.allowsAirPlayForMediaPlayback = false
        webViewConfig.mediaTypesRequiringUserActionForPlayback = .all
        
        let webView = WKWebView(frame: .zero, configuration: webViewConfig)
        webView.loadHTMLString(htmlString, baseURL: nil)
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        
    }
}
