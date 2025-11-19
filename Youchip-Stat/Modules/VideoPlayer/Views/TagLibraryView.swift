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
    
    @State private var expandedGroups: Set<String> = []
    
    @State var activeIntervalTags: [ActiveIntervalTag] = []
    
    @State private var tagCounts: [String: Int] = [:]
    
    @State private var updateTimer: Timer?
    
    @State private var refreshID = UUID()
    @State private var windowWidth: CGFloat = 0
    
    struct ActiveIntervalTag: Identifiable {
        let id: String
        let tag: Tag
        var startTime: Double
    }
    
    func loadUserCollections() {
        userCollections = UserDefaults.standard.getCollectionBookmarks()
    }
    
    func backupDefaultData() {}
    
    func forceWindowRefresh() {
        if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow && $0.title == ^String.Titles.tagLibrary }) {
            let currentFrame = window.frame
            let newWidth = currentFrame.width + 1
            
            window.setFrame(NSRect(x: currentFrame.origin.x, y: currentFrame.origin.y, width: newWidth, height: currentFrame.height), display: true)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                window.setFrame(currentFrame, display: true)
            }
        }
    }
    
    func restoreDefaultData() {
        if let selectedName = tagLibrary.selectedStandardCollectionName {
            tagLibrary.applyStandardCollection(named: selectedName)
        } else {
            tagLibrary.restoreDefaultData()
        }
        hotkeyManager.registerHotkeys(from: tagLibrary.tags, for: .standard)
        expandedGroups = Set(tagLibrary.tagGroups.map { $0.id })
        forceWindowRefresh()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            modernHeaderView
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    if !tagLibrary.timeEvents.isEmpty {
                        timeEventsSection
                    }
                    
                    if !tagLibrary.tagGroups.isEmpty {
                        tagGroupsSection
                    }
                    
                    if tagLibrary.timeEvents.isEmpty && tagLibrary.tagGroups.isEmpty {
                        emptyStateView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(.controlBackgroundColor))
            
            if !showUserCollectionsMenu, showCollectionsList {
                legacyCollectionsListView
                    .background(Color(.windowBackgroundColor))
                    .frame(height: 300)
            }
        }
        .background(Color(.controlBackgroundColor))
        .id(refreshID)
        .sheet(isPresented: $showLabelSheet) {
            stampLabelSheet
        }
        .onAppear(perform: onAppearSetup)
        .onDisappear(perform: onDisappearCleanup)
        .alert(isPresented: $showDeleteAlert) {
            deleteCollectionAlert
        }
        .onChange(of: tagLibrary.timeEvents.count) { _ in
            refreshID = UUID()
            forceWindowRefresh()
        }
        .onChange(of: tagLibrary.tagGroups.count) { _ in
            refreshID = UUID()
            forceWindowRefresh()
        }
        .onChange(of: tagLibrary.selectedStandardCollectionName) { _ in
            refreshID = UUID()
            forceWindowRefresh()
        }
        .onChange(of: isUserCollectionActive) { _ in
            refreshID = UUID()
            forceWindowRefresh()
        }
        .onReceive(timelineData.$lines) { _ in
            DispatchQueue.main.async {
                self.updateTagCounts()
            }
        }
        .onChange(of: timelineData.selectedLineID) { _ in
            DispatchQueue.main.async {
                self.updateTagCounts()
            }
        }
    }
    
    private var modernHeaderView: some View {
        VStack(spacing: 0) {
            HStack {
                collectionTitleView
                Spacer()
                Button(action: {
                    WindowsManager.shared.openCustomCollectionsWindow()
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text(^String.Titles.createCollection)
                    }
                }
                .buttonStyle(.borderless)
                .help(^String.Titles.createCollection)
                .disabled(!activeIntervalTags.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.windowBackgroundColor))
            
            collectionsScrollView
            
            Divider()
                .background(Color(.separatorColor))
        }
    }
    
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tag")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)
            
            Text(^String.Titles.noTagsToDisplay)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var collectionTitleView: some View {
        HStack {
            Text(isUserCollectionActive ?
                 "\(^String.Titles.customCollection) \(selectedUserCollection?.name ?? "")" :
                    ^String.Titles.tagGroups)
            .font(.headline)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            
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
            
            .help(^String.Titles.deleteCollection)
        }
    }
    
    private var collectionsScrollView: some View {
        VStack(spacing: 8) {
            if !tagLibrary.standardCollections.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(^String.Titles.standardCollections)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tagLibrary.standardCollections, id: \.name) { collection in
                                standardCollectionChip(
                                    collection: collection,
                                    isSelected: tagLibrary.selectedStandardCollectionName == collection.name && !isUserCollectionActive
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            
            if !userCollections.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(^String.Titles.customCollections)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(userCollections, id: \.name) { collection in
                                customCollectionChip(collection: collection)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }
    
    private func standardCollectionChip(collection: StandardCollection, isSelected: Bool) -> some View {
        Button(action: {
            guard activeIntervalTags.isEmpty else { return }
            isUserCollectionActive = false
            selectedUserCollection = nil
            tagLibrary.applyStandardCollection(named: collection.name)
            DispatchQueue.main.async {
                self.expandedGroups = Set(self.tagLibrary.tagGroups.map { $0.id })
                self.refreshID = UUID()
                self.forceWindowRefresh()
            }
        }) {
            HStack(spacing: 6) {
                Text(collection.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color(.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!activeIntervalTags.isEmpty)
    }
    
    private func customCollectionChip(collection: CollectionBookmark) -> some View {
        let isSelected = isUserCollectionActive && selectedUserCollection?.name == collection.name
        
        return Button(action: {
            guard activeIntervalTags.isEmpty else { return }
            selectedUserCollection = collection
            isUserCollectionActive = true
            loadUserCollection(collection)
        }) {
            HStack(spacing: 6) {
                Text(collection.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color(.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!activeIntervalTags.isEmpty)
        .contextMenu {
            Button(^String.Titles.editButtonTitle) {
                WindowsManager.shared.openCustomCollectionsWindow(withExistingCollection: collection)
            }
            
            Button(^String.Titles.delete) {
                collectionToDelete = collection
                showDeleteAlert = true
            }
        }
    }
    
    private var collectionsMenuButton: some View {
        Menu {
            createCollectionButton
            Divider()
            standardCollectionsSection
            userCollectionsSection
        } label: {
            HStack {
                Image(systemName: "folder.badge.plus")
                Text(^String.Titles.collections)
            }
        }
        .buttonStyle(.borderless)
        .help(^String.Titles.manageCustomTagCollections)
        .disabled(!activeIntervalTags.isEmpty)
    }
    
    @ViewBuilder
    private var standardCollectionsSection: some View {
        if !tagLibrary.standardCollections.isEmpty {
            Text(^String.Titles.standardCollections)
            ForEach(tagLibrary.standardCollections, id: \.name) { collection in
                Button(action: {
                    isUserCollectionActive = false
                    selectedUserCollection = nil
                    tagLibrary.applyStandardCollection(named: collection.name)
                    DispatchQueue.main.async {
                        self.expandedGroups = Set(self.tagLibrary.tagGroups.map { $0.id })
                        self.refreshID = UUID()
                        self.forceWindowRefresh()
                    }
                }) {
                    HStack {
                        Text(collection.name)
                        Spacer()
                        if tagLibrary.selectedStandardCollectionName == collection.name && !isUserCollectionActive {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(!activeIntervalTags.isEmpty)
            }
            Divider()
        }
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
            selectedUserCollection = nil
            if let selectedName = tagLibrary.selectedStandardCollectionName {
                tagLibrary.applyStandardCollection(named: selectedName)
            } else if let firstCollection = tagLibrary.standardCollections.first {
                tagLibrary.applyStandardCollection(named: firstCollection.name)
            }
            DispatchQueue.main.async {
                self.expandedGroups = Set(self.tagLibrary.tagGroups.map { $0.id })
                self.refreshID = UUID()
                self.forceWindowRefresh()
            }
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
            .disabled(!activeIntervalTags.isEmpty)
            
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
                selectedUserCollection = nil
                if let selectedName = tagLibrary.selectedStandardCollectionName {
                    tagLibrary.applyStandardCollection(named: selectedName)
                } else if let firstCollection = tagLibrary.standardCollections.first {
                    tagLibrary.applyStandardCollection(named: firstCollection.name)
                }
                DispatchQueue.main.async {
                    self.expandedGroups = Set(self.tagLibrary.tagGroups.map { $0.id })
                    self.refreshID = UUID()
                    self.forceWindowRefresh()
                }
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
            .disabled(!activeIntervalTags.isEmpty)
            
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16, weight: .medium))
                
                Text(^String.Titles.commonEvents)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(tagLibrary.timeEvents.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(10)
            }
            
            FlexibleTimeEventGrid(events: tagLibrary.timeEvents, tagLibrary: tagLibrary, onEventTap: { event in
                withAnimation(.easeInOut(duration: 0.2)) {
                    tagLibrary.toggleTimeEvent(id: event.id)
                }
            })
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    
    private var tagGroupsSection: some View {
        ForEach(tagLibrary.tagGroups) { group in
            tagGroupView(for: group)
        }
    }
    
    private func tagGroupView(for group: TagGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    if expandedGroups.contains(group.id) {
                        expandedGroups.remove(group.id)
                    } else {
                        expandedGroups.insert(group.id)
                    }
                }
            }) {
                HStack {
                    Image(systemName: "tag")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 16, weight: .medium))
                    
                    Text(group.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(group.tags.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(10)
                    
                    Image(systemName: expandedGroups.contains(group.id) ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .medium))
                        .rotationEffect(.degrees(expandedGroups.contains(group.id) ? 0 : 0))
                }
            }
            .buttonStyle(.plain)
            
            if expandedGroups.contains(group.id) {
                FlexibleTagGrid(tags: group.tags, tagLibrary: tagLibrary, activeIntervalTags: activeIntervalTags, hoveredTagID: hoveredTagID, tagCounts: $tagCounts, onTagTap: handleTagButtonTap, onTagHover: { hovering, tagID in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if hovering {
                            hoveredTagID = tagID
                        } else if hoveredTagID == tagID {
                            hoveredTagID = nil
                        }
                    }
                })
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
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
            if videoManager.playbackSpeed > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    videoManager.player?.play()
                }
            }
        }
    }
    
    private func proceedWithTagAddition(tag: Tag, selectedLabels: [String], coordinates: CGPoint?) {
        let currentTime = videoManager.currentTime
        let videoDuration = max(1.0, videoManager.videoDuration)
        let startTime = max(0, currentTime - tag.defaultTimeBefore)
        let finishTime = min(videoDuration, startTime + tag.defaultTimeBefore + tag.defaultTimeAfter)
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
        
        DispatchQueue.main.async {
            self.updateTagCounts()
        }
        
        if tag.mapEnabled != true {
            if videoManager.playbackSpeed > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    videoManager.player?.play()
                }
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
                        tagLibrary: TagLibraryManager.shared,
                        onDone: { selectedLabels in
                            if tag.isInterval == true {
                                if let firstActiveTag = activeIntervalTags.first(where: { $0.tag.id == tag.id }) {
                                    let videoDuration = max(1.0, videoManager.videoDuration)
                                    let start = max(0, firstActiveTag.startTime - tag.defaultTimeBefore)
                                    let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
                                    let timeStart = min(start, end)
                                    let timeFinish = max(start, end)
                                    let timeStartString = secondsToTimeString(timeStart)
                                    let timeFinishString = secondsToTimeString(timeFinish)
                                    
                                    
                                    activeIntervalTags.removeAll { $0.tag.id == tag.id }
                                    
                                    addTagToTimelineInterval(
                                        tag: tag,
                                        timeStartString: timeStartString,
                                        timeFinishString: timeFinishString,
                                        selectedLabels: selectedLabels
                                    )
                                }
                            } else {
                                addTagToTimeline(tag: tag, selectedLabels: selectedLabels)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showLabelSheet = false
                            }
                        },
                        onCancel: {
                            self.videoManager.player?.play()
                            if let tag = selectedTag, tag.isInterval == true {
                                activeIntervalTags.removeAll { $0.tag.id == tag.id }
                            }
                        }
                    )
                } else {
                    VStack {
                        Text(^String.Titles.tagLibraryAddingTag)
                            .onAppear {
                                if tag.isInterval == true {
                                    if let firstActiveTag = activeIntervalTags.first(where: { $0.tag.id == tag.id }) {
                                        let videoDuration = max(1.0, videoManager.videoDuration)
                                        let start = max(0, firstActiveTag.startTime - tag.defaultTimeBefore)
                                        let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
                                        let timeStart = min(start, end)
                                        let timeFinish = max(start, end)
                                        let timeStartString = secondsToTimeString(timeStart)
                                        let timeFinishString = secondsToTimeString(timeFinish)
                                        
                                        
                                        activeIntervalTags.removeAll { $0.tag.id == tag.id }
                                        
                                        addTagToTimelineInterval(
                                            tag: tag,
                                            timeStartString: timeStartString,
                                            timeFinishString: timeFinishString,
                                            selectedLabels: []
                                        )
                                    }
                                } else {
                                    addTagToTimeline(tag: tag, selectedLabels: [])
                                }
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
                        tagLibrary: TagLibraryManager.shared,
                        onDone: { selectedLabels in
                            if tag.isInterval == true {
                                if let firstActiveTag = activeIntervalTags.first(where: { $0.tag.id == tag.id }) {
                                    let videoDuration = max(1.0, videoManager.videoDuration)
                                    let start = max(0, firstActiveTag.startTime - tag.defaultTimeBefore)
                                    let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
                                    let timeStart = min(start, end)
                                    let timeFinish = max(start, end)
                                    let timeStartString = secondsToTimeString(timeStart)
                                    let timeFinishString = secondsToTimeString(timeFinish)
                                    
                                    
                                    activeIntervalTags.removeAll { $0.tag.id == tag.id }
                                    
                                    addTagToTimelineInterval(
                                        tag: tag,
                                        timeStartString: timeStartString,
                                        timeFinishString: timeFinishString,
                                        selectedLabels: selectedLabels
                                    )
                                }
                            } else {
                                addTagToTimeline(tag: tag, selectedLabels: selectedLabels)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showLabelSheet = false
                            }
                        },
                        onCancel: {
                            self.videoManager.player?.play()
                            if let tag = selectedTag, tag.isInterval == true {
                                activeIntervalTags.removeAll { $0.tag.id == tag.id }
                            }
                        }
                    )
                } else {
                    VStack {
                        Text(^String.Titles.tagLibraryAddingTag)
                            .onAppear {
                                if tag.isInterval == true {
                                    if let firstActiveTag = activeIntervalTags.first(where: { $0.tag.id == tag.id }) {
                                        let videoDuration = max(1.0, videoManager.videoDuration)
                                        let start = max(0, firstActiveTag.startTime - tag.defaultTimeBefore)
                                        let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
                                        let timeStart = min(start, end)
                                        let timeFinish = max(start, end)
                                        let timeStartString = secondsToTimeString(timeStart)
                                        let timeFinishString = secondsToTimeString(timeFinish)
                                        
                                        
                                        activeIntervalTags.removeAll { $0.tag.id == tag.id }
                                        
                                        addTagToTimelineInterval(
                                            tag: tag,
                                            timeStartString: timeStartString,
                                            timeFinishString: timeFinishString,
                                            selectedLabels: []
                                        )
                                    }
                                } else {
                                    addTagToTimeline(tag: tag, selectedLabels: [])
                                }
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
        
        updateTagCounts()
        expandedGroups = Set(tagLibrary.tagGroups.map { $0.id })
        
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
                if tag.isInterval ?? false {
                    if let index = activeIntervalTags.firstIndex(where: { $0.tag.id == tag.id }) {
                        let activeTag = activeIntervalTags[index]
                        let videoDuration = max(1.0, videoManager.videoDuration)
                        let start = max(0, activeTag.startTime - tag.defaultTimeBefore)
                        let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
                        let timeStart = min(start, end)
                        let timeFinish = max(start, end)
                        let timeStartString = secondsToTimeString(timeStart)
                        let timeFinishString = secondsToTimeString(timeFinish)
                        
                        selectedTag = tag
                        showLabelSheet = false
                        
                        DispatchQueue.main.async {
                            videoManager.player?.pause()
                            let hasLabels = !tagLibrary.allLabelGroups.filter({ tag.lablesGroup.contains($0.id) }).isEmpty
                            if hasLabels {
                                showLabelSheet = true
                            } else {
                                activeIntervalTags.remove(at: index)
                                addTagToTimelineInterval(tag: tag, timeStartString: timeStartString, timeFinishString: timeFinishString, selectedLabels: [])
                            }
                        }
                    } else {
                        guard !activeIntervalTags.contains(where: { $0.tag.id == tag.id }) else {
                            return
                        }
                        activeIntervalTags.append(ActiveIntervalTag(id: UUID().uuidString, tag: tag, startTime: videoManager.currentTime))
                    }
                    return
                }
                
                selectedTag = tag
                videoManager.player?.pause()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showLabelSheet = true
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .stampCountsChanged, object: nil, queue: .main) { _ in
            DispatchQueue.main.async {
                self.updateTagCounts()
            }
        }
    }
    
    
    private func onDisappearCleanup() {
        updateTimer?.invalidate()
        updateTimer = nil
        NotificationCenter.default.removeObserver(self, name: .collectionDataChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: .showLabelSheet, object: nil)
        NotificationCenter.default.removeObserver(self, name: .markupModeChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: .stampCountsChanged, object: nil)
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
            tagLibrary.currentCollectionType = .standard
            HotKeyManager.shared.clearHotkeys()
        }
        
        DispatchQueue.main.async {
            self.updateTagCounts()
            self.expandedGroups = Set(self.tagLibrary.tagGroups.map { $0.id })
            self.refreshID = UUID()
            self.forceWindowRefresh()
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
    
    private func handleTagButtonTap(tag: Tag) {
        if tag.isInterval ?? false {
            if let index = activeIntervalTags.firstIndex(where: { $0.tag.id == tag.id }) {
                let activeTag = activeIntervalTags[index]
                let videoDuration = max(1.0, videoManager.videoDuration)
                let start = max(0, activeTag.startTime - tag.defaultTimeBefore)
                let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
                let timeStart = min(start, end)
                let timeFinish = max(start, end)
                let timeStartString = secondsToTimeString(timeStart)
                let timeFinishString = secondsToTimeString(timeFinish)
                
                selectedTag = tag
                showLabelSheet = false
                
                DispatchQueue.main.async {
                    videoManager.player?.pause()
                    let hasLabels = !tagLibrary.allLabelGroups.filter({ tag.lablesGroup.contains($0.id) }).isEmpty
                    if hasLabels {
                        showLabelSheet = true
                    } else {
                        activeIntervalTags.remove(at: index)
                        addTagToTimelineInterval(tag: tag, timeStartString: timeStartString, timeFinishString: timeFinishString, selectedLabels: [])
                    }
                }
            } else {
                guard !activeIntervalTags.contains(where: { $0.tag.id == tag.id }) else {
                    return
                }
                activeIntervalTags.append(ActiveIntervalTag(id: UUID().uuidString, tag: tag, startTime: videoManager.currentTime))
            }
            return
        }
        
        videoManager.player?.pause()
        selectedTag = tag
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showLabelSheet = true
        }
    }
    
    private func addTagToTimelineInterval(tag: Tag, timeStartString: String, timeFinishString: String, selectedLabels: [String]) {
        if tag.mapEnabled == true {
            let collectionManager = CustomCollectionManager()
            if let collectionName = tagLibrary.currentCollectionType.name,
               collectionManager.loadCollectionFromBookmarks(named: collectionName),
               let playField = collectionManager.playField,
               let imageBookmark = playField.imageBookmark {
                showFieldMapSelectionInterval(tag: tag, imageBookmark: imageBookmark, timeStartString: timeStartString, timeFinishString: timeFinishString, selectedLabels: selectedLabels)
                return
            }
        }
        proceedWithTagAdditionInterval(tag: tag, timeStartString: timeStartString, timeFinishString: timeFinishString, coordinates: nil, selectedLabels: selectedLabels)
    }
    
    private func showFieldMapSelectionInterval(tag: Tag, imageBookmark: Data, timeStartString: String, timeFinishString: String, selectedLabels: [String]) {
        WindowsManager.shared.showFieldMapSelection(tag: tag, imageBookmark: imageBookmark) { [self] coordinates in
            proceedWithTagAdditionInterval(tag: tag, timeStartString: timeStartString, timeFinishString: timeFinishString, coordinates: coordinates, selectedLabels: selectedLabels)
            if videoManager.playbackSpeed > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    videoManager.player?.play()
                }
            }
        }
    }
    
    private func proceedWithTagAdditionInterval(tag: Tag, timeStartString: String, timeFinishString: String, coordinates: CGPoint?, selectedLabels: [String]) {
        
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
        
        
        DispatchQueue.main.async {
            self.updateTagCounts()
        }
        
        if tag.mapEnabled != true {
            if videoManager.playbackSpeed > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    videoManager.player?.play()
                }
            }
        }
    }
    
    private func updateTagCounts() {
        var counts: [String: Int] = [:]
        
        for line in timelineData.lines {
            for stamp in line.stamps {
                counts[stamp.idTag, default: 0] += 1
            }
        }
        
        tagCounts = counts
    }
    
    private func countTagsInTimeline(tagId: String) -> Int {
        return tagCounts[tagId] ?? 0
    }
}

