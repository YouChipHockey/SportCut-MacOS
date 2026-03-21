//
//  VideoMarkupActivityBanner.swift
//  Youchip-Stat
//

import SwiftUI

@MainActor
final class VideoMarkupActivityBanner: ObservableObject {
    static let shared = VideoMarkupActivityBanner()
    
    @Published private(set) var isIntervalRecording = false
    @Published private(set) var recordingTagName = ""
    @Published private(set) var toastText = ""
    @Published private(set) var toastVisible = false
    
    private var hideToastTask: DispatchWorkItem?
    
    private init() {}
    
    func startIntervalRecording(tagName: String) {
        cancelToastHide()
        isIntervalRecording = true
        recordingTagName = tagName
        toastText = String.Titles.videoMarkupToastIntervalRecording.format(tagName)
        toastVisible = true
    }
    
    func cancelIntervalRecording() {
        isIntervalRecording = false
        recordingTagName = ""
        toastVisible = false
        toastText = ""
        cancelToastHide()
    }
    
    func completeIntervalRecording(tagName: String) {
        isIntervalRecording = false
        recordingTagName = ""
        showTransientToast(String.Titles.videoMarkupToastIntervalSaved.format(tagName))
    }
    
    func notifyInstantTagAdded(tagName: String) {
        showTransientToast(String.Titles.videoMarkupToastTagAdded.format(tagName))
    }
    
    private func showTransientToast(_ text: String) {
        cancelToastHide()
        toastText = text
        toastVisible = true
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.toastVisible = false
            self.toastText = ""
        }
        hideToastTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
    
    private func cancelToastHide() {
        hideToastTask?.cancel()
        hideToastTask = nil
    }
}

struct VideoMarkupActivityOverlay: View {
    @ObservedObject private var banner = VideoMarkupActivityBanner.shared
    
    var body: some View {
        Group {
            if banner.toastVisible && !banner.toastText.isEmpty {
                HStack(alignment: .center, spacing: 10) {
                    if banner.isIntervalRecording {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                            let t = context.date.timeIntervalSinceReferenceDate
                            let opacity = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 5.0))
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                                .opacity(opacity)
                        }
                        .frame(width: 12, height: 12)
                    }
                    
                    Text(banner.toastText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .frame(maxWidth: 300, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 14)
        .padding(.top, 14)
        .allowsHitTesting(false)
    }
}
