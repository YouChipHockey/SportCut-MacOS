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
import Combine

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
    @State private var lastSelectedCollectionName: String? = nil
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
    @State private var collectionsScrollPosition: CGFloat = 0
    @State private var cachedPlayField: (name: String, playField: PlayField)? = nil
    
    @State var activeIntervalTags: [ActiveIntervalTag] = []
    
    @State private var tagCounts: [String: Int] = [:]
    
    @State private var updateTimer: Timer?
    
    @State private var refreshID = UUID()
    @State private var windowWidth: CGFloat = 0
    @State private var isEditorModeActive = false
    @State private var isLoadingCollections = false
    
    @State private var isCollectionsPanelCollapsed = false
    @State private var isTimeEventsCollapsed = false
    @State private var isTagsPanelCollapsed = false
    
    enum TagDisplayMode: String {
        case grouped
        case free
    }
    
    @State private var tagDisplayMode: TagDisplayMode = .grouped
    @State private var showFreeModeMissingAlert = false
    
    @EnvironmentObject private var notificationSubscriptions: ProjectNotificationSubscriptions
    
    struct ActiveIntervalTag: Identifiable {
        let id: String
        let tag: Tag
        var startTime: Double
    }
    
    func loadUserCollections() {
        let previousSelectedName = lastSelectedCollectionName
        
        let allCollectionsInfo = CollectionsBookmarksManager.shared.loadCollections()
        userCollections = allCollectionsInfo.map { info in
            CollectionBookmark(
                id: info.id,
                name: info.name,
                tagGroupsBookmark: Data(),
                tagsBookmark: Data(),
                labelGroupsBookmark: Data(),
                labelsBookmark: Data(),
                timeEventsBookmark: Data(),
                playFieldBookmark: nil
            )
        }
        
        if let previousName = previousSelectedName,
           userCollections.contains(where: { $0.name == previousName }) {
            lastSelectedCollectionName = previousName
        }
    }
    
    func backupDefaultData() {}
    
    func forceWindowRefresh() {
        // Removed expensive window resize - SwiftUI updates automatically
    }
    
    func restoreDefaultData() {
        tagLibrary.applyDefaultCollection()
        if let collectionBookmarkName = userCollections.first(where: { $0.name == tagLibrary.selectedStandardCollectionName })?.name ?? tagLibrary.standardCollections.first(where: { $0.name == tagLibrary.selectedStandardCollectionName })?.name {
            lastSelectedCollectionName = collectionBookmarkName
            isUserCollectionActive = !tagLibrary.standardCollections.contains { $0.name == collectionBookmarkName }
        }
        hotkeyManager.registerHotkeys(from: tagLibrary.tags, for: .standard)
        expandedGroups = Set(tagLibrary.tagGroups.map { $0.id })
        loadDisplayModePreference()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            modernHeaderView
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    if !tagLibrary.timeEvents.isEmpty {
                        timeEventsSection
                            .id("timeEvents-\(tagLibrary.timeEvents.count)")
                    }
                    
                    if tagDisplayMode == .grouped {
                        if !tagLibrary.tagGroups.isEmpty {
                            tagGroupsSection
                                .id("tagGroups-\(tagLibrary.tagGroups.count)")
                        }
                    } else {
                        freeTagsSection
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
        .id(refreshID)
        .background(Color(.controlBackgroundColor))
        .sheet(isPresented: $showLabelSheet) {
            stampLabelSheet
        }
        .onAppear(perform: onAppearSetup)
        .onDisappear(perform: onDisappearCleanup)
        .alert(isPresented: $showDeleteAlert) {
            deleteCollectionAlert
        }
        .onReceive(timelineData.$lines.throttle(for: .milliseconds(300), scheduler: DispatchQueue.main, latest: true)) { _ in
            self.updateTagCounts()
        }
        .onChange(of: timelineData.selectedLineID) { _ in
            self.updateTagCounts()
        }
    }
    
    private var modernHeaderView: some View {
        VStack(spacing: 0) {
            HStack {
                collectionTitleView

                if isUserCollectionActive {
                    tagDisplayModePicker
                }

                Spacer()
                
                Text(^String.Titles.groups)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 88, alignment: .leading)
                
                if isLoadingCollections {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(^String.Titles.sportCutLoading)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCollectionsPanelCollapsed.toggle()
                    }
                }) {
                    Image(systemName: isCollectionsPanelCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help(^String.Titles.collections)
                
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
                .disabled(!activeIntervalTags.isEmpty || isLoadingCollections)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.windowBackgroundColor))
            
            if !isCollectionsPanelCollapsed {
                collectionsScrollView
            }
            
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
                 "\(^String.Titles.customCollection) \(lastSelectedCollectionName ?? "")" :
                    ^String.Titles.tagGroups)
            .font(.headline)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            
            if isUserCollectionActive && lastSelectedCollectionName != nil {
                collectionActionButtons
            }
        }
    }
    
    private var tagDisplayModePicker: some View {
        HStack(spacing: 4) {
            Button(action: {
                tagDisplayMode = .grouped
                saveDisplayModePreference()
            }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 11))
                    .foregroundColor(tagDisplayMode == .grouped ? .accentColor : .secondary)
                    .frame(width: 24, height: 24)
                    .background(tagDisplayMode == .grouped ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .help(^String.Titles.freeTagModeGrouped)
            
            Button(action: {
                if isFreeLayoutConfigured {
                    tagDisplayMode = .free
                    saveDisplayModePreference()
                } else {
                    showFreeModeMissingAlert = true
                }
            }) {
                Image(systemName: "rectangle.3.offgrid")
                    .font(.system(size: 11))
                    .foregroundColor(tagDisplayMode == .free ? .accentColor : .secondary)
                    .frame(width: 24, height: 24)
                    .background(tagDisplayMode == .free ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .help(^String.Titles.freeTagModeFree)
        }
        .alert(isPresented: $showFreeModeMissingAlert) {
            Alert(
                title: Text(^String.Titles.freeTagModeNotConfiguredTitle),
                message: Text(^String.Titles.freeTagModeNotConfiguredMessage),
                dismissButton: .default(Text(^String.Titles.alertsOkTitle))
            )
        }
    }

    private var collectionActionButtons: some View {
        HStack(spacing: 8) {
            Button(action: {
                guard let name = lastSelectedCollectionName,
                      let collection = userCollections.first(where: { $0.name == name }) else { return }
                let bookmark = UserDefaults.standard.getCollectionBookmarks().first(where: { $0.name == name })
                    ?? collection
                WindowsManager.shared.openCustomCollectionsWindow(withExistingCollection: bookmark)
            }) {
                Image(systemName: "pencil.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .help(^String.Titles.editCollection)
            
            Button(action: {
                guard let name = lastSelectedCollectionName,
                      let collection = userCollections.first(where: { $0.name == name }) else { return }
                collectionToDelete = collection
                showDeleteAlert = true
            }) {
                Image(systemName: "trash.circle")
                    .foregroundColor(.red)
            }
            
            .help(^String.Titles.deleteCollection)
        }
    }
    
    private var collectionsScrollView: some View {
        VStack(spacing: 4) {
            if !tagLibrary.standardCollections.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(^String.Titles.standardCollections)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tagLibrary.standardCollections, id: \.name) { collection in
                                standardCollectionChip(
                                    collection: collection,
                                    isSelected: tagLibrary.selectedStandardCollectionName == collection.name && !isUserCollectionActive
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            
            if !userCollections.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(^String.Titles.customCollections)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(userCollections, id: \.name) { collection in
                                customCollectionChip(collection: collection)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor))
    }
    
    private func standardCollectionChip(collection: StandardCollection, isSelected: Bool) -> some View {
        Button(action: {
            guard activeIntervalTags.isEmpty else { return }
            guard !isLoadingCollections else { return }
            isUserCollectionActive = false
            lastSelectedCollectionName = collection.name
            cachedPlayField = nil
            tagLibrary.applyStandardCollection(named: collection.name)
            tagDisplayMode = .grouped
            DispatchQueue.main.async {
                self.expandedGroups = Set(self.tagLibrary.tagGroups.map { $0.id })
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
            .opacity(isLoadingCollections ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!activeIntervalTags.isEmpty || isLoadingCollections)
    }
    
    private func customCollectionChip(collection: CollectionBookmark) -> some View {
        let isSelected = isUserCollectionActive && lastSelectedCollectionName == collection.name
        
        return Button(action: {
            guard activeIntervalTags.isEmpty else { return }
            guard !isLoadingCollections else { return }
            lastSelectedCollectionName = collection.name
            isUserCollectionActive = true
            loadUserCollection(collection)
            loadDisplayModePreference()
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
            .opacity(isLoadingCollections ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!activeIntervalTags.isEmpty || isLoadingCollections)
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
                    lastSelectedCollectionName = collection.name
                    tagLibrary.applyStandardCollection(named: collection.name)
                    DispatchQueue.main.async {
                        self.expandedGroups = Set(self.tagLibrary.tagGroups.map { $0.id })
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
            cachedPlayField = nil // Clear cached playField when switching to standard collection
            if let collectionName =
                tagLibrary.selectedStandardCollectionName
                ??
                tagLibrary.standardCollections.first?.name
            {
                tagLibrary.applyStandardCollection(named: collectionName)
                lastSelectedCollectionName = collectionName
            }
            DispatchQueue.main.async {
                self.expandedGroups = Set(self.tagLibrary.tagGroups.map { $0.id })
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
                lastSelectedCollectionName = collection.name
                isUserCollectionActive = true
                loadUserCollection(collection)
            }) {
                HStack {
                    Text(collection.name)
                    Spacer()
                    if isUserCollectionActive && lastSelectedCollectionName == collection.name {
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
                cachedPlayField = nil // Clear cached playField when switching to standard collection
                if let collectionName =
                    tagLibrary.selectedStandardCollectionName
                    ??
                    tagLibrary.standardCollections.first?.name
                {
                    tagLibrary.applyStandardCollection(named: collectionName)
                    lastSelectedCollectionName = collectionName
                }
                DispatchQueue.main.async {
                    self.expandedGroups = Set(self.tagLibrary.tagGroups.map { $0.id })
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
                    LazyVStack(alignment: .leading, spacing: 4) {
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
                lastSelectedCollectionName = collection.name
                isUserCollectionActive = true
                loadUserCollection(collection)
                showCollectionsList = false
            }) {
                Text(collection.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(5)
            .background(isUserCollectionActive && lastSelectedCollectionName == collection.name
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
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTimeEventsCollapsed.toggle()
                    }
                }) {
                    Image(systemName: isTimeEventsCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            
            if !isTimeEventsCollapsed {
                FlexibleTimeEventGrid(events: tagLibrary.timeEvents, tagLibrary: tagLibrary, onEventTap: { event in
                    guard !isEditorModeActive else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tagLibrary.toggleTimeEvent(id: event.id)
                    }
                })
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
        )
    }
    
    
    private var tagGroupsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "tag")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14, weight: .medium))
                
                Text(^String.Titles.tagGroups)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTagsPanelCollapsed.toggle()
                    }
                }) {
                    Image(systemName: isTagsPanelCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            
            if !isTagsPanelCollapsed {
                ForEach(tagLibrary.tagGroups) { group in
                    tagGroupView(for: group)
                }
            }
        }
    }
    
    @ViewBuilder
    private var freeTagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "rectangle.3.offgrid")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14, weight: .medium))
                
                Text(^String.Titles.freeTagModeDisplay)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTagsPanelCollapsed.toggle()
                    }
                }) {
                    Image(systemName: isTagsPanelCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            
            if !isTagsPanelCollapsed {
                FreeTagsCanvasView(
                    tags: tagLibrary.tags,
                    onTagTap: handleTagButtonTap,
                    activeIntervalTags: activeIntervalTags,
                    hoveredTagID: hoveredTagID,
                    tagCounts: tagCounts
                )
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
        )
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
    
    
    private func addTagToTimeline(tag: Tag, selectedLabels: [FullLabelWithGroup]) {
        if tag.mapEnabled == true {
            // Use cached playField if available, otherwise load
            if let collectionName = tagLibrary.currentCollectionType.name {
                if let cached = cachedPlayField, cached.name == collectionName,
                   let imageBookmark = cached.playField.imageBookmark {
                    showFieldMapSelection(tag: tag, imageBookmark: imageBookmark, selectedLabels: selectedLabels)
                    return
                } else {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let collectionManager = CustomCollectionManager()
                        if collectionManager.loadCollectionFromBookmarks(named: collectionName),
                           let playField = collectionManager.playField,
                           let imageBookmark = playField.imageBookmark {
                            DispatchQueue.main.async {
                                self.cachedPlayField = (name: collectionName, playField: playField)
                                self.showFieldMapSelection(tag: tag, imageBookmark: imageBookmark, selectedLabels: selectedLabels)
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.proceedWithTagAddition(tag: tag, selectedLabels: selectedLabels, coordinates: nil)
                            }
                        }
                    }
                    return
                }
            }
        }
        
        proceedWithTagAddition(tag: tag, selectedLabels: selectedLabels, coordinates: nil)
    }
    
    private func showFieldMapSelection(tag: Tag, imageBookmark: Data, selectedLabels: [FullLabelWithGroup]) {
        WindowsManager.shared.showFieldMapSelection(tag: tag, imageBookmark: imageBookmark) { [self] coordinates in
            proceedWithTagAddition(tag: tag, selectedLabels: selectedLabels, coordinates: coordinates)
            if videoManager.playbackSpeed > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    videoManager.player?.play()
                }
            }
        }
    }
    
    private func proceedWithTagAddition(tag: Tag, selectedLabels: [FullLabelWithGroup], coordinates: CGPoint?) {
        let currentTime = videoManager.currentTime
        let videoDuration = max(1.0, videoManager.timelineDuration)
        let startTime = max(0, currentTime - tag.defaultTimeBefore)
        let finishTime = min(videoDuration, startTime + tag.defaultTimeBefore + tag.defaultTimeAfter)
        
        var fieldPosition: CGPoint? = nil
        if let normalizedCoords = coordinates {
            // Use cached playField if available
            if let collectionName = tagLibrary.currentCollectionType.name,
               let cached = cachedPlayField, cached.name == collectionName {
                let playField = cached.playField
                let fieldWidth = CGFloat(playField.width)
                let fieldHeight = CGFloat(playField.height)
                
                let fieldX = normalizedCoords.x * fieldWidth
                let fieldY = normalizedCoords.y * fieldHeight
                
                fieldPosition = CGPoint(x: fieldX, y: fieldY)
            }
        }
        
        let tagGroupId = tagLibrary.allTagGroups.first(where: { $0.tags.contains(tag.id) })?.id ?? ""
        
        timelineData.addStampToSelectedLine(
            tagRefs: [StampTagRef(id: tag.id, tagGroupId: tagGroupId)],
            primaryId: tag.primaryID,
            name: tag.name,
            timeStartSeconds: startTime,
            timeFinishSeconds: finishTime,
            color: tag.color,
            labels: selectedLabels,
            position: fieldPosition
        )
        
        VideoMarkupActivityBanner.shared.notifyInstantTagAdded(tagName: tag.name)
        
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
                // Optimize label check using Set for O(1) lookup
                let labelGroupIdsSet = Set(tag.lablesGroup)
                let hasLabels = tagLibrary.allLabelGroups.contains { labelGroupIdsSet.contains($0.id) }
                
                if hasLabels {
                    StampItemsSelectionSheet(
                        sheetType: .lables,
                        stampName: tag.name,
                        initialIds: [],
                        tag: tag,
                        tagLibrary: TagLibraryManager.shared,
                        onDone: { selectedLabelIds in
                            let fullLabels = Self.buildFullLabels(from: selectedLabelIds)
                            if tag.isInterval == true {
                                if let firstActiveTag = activeIntervalTags.first(where: { $0.tag.id == tag.id }) {
                                    let videoDuration = max(1.0, videoManager.timelineDuration)
                                    let start = max(0, firstActiveTag.startTime - tag.defaultTimeBefore)
                                    let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
                                    let timeStart = min(start, end)
                                    let timeFinish = max(start, end)
                                    
                                    
                                    activeIntervalTags.removeAll { $0.tag.id == tag.id }
                                    
                                    addTagToTimelineInterval(
                                        tag: tag,
                                        timeStartSeconds: timeStart,
                                        timeFinishSeconds: timeFinish,
                                        selectedLabels: fullLabels
                                    )
                                }
                            } else {
                                addTagToTimeline(tag: tag, selectedLabels: fullLabels)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showLabelSheet = false
                            }
                        },
                        onCancel: {
                            self.videoManager.player?.play()
                            if let tag = selectedTag, tag.isInterval == true {
                                activeIntervalTags.removeAll { $0.tag.id == tag.id }
                                VideoMarkupActivityBanner.shared.cancelIntervalRecording(tagName: tag.name)
                            }
                        }
                    )
                } else {
                    VStack {
                        Text(^String.Titles.tagLibraryAddingTag)
                            .onAppear {
                                if tag.isInterval == true {
                                    if let firstActiveTag = activeIntervalTags.first(where: { $0.tag.id == tag.id }) {
                                        let videoDuration = max(1.0, videoManager.timelineDuration)
                                        let start = max(0, firstActiveTag.startTime - tag.defaultTimeBefore)
                                        let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
                                        let timeStart = min(start, end)
                                        let timeFinish = max(start, end)
                                        
                                        
                                        activeIntervalTags.removeAll { $0.tag.id == tag.id }
                                        
                                        addTagToTimelineInterval(
                                            tag: tag,
                                            timeStartSeconds: timeStart,
                                            timeFinishSeconds: timeFinish,
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
                // Optimize label check using Set for O(1) lookup
                let labelGroupIdsSet = Set(tag.lablesGroup)
                let hasLabels = tagLibrary.allLabelGroups.contains { labelGroupIdsSet.contains($0.id) }
                
                if hasLabels {
                    StampItemsSelectionSheet(
                        sheetType: .lables,
                        stampName: tag.name,
                        initialIds: [],
                        tag: tag,
                        tagLibrary: TagLibraryManager.shared,
                        onDone: { selectedLabelIds in
                            let fullLabels = Self.buildFullLabels(from: selectedLabelIds)
                            if tag.isInterval == true {
                                if let firstActiveTag = activeIntervalTags.first(where: { $0.tag.id == tag.id }) {
                                    let videoDuration = max(1.0, videoManager.timelineDuration)
                                    let start = max(0, firstActiveTag.startTime - tag.defaultTimeBefore)
                                    let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
                                    let timeStart = min(start, end)
                                    let timeFinish = max(start, end)
                                    
                                    
                                    activeIntervalTags.removeAll { $0.tag.id == tag.id }
                                    
                                    addTagToTimelineInterval(
                                        tag: tag,
                                        timeStartSeconds: timeStart,
                                        timeFinishSeconds: timeFinish,
                                        selectedLabels: fullLabels
                                    )
                                }
                            } else {
                                addTagToTimeline(tag: tag, selectedLabels: fullLabels)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showLabelSheet = false
                            }
                        },
                        onCancel: {
                            self.videoManager.player?.play()
                            if let tag = selectedTag, tag.isInterval == true {
                                activeIntervalTags.removeAll { $0.tag.id == tag.id }
                                VideoMarkupActivityBanner.shared.cancelIntervalRecording(tagName: tag.name)
                            }
                        }
                    )
                } else {
                    VStack {
                        Text(^String.Titles.tagLibraryAddingTag)
                            .onAppear {
                                if tag.isInterval == true {
                                    if let firstActiveTag = activeIntervalTags.first(where: { $0.tag.id == tag.id }) {
                                        let videoDuration = max(1.0, videoManager.timelineDuration)
                                        let start = max(0, firstActiveTag.startTime - tag.defaultTimeBefore)
                                        let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
                                        let timeStart = min(start, end)
                                        let timeFinish = max(start, end)
                                        
                                        
                                        activeIntervalTags.removeAll { $0.tag.id == tag.id }
                                        
                                        addTagToTimelineInterval(
                                            tag: tag,
                                            timeStartSeconds: timeStart,
                                            timeFinishSeconds: timeFinish,
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
        setupNotificationSubscriptions()
        loadUserCollections()
        backupDefaultData()
        restoreDefaultData()
        markupMode = MarkupMode.current
        updateTagCounts()
        expandedGroups = Set(tagLibrary.tagGroups.map { $0.id })
    }
    
    private func setupNotificationSubscriptions() {
        notificationSubscriptions.cancelAll()
        notificationSubscriptions.store(
            NotificationCenter.default.publisher(for: .markupModeChanged)
                .receive(on: DispatchQueue.main)
                .sink { [self] notification in
                    if let newMode = notification.object as? MarkupMode {
                        markupMode = newMode
                    } else {
                        markupMode = MarkupMode.current
                    }
                }
        )
        notificationSubscriptions.store(
            NotificationCenter.default.publisher(for: .collectionDataChanged)
                .receive(on: DispatchQueue.main)
                .sink { [self] notification in
                    let allCollectionsInfo = CollectionsBookmarksManager.shared.loadCollections()
                    userCollections = allCollectionsInfo.map { info in
                        CollectionBookmark(
                            id: info.id, name: info.name,
                            tagGroupsBookmark: Data(), tagsBookmark: Data(),
                            labelGroupsBookmark: Data(), labelsBookmark: Data(),
                            timeEventsBookmark: Data(), playFieldBookmark: nil
                        )
                    }
                    let changedName = notification.userInfo?[Notification.Key.collectionName] as? String
                    if changedName != nil {
                        return
                    }
                    if isUserCollectionActive, let currentName = lastSelectedCollectionName,
                       let updatedCollection = userCollections.first(where: { $0.name == currentName }) {
                        lastSelectedCollectionName = updatedCollection.name
                        tagLibrary.invalidateCollectionCache(for: updatedCollection.name)
                        loadUserCollection(updatedCollection)
                    }
                }
        )
        notificationSubscriptions.store(
            NotificationCenter.default.publisher(for: .currentCollectionRefreshed)
                .receive(on: DispatchQueue.main)
                .sink { [self] _ in refreshID = UUID() }
        )
        notificationSubscriptions.store(
            NotificationCenter.default.publisher(for: .showLabelSheet)
                .receive(on: DispatchQueue.main)
                .sink { [self] notification in
                    guard let tag = notification.object as? Tag else { return }
                    if tag.isInterval ?? false {
                        if let index = activeIntervalTags.firstIndex(where: { $0.tag.id == tag.id }) {
                            let activeTag = activeIntervalTags[index]
                            let videoDuration = max(1.0, videoManager.videoDuration)
                            let start = max(0, activeTag.startTime - tag.defaultTimeBefore)
                            let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
                            let timeStart = min(start, end)
                            let timeFinish = max(start, end)
                            selectedTag = tag
                            showLabelSheet = false
                            videoManager.player?.pause()
                            let labelGroupIdsSet = Set(tag.lablesGroup)
                            let hasLabels = tagLibrary.allLabelGroups.contains { labelGroupIdsSet.contains($0.id) }
                            if hasLabels {
                                showLabelSheet = true
                            } else {
                                activeIntervalTags.remove(at: index)
                                addTagToTimelineInterval(tag: tag, timeStartSeconds: timeStart, timeFinishSeconds: timeFinish, selectedLabels: [])
                            }
                        } else {
                            guard !activeIntervalTags.contains(where: { $0.tag.id == tag.id }) else { return }
                            activeIntervalTags.append(ActiveIntervalTag(id: UUID().uuidString, tag: tag, startTime: videoManager.currentTime))
                            VideoMarkupActivityBanner.shared.startIntervalRecording(tagName: tag.name)
                        }
                        return
                    }
                    selectedTag = tag
                    videoManager.player?.pause()
                    let labelGroupIdsSet = Set(tag.lablesGroup)
                    let hasLabels = tagLibrary.allLabelGroups.contains { labelGroupIdsSet.contains($0.id) }
                    if hasLabels {
                        showLabelSheet = true
                    } else {
                        addTagToTimeline(tag: tag, selectedLabels: [])
                    }
                }
        )
        notificationSubscriptions.store(
            NotificationCenter.default.publisher(for: .stampCountsChanged)
                .receive(on: DispatchQueue.main)
                .sink { [self] _ in updateTagCounts() }
        )
        notificationSubscriptions.store(
            NotificationCenter.default.publisher(for: .editorModeChanged)
                .receive(on: DispatchQueue.main)
                .sink { [self] notification in
                    if let isActive = notification.object as? Bool {
                        isEditorModeActive = isActive
                    }
                }
        )
        notificationSubscriptions.store(
            NotificationCenter.default.publisher(for: .collectionsLoadingStarted)
                .receive(on: DispatchQueue.main)
                .sink { [self] _ in isLoadingCollections = true }
        )
        notificationSubscriptions.store(
            NotificationCenter.default.publisher(for: .collectionsLoadingFinished)
                .receive(on: DispatchQueue.main)
                .sink { [self] _ in
                    isLoadingCollections = false
                    if isUserCollectionActive, let currentName = lastSelectedCollectionName,
                       let collection = userCollections.first(where: { $0.name == currentName }) {
                        loadUserCollection(collection)
                        refreshID = UUID()
                    }
                }
        )
    }
    
    private func onDisappearCleanup() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    func loadUserCollection(_ collection: CollectionBookmark) {
        // Try to get from cache first, otherwise load asynchronously
        if let cachedData = tagLibrary.getCollectionData(for: collection.name) {
            // Use cached data immediately
            tagLibrary.tags = cachedData.tags
            tagLibrary.tagGroups = cachedData.tagGroups
            tagLibrary.labelGroups = cachedData.labelGroups
            tagLibrary.labels = cachedData.labels
            tagLibrary.timeEvents = cachedData.timeEvents
            tagLibrary.selectedTimeEvents.removeAll()
            tagLibrary.currentCollectionType = .user(name: collection.name)
            HotKeyManager.shared.clearHotkeys()
            HotKeyManager.shared.registerHotkeys(from: cachedData.tags, for: .user(name: collection.name))
            UserDefaults.standard.set(collection.name, forKey: UserDefaults.Keys.lastSelectedCollection)
            
            cachePlayFieldForCollection(collection.name)
            
            updateTagCounts()
            expandedGroups = Set(tagLibrary.tagGroups.map { $0.id })
            tagLibrary.objectWillChange.send()
        } else {
            // Load asynchronously if not cached
            DispatchQueue.global(qos: .userInitiated).async {
                let collectionManager = CustomCollectionManager()
                if collectionManager.loadCollectionFromBookmarks(named: collection.name) {
                    DispatchQueue.main.async {
                        self.tagLibrary.tags = collectionManager.tags
                        self.tagLibrary.tagGroups = collectionManager.tagGroups
                        self.tagLibrary.labelGroups = collectionManager.labelGroups
                        self.tagLibrary.labels = collectionManager.labels
                        self.tagLibrary.timeEvents = collectionManager.timeEvents
                        self.tagLibrary.selectedTimeEvents.removeAll()
                        self.tagLibrary.currentCollectionType = .user(name: collection.name)
                        HotKeyManager.shared.clearHotkeys()
                        HotKeyManager.shared.registerHotkeys(from: collectionManager.tags, for: .user(name: collection.name))
                        UserDefaults.standard.set(collection.name, forKey: UserDefaults.Keys.lastSelectedCollection)
                        
                        // Cache playField
                        if let playField = collectionManager.playField {
                            self.cachedPlayField = (name: collection.name, playField: playField)
                        }
                        
                        self.updateTagCounts()
                        self.expandedGroups = Set(self.tagLibrary.tagGroups.map { $0.id })
                        self.tagLibrary.objectWillChange.send()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.tagLibrary.tags = []
                        self.tagLibrary.tagGroups = []
                        self.tagLibrary.labelGroups = []
                        self.tagLibrary.labels = []
                        self.tagLibrary.timeEvents = []
                        self.tagLibrary.selectedTimeEvents.removeAll()
                        self.tagLibrary.currentCollectionType = .standard
                        HotKeyManager.shared.clearHotkeys()
                        self.cachedPlayField = nil
                    }
                }
            }
        }
    }
    
    /// Cache playField for current collection to avoid reloading
    private func cachePlayFieldForCollection(_ collectionName: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let collectionManager = CustomCollectionManager()
            if collectionManager.loadCollectionFromBookmarks(named: collectionName),
               let playField = collectionManager.playField {
                DispatchQueue.main.async {
                    self.cachedPlayField = (name: collectionName, playField: playField)
                }
            }
        }
    }
    
    private func deleteCollection(_ collection: CollectionBookmark) {
        InMemoryStorageManager.shared.deleteCollection(id: collection.id)
        
        CollectionsBookmarksManager.shared.removeCollection(id: collection.id)
        
        tagLibrary.invalidateCollectionCache(for: collection.name)
        
        if isUserCollectionActive && lastSelectedCollectionName == collection.name {
            isUserCollectionActive = false
            lastSelectedCollectionName = nil
            restoreDefaultData()
        }
        
        loadUserCollections()
        tagLibrary.refreshGlobalPools()
        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
    }
    
    private func handleTagButtonTap(tag: Tag) {
        // Блокируем добавление тегов в режиме редактирования
        guard !isEditorModeActive else { return }
        
        if tag.isInterval ?? false {
            if let index = activeIntervalTags.firstIndex(where: { $0.tag.id == tag.id }) {
                let activeTag = activeIntervalTags[index]
                let videoDuration = max(1.0, videoManager.timelineDuration)
                let start = max(0, activeTag.startTime - tag.defaultTimeBefore)
                let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
                let timeStart = min(start, end)
                let timeFinish = max(start, end)
                
                selectedTag = tag
                showLabelSheet = false
                
                DispatchQueue.main.async {
                    videoManager.player?.pause()
                    // Optimize label check using Set for O(1) lookup
                let labelGroupIdsSet = Set(tag.lablesGroup)
                let hasLabels = tagLibrary.allLabelGroups.contains { labelGroupIdsSet.contains($0.id) }
                    if hasLabels {
                        showLabelSheet = true
                    } else {
                        activeIntervalTags.remove(at: index)
                        addTagToTimelineInterval(tag: tag, timeStartSeconds: timeStart, timeFinishSeconds: timeFinish, selectedLabels: [])
                    }
                }
            } else {
                guard !activeIntervalTags.contains(where: { $0.tag.id == tag.id }) else {
                    return
                }
                activeIntervalTags.append(ActiveIntervalTag(id: UUID().uuidString, tag: tag, startTime: videoManager.currentTime))
                VideoMarkupActivityBanner.shared.startIntervalRecording(tagName: tag.name)
            }
            return
        }
        
        videoManager.player?.pause()
        selectedTag = tag
        
        // Optimize label check using Set for O(1) lookup - do it immediately
        let labelGroupIdsSet = Set(tag.lablesGroup)
        let hasLabels = tagLibrary.allLabelGroups.contains { labelGroupIdsSet.contains($0.id) }
        
        if hasLabels {
            // Show sheet immediately without delay
            showLabelSheet = true
        } else {
            // No labels - add tag immediately without showing sheet
            addTagToTimeline(tag: tag, selectedLabels: [])
        }
    }
    
    private func addTagToTimelineInterval(tag: Tag, timeStartSeconds: Double, timeFinishSeconds: Double, selectedLabels: [FullLabelWithGroup]) {
        if tag.mapEnabled == true {
            // Use cached playField if available, otherwise load
            if let collectionName = tagLibrary.currentCollectionType.name {
                if let cached = cachedPlayField, cached.name == collectionName,
                   let imageBookmark = cached.playField.imageBookmark {
                    showFieldMapSelectionInterval(tag: tag, imageBookmark: imageBookmark, timeStartSeconds: timeStartSeconds, timeFinishSeconds: timeFinishSeconds, selectedLabels: selectedLabels)
                    return
                } else {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let collectionManager = CustomCollectionManager()
                        if collectionManager.loadCollectionFromBookmarks(named: collectionName),
                           let playField = collectionManager.playField,
                           let imageBookmark = playField.imageBookmark {
                            DispatchQueue.main.async {
                                self.cachedPlayField = (name: collectionName, playField: playField)
                                self.showFieldMapSelectionInterval(tag: tag, imageBookmark: imageBookmark, timeStartSeconds: timeStartSeconds, timeFinishSeconds: timeFinishSeconds, selectedLabels: selectedLabels)
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.proceedWithTagAdditionInterval(tag: tag, timeStartSeconds: timeStartSeconds, timeFinishSeconds: timeFinishSeconds, coordinates: nil, selectedLabels: selectedLabels)
                            }
                        }
                    }
                    return
                }
            }
        }
        proceedWithTagAdditionInterval(tag: tag, timeStartSeconds: timeStartSeconds, timeFinishSeconds: timeFinishSeconds, coordinates: nil, selectedLabels: selectedLabels)
    }
    
    private func showFieldMapSelectionInterval(tag: Tag, imageBookmark: Data, timeStartSeconds: Double, timeFinishSeconds: Double, selectedLabels: [FullLabelWithGroup]) {
        WindowsManager.shared.showFieldMapSelection(tag: tag, imageBookmark: imageBookmark) { [self] coordinates in
            proceedWithTagAdditionInterval(tag: tag, timeStartSeconds: timeStartSeconds, timeFinishSeconds: timeFinishSeconds, coordinates: coordinates, selectedLabels: selectedLabels)
            if videoManager.playbackSpeed > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    videoManager.player?.play()
                }
            }
        }
    }
    
    private func proceedWithTagAdditionInterval(tag: Tag, timeStartSeconds: Double, timeFinishSeconds: Double, coordinates: CGPoint?, selectedLabels: [FullLabelWithGroup]) {
        
        var fieldPosition: CGPoint? = nil
        if let normalizedCoords = coordinates {
            // Use cached playField if available
            if let collectionName = tagLibrary.currentCollectionType.name,
               let cached = cachedPlayField, cached.name == collectionName {
                let playField = cached.playField
                let fieldWidth = CGFloat(playField.width)
                let fieldHeight = CGFloat(playField.height)
                let fieldX = normalizedCoords.x * fieldWidth
                let fieldY = normalizedCoords.y * fieldHeight
                fieldPosition = CGPoint(x: fieldX, y: fieldY)
            }
        }
        
        let tagGroupId = tagLibrary.allTagGroups.first(where: { $0.tags.contains(tag.id) })?.id ?? ""
        
        timelineData.addStampToSelectedLine(
            tagRefs: [StampTagRef(id: tag.id, tagGroupId: tagGroupId)],
            primaryId: tag.primaryID,
            name: tag.name,
            timeStartSeconds: timeStartSeconds,
            timeFinishSeconds: timeFinishSeconds,
            color: tag.color,
            labels: selectedLabels,
            position: fieldPosition
        )
        
        VideoMarkupActivityBanner.shared.completeIntervalRecording(tagName: tag.name)
        
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
    
    static func buildFullLabels(from labelIds: [String]) -> [FullLabelWithGroup] {
        let tagLibrary = TagLibraryManager.shared
        return labelIds.compactMap { labelID -> FullLabelWithGroup? in
            guard let label = tagLibrary.findLabelById(labelID) else { return nil }
            let groupId = tagLibrary.allLabelGroups.first(where: { $0.lables.contains(labelID) })?.id ?? ""
            return FullLabelWithGroup(id: label.id, name: label.name, description: label.description, lableGroupId: groupId)
        }
    }
    
    private func updateTagCounts() {
        var counts: [String: Int] = [:]
        
        for line in timelineData.lines {
            for stamp in line.stamps {
                for tagID in stamp.idTags {
                    counts[tagID, default: 0] += 1
                }
            }
        }
        
        tagCounts = counts
    }
    
    private func countTagsInTimeline(tagId: String) -> Int {
        return tagCounts[tagId] ?? 0
    }

    private func loadDisplayModePreference() {
        if let raw = UserDefaults.standard.string(forKey: displayModeKey),
           let mode = TagDisplayMode(rawValue: raw) {
            if mode == .free && !isFreeLayoutConfigured {
                tagDisplayMode = .grouped
            } else {
                tagDisplayMode = mode
            }
        } else {
            tagDisplayMode = .grouped
        }
    }

    private func saveDisplayModePreference() {
        UserDefaults.standard.set(tagDisplayMode.rawValue, forKey: displayModeKey)
    }

    private var displayModeKey: String {
        let suffix = lastSelectedCollectionName ?? "__standard__"
        return "TagLibraryDisplayMode_\(suffix)"
    }

    private var isFreeLayoutConfigured: Bool {
        guard case .user(let name) = TagLibraryManager.shared.currentCollectionType,
              let info = CollectionsBookmarksManager.shared.loadCollections().first(where: { $0.name == name }) else {
            return false
        }
        return TagFreeLayoutStorage.loadLayoutIfExists(collectionId: info.id, tags: tagLibrary.tags) != nil
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