struct TagButtonView: View, Equatable {
    let tag: Tag
    let isActive: Bool
    let isHovered: Bool
    let tagCount: Int
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    
    static func == (lhs: TagButtonView, rhs: TagButtonView) -> Bool {
        return lhs.tag.id == rhs.tag.id &&
               lhs.isActive == rhs.isActive &&
               lhs.isHovered == rhs.isHovered &&
               lhs.tagCount == rhs.tagCount
    }
    
    var body: some View {
        let hasHotkey = tag.hotkey != nil && !tag.hotkey!.isEmpty
        let isInterval = tag.isInterval ?? false
        
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .center, spacing: 8) {
                    Text(tag.name)
                        .font(.system(size: 14, weight: isActive ? .bold : .medium))
                        .foregroundColor(isActive ? .white : Color(hex: tag.color).isDark ? .white : .black)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .minimumScaleFactor(0.5)
                    
                    if tagCount > 0 {
                        Text("\(tagCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isActive ? .white : Color(hex: tag.color).isDark ? .white : .black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isActive ? Color.white.opacity(0.3) : Color(hex: tag.color).isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                            )
                    }
                }
            .frame(height: 22)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
                
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        if isInterval {
                            Image(systemName: "timer")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isActive ? .white : Color(hex: tag.color).isDark ? .white : .black)
                        }
                        
