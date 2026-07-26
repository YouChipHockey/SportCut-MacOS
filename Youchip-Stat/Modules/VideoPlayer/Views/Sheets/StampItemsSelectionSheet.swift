//
//  StampItemsSelectionSheet.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct StampItemsSelectionSheet: View {
    
    let sheetType: StampEditSheetType
    let stampName: String
    let initialIds: [String]
    let tag: Tag?
    let tagLibrary: TagLibraryManager
    var isDop: Bool = false
    let onDone: ([String]) -> Void
    let onCancel: () -> Void
    
    /// Ordered by click — NOT a Set. The pick order is what the user sees later in the
    /// tag info line and the viewer table (it flows through to `stamp.labels`), so it
    /// must be preserved here rather than collapsed into an arbitrary hash order.
    @State private var selectedItems: [String] = []
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var hotkeyManager = HotKeyManager.shared
    @State private var markupMode = MarkupMode.current
    @ObservedObject var timelineData = TimelineDataManager.shared
    @State private var hotkeyObserver: Any? = nil
    
    /// Groups keep the order set in the collection editor rather than being sorted by
    /// name, so the arrangement authored there is what the user sees while tagging.
    private var filteredLabelGroups: [LabelGroupData] {
        if let tag {
            // Optimize using Set for O(1) lookup
            let labelGroupIdsSet = Set(tag.lablesGroup)
            return tagLibrary.allLabelGroups.filter { labelGroupIdsSet.contains($0.id) }
        } else {
            return tagLibrary.allLabelGroups
        }
    }
    
    private var maxSheetContentHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 600) * 0.75
    }
    
    private let timeEvents: [TimeEvent]
    
    init(sheetType: StampEditSheetType, stampName: String, initialIds: [String], tag: Tag?, tagLibrary: TagLibraryManager, isDop: Bool = false, onDone: @escaping ([String]) -> Void, onCancel: @escaping () -> Void) {
        self.sheetType = sheetType
        self.stampName = stampName
        self.initialIds = initialIds
        self.tag = tag
        self.tagLibrary = tagLibrary
        self.isDop = isDop
        self.onDone = onDone
        self.onCancel = onCancel
        
        // Initialize timeEvents - use cached data from TagLibraryManager instead of loading collections
        guard let tag else {
            timeEvents = []
            return
        }
        
        // Fast lookup: check standard collections first (already loaded)
        if let standardCollection = tagLibrary.standardCollections.first(where: { $0.tags.contains(where: { $0.id == tag.id }) }) {
            timeEvents = standardCollection.timeEvents
            return
        }
        
        // Check user collections from cache (already loaded in allTags/allTagGroups)
        // Find which collection contains this tag by checking tagLibrary.allTags
        if tagLibrary.allTags.contains(where: { $0.id == tag.id }) {
            // Tag exists in loaded collections, find timeEvents from allTimeEvents
            // Since we don't know which collection, we'll use all available timeEvents
            // This is faster than loading collections synchronously
            timeEvents = tagLibrary.allTimeEvents
            return
        }
        
        timeEvents = []
    }
    
    
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
                switch sheetType {
                case .lables:
                    stackForLabelsLayout()
                case .timeEvents:
                    stackForTimeEventsLayout()
                }
            }
            .frame(maxHeight: maxSheetContentHeight)
            
            HStack {
                Spacer()
                Button(^String.Titles.collectionsButtonCancel) {
                    dismissSheet()
                }
                Button(^String.Titles.collectionsButtonAdd) {
                    completeSelection()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: isDop ? 0 : 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // Keep the previously stored order; drop any accidental duplicates.
            var seen = Set<String>()
            selectedItems = initialIds.filter { seen.insert($0).inserted }
            setupLabelHotkeys()
            markupMode = MarkupMode.current
        }
        .onDisappear {
            cleanupHotkeys()
        }
    }
    
    // MARK: - Helpers

    /// Toggles an item, appending on select so the pick order is preserved.
    private func toggleSelection(_ id: String) {
        if let index = selectedItems.firstIndex(of: id) {
            selectedItems.remove(at: index)
        } else {
            selectedItems.append(id)
        }
    }

    private func stackForLabelsLayout() -> some View {
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
                                    toggleSelection(label.id)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(
                                            systemName: selectedItems.contains(label.id)
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
                                    .background(selectedItems.contains(label.id)
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
    
    private func stackForTimeEventsLayout() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: .constant(true)) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)],
                    spacing: 16
                ) {
                    ForEach(timeEvents, id: \.self) { event in
                        Button {
                            toggleSelection(event.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(
                                    systemName: selectedItems.contains(event.id)
                                    ? "checkmark.square"
                                    : "square"
                                )
                                Text(event.name)
                                    .lineLimit(1)
                                    .font(.system(size: 12))
                                
                                if let tagHotkeys = tag?.labelHotkeys,
                                   let hotkey = tagHotkeys[event.id], !hotkey.isEmpty {
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
                            .background(selectedItems.contains(event.id)
                                        ? Color.blue.opacity(0.2)
                                        : Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
            } label: {
                Text(^String.Titles.commonEvents)
                    .font(.subheadline)
                    .bold()
            }
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
                toggleSelection(labelInfo.labelId)
            }
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
        onCancel()
        presentationMode.wrappedValue.dismiss()
    }
    
    private func completeSelection() {
        onDone(selectedItems)
        presentationMode.wrappedValue.dismiss()
    }
    
}
