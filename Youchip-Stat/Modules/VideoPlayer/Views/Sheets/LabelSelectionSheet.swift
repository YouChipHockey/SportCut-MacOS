//
//  LabelSelectionSheet.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct LabelSelectionSheet: View {
    
    let stampName: String
    let initialLabels: [String]
    let tag: Tag?
    let tagLibrary: TagLibraryManager
    var isDop: Bool = false
    let onDone: ([String]) -> Void
    
    @State private var selectedLabels: Set<String> = []
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var hotkeyManager = HotKeyManager.shared
    @State private var markupMode = MarkupMode.current
    @ObservedObject var timelineData = TimelineDataManager.shared
    @State private var hotkeyObserver: Any? = nil
    @State private var keyEventMonitor: Any? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if markupMode == .tagBased && tag != nil {
                Text("\(^String.Titles.labelSheetInfoTagAdd) \(tag?.name ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            } else if markupMode == .standard && timelineData.selectedLineID == nil {
                Text(^String.Titles.labelSheetErrorNoTimeline)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(.bottom, 4)
            }
            
            Text("\(^String.Titles.labelSheetTimestamp) \(stampName)")
                .font(.headline)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(filteredLabelGroups) { group in
                        DisclosureGroup(isExpanded: .constant(true)) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)],
                                spacing: 16
                            ) {
                                ForEach(group.lables, id: \.self) { labelID in
                                    if let label = tagLibrary.findLabelById(labelID) {
                                        Button {
                                            if selectedLabels.contains(label.id) {
                                                selectedLabels.remove(label.id)
                                            } else {
                                                selectedLabels.insert(label.id)
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(
                                                    systemName: selectedLabels.contains(label.id)
                                                    ? "checkmark.square"
                                                    : "square"
                                                )
                                                Text(label.name)
                                                    .lineLimit(1)
                                                    .font(.system(size: 12))
                                                
                                                if let tagHotkeys = tag?.labelHotkeys,
                                                   let hotkey = tagHotkeys[label.id], !hotkey.isEmpty {
                                                    Spacer()
                                                    Text(hotkey)
                                                        .font(.system(size: 9, weight: .light))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.black.opacity(0.15))
                                                        .cornerRadius(3)
                                                }
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(selectedLabels.contains(label.id)
                                                        ? Color.blue.opacity(0.2)
                                                        : Color.gray.opacity(0.1))
                                            .cornerRadius(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                }
                            }
                        } label: {
                            Text(group.name)
                                .font(.subheadline)
                                .bold()
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button(^String.Titles.collectionsButtonCancel) {
                    dismissSheet()
                }
                Button(^String.Titles.collectionsButtonAdd) {
                    completeSelection()
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: isDop ? 0 : 400)
        .onAppear {
            selectedLabels = Set(initialLabels)
            setupLabelHotkeys()
            setupEnterKeyMonitor()
            markupMode = MarkupMode.current
        }
        .onDisappear {
            cleanupHotkeys()
            removeEnterKeyMonitor()
        }
    }
    
    var filteredLabelGroups: [LabelGroupData] {
        if let tag = tag {
            return tagLibrary.allLabelGroups.filter { tag.lablesGroup.contains($0.id) }
        } else {
            return tagLibrary.allLabelGroups
        }
    }
    
    private func setupLabelHotkeys() {
        hotkeyManager.enableLabelHotkeyMode()
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .labelHotkeyPressed,
            object: nil,
            queue: .main
        ) { notification in
            if let labelInfo = notification.object as? (labelId: String, tagId: String),
               labelInfo.tagId == tag?.id {
                if selectedLabels.contains(labelInfo.labelId) {
                    selectedLabels.remove(labelInfo.labelId)
                } else {
                    selectedLabels.insert(labelInfo.labelId)
                }
            }
        }
    }
    
    private func setupEnterKeyMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 36 || event.keyCode == 76 {
                completeSelection()
                return nil
            }
            return event
        }
    }
    
    private func removeEnterKeyMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }
    
    private func cleanupHotkeys() {
        hotkeyManager.disableLabelHotkeyMode()
        if let observer = hotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
            hotkeyObserver = nil
        }
    }
    
    private func dismissSheet() {
        presentationMode.wrappedValue.dismiss()
    }
    
    private func completeSelection() {
        onDone(Array(selectedLabels))
        dismissSheet()
    }
    
}
