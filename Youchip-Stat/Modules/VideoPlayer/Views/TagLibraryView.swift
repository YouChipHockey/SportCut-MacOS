//
//  TagLibraryView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct TagLibraryView: View {
    
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @ObservedObject var hotkeyManager = HotKeyManager.shared
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    @State private var activeCollection: TagCollection = .standard
    @State private var markupMode = MarkupMode.current
    @State private var showLabelSheet = false
    @State private var selectedTag: Tag? = nil
    @State private var hoveredTagID: String? = nil
    @State private var showUserCollectionsMenu = false
    @State private var userCollections: [CollectionBookmark] = []
    @State private var selectedUserCollection: CollectionBookmark? = nil
    @State private var isUserCollectionActive = false
    @State private var defaultTagGroups: [TagGroup] = []
    @State private var defaultTags: [Tag] = []
    @State private var defaultLabelGroups: [LabelGroupData] = []
    @State private var defaultLabels: [Label] = []
    @State private var defaultTimeEvents: [TimeEvent] = []
    @State private var showDeleteAlert = false
    @State private var collectionToDelete: CollectionBookmark? = nil
    @State private var showCollectionsList = false
    @State private var currentTagForMap: Tag? = nil
    @State private var currentSelectedLabels: [String] = []
    @State private var fieldMapBookmark: Data? = nil
    
    func loadUserCollections() {
        userCollections = UserDefaults.standard.getCollectionBookmarks()
    }
    
    func backupDefaultData() {}
    
    func restoreDefaultData() {
        tagLibrary.restoreDefaultData()
        hotkeyManager.registerHotkeys(from: tagLibrary.tags, for: .standard)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if #available(macOS 14.0, *) {
                modernHeaderView
            } else {
                legacyHeaderView
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    timeEventsSection
                    tagGroupsSection
                }
            }
            if !showUserCollectionsMenu, showCollectionsList {
                legacyCollectionsListView
                    .background(Color(.windowBackgroundColor))
                    .frame(height: 300)
            }
        }
        .sheet(isPresented: $showLabelSheet) {
            stampLabelSheet
        }
        .onAppear(perform: onAppearSetup)
        .onDisappear(perform: onDisappearCleanup)
        .alert(isPresented: $showDeleteAlert) {
            deleteCollectionAlert
        }
    }
    
    private var modernHeaderView: some View {
        HStack {
            collectionTitleView
            Spacer()
            collectionsMenuButton
        }
        .padding(.horizontal)
    }
    
    private var collectionTitleView: some View {
        HStack {
            Text(isUserCollectionActive ?
                 "\(^String.Titles.customCollection) \(selectedUserCollection?.name ?? "")" :
                    ^String.Titles.tagGroups)
            .font(.headline)
            
            if isUserCollectionActive && selectedUserCollection != nil {
                collectionActionButtons
            }
        }
    }
    
    private var collectionActionButtons: some View {
        HStack(spacing: 8) {
            Button(action: {
                guard let collection = selectedUserCollection else { return }
                WindowsManager.shared.openCustomCollectionsWindow(withExistingCollection: collection)
            }) {
                Image(systemName: "pencil.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .help(^String.Titles.editCollection)
            
            Button(action: {
                collectionToDelete = selectedUserCollection
                showDeleteAlert = true
            }) {
                Image(systemName: "trash.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help(^String.Titles.deleteCollection)
        }
    }
    
    private var collectionsMenuButton: some View {
        Menu {
            createCollectionButton
            Divider()
            standardCollectionButton
            userCollectionsSection
        } label: {
            HStack {
                Image(systemName: "folder.badge.plus")
                Text(^String.Titles.collections)
            }
        }
        .buttonStyle(.borderless)
        .help(^String.Titles.manageCustomTagCollections)
    }
    
    private var createCollectionButton: some View {
        Button(action: {
            WindowsManager.shared.openCustomCollectionsWindow()
        }) {
            HStack {
                Image(systemName: "plus")
                Text(^String.Titles.createCollection)
            }
        }
    }
    
    private var standardCollectionButton: some View {
        Button(action: {
            isUserCollectionActive = false
            restoreDefaultData()
            selectedUserCollection = nil
        }) {
            HStack {
                Text(^String.Titles.standardCollection)
                Spacer()
                if !isUserCollectionActive {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
    
    @ViewBuilder
    private var userCollectionsSection: some View {
        if !userCollections.isEmpty {
            Divider()
            Text(^String.Titles.customCollections)
            
            ForEach(userCollections, id: \.name) { collection in
                userCollectionRow(for: collection)
            }
        }
    }
    
    private func userCollectionRow(for collection: CollectionBookmark) -> some View {
        HStack {
            Button(action: {
                selectedUserCollection = collection
                isUserCollectionActive = true
                loadUserCollection(collection)
            }) {
                HStack {
                    Text(collection.name)
                    Spacer()
                    if isUserCollectionActive && selectedUserCollection?.name == collection.name {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Menu {
                Button(action: {
                    WindowsManager.shared.openCustomCollectionsWindow(withExistingCollection: collection)
                }) {
                    HStack {
                        Image(systemName: "pencil")
                        Text(^String.Titles.editButtonTitle)
                    }
                }
                
                Button(action: {
                    collectionToDelete = collection
                    showDeleteAlert = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text(^String.Titles.delete)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width:20)
            }
            .buttonStyle(.borderless)
        }
    }
    
    // MARK: - Legacy UI Components (macOS 13 and below)
    
    private var legacyHeaderView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                collectionTitleView
                Spacer()
                Button(action: {
                    showCollectionsList.toggle()
                }) {
                    HStack {
                        Image(systemName: showCollectionsList ? "folder.badge.minus" : "folder.badge.plus")
                        Text(^String.Titles.collections)
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
        }
    }
    
    private var legacyCollectionsListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(^String.Titles.manageCollections)
                    .font(.headline)
                Spacer()
                Button(action: {
                    showCollectionsList = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.borderless)
            }
            
            Divider()
            
            Button(action: {
                WindowsManager.shared.openCustomCollectionsWindow()
                showCollectionsList = false
            }) {
                HStack {
                    Image(systemName: "plus.circle")
                    Text(^String.Titles.createNewCollection)
                    Spacer()
                }
                .padding(5)
            }
            .buttonStyle(.borderless)
            
            Button(action: {
                isUserCollectionActive = false
                restoreDefaultData()
                selectedUserCollection = nil
                showCollectionsList = false
            }) {
                HStack {
                    Text(^String.Titles.standardCollection)
                    Spacer()
                    if !isUserCollectionActive {
                        Image(systemName: "checkmark")
                    }
                }
                .padding(5)
            }
            .buttonStyle(.borderless)
            .background(!isUserCollectionActive ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(4)
            
            if !userCollections.isEmpty {
                Divider()
                Text("\(^String.Titles.customCollections):")
                    .font(.headline)
                    .padding(.top, 5)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(userCollections, id: \.name) { collection in
                            legacyCollectionRow(for: collection)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
        )
        .padding(.horizontal)
    }
    
    private func legacyCollectionRow(for collection: CollectionBookmark) -> some View {
        HStack {
            Button(action: {
                selectedUserCollection = collection
                isUserCollectionActive = true
                loadUserCollection(collection)
                showCollectionsList = false
            }) {
                Text(collection.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(5)
            .background(isUserCollectionActive && selectedUserCollection?.name == collection.name
                        ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(4)
            
            Button(action: {
                WindowsManager.shared.openCustomCollectionsWindow(withExistingCollection: collection)
                showCollectionsList = false
            }) {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .help(^String.Titles.editCollection)
            
            Button(action: {
                collectionToDelete = collection
                showDeleteAlert = true
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help(^String.Titles.deleteCollection)
        }
    }
    
    @ViewBuilder
    private var timeEventsSection: some View {
        if !tagLibrary.timeEvents.isEmpty {
            DisclosureGroup(isExpanded: .constant(true)) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(tagLibrary.timeEvents) { event in
                        timeEventButton(for: event)
                    }
                }
                .padding(.horizontal)
            } label: {
                Text(^String.Titles.commonEvents)
                    .font(.headline)
            }
            .padding(.horizontal)
        }
    }
    
    private func timeEventButton(for event: TimeEvent) -> some View {
        Button {
            tagLibrary.toggleTimeEvent(id: event.id)
        } label: {
            HStack {
                Image(systemName: tagLibrary.selectedTimeEvents.contains(event.id) ?
                      "checkmark.square.fill" : "square")
                .foregroundColor(tagLibrary.selectedTimeEvents.contains(event.id) ?
                    .blue : .gray)
                
                Text(event.name)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 135, alignment: .leading)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(BorderlessButtonStyle())
    }
    
    private var tagGroupsSection: some View {
        ForEach(tagLibrary.tagGroups) { group in
            tagGroupView(for: group)
        }
    }
    
    private func tagGroupView(for group: TagGroup) -> some View {
        DisclosureGroup(isExpanded: .constant(true)) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                ForEach(group.tags, id: \.self) { tagID in
                    if let tag = tagLibrary.tags.first(where: { $0.id == tagID }) {
                        tagButton(for: tag)
                    }
                }
            }
            .padding(.horizontal)
        } label: {
            Text(group.name)
                .font(.headline)
        }
        .padding(.horizontal)
    }
    
    private func tagButton(for tag: Tag) -> some View {
        Button {
            videoManager.player?.pause()
            selectedTag = tag
            
            let hasValidTimeline = timelineData.selectedLineID != nil &&
            timelineData.lines.contains(where: { $0.id == timelineData.selectedLineID })
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showLabelSheet = true
            }
        } label: {
            VStack(alignment: .center, spacing: 2) {
                HStack(alignment: .center, spacing: 4) {
                    Text(tag.name)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                    if let hotkey = tag.hotkey, !hotkey.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "button.roundedtop.horizontal.fill")
                                .font(.system(size: 9))
                            Text(hotkey)
                                .font(.system(size: 9, weight: .light))
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(3)
                    }
                }
                .frame(width: 135, alignment: .leading)
            }
            .padding(5)
            .foregroundColor(Color(hex: tag.color).isDark ? .white : .black)
        }
        .background(Color(hex: tag.color))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(hoveredTagID == tag.id ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            if hovering {
                hoveredTagID = tag.id
            } else if hoveredTagID == tag.id {
                hoveredTagID = nil
            }
        }
    }
    
    private func addTagToTimeline(tag: Tag, selectedLabels: [String]) {
        if tag.mapEnabled == true {
            let collectionManager = CustomCollectionManager()
            if let collectionName = tagLibrary.currentCollectionType.name,
               collectionManager.loadCollectionFromBookmarks(named: collectionName),
               let playField = collectionManager.playField,
               let imageBookmark = playField.imageBookmark {
                
                showFieldMapSelection(tag: tag, imageBookmark: imageBookmark, selectedLabels: selectedLabels)
                return
            }
        }
        
        proceedWithTagAddition(tag: tag, selectedLabels: selectedLabels, coordinates: nil)
    }
    
    private func showFieldMapSelection(tag: Tag, imageBookmark: Data, selectedLabels: [String]) {
        WindowsManager.shared.showFieldMapSelection(tag: tag, imageBookmark: imageBookmark) { [self] coordinates in
            proceedWithTagAddition(tag: tag, selectedLabels: selectedLabels, coordinates: coordinates)
        }
    }
    
    private func proceedWithTagAddition(tag: Tag, selectedLabels: [String], coordinates: CGPoint?) {
        let currentTime = videoManager.currentTime
        let startTime = max(0, currentTime - tag.defaultTimeBefore)
        let finishTime = startTime + tag.defaultTimeBefore + tag.defaultTimeAfter
        let timeStartString = secondsToTimeString(startTime)
        let timeFinishString = secondsToTimeString(finishTime)
        
        var fieldPosition: CGPoint? = nil
        if let normalizedCoords = coordinates {
            let collectionManager = CustomCollectionManager()
            if let collectionName = tagLibrary.currentCollectionType.name,
               collectionManager.loadCollectionFromBookmarks(named: collectionName),
               let playField = collectionManager.playField {
                let fieldWidth = CGFloat(playField.width)
                let fieldHeight = CGFloat(playField.height)
                
                let fieldX = normalizedCoords.x * fieldWidth
                let fieldY = normalizedCoords.y * fieldHeight
                
                fieldPosition = CGPoint(x: fieldX, y: fieldY)
                
                print("Field position selected for tag '\(tag.name)': " +
                      "normalized: x: \(normalizedCoords.x), y: \(normalizedCoords.y), " +
                      "field position: x: \(fieldX), y: \(fieldY)")
            }
        }
        
        timelineData.addStampToSelectedLine(
            idTag: tag.id,
            primaryId: tag.primaryID,
            name: tag.name,
            timeStart: timeStartString,
            timeFinish: timeFinishString,
            color: tag.color,
            labels: selectedLabels,
            position: fieldPosition
        )
        
        if videoManager.playbackSpeed > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                videoManager.player?.play()
            }
        }
    }
    
    @ViewBuilder
    private var stampLabelSheet: some View {
        if markupMode == .tagBased {
            if let tag = selectedTag {
                let hasLabels = !tagLibrary.allLabelGroups.filter({ tag.lablesGroup.contains($0.id) }).isEmpty
                
                if hasLabels {
                    LabelSelectionSheet(
                        stampName: tag.name,
                        initialLabels: [],
                        tag: tag,
                        tagLibrary: TagLibraryManager.shared
                    ) { selectedLabels in
                        addTagToTimeline(tag: tag, selectedLabels: selectedLabels)
                    }
                } else {
                    VStack {
                        Text(^String.Titles.tagLibraryAddingTag)
                            .onAppear {
                                addTagToTimeline(tag: tag, selectedLabels: [])
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showLabelSheet = false
                                }
                            }
                    }
                }
            }
        } else {
            if let selectedLineID = timelineData.selectedLineID,
               timelineData.lines.contains(where: { $0.id == selectedLineID }),
               let tag = selectedTag {
                let hasLabels = !tagLibrary.allLabelGroups.filter({ tag.lablesGroup.contains($0.id) }).isEmpty
                
                if hasLabels {
                    LabelSelectionSheet(
                        stampName: tag.name,
                        initialLabels: [],
                        tag: tag,
                        tagLibrary: TagLibraryManager.shared
                    ) { selectedLabels in
                        addTagToTimeline(tag: tag, selectedLabels: selectedLabels)
                    }
                } else {
                    VStack {
                        Text(^String.Titles.tagLibraryAddingTag)
                            .onAppear {
                                addTagToTimeline(tag: tag, selectedLabels: [])
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showLabelSheet = false
                                }
                            }
                    }
                }
            } else {
                Text(^String.Titles.tagLibraryNoTimeline)
                .padding()
                .multilineTextAlignment(.center)
            }
        }
    }
    
    private var deleteCollectionAlert: Alert {
        Alert(
            title: Text(^String.Titles.tagLibraryDeleteTitle),
            message: Text("\(^String.Titles.confirmDeleteCollection) \"\(collectionToDelete?.name ?? "")\"?"),
            primaryButton: .destructive(Text(^String.Titles.delete)) {
                if let collection = collectionToDelete {
                    deleteCollection(collection)
                }
            },
            secondaryButton: .cancel(Text(^String.Titles.collectionsButtonCancel))
        )
    }
    
    private func onAppearSetup() {
        loadUserCollections()
        backupDefaultData()
        restoreDefaultData()
        markupMode = MarkupMode.current
        NotificationCenter.default.addObserver(forName: .markupModeChanged, object: nil, queue: .main) { notification in
            if let newMode = notification.object as? MarkupMode {
                self.markupMode = newMode
            } else {
                self.markupMode = MarkupMode.current
            }
        }
        NotificationCenter.default.addObserver(forName: .collectionDataChanged, object: nil, queue: .main) { _ in
            loadUserCollections()
            if self.isUserCollectionActive, let currentCollection = self.selectedUserCollection,
               let updatedCollection = UserDefaults.standard.getCollectionBookmarks().first(where: { $0.name == currentCollection.name }) {
                self.selectedUserCollection = updatedCollection
                self.loadUserCollection(updatedCollection)
            }
        }
        NotificationCenter.default.addObserver(forName: .showLabelSheet, object: nil, queue: .main) { notification in
            if let tag = notification.object as? Tag {
                self.selectedTag = tag
                let hasValidTimeline = timelineData.selectedLineID != nil &&
                timelineData.lines.contains(where: { $0.id == timelineData.selectedLineID })
                if hasValidTimeline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.showLabelSheet = true
                    }
                }
            }
        }
    }
    
    private func onDisappearCleanup() {
        NotificationCenter.default.removeObserver(self, name: .collectionDataChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: .showLabelSheet, object: nil)
    }
    
    func loadUserCollection(_ collection: CollectionBookmark) {
        let collectionManager = CustomCollectionManager()
        if collectionManager.loadCollectionFromBookmarks(named: collection.name) {
            tagLibrary.tags = collectionManager.tags
            tagLibrary.tagGroups = collectionManager.tagGroups
            tagLibrary.labelGroups = collectionManager.labelGroups
            tagLibrary.labels = collectionManager.labels
            tagLibrary.timeEvents = collectionManager.timeEvents
            tagLibrary.selectedTimeEvents.removeAll()
            tagLibrary.currentCollectionType = .user(name: collection.name)
            HotKeyManager.shared.clearHotkeys()
            HotKeyManager.shared.registerHotkeys(from: collectionManager.tags, for: .user(name: collection.name))
        } else {
            tagLibrary.tags = []
            tagLibrary.tagGroups = []
            tagLibrary.labelGroups = []
            tagLibrary.labels = []
            tagLibrary.timeEvents = []
            tagLibrary.selectedTimeEvents.removeAll()
            HotKeyManager.shared.clearHotkeys()
        }
    }
    
    private func deleteCollection(_ collection: CollectionBookmark) {
        UserDefaults.standard.removeCollectionBookmark(named: collection.name)
        
        let collectionsFolder = URL.appDocumentsDirectory
            .appendingPathComponent("YouChip-Stat/Collections/\(collection.name)", isDirectory: true)
            .fixedFile()
        
        try? FileManager.default.removeItem(at: collectionsFolder)
        
        if isUserCollectionActive && selectedUserCollection?.name == collection.name {
            isUserCollectionActive = false
            selectedUserCollection = nil
            restoreDefaultData()
        }
        
        loadUserCollections()
        tagLibrary.refreshGlobalPools()
        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
    }
    
}
