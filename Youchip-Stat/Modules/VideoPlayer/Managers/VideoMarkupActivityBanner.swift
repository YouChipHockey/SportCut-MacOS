//
//  VideoMarkupActivityBanner.swift
//  Youchip-Stat
//

import SwiftUI

struct VideoMarkupHistoryItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isSaved: Bool
}

struct VideoMarkupRecordingItem: Identifiable, Equatable {
    let id = UUID()
    let tagName: String
}

@MainActor
final class VideoMarkupActivityBanner: ObservableObject {
    static let shared = VideoMarkupActivityBanner()
    
    @Published var isHistoryEnabled: Bool
    @Published private(set) var toastText = ""
    @Published private(set) var toastVisible = false
    @Published private(set) var historyItems: [VideoMarkupHistoryItem] = []
    @Published private(set) var activeRecordings: [VideoMarkupRecordingItem] = []
    
    private var hideToastTask: DispatchWorkItem?
    private let historyEnabledKey = "VideoMarkupHistoryEnabled"
    
    private init() {
        if UserDefaults.standard.object(forKey: historyEnabledKey) == nil {
            self.isHistoryEnabled = true
        } else {
            self.isHistoryEnabled = UserDefaults.standard.bool(forKey: historyEnabledKey)
        }
    }
    
    func startIntervalRecording(tagName: String) {
        if !activeRecordings.contains(where: { $0.tagName == tagName }) {
            activeRecordings.insert(VideoMarkupRecordingItem(tagName: tagName), at: 0)
        }
        showTransientToast(String.Titles.videoMarkupToastIntervalRecording.format(tagName), addToHistory: false)
    }
    
    func cancelIntervalRecording(tagName: String? = nil) {
        if let tagName {
            activeRecordings.removeAll { $0.tagName == tagName }
        } else {
            activeRecordings.removeAll()
        }
    }
    
    func completeIntervalRecording(tagName: String) {
        activeRecordings.removeAll { $0.tagName == tagName }
        let savedText = String.Titles.videoMarkupToastIntervalSaved.format(tagName)
        showTransientToast(savedText, addToHistory: false)
        appendToHistory(text: savedText, isSaved: true)
    }
    
    func notifyInstantTagAdded(tagName: String) {
        let text = String.Titles.videoMarkupToastTagAdded.format(tagName)
        showTransientToast(text, addToHistory: false)
        appendToHistory(text: text, isSaved: true)
    }
    
    func setHistoryEnabled(_ enabled: Bool) {
        isHistoryEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: historyEnabledKey)
    }
    
    private func showTransientToast(_ text: String, addToHistory: Bool) {
        cancelToastHide()
        toastText = text
        toastVisible = true
        if addToHistory {
            appendToHistory(text: text, isSaved: true)
        }
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

    private func appendToHistory(text: String, isSaved: Bool) {
        let item = VideoMarkupHistoryItem(text: text, isSaved: isSaved)
        historyItems.insert(item, at: 0)
        if historyItems.count > 12 {
            historyItems.removeLast(historyItems.count - 12)
        }
    }
}

struct VideoMarkupActivityOverlay: View {
    @ObservedObject private var banner = VideoMarkupActivityBanner.shared
    
    private var limitedHistoryItems: [VideoMarkupHistoryItem] {
        Array(banner.historyItems.prefix(8))
    }
    
    private func textOpacity(for index: Int) -> Double {
        max(0.25, 1.0 - (Double(index) * 0.12))
    }
    
    @ViewBuilder
    private func recordingRow(_ item: VideoMarkupRecordingItem) -> some View {
        HStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let opacity = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 5.0))
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(opacity)
            }
            .frame(width: 8, height: 8)
            Text("REC: \(item.tagName)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.red.opacity(0.7), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    @ViewBuilder
    private func historyRow(_ item: VideoMarkupHistoryItem, index: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 6, height: 6)
            Text(item.text)
                .font(.system(size: 11, weight: index == 0 ? .semibold : .regular))
                .foregroundColor(.white.opacity(textOpacity(for: index)))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    var body: some View {
        GeometryReader { geo in
            if banner.isHistoryEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(banner.activeRecordings) { item in
                        recordingRow(item)
                    }
                    
                    ForEach(limitedHistoryItems.indices, id: \.self) { index in
                        historyRow(limitedHistoryItems[index], index: index)
                    }
                    
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.top, 12)
                .frame(
                    width: min(geo.size.width * 0.34, 340),
                    height: min(geo.size.height / 3.0, 220),
                    alignment: .topLeading
                )
                .animation(.easeInOut(duration: 0.22), value: banner.historyItems)
                .animation(.easeInOut(duration: 0.22), value: banner.activeRecordings)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
            } else {
                EmptyView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct VideoMarkupInlineStatusView: View {
    @ObservedObject private var banner = VideoMarkupActivityBanner.shared
    
    var body: some View {
        Group {
            if banner.toastVisible && !banner.toastText.isEmpty {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 6, height: 6)
                    Text(banner.toastText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: banner.toastVisible)
    }
}
