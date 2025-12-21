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
    
    @State private var selectedItems: Set<String> = []
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var hotkeyManager = HotKeyManager.shared
    @State private var markupMode = MarkupMode.current
    @ObservedObject var timelineData = TimelineDataManager.shared
    @State private var hotkeyObserver: Any? = nil
    
    private var filteredLabelGroups: [LabelGroupData] {
        if let tag = tag {
            return tagLibrary.allLabelGroups.filter { tag.lablesGroup.contains($0.id) }
        } else {
            return tagLibrary.allLabelGroups
        }
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
        
        // Initialize timeEvents
        guard let tag else {
            timeEvents = []
            return
        }
        let userCollections = UserDefaults.standard.getCollectionBookmarks()
        for collection in userCollections {
            let collectionManager = CustomCollectionManager()
            if collectionManager.loadCollectionFromBookmarks(named: collection.name),
               collectionManager.tags.contains(where: { $0.id == tag.id })
            {
                timeEvents = collectionManager.timeEvents
                return
            }
        }
        for standardCollection in tagLibrary.standardCollections {
            if standardCollection.tags.contains(where: { $0.id == tag.id }) {
                timeEvents = standardCollection.timeEvents
                return
            }
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
        .onAppear {
            selectedItems = Set(initialIds)
            setupLabelHotkeys()
            markupMode = MarkupMode.current
        }
        .onDisappear {
            cleanupHotkeys()
        }
    }
    
    // MARK: - Helpers
    
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
                                    if selectedItems.contains(label.id) {
                                        selectedItems.remove(label.id)
                                    } else {
                                        selectedItems.insert(label.id)
                                    }
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
                            if selectedItems.contains(event.id) {
                                selectedItems.remove(event.id)
                            } else {
                                selectedItems.insert(event.id)
                            }
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
                if selectedItems.contains(labelInfo.labelId) {
                    selectedItems.remove(labelInfo.labelId)
                } else {
                    selectedItems.insert(labelInfo.labelId)
                }
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
        onDone(Array(selectedItems))
        presentationMode.wrappedValue.dismiss()
    }
    
}