                        if tag.mapEnabled == true {
                            Image(systemName: "map")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isActive ? .white : Color(hex: tag.color).isDark ? .white : .black)
                        }
                        
                        if hasHotkey {
                            HStack(spacing: 2) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 10, weight: .medium))
                                Text(tag.hotkey!)
                                    .font(.system(size: 10, weight: .medium))
                                    .minimumScaleFactor(0.8)
                            }
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isActive ? Color.white.opacity(0.2) : Color(hex: tag.color).isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                            )
                        }
                        
                        if isActive {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                
                if isActive && isInterval {
                    HStack(spacing: 2) {
                        ForEach(0..<6) { _ in
                            Rectangle()
                                .frame(width: 2, height: 4)
                                .opacity(0.6)
                        }
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isActive ? 
                        LinearGradient(
                            gradient: Gradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            gradient: Gradient(colors: [Color(hex: tag.color), Color(hex: tag.color).opacity(0.9)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: isActive ? Color.accentColor.opacity(0.3) : Color(hex: tag.color).opacity(0.2),
                        radius: isHovered ? 8 : 4,
                        x: 0,
                        y: isHovered ? 4 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isHovered ? Color.accentColor.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
            .scaleEffect(isHovered ? 1.05 : (isActive ? 1.02 : 1.0))
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
    }
}

struct FlexibleTagGrid: View {
    let tags: [String]
    let tagLibrary: TagLibraryManager
    let activeIntervalTags: [TagLibraryView.ActiveIntervalTag]
    let hoveredTagID: String?
    @Binding var tagCounts: [String: Int]
    let onTagTap: (Tag) -> Void
    let onTagHover: (Bool, String) -> Void
    
    @State private var availableWidth: CGFloat = 0
    @State private var tagRows: [[String]] = []
    
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(tagRows.enumerated()), id: \.offset) { rowIndex, rowTags in
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(rowTags, id: \.self) { tagID in
                            if let tag = tagLibrary.tags.first(where: { $0.id == tagID }) {
                                TagButtonView(
                                    tag: tag,
                                    isActive: activeIntervalTags.contains(where: { $0.tag.id == tag.id }),
                                    isHovered: hoveredTagID == tag.id,
                                    tagCount: tagCounts[tag.id] ?? 0,
                                    onTap: { onTagTap(tag) },
                                    onHover: { hovering in
                                        onTagHover(hovering, tag.id)
                                    }
                                )
                                .frame(height: calculateMaxHeightInGroup())
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .onAppear {
                availableWidth = geometry.size.width
                calculateTagRows()
            }
            .onChange(of: geometry.size.width) { newWidth in
                availableWidth = newWidth
                calculateTagRows()
            }
            .onChange(of: tags.count) { _ in
                calculateTagRows()
            }
            .onChange(of: tagCounts) { _ in
                calculateTagRows()
            }
        }
        .frame(height: calculateTotalHeight())
    }
    
    private func calculateTagRows() {
        guard availableWidth > 0 else { return }
        
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentRowWidth: CGFloat = 0
        
        let spacing: CGFloat = 6
        let maxButtonWidth: CGFloat = 200
        
        for tagID in tags {
            guard let tag = tagLibrary.tags.first(where: { $0.id == tagID }) else { continue }
            
            let buttonWidth = min(calculateButtonWidth(for: tag), maxButtonWidth)
            
            if currentRowWidth + buttonWidth + (currentRow.isEmpty ? 0 : spacing) <= availableWidth {
                currentRow.append(tagID)
                currentRowWidth += buttonWidth + (currentRow.count > 1 ? spacing : 0)
            } else {
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                }
                currentRow = [tagID]
                currentRowWidth = buttonWidth
            }
        }
        
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        
        tagRows = rows
    }
    
    private func calculateButtonWidth(for tag: Tag) -> CGFloat {
        let textFont = NSFont.systemFont(ofSize: 14, weight: .medium)
        let textAttributes = [NSAttributedString.Key.font: textFont]
        let textWidth = tag.name.size(withAttributes: textAttributes).width
        
        var totalWidth = textWidth
        
        totalWidth += 16
        
        if let tagCount = tagCounts[tag.id], tagCount > 0 {
            let countText = "\(tagCount)"
            let countFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
            let countAttributes = [NSAttributedString.Key.font: countFont]
            let countWidth = countText.size(withAttributes: countAttributes).width
            totalWidth += countWidth + 12
        }
        
        totalWidth += 8
        
        return totalWidth
    }
    
    private func calculateTagButtonHeight(for tag: Tag) -> CGFloat {
        var height: CGFloat = 22
        
        let hasIndicators = (tag.isInterval == true) || 
                           (tag.mapEnabled == true) || 
                           (tag.hotkey != nil && !tag.hotkey!.isEmpty) ||
                           activeIntervalTags.contains(where: { $0.tag.id == tag.id })
        
        if hasIndicators {
            height += 16
        }
        
        if activeIntervalTags.contains(where: { $0.tag.id == tag.id }) && (tag.isInterval == true) {
            height += 8
        }
        
        height += 8
        
        return height
    }
    
    private func calculateTotalHeight() -> CGFloat {
        let maxHeightInGroup = calculateMaxHeightInGroup()
        let spacing: CGFloat = 8
        let totalHeight = CGFloat(tagRows.count) * (maxHeightInGroup + spacing)
        
        return totalHeight
    }
    
    private func calculateMaxHeightInRow(_ rowTags: [String]) -> CGFloat {
        var maxHeight: CGFloat = 0
        
        for tagID in rowTags {
            if let tag = tagLibrary.tags.first(where: { $0.id == tagID }) {
                let buttonHeight = calculateTagButtonHeight(for: tag)
                maxHeight = max(maxHeight, buttonHeight)
            }
        }
        
        return maxHeight
    }
    
    private func calculateMaxHeightInGroup() -> CGFloat {
        var maxHeight: CGFloat = 0
        
        for row in tagRows {
            for tagID in row {
                if let tag = tagLibrary.tags.first(where: { $0.id == tagID }) {
                    let buttonHeight = calculateTagButtonHeight(for: tag)
                    maxHeight = max(maxHeight, buttonHeight)
                }
            }
        }
        
        return maxHeight
    }
    
    private func calculateTextWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let attributes = [NSAttributedString.Key.font: font]
        let size = text.size(withAttributes: attributes)
        return size.width
    }
}

struct FlexibleTimeEventGrid: View {
    let events: [TimeEvent]
    let tagLibrary: TagLibraryManager
    let onEventTap: (TimeEvent) -> Void
    
    @State private var availableWidth: CGFloat = 0
    @State private var eventRows: [[TimeEvent]] = []
    
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(eventRows.enumerated()), id: \.offset) { rowIndex, rowEvents in
                    HStack(spacing: 6) {
                        ForEach(rowEvents) { event in
                            timeEventButton(for: event)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .onAppear {
                availableWidth = geometry.size.width
                calculateEventRows()
            }
            .onChange(of: geometry.size.width) { newWidth in
                availableWidth = newWidth
                calculateEventRows()
            }
            .onChange(of: events.count) { _ in
                calculateEventRows()
            }
        }
        .frame(height: CGFloat(eventRows.count) * (25 + 8))
    }
    
    private func timeEventButton(for event: TimeEvent) -> some View {
        Button {
            onEventTap(event)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tagLibrary.selectedTimeEvents.contains(event.id) ?
                      "checkmark.circle.fill" : "circle")
                .foregroundColor(tagLibrary.selectedTimeEvents.contains(event.id) ?
                    .accentColor : .secondary)
                .font(.system(size: 20, weight: .medium))
                
                Text(event.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .minimumScaleFactor(0.5)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(minHeight: 25, maxHeight: 25)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tagLibrary.selectedTimeEvents.contains(event.id) ? 
                          Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(tagLibrary.selectedTimeEvents.contains(event.id) ? 
                                   Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(tagLibrary.selectedTimeEvents.contains(event.id) ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: tagLibrary.selectedTimeEvents.contains(event.id))
    }
    
    private func calculateEventRows() {
        guard availableWidth > 0 else { return }
        
        var rows: [[TimeEvent]] = []
        var currentRow: [TimeEvent] = []
        var currentRowWidth: CGFloat = 0
        
        let spacing: CGFloat = 6
        let maxButtonWidth: CGFloat = 200
        
        for event in events {
            let buttonWidth = min(calculateEventButtonWidth(for: event), maxButtonWidth)
            
            if currentRowWidth + buttonWidth + (currentRow.isEmpty ? 0 : spacing) <= availableWidth {
                currentRow.append(event)
                currentRowWidth += buttonWidth + (currentRow.count > 1 ? spacing : 0)
            } else {
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                }
                currentRow = [event]
                currentRowWidth = buttonWidth
            }
        }
        
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        
        eventRows = rows
    }
    
    private func calculateEventButtonWidth(for event: TimeEvent) -> CGFloat {
        let textFont = NSFont.systemFont(ofSize: 14, weight: .medium)
        let textAttributes = [NSAttributedString.Key.font: textFont]
        let textWidth = event.name.size(withAttributes: textAttributes).width
        
        var totalWidth = textWidth
        
        totalWidth += 32
        
        let checkmarkSize: CGFloat = 20
        let checkmarkSpacing: CGFloat = 10
        totalWidth += checkmarkSize + checkmarkSpacing
        
        totalWidth += 8
        
        return totalWidth
    }
    
    private func calculateTextWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let attributes = [NSAttributedString.Key.font: font]
        let size = text.size(withAttributes: attributes)
        return size.width
    }
}

