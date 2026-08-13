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
    @ObservedObject var keyBindingRuntime = KeyBindingRuntimeManager.shared
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
    @State private var showCollectionsList = false
    @State private var showCreateCollectionTypeSheet = false
    @State private var currentTagForMap: Tag? = nil
    @State private var currentSelectedLabels: [String] = []
    @State private var fieldMapBookmark: Data? = nil
    
    @State private var expandedGroups: Set<String> = []
    @State private var collectionsScrollPosition: CGFloat = 0
    /// Кэш всех карт текущей коллекции. Карта для тега выбирается по `tag.mapFieldId` (иначе первая).
    @State private var cachedPlayFields: (name: String, fields: [PlayField])? = nil
    
    @State var activeIntervalTags: [ActiveIntervalTag] = []
    /// Время клика по мгновенному тегу до листа лейблов (в live иначе подтверждение сдвигает `currentTime`).
    @State private var pendingInstantTagAnchorTime: Double? = nil
    /// Зафиксированный диапазон интервала при открытии листа лейблов на втором нажатии.
    @State private var pendingIntervalClosureRange: (timeStart: Double, timeFinish: Double)? = nil
    
    @State private var tagCounts: [String: Int] = [:]
    
    @State private var updateTimer: Timer?
    
    @State private var refreshID = UUID()
    @State private var windowWidth: CGFloat = 0
    @State private var isEditorModeActive = false
    @State private var isLoadingCollections = false
    
    @State private var isTimeEventsCollapsed = false
    @State private var isTagsPanelCollapsed = false
    
    enum TagDisplayMode: String {
        case grouped
        case free
    }
    
    @State private var tagDisplayMode: TagDisplayMode = .grouped
    /// Режим визуального показа связок: под/над кнопками — включён (нажатие на тег рисует стрелки), скрыто — выключен.
    @State private var bindingsArrowVisibility: KeyBindingArrowVisibility = .hidden
    @State private var tagLibraryScale: Double = 1.0
    @State private var isScalePopoverPresented = false
    /// Масштаб на момент начала pinch-жеста тачпада — база для относительного зума.
    @State private var tagLibraryScaleGestureStart: Double? = nil

    private static let tagLibraryScaleRange = 0.75...3.0

    private func clampedTagLibraryScale(_ value: Double) -> Double {
        min(max(value, Self.tagLibraryScaleRange.lowerBound), Self.tagLibraryScaleRange.upperBound)
    }

    /// Зум двумя пальцами по тачпаду (pinch). Не блокирует тапы/скролл — навешивается как simultaneousGesture.
    private var tagLibraryMagnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let start = tagLibraryScaleGestureStart ?? tagLibraryScale
                if tagLibraryScaleGestureStart == nil {
                    tagLibraryScaleGestureStart = start
                }
                tagLibraryScale = clampedTagLibraryScale(start * Double(value))
            }
            .onEnded { value in
                let start = tagLibraryScaleGestureStart ?? tagLibraryScale
                tagLibraryScale = clampedTagLibraryScale(start * Double(value))
                tagLibraryScaleGestureStart = nil
                saveScalePreference()
            }
    }
    
    @EnvironmentObject private var notificationSubscriptions: ProjectNotificationSubscriptions
    
    struct ActiveIntervalTag: Identifiable {
        let id: String
        let tag: Tag
        var startTime: Double
        var pendingLabelIds: [String] = []
        /// Позиция с инлайн-карты, выбранная во время записи (штампа ещё нет) — применится по завершении.
        var pendingPosition: CGPoint? = nil
        var pendingMapFieldId: String? = nil
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
        applyCollectionDisplayMode()
        loadScalePreference()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            modernHeaderView
            
            Group {
                if tagDisplayMode == .free {
                    freeModeBody
                } else {
                    groupedModeBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.controlBackgroundColor))
            
            if !showUserCollectionsMenu, showCollectionsList {
                legacyCollectionsListView
                    .background(Color(.windowBackgroundColor))
                    .frame(height: 300)
            }
        }
        .id(refreshID)
        .background(Color(.controlBackgroundColor))
        .sheet(isPresented: $showLabelSheet, onDismiss: {
            pendingInstantTagAnchorTime = nil
            pendingIntervalClosureRange = nil
        }) {
            stampLabelSheet
        }
        .onAppear(perform: onAppearSetup)
        .onDisappear(perform: onDisappearCleanup)
        .onReceive(timelineData.$lines.throttle(for: .milliseconds(300), scheduler: DispatchQueue.main, latest: true)) { _ in
            self.updateTagCounts()
        }
        .onChange(of: timelineData.selectedLineID) { _ in
            self.updateTagCounts()
        }
        .simultaneousGesture(tagLibraryMagnificationGesture)
    }

    private var groupedModeBody: some View {
        ScrollView {
            // On older macOS a `LazyVStack` inside a `ScrollView` can mis-measure its content height
            // (content built from GeometryReader-based flow layouts), which leaves the list
            // unscrollable. A plain `VStack` measures eagerly and scrolls correctly; tag collections
            // are small enough that we don't need laziness here. New macOS keeps `LazyVStack`.
            Group {
                if #available(macOS 14.0, *) {
                    LazyVStack(spacing: 8) { groupedModeContent }
                } else {
                    VStack(spacing: 8) { groupedModeContent }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var groupedModeContent: some View {
        if !tagLibrary.timeEvents.isEmpty {
            timeEventsSection
                .id("timeEvents-\(tagLibrary.timeEvents.count)")
        }

        if !tagLibrary.tagGroups.isEmpty {
            tagGroupsSection
                .id("tagGroups-\(tagLibrary.tagGroups.count)")
        }

        if tagLibrary.timeEvents.isEmpty && tagLibrary.tagGroups.isEmpty {
            emptyStateView
        }
    }

    private var freeModeBody: some View {
        VStack(spacing: 8) {
            if !tagLibrary.tags.isEmpty {
                freeTagsSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyStateView
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private var modernHeaderView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                collectionsPickerMenu

                if isUserCollectionActive, lastSelectedCollectionName != nil {
                    editCollectionButton
                }

                tagLibraryScaleControl

                if tagDisplayMode == .free {
                    bindingsVisibilityControl
                }

                Spacer()

                if isLoadingCollections {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(^String.Titles.sportCutLoading)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.windowBackgroundColor))

            Divider()
                .background(Color(.separatorColor))
        }
    }

    private var selectedCollectionTitle: String {
        if isUserCollectionActive, let name = lastSelectedCollectionName {
            return name
        }
        if let standardName = tagLibrary.selectedStandardCollectionName {
            return standardName
        }
        return ^String.Titles.tagGroups
    }

    private var collectionsPickerMenu: some View {
        Menu {
            Button(action: { showCreateCollectionTypeSheet = true }) {
                SwiftUI.Label(^String.Titles.createNewCollection, systemImage: "plus.circle")
            }
            Divider()

            if !tagLibrary.standardCollections.isEmpty {
                Section(^String.Titles.standardCollections) {
                    ForEach(tagLibrary.standardCollections, id: \.name) { collection in
                        Button(action: {
                            selectStandardCollection(collection)
                        }) {
                            HStack {
                                Text(collection.name)
                                Spacer()
                                if tagLibrary.selectedStandardCollectionName == collection.name && !isUserCollectionActive {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(!activeIntervalTags.isEmpty || isLoadingCollections)
                    }
                }
            }

            if !userCollections.isEmpty {
                Section(^String.Titles.customCollections) {
                    ForEach(userCollections, id: \.name) { collection in
                        Button(action: {
                            selectUserCollection(collection)
                        }) {
                            HStack {
                                Text(collection.name)
                                Spacer()
                                if isUserCollectionActive && lastSelectedCollectionName == collection.name {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(!activeIntervalTags.isEmpty || isLoadingCollections)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 13))
                Text(selectedCollectionTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(isLoadingCollections)
        .sheet(isPresented: $showCreateCollectionTypeSheet) {
            CreateCollectionTypeSheet(isPresented: $showCreateCollectionTypeSheet)
        }
    }

    private var editCollectionButton: some View {
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
    }

    private var tagLibraryScaleControl: some View {
        Button {
            isScalePopoverPresented.toggle()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .help(^String.Titles.momentScaleLabel)
        .popover(isPresented: $isScalePopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(^String.Titles.momentScaleLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    // Older macOS: the slider alone is fiddly, so expose explicit −/+ zoom buttons.
                    if #unavailable(macOS 18.0) {
                        Button {
                            adjustTagLibraryScale(by: -Self.tagLibraryScaleStep)
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .disabled(tagLibraryScale <= Self.tagLibraryScaleRange.lowerBound + 0.0001)
                        .help(^String.Titles.videoZoomOutHelp)
                    }

                    Slider(
                        value: Binding(
                            get: { tagLibraryScale },
                            set: { newValue in
                                tagLibraryScale = newValue
                                saveScalePreference()
                            }
                        ),
                        in: Self.tagLibraryScaleRange
                    )
                    .frame(width: 180)

                    if #unavailable(macOS 18.0) {
                        Button {
                            adjustTagLibraryScale(by: Self.tagLibraryScaleStep)
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .disabled(tagLibraryScale >= Self.tagLibraryScaleRange.upperBound - 0.0001)
                        .help(^String.Titles.videoZoomInHelp)
                    }
                }
            }
            .padding(12)
        }
    }

    /// Step for the tag-library −/+ zoom buttons (shown on older macOS alongside the slider).
    private static let tagLibraryScaleStep: Double = 0.25

    private func adjustTagLibraryScale(by delta: Double) {
        tagLibraryScale = clampedTagLibraryScale(tagLibraryScale + delta)
        saveScalePreference()
    }

    /// Показ связок: под кнопками / над кнопками / скрыть — как в редакторе.
    private var bindingsVisibilityControl: some View {
        Menu {
            Picker("", selection: $bindingsArrowVisibility) {
                ForEach(KeyBindingArrowVisibility.allCases, id: \.self) { mode in
                    SwiftUI.Label(^mode.titleKey, systemImage: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            SwiftUI.Label(^bindingsArrowVisibility.titleKey, systemImage: bindingsArrowVisibility.iconName)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(^String.Titles.keyBindingsShowConnectionsHint)
    }

    private var scaleStorageKey: String {
        let name = isUserCollectionActive
            ? (lastSelectedCollectionName ?? "custom")
            : (tagLibrary.selectedStandardCollectionName ?? "standard")
        return "TagLibraryScale_\(name)"
    }

    private func loadScalePreference() {
        let stored = UserDefaults.standard.double(forKey: scaleStorageKey)
        if stored == 0 {
            tagLibraryScale = 1.0
        } else {
            tagLibraryScale = min(max(stored, Self.tagLibraryScaleRange.lowerBound), Self.tagLibraryScaleRange.upperBound)
        }
    }

    private func saveScalePreference() {
        UserDefaults.standard.set(tagLibraryScale, forKey: scaleStorageKey)
    }

    private func selectStandardCollection(_ collection: StandardCollection) {
        guard activeIntervalTags.isEmpty, !isLoadingCollections else { return }
        isUserCollectionActive = false
        lastSelectedCollectionName = collection.name
        cachedPlayFields = nil
        tagLibrary.applyStandardCollection(named: collection.name)
        tagDisplayMode = .grouped
        loadScalePreference()
        DispatchQueue.main.async {
            self.expandedGroups = Set(self.tagLibrary.tagGroups.map { $0.id })
        }
    }

    private func selectUserCollection(_ collection: CollectionBookmark) {
        guard activeIntervalTags.isEmpty, !isLoadingCollections else { return }
        lastSelectedCollectionName = collection.name
        isUserCollectionActive = true
        loadUserCollection(collection)
        applyCollectionDisplayMode()
        loadScalePreference()
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
    
    private var legacyHeaderView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(selectedCollectionTitle)
                    .font(.headline)
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
                cachedPlayFields = nil // Clear cached playField when switching to standard collection
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
        FreeTagsCanvasView(
            tags: tagLibrary.tags,
            labels: tagLibrary.allLabels,
            timeEvents: tagLibrary.timeEvents,
            playFields: cachedPlayFields?.fields ?? [],
            onTagTap: { tag in handleCanvasButtonTap(kind: .tag, elementId: tag.id) },
            onLabelTap: { label, commandPressed in
                handleCanvasLabelTap(label: label, commandPressed: commandPressed)
            },
            onTimeEventTap: { event in handleCanvasButtonTap(kind: .timeEvent, elementId: event.id) },
            onMapTap: { fieldId, normalized in handleCanvasMapTap(fieldId: fieldId, normalized: normalized) },
            activeIntervalTags: activeIntervalTags,
            hoveredTagID: hoveredTagID,
            tagCounts: tagCounts,
            runtime: keyBindingRuntime,
            userScale: CGFloat(tagLibraryScale),
            arrowVisibility: bindingsArrowVisibility
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Пересоздаём канвас при смене коллекции. Между коллекциями связок обе — в .free-режиме,
        // поэтому FreeTagsCanvasView НЕ размонтируется и переиспользуется (его @State layout остаётся
        // от прежней коллекции; лейблы берутся из глобального allLabels и всё равно рисуются, а
        // теги/карта — из текущей коллекции — нет). Смена .id форсирует remount → onAppear грузит
        // раскладку заново с уже устаканенными данными (как при заходе из стандартной коллекции).
        .id(freeCanvasCollectionKey)
    }

    /// Ключ идентичности канваса свободной раскладки — меняется при смене пользовательской коллекции.
    private var freeCanvasCollectionKey: String {
        if case .user(let name) = tagLibrary.currentCollectionType {
            return "free-\(name)"
        }
        return "free-none"
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
                FlexibleTagGrid(
                    tags: group.tags,
                    tagLibrary: tagLibrary,
                    activeIntervalTags: activeIntervalTags,
                    hoveredTagID: hoveredTagID,
                    tagCounts: $tagCounts,
                    scaleFactor: CGFloat(tagLibraryScale),
                    onTagTap: handleTagButtonTap,
                    onTagHover: { hovering, tagID in
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
    
    
    private func addTagToTimeline(tag: Tag, selectedLabels: [FullLabelWithGroup], instantAnchorTime: Double? = nil,
                                   overrideTimeBefore: Double? = nil, overrideTimeAfter: Double? = nil,
                                   useFieldMap: Bool = true,
                                   lockWindowsDuringFieldMap: Bool = true,
                                   onComplete: (() -> Void)? = nil) {
        if useFieldMap, tag.mapEnabled == true, let collectionName = resolvedCollectionName() {
            ensureCollectionFields(collectionName: collectionName) { fields in
                let usable = self.usableMapFields(for: tag, in: fields)
                if usable.count > 1 {
                    // Несколько карт: показываем стопкой, точку ставим на каждой.
                    WindowsManager.shared.showMultiFieldMapSelection(
                        tag: tag, items: self.mapItems(from: usable), lockWindows: lockWindowsDuringFieldMap
                    ) { normalizedByField in
                        self.proceedWithTagAdditionMulti(
                            tag: tag, fields: usable, normalizedByField: normalizedByField,
                            selectedLabels: selectedLabels, instantAnchorTime: instantAnchorTime,
                            overrideTimeBefore: overrideTimeBefore, overrideTimeAfter: overrideTimeAfter
                        )
                        onComplete?()
                        if lockWindowsDuringFieldMap, self.videoManager.playbackSpeed > 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.videoManager.player?.play() }
                        }
                    }
                } else if let field = usable.first, let imageBookmark = field.imageBookmark {
                    self.showFieldMapSelection(
                        tag: tag, imageBookmark: imageBookmark, selectedLabels: selectedLabels,
                        instantAnchorTime: instantAnchorTime,
                        overrideTimeBefore: overrideTimeBefore, overrideTimeAfter: overrideTimeAfter,
                        lockWindows: lockWindowsDuringFieldMap, onComplete: onComplete
                    )
                } else {
                    self.proceedWithTagAddition(tag: tag, selectedLabels: selectedLabels, coordinates: nil,
                                                instantAnchorTime: instantAnchorTime,
                                                overrideTimeBefore: overrideTimeBefore,
                                                overrideTimeAfter: overrideTimeAfter)
                    onComplete?()
                }
            }
            return
        }

        proceedWithTagAddition(tag: tag, selectedLabels: selectedLabels, coordinates: nil,
                               instantAnchorTime: instantAnchorTime,
                               overrideTimeBefore: overrideTimeBefore, overrideTimeAfter: overrideTimeAfter)
        onComplete?()
    }
    
    private func showFieldMapSelection(
        tag: Tag, imageBookmark: Data, selectedLabels: [FullLabelWithGroup],
        instantAnchorTime: Double? = nil,
        overrideTimeBefore: Double? = nil, overrideTimeAfter: Double? = nil,
        lockWindows: Bool = true,
        onComplete: (() -> Void)? = nil
    ) {
        WindowsManager.shared.showFieldMapSelection(tag: tag, imageBookmark: imageBookmark, lockWindows: lockWindows) { [self] coordinates in
            proceedWithTagAddition(
                tag: tag, selectedLabels: selectedLabels, coordinates: coordinates,
                instantAnchorTime: instantAnchorTime,
                overrideTimeBefore: overrideTimeBefore, overrideTimeAfter: overrideTimeAfter
            )
            onComplete?()
            // Когда окна не блокировались (режим связок клавиш), видео не паузилось —
            // ничего не возобновляем, чтобы не дёргать воспроизведение.
            if lockWindows, videoManager.playbackSpeed > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    videoManager.player?.play()
                }
            }
        }
    }

    /// Имя пользовательской коллекции для загрузки карты поля.
    private func resolvedCollectionName() -> String? {
        if let name = tagLibrary.currentCollectionType.name { return name }
        if isUserCollectionActive, let name = lastSelectedCollectionName { return name }
        return UserDefaults.standard.string(forKey: UserDefaults.Keys.lastSelectedCollection)
    }

    /// Карта, назначенная тегу (по `tag.mapFieldId`); если не задана — первая карта коллекции.
    private func resolveMapField(for tag: Tag, in fields: [PlayField]) -> PlayField? {
        if let mid = tag.mapFieldId, let field = fields.first(where: { $0.id == mid }) {
            return field
        }
        return fields.first
    }

    /// Все карты, привязанные к тегу (по `tag.resolvedMapFieldIds`), с сохранением порядка.
    /// Пустой список привязок → первая карта коллекции (обратная совместимость).
    private func resolveMapFields(for tag: Tag, in fields: [PlayField]) -> [PlayField] {
        let ids = tag.resolvedMapFieldIds
        if ids.isEmpty {
            return [fields.first].compactMap { $0 }
        }
        return ids.compactMap { id in fields.first(where: { $0.id == id }) }
    }

    /// Гарантирует, что карты коллекции загружены в кэш, затем выполняет `completion` на главном потоке.
    private func ensureCollectionFields(collectionName: String, completion: @escaping ([PlayField]) -> Void) {
        if let cached = cachedPlayFields, cached.name == collectionName {
            completion(cached.fields)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = CustomCollectionManager()
            let fields = manager.loadCollectionFromBookmarks(named: collectionName) ? manager.playFields : []
            DispatchQueue.main.async {
                if !fields.isEmpty {
                    self.cachedPlayFields = (name: collectionName, fields: fields)
                }
                completion(fields)
            }
        }
    }

    /// Карты для разметки тега (только те, у которых есть изображение).
    private func usableMapFields(for tag: Tag, in fields: [PlayField]) -> [PlayField] {
        resolveMapFields(for: tag, in: fields).filter { $0.imageBookmark != nil }
    }

    private func mapItems(from fields: [PlayField]) -> [FieldMapSelectionItem] {
        fields.compactMap { field in
            field.imageBookmark.map { FieldMapSelectionItem(id: field.id, name: field.name, imageBookmark: $0) }
        }
    }

    /// Карта, назначенная тегу, из текущего кэша карт коллекции.
    private func cachedMapField(for tag: Tag) -> PlayField? {
        guard let collectionName = resolvedCollectionName(),
              let cached = cachedPlayFields, cached.name == collectionName else { return nil }
        return resolveMapField(for: tag, in: cached.fields)
    }
    
    private func proceedWithTagAddition(tag: Tag, selectedLabels: [FullLabelWithGroup], coordinates: CGPoint?,
                                        instantAnchorTime: Double? = nil,
                                        overrideTimeBefore: Double? = nil, overrideTimeAfter: Double? = nil) {
        let anchorTime = instantAnchorTime ?? videoManager.currentTime
        let videoDuration = max(1.0, videoManager.timelineDuration)
        let timeBefore = overrideTimeBefore ?? tag.defaultTimeBefore
        let timeAfter = overrideTimeAfter ?? tag.defaultTimeAfter
        let startTime = max(0, anchorTime - timeBefore)
        let finishTime = min(videoDuration, startTime + timeBefore + timeAfter)
        
        let mapField = cachedMapField(for: tag)
        var fieldPosition: CGPoint? = nil
        if let normalizedCoords = coordinates, let playField = mapField {
            fieldPosition = CGPoint(x: normalizedCoords.x * CGFloat(playField.width),
                                    y: normalizedCoords.y * CGFloat(playField.height))
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
            position: fieldPosition,
            mapFieldId: fieldPosition != nil ? mapField?.id : nil,
            timeEvents: effectiveTimeEventsForStamp()
        )
        
        VideoMarkupActivityBanner.shared.notifyInstantTagAdded(tagName: tag.name, tagColorHex: tag.color)
        
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

    /// Точки на нескольких картах → массив позиций (по одной на карту). Порядок — как у `fields`.
    private func mapPositions(fields: [PlayField], normalizedByField: [String: CGPoint]) -> [StampMapPosition] {
        fields.compactMap { field in
            guard let norm = normalizedByField[field.id] else { return nil }
            let position = CGPoint(x: norm.x * CGFloat(field.width), y: norm.y * CGFloat(field.height))
            return StampMapPosition(mapFieldId: field.id, position: position)
        }
    }

    /// Мгновенный тег с несколькими картами: ОДИН штамп со всеми позициями (по точке на карту).
    private func proceedWithTagAdditionMulti(tag: Tag, fields: [PlayField], normalizedByField: [String: CGPoint],
                                             selectedLabels: [FullLabelWithGroup],
                                             instantAnchorTime: Double? = nil,
                                             overrideTimeBefore: Double? = nil, overrideTimeAfter: Double? = nil) {
        let anchorTime = instantAnchorTime ?? videoManager.currentTime
        let videoDuration = max(1.0, videoManager.timelineDuration)
        let timeBefore = overrideTimeBefore ?? tag.defaultTimeBefore
        let timeAfter = overrideTimeAfter ?? tag.defaultTimeAfter
        let startTime = max(0, anchorTime - timeBefore)
        let finishTime = min(videoDuration, startTime + timeBefore + timeAfter)
        let tagGroupId = tagLibrary.allTagGroups.first(where: { $0.tags.contains(tag.id) })?.id ?? ""
        let events = effectiveTimeEventsForStamp()
        let positions = mapPositions(fields: fields, normalizedByField: normalizedByField)

        timelineData.addStampToSelectedLine(
            tagRefs: [StampTagRef(id: tag.id, tagGroupId: tagGroupId)],
            primaryId: tag.primaryID,
            name: tag.name,
            timeStartSeconds: startTime,
            timeFinishSeconds: finishTime,
            color: tag.color,
            labels: selectedLabels,
            mapPositions: positions,
            timeEvents: events
        )

        VideoMarkupActivityBanner.shared.notifyInstantTagAdded(tagName: tag.name, tagColorHex: tag.color)
        DispatchQueue.main.async { self.updateTagCounts() }
    }

    /// Интервальный тег с несколькими картами: ОДИН штамп со всеми позициями (по точке на карту).
    private func proceedWithTagAdditionIntervalMulti(tag: Tag, fields: [PlayField], normalizedByField: [String: CGPoint],
                                                     timeStartSeconds: Double, timeFinishSeconds: Double,
                                                     selectedLabels: [FullLabelWithGroup]) {
        let tagGroupId = tagLibrary.allTagGroups.first(where: { $0.tags.contains(tag.id) })?.id ?? ""
        let events = effectiveTimeEventsForStamp()
        let positions = mapPositions(fields: fields, normalizedByField: normalizedByField)

        timelineData.addStampToSelectedLine(
            tagRefs: [StampTagRef(id: tag.id, tagGroupId: tagGroupId)],
            primaryId: tag.primaryID,
            name: tag.name,
            timeStartSeconds: timeStartSeconds,
            timeFinishSeconds: timeFinishSeconds,
            color: tag.color,
            labels: selectedLabels,
            mapPositions: positions,
            timeEvents: events
        )

        VideoMarkupActivityBanner.shared.completeIntervalRecording(tagName: tag.name, tagColorHex: tag.color)
        DispatchQueue.main.async { self.updateTagCounts() }
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
                                if let range = pendingIntervalClosureRange {
                                    pendingIntervalClosureRange = nil
                                    pendingInstantTagAnchorTime = nil
                                    activeIntervalTags.removeAll { $0.tag.id == tag.id }
                                    addTagToTimelineInterval(
                                        tag: tag,
                                        timeStartSeconds: range.timeStart,
                                        timeFinishSeconds: range.timeFinish,
                                        selectedLabels: fullLabels
                                    )
                                } else if let firstActiveTag = activeIntervalTags.first(where: { $0.tag.id == tag.id }) {
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
                                let anchor = pendingInstantTagAnchorTime
                                pendingInstantTagAnchorTime = nil
                                pendingIntervalClosureRange = nil
                                addTagToTimeline(tag: tag, selectedLabels: fullLabels, instantAnchorTime: anchor)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showLabelSheet = false
                            }
                        },
                        onCancel: {
                            pendingInstantTagAnchorTime = nil
                            pendingIntervalClosureRange = nil
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
                                if let range = pendingIntervalClosureRange {
                                    pendingIntervalClosureRange = nil
                                    pendingInstantTagAnchorTime = nil
                                    activeIntervalTags.removeAll { $0.tag.id == tag.id }
                                    addTagToTimelineInterval(
                                        tag: tag,
                                        timeStartSeconds: range.timeStart,
                                        timeFinishSeconds: range.timeFinish,
                                        selectedLabels: fullLabels
                                    )
                                } else if let firstActiveTag = activeIntervalTags.first(where: { $0.tag.id == tag.id }) {
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
                                let anchor = pendingInstantTagAnchorTime
                                pendingInstantTagAnchorTime = nil
                                pendingIntervalClosureRange = nil
                                addTagToTimeline(tag: tag, selectedLabels: fullLabels, instantAnchorTime: anchor)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showLabelSheet = false
                            }
                        },
                        onCancel: {
                            pendingInstantTagAnchorTime = nil
                            pendingIntervalClosureRange = nil
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
                    if let changedName {
                        if isUserCollectionActive,
                           let updatedCollection = userCollections.first(where: { $0.name == changedName }) {
                            lastSelectedCollectionName = changedName
                            tagLibrary.invalidateCollectionCache(for: changedName)
                            loadUserCollection(updatedCollection)
                        }
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
                    guard let notified = notification.object as? Tag else { return }
                    // `HotKeyManager.registeredHotkeys` хранит СНИМОК объекта Tag на момент
                    // регистрации хоткеев, и именно он приезжает сюда в object уведомления.
                    // Пересобираем тег по id из текущей коллекции: иначе в СГРУППИРОВАННОМ режиме
                    // (в отличие от связок, где handleCanvasButtonTap и так резолвит по id) на
                    // таймлайн уходят время до/после и интервальность, актуальные на момент
                    // регистрации, а при совпадающих id в двух коллекциях — копия из чужой.
                    // Клик мышью этим не задет: FlexibleTagGrid берёт тег из `tagLibrary.tags`.
                    let tag = resolveTag(id: notified.id) ?? notified
                    // В коллекциях со связками клавиш хоткей должен работать как ЛКМ по тегу:
                    // без окна лейблов — всё через канвас-обработчик.
                    if isKeyBindingsCanvasMode {
                        handleCanvasButtonTap(kind: .tag, elementId: tag.id)
                        return
                    }
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
                            let labelGroupIdsSet = Set(tag.lablesGroup)
                            let hasLabels = tagLibrary.allLabelGroups.contains { labelGroupIdsSet.contains($0.id) }
                            if hasLabels {
                                videoManager.player?.pause()
                                pendingIntervalClosureRange = (timeStart, timeFinish)
                                showLabelSheet = true
                            } else {
                                pendingIntervalClosureRange = nil
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
                        pendingInstantTagAnchorTime = videoManager.currentTime
                        showLabelSheet = true
                    } else {
                        pendingInstantTagAnchorTime = nil
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

        notificationSubscriptions.store(
            NotificationCenter.default.publisher(for: .liveRecordingWillStop)
                // Синхронно (без receive(on:)): финализация должна успеть записать
                // метки в TimelineDataManager ДО того, как остановка записи захватит
                // текущий снимок таймлайнов, иначе метки будут перетёрты старым снимком.
                .sink { [self] _ in
                    finalizeAllActiveIntervalTags()
                }
        )
        notificationSubscriptions.store(
            // Открыли редактор коллекций из разметки — закрываем все интервальные теги,
            // чтобы они не «писались» дальше, пока правится коллекция.
            NotificationCenter.default.publisher(for: .collectionEditorOpened)
                .receive(on: DispatchQueue.main)
                .sink { [self] _ in
                    finalizeAllActiveIntervalTags()
                }
        )
    }

    /// Закрывает все открытые интервальные теги по текущему времени записи и пишет
    /// их на таймлайн. Вызывается при завершении записи с камеры — иначе теги
    /// «пишутся» дальше и не сохраняются.
    private func finalizeAllActiveIntervalTags() {
        guard !activeIntervalTags.isEmpty else { return }

        let videoDuration = max(1.0, videoManager.timelineDuration)
        let stopTime = videoManager.currentTime

        // Забираем и очищаем список сразу, чтобы UI сбросил состояние «идёт запись».
        let tagsToClose = activeIntervalTags
        activeIntervalTags.removeAll()
        pendingIntervalClosureRange = nil
        showLabelSheet = false

        for activeTag in tagsToClose {
            let tag = activeTag.tag
            let start = max(0, activeTag.startTime - tag.defaultTimeBefore)
            let end = min(videoDuration, stopTime + tag.defaultTimeAfter)
            let timeStart = min(start, end)
            let timeFinish = max(start, end)
            // useFieldMap: false — при завершении записи нельзя открывать интерактивный
            // выбор карты поля; пишем метку сразу, синхронно. Завершение записи в
            // баннере делает сам proceedWithTagAdditionInterval.
            addTagToTimelineInterval(tag: tag, timeStartSeconds: timeStart, timeFinishSeconds: timeFinish, selectedLabels: [], useFieldMap: false)
        }
    }
    
    private func onDisappearCleanup() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    func loadUserCollection(_ collection: CollectionBookmark) {
        // Сбрасываем карты прошлой коллекции СРАЗУ: иначе при переключении между коллекциями связок
        // в раскладку уходят чужие playFields, и normalizeLayout выкидывает карты новой коллекции
        // (их id нет среди старых). Пустой список → карты сохраняются, а канвас догружает их сам.
        cachedPlayFields = nil
        // Try to get from cache first, otherwise load asynchronously
        if let cachedData = tagLibrary.getCollectionData(for: collection.name) {
            // Use cached data immediately
            tagLibrary.tags = cachedData.tags
            tagLibrary.tagGroups = cachedData.tagGroups
            tagLibrary.labelGroups = cachedData.labelGroups
            tagLibrary.labels = cachedData.labels
            tagLibrary.timeEvents = cachedData.timeEvents
            tagLibrary.selectedTimeEvents.removeAll()
            keyBindingRuntime.clearConfiguration()
            tagLibrary.currentCollectionType = .user(name: collection.name)
            HotKeyManager.shared.clearHotkeys()
            HotKeyManager.shared.registerHotkeys(from: cachedData.tags, for: .user(name: collection.name))
            UserDefaults.standard.set(collection.name, forKey: UserDefaults.Keys.lastSelectedCollection)
            
            cachePlayFieldForCollection(collection.name)
            
            updateTagCounts()
            expandedGroups = Set(tagLibrary.tagGroups.map { $0.id })
            tagLibrary.objectWillChange.send()
            applyCollectionDisplayMode()
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
                        self.keyBindingRuntime.clearConfiguration()
                        self.tagLibrary.currentCollectionType = .user(name: collection.name)
                        HotKeyManager.shared.clearHotkeys()
                        HotKeyManager.shared.registerHotkeys(from: collectionManager.tags, for: .user(name: collection.name))
                        UserDefaults.standard.set(collection.name, forKey: UserDefaults.Keys.lastSelectedCollection)
                        
                        // Cache all play fields (maps) of the collection.
                        if !collectionManager.playFields.isEmpty {
                            self.cachedPlayFields = (name: collection.name, fields: collectionManager.playFields)
                        }
                        
                        self.updateTagCounts()
                        self.expandedGroups = Set(self.tagLibrary.tagGroups.map { $0.id })
                        self.tagLibrary.objectWillChange.send()
                        self.applyCollectionDisplayMode()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.tagLibrary.tags = []
                        self.tagLibrary.tagGroups = []
                        self.tagLibrary.labelGroups = []
                        self.tagLibrary.labels = []
                        self.tagLibrary.timeEvents = []
                        self.tagLibrary.selectedTimeEvents.removeAll()
                        self.keyBindingRuntime.clearConfiguration()
                        self.tagLibrary.currentCollectionType = .standard
                        HotKeyManager.shared.clearHotkeys()
                        self.cachedPlayFields = nil
                    }
                }
            }
        }
    }
    
    /// Cache play fields for current collection to avoid reloading
    private func cachePlayFieldForCollection(_ collectionName: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let collectionManager = CustomCollectionManager()
            if collectionManager.loadCollectionFromBookmarks(named: collectionName),
               !collectionManager.playFields.isEmpty {
                let fields = collectionManager.playFields
                DispatchQueue.main.async {
                    self.cachedPlayFields = (name: collectionName, fields: fields)
                }
            }
        }
    }
    
    private func handleTagButtonTap(tag incoming: Tag) {
        // Блокируем добавление тегов в режиме редактирования
        guard !isEditorModeActive else { return }

        // Тег ВСЕГДА берём по id из текущей коллекции, а не доверяем пришедшему объекту: он может
        // быть копией из другой коллекции с тем же id (дубликат коллекции или повторный импорт —
        // id при этом сохраняются) либо снимком с прежними настройками. Ровно так же поступает
        // путь связок клавиш, поэтому там этой проблемы нет.
        let tag = resolveTag(id: incoming.id) ?? incoming


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
                    // Optimize label check using Set for O(1) lookup
                let labelGroupIdsSet = Set(tag.lablesGroup)
                let hasLabels = tagLibrary.allLabelGroups.contains { labelGroupIdsSet.contains($0.id) }
                    if hasLabels {
                        videoManager.player?.pause()
                        pendingIntervalClosureRange = (timeStart, timeFinish)
                        showLabelSheet = true
                    } else {
                        pendingIntervalClosureRange = nil
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
            pendingInstantTagAnchorTime = videoManager.currentTime
            showLabelSheet = true
        } else {
            pendingInstantTagAnchorTime = nil
            addTagToTimeline(tag: tag, selectedLabels: [])
        }
    }
    
    private func addTagToTimelineInterval(tag: Tag, timeStartSeconds: Double, timeFinishSeconds: Double, selectedLabels: [FullLabelWithGroup], useFieldMap: Bool = true, lockWindowsDuringFieldMap: Bool = true) {
        if useFieldMap, tag.mapEnabled == true, let collectionName = resolvedCollectionName() {
            ensureCollectionFields(collectionName: collectionName) { fields in
                let usable = self.usableMapFields(for: tag, in: fields)
                if usable.count > 1 {
                    WindowsManager.shared.showMultiFieldMapSelection(
                        tag: tag, items: self.mapItems(from: usable), lockWindows: lockWindowsDuringFieldMap
                    ) { normalizedByField in
                        self.proceedWithTagAdditionIntervalMulti(
                            tag: tag, fields: usable, normalizedByField: normalizedByField,
                            timeStartSeconds: timeStartSeconds, timeFinishSeconds: timeFinishSeconds,
                            selectedLabels: selectedLabels
                        )
                        if lockWindowsDuringFieldMap, self.videoManager.playbackSpeed > 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.videoManager.player?.play() }
                        }
                    }
                } else if let field = usable.first, let imageBookmark = field.imageBookmark {
                    self.showFieldMapSelectionInterval(tag: tag, imageBookmark: imageBookmark, timeStartSeconds: timeStartSeconds, timeFinishSeconds: timeFinishSeconds, selectedLabels: selectedLabels, lockWindows: lockWindowsDuringFieldMap)
                } else {
                    self.proceedWithTagAdditionInterval(tag: tag, timeStartSeconds: timeStartSeconds, timeFinishSeconds: timeFinishSeconds, coordinates: nil, selectedLabels: selectedLabels)
                }
            }
            return
        }
        proceedWithTagAdditionInterval(tag: tag, timeStartSeconds: timeStartSeconds, timeFinishSeconds: timeFinishSeconds, coordinates: nil, selectedLabels: selectedLabels)
    }

    private func showFieldMapSelectionInterval(tag: Tag, imageBookmark: Data, timeStartSeconds: Double, timeFinishSeconds: Double, selectedLabels: [FullLabelWithGroup], lockWindows: Bool = true) {
        WindowsManager.shared.showFieldMapSelection(tag: tag, imageBookmark: imageBookmark, lockWindows: lockWindows) { [self] coordinates in
            proceedWithTagAdditionInterval(tag: tag, timeStartSeconds: timeStartSeconds, timeFinishSeconds: timeFinishSeconds, coordinates: coordinates, selectedLabels: selectedLabels)
            // Если окна не блокировались (режим связок), видео не паузилось — не дёргаем play.
            if lockWindows, videoManager.playbackSpeed > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    videoManager.player?.play()
                }
            }
        }
    }
    
    private func proceedWithTagAdditionInterval(tag: Tag, timeStartSeconds: Double, timeFinishSeconds: Double, coordinates: CGPoint?, selectedLabels: [FullLabelWithGroup]) {
        
        let mapField = cachedMapField(for: tag)
        var fieldPosition: CGPoint? = nil
        if let normalizedCoords = coordinates, let playField = mapField {
            fieldPosition = CGPoint(x: normalizedCoords.x * CGFloat(playField.width),
                                    y: normalizedCoords.y * CGFloat(playField.height))
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
            position: fieldPosition,
            mapFieldId: fieldPosition != nil ? mapField?.id : nil,
            timeEvents: effectiveTimeEventsForStamp()
        )
        
        VideoMarkupActivityBanner.shared.completeIntervalRecording(tagName: tag.name, tagColorHex: tag.color)
        
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

    private func applyCollectionDisplayMode() {
        defer {
            // Режим показа связок доступен только для коллекций связок клавиш.
            if tagDisplayMode != .free { bindingsArrowVisibility = .hidden }
        }
        guard isUserCollectionActive,
              let name = lastSelectedCollectionName,
              let info = CollectionsBookmarksManager.shared.loadCollections().first(where: { $0.name == name }) else {
            tagDisplayMode = .grouped
            keyBindingRuntime.clearConfiguration()
            return
        }

        switch info.displayMode {
        case .grouped:
            tagDisplayMode = .grouped
            keyBindingRuntime.clearConfiguration()
        case .free:
            tagDisplayMode = isFreeLayoutConfigured ? .free : .grouped
            if tagDisplayMode == .grouped {
                keyBindingRuntime.clearConfiguration()
            } else {
                reloadKeyBindingRuntimeLayout()
            }
        }
    }

    private func reloadKeyBindingRuntimeLayout() {
        guard case .user(let name) = tagLibrary.currentCollectionType,
              let info = CollectionsBookmarksManager.shared.loadCollections().first(where: { $0.name == name }) else {
            return
        }
        if let stored = TagFreeLayoutStorage.loadLayoutIfExists(
            collectionId: info.id,
            tags: tagLibrary.tags,
            labels: tagLibrary.allLabels,
            timeEvents: tagLibrary.timeEvents,
            playFields: cachedPlayFields?.fields ?? []
        ) {
            keyBindingRuntime.configure(layout: stored, collectionId: info.id)
        }
    }

    /// Свободная раскладка коллекции «Связки клавиш» (не групповой режим тегов).
    private var isKeyBindingsCanvasMode: Bool {
        tagDisplayMode == .free
    }

    private var isFreeLayoutConfigured: Bool {
        guard case .user(let name) = TagLibraryManager.shared.currentCollectionType,
              let info = CollectionsBookmarksManager.shared.loadCollections().first(where: { $0.name == name }) else {
            return false
        }
        return TagFreeLayoutStorage.loadLayoutIfExists(
            collectionId: info.id, tags: tagLibrary.tags, labels: tagLibrary.allLabels, timeEvents: tagLibrary.timeEvents
        ) != nil
    }

    // MARK: - Key Binding canvas tap handler

    private func handleCanvasLabelTap(label: Label, commandPressed: Bool) {
        guard isKeyBindingsCanvasMode, !isEditorModeActive else { return }

        prepareRuntimeForTap()

        let labelId = label.id

        if commandPressed {
            if keyBindingRuntime.isLabelActivated(labelId) {
                keyBindingRuntime.deactivateLabel(id: labelId)
            } else {
                keyBindingRuntime.activateLabel(id: labelId)
                _ = keyBindingRuntime.handleButtonTap(kind: .label, elementId: labelId)
            }
            return
        }

        if keyBindingRuntime.isLabelActivated(labelId) {
            keyBindingRuntime.deactivateLabel(id: labelId)
            return
        }

        // Вся логика простого ЛКМ по лейблу (цепочки подсветки, привязка к якорю/крайнему) — в runtime.
        keyBindingRuntime.handleLabelTap(labelId: labelId)
    }

    /// Тег по id из ВЫБРАННОЙ сейчас коллекции (с фолбэком на глобальный пул).
    /// Единое правило живёт в `TagLibraryManager.findTagById` — см. комментарий там.
    private func resolveTag(id: String) -> Tag? {
        tagLibrary.findTagById(id)
    }

    private func handleCanvasButtonTap(kind: CanvasButtonKind, elementId: String) {
        guard isKeyBindingsCanvasMode, !isEditorModeActive else { return }

        prepareRuntimeForTap()

        if kind == .label {
            return
        }

        if kind == .timeEvent {
            // Нажатие/снятие общего события не паузит видео.
            _ = keyBindingRuntime.handleButtonTap(kind: kind, elementId: elementId)
            if !keyBindingRuntime.highlightModeActive {
                keyBindingRuntime.togglePendingTimeEvent(id: elementId)
            }
            return
        }

        guard kind == .tag, let tag = resolveTag(id: elementId) else { return }

        let isIntervalTag = tag.isInterval ?? false
        let isMapTag = tag.mapEnabled == true

        // Интервальный тег: запускаем/останавливаем запись (видео не паузим).
        if isIntervalTag {
            let isStopping = activeIntervalTags.contains(where: { $0.tag.id == tag.id })
            if isStopping {
                keyBindingRuntime.applyExclusiveOnTagDeactivation(tagId: elementId)
                // Гасим подсветку лейблов, поднятую этим тегом при старте записи.
                keyBindingRuntime.clearHighlightIfOriginatedFromTag(elementId)
            } else {
                _ = keyBindingRuntime.handleButtonTap(kind: .tag, elementId: elementId)
            }
            handleIntervalTagTapInFreeMode(tag)
            return
        }

        // Сначала применяем связки (подсветка и т.п.), потом решаем про паузу.
        _ = keyBindingRuntime.handleButtonTap(kind: .tag, elementId: elementId)

        if keyBindingRuntime.didCompleteHighlightPair { return }

        // Обычное добавление тега. Тег добавляется на таймлайн сразу (в т.ч. если он подсветил лейбл —
        // лейблы прикрепятся к нему позже как к якорю). Паузу ставим только если нажатие НЕ активировало
        // подсветку (партнёр подсвечен — видео не паузим) и тег без карты.
        if !isMapTag && !keyBindingRuntime.highlightModeActive {
            videoManager.player?.pause()
        }

        let selectedLabels = buildFullLabels(from: keyBindingRuntime.takeActivatedLabels())
        // Для тега с картой запоминаем момент нажатия и открываем карту,
        // не блокируя библиотеку тегов; метка добавится на таймлайн на это время.
        addTagToTimeline(
            tag: tag,
            selectedLabels: selectedLabels,
            instantAnchorTime: isMapTag ? videoManager.currentTime : nil,
            useFieldMap: isMapTag,
            lockWindowsDuringFieldMap: false
        )
    }

    private func startIntervalRecording(tag: Tag, labelIds: [String]) {
        guard isKeyBindingsCanvasMode else {
            KeyBindingLog.log("startIntervalRecording '\(tag.name)': отказ — вьюха не в режиме связок (tagDisplayMode=\(tagDisplayMode)) ❌")
            return
        }
        guard !activeIntervalTags.contains(where: { $0.tag.id == tag.id }) else {
            KeyBindingLog.log("startIntervalRecording '\(tag.name)': уже пишется — пропуск")
            return
        }
        KeyBindingLog.log("startIntervalRecording '\(tag.name)' ▶︎ (активных интервалов было \(activeIntervalTags.count))")
        keyBindingRuntime.clearActivatedLabels()
        activeIntervalTags.append(
            ActiveIntervalTag(
                id: UUID().uuidString,
                tag: tag,
                startTime: videoManager.currentTime,
                pendingLabelIds: labelIds
            )
        )
        VideoMarkupActivityBanner.shared.startIntervalRecording(tagName: tag.name)
    }

    private func finishIntervalRecording(at index: Int) {
        guard isKeyBindingsCanvasMode else {
            KeyBindingLog.log("finishIntervalRecording: отказ — вьюха не в режиме связок ❌")
            return
        }
        let activeTag = activeIntervalTags[index]
        let tag = activeTag.tag
        KeyBindingLog.log("finishIntervalRecording '\(tag.name)' ■")
        let videoDuration = max(1.0, videoManager.timelineDuration)
        let start = max(0, activeTag.startTime - tag.defaultTimeBefore)
        let end = min(videoDuration, videoManager.currentTime + tag.defaultTimeAfter)
        let timeStart = min(start, end)
        let timeFinish = max(start, end)
        let labelIds = activeTag.pendingLabelIds + keyBindingRuntime.takeActivatedLabels()
        activeIntervalTags.remove(at: index)
        // Для тега с картой по завершении интервала открываем карту (видео не паузим,
        // библиотеку не блокируем); метка добавится на интервал [start, finish] с координатой.
        let isMapTag = tag.mapEnabled == true
        addTagToTimelineInterval(
            tag: tag,
            timeStartSeconds: timeStart,
            timeFinishSeconds: timeFinish,
            selectedLabels: buildFullLabels(from: labelIds),
            useFieldMap: isMapTag,
            lockWindowsDuringFieldMap: false
        )
        // Позиция с инлайн-карты, накопленная во время записи, — применяем к только что созданному штампу.
        if let pos = activeTag.pendingPosition, let fid = activeTag.pendingMapFieldId,
           let stampID = timelineData.lastAddedStampID, let (lineID, stamp) = locateStamp(stampID: stampID) {
            timelineData.updateStampPosition(lineID: lineID, stampID: stamp.id, position: pos, mapFieldId: fid)
        }
    }

    private func handleIntervalTagTapInFreeMode(_ tag: Tag, triggeringLabelId: String? = nil) {
        guard isKeyBindingsCanvasMode else { return }
        if let index = activeIntervalTags.firstIndex(where: { $0.tag.id == tag.id }) {
            finishIntervalRecording(at: index)
        } else {
            let labelIds = keyBindingRuntime.takeActivatedLabels(triggeringLabelId: triggeringLabelId)
            startIntervalRecording(tag: tag, labelIds: labelIds)
        }
    }

    /// Простой ЛКМ по лейблу без связки → к последнему по времени добавления тегу (любая линия/режим).
    private func attachLabelsToLastTimelineStamp(labelIds: [String]) {
        guard isKeyBindingsCanvasMode, !labelIds.isEmpty else { return }
        // Если есть активная интервальная запись — лейблы копятся в неё (штампа ещё нет).
        if let idx = activeIntervalTags.indices.last {
            appendPendingLabels(labelIds, toIntervalAt: idx)
            return
        }
        guard let stampID = timelineData.lastAddedStampID,
              let (lineID, stamp) = locateStamp(stampID: stampID) else { return }
        mergeLabels(labelIds, intoLineID: lineID, stamp: stamp)
    }

    /// Находит линию и штамп по id штампа в любой линии.
    private func locateStamp(stampID: UUID) -> (lineID: UUID, stamp: TimelineStamp)? {
        for line in timelineData.lines {
            if let stamp = line.stamps.first(where: { $0.id == stampID }) {
                return (line.id, stamp)
            }
        }
        return nil
    }

    /// Находит последний штамп, содержащий указанный тег (per-tag линия в tagBased или поиск по всем линиям).
    private func locateLastStamp(containingTag tagId: String) -> (lineID: UUID, stamp: TimelineStamp)? {
        if let line = timelineData.lines.first(where: { $0.tagIdForMode == tagId }),
           let stamp = line.stamps.last {
            return (line.id, stamp)
        }
        for line in timelineData.lines.reversed() {
            if let stamp = line.stamps.last(where: { $0.idTags.contains(tagId) }) {
                return (line.id, stamp)
            }
        }
        return nil
    }

    // MARK: - Инлайн-карта на холсте

    /// Клик по зоне карты в раскладке связок: ставит позицию тегу (как лейбл) и запускает связки карты.
    private func handleCanvasMapTap(fieldId: String, normalized: CGPoint) {
        guard isKeyBindingsCanvasMode, !isEditorModeActive else { return }
        prepareRuntimeForTap()
        keyBindingRuntime.handleMapTap(mapId: fieldId, normalized: normalized)
    }

    /// Ставит позицию на карте нужному тегу-штампу (логика выбора штампа — как у лейблов).
    /// Если целевой тег ещё пишется как интервал (штампа нет), позиция копится в pending —
    /// как и лейблы — и применится по завершении записи.
    private func attachMapPosition(fieldId: String, normalized: CGPoint, allowedTagIds: Set<String>?) {
        guard isKeyBindingsCanvasMode,
              let field = (cachedPlayFields?.fields ?? []).first(where: { $0.id == fieldId }) else { return }
        let position = CGPoint(x: normalized.x * CGFloat(field.width), y: normalized.y * CGFloat(field.height))

        // 0. Активная интервальная запись (штампа ещё нет) — копим позицию в pending.
        if let allowed = allowedTagIds {
            if let idx = activeIntervalTags.lastIndex(where: { allowed.contains($0.tag.id) }) {
                setPendingMapPosition(position, fieldId: fieldId, atIntervalIndex: idx); return
            }
        } else if let anchor = keyBindingRuntime.anchorTagId,
                  let idx = activeIntervalTags.lastIndex(where: { $0.tag.id == anchor }) {
            setPendingMapPosition(position, fieldId: fieldId, atIntervalIndex: idx); return
        } else if allowedTagIds == nil, keyBindingRuntime.anchorTagId == nil,
                  let idx = activeIntervalTags.indices.last {
            setPendingMapPosition(position, fieldId: fieldId, atIntervalIndex: idx); return
        }

        var target: (lineID: UUID, stamp: TimelineStamp)? = nil
        // 1. Якорь цепочки подсветки (если он на таймлайне).
        if let anchor = keyBindingRuntime.anchorTagId {
            target = locateLastStamp(containingTag: anchor)
        }
        // 2. Эксклюзив: последний по времени штамп разрешённого тега.
        if target == nil, let allowed = allowedTagIds {
            var best: (lineID: UUID, stamp: TimelineStamp)? = nil
            for line in timelineData.lines {
                for stamp in line.stamps where stamp.idTags.contains(where: { allowed.contains($0) }) {
                    if best == nil || stamp.timeStartSeconds > best!.stamp.timeStartSeconds { best = (line.id, stamp) }
                }
            }
            target = best
        }
        // 3. Со всеми тегами: крайний добавленный штамп.
        if target == nil, allowedTagIds == nil, let stampID = timelineData.lastAddedStampID {
            target = locateStamp(stampID: stampID)
        }
        guard let t = target else { return }
        timelineData.updateStampPosition(lineID: t.lineID, stampID: t.stamp.id, position: position, mapFieldId: fieldId)
    }

    private func setPendingMapPosition(_ position: CGPoint, fieldId: String, atIntervalIndex idx: Int) {
        activeIntervalTags[idx].pendingPosition = position
        activeIntervalTags[idx].pendingMapFieldId = fieldId
    }

    /// Дописывает лейблы в штамп без дублей.
    private func mergeLabels(_ newLabelIds: [String], intoLineID lineID: UUID, stamp: TimelineStamp) {
        let newLabels = buildFullLabels(from: newLabelIds)
        guard !newLabels.isEmpty else { return }
        var merged = stamp.labels
        for label in newLabels where !merged.contains(where: { $0.id == label.id }) {
            merged.append(label)
        }
        timelineData.updateStampLabels(lineID: lineID, stampID: stamp.id, newLabels: merged)
    }

    /// Эксклюзивный лейбл привязывается к своему тегу независимо от того, когда его нажали:
    /// ищем на таймлайне ПОСЛЕДНИЙ по времени штамп любого из эксклюзивных партнёров и ставим на него.
    /// Если партнёров несколько — попадёт на последний отмеченный такой тег.
    private func attachLabelsToLastStampIfTagMatches(labelIds: [String], allowedTagIds: Set<String>) {
        guard isKeyBindingsCanvasMode, !labelIds.isEmpty else { return }
        // Активная интервальная запись допустимого тега — самый «свежий» тег (ещё пишется).
        if let idx = activeIntervalTags.lastIndex(where: { allowedTagIds.contains($0.tag.id) }) {
            appendPendingLabels(labelIds, toIntervalAt: idx)
            return
        }
        // Иначе — последний по времени начала штамп любого разрешённого тега во всех линиях.
        var best: (lineID: UUID, stamp: TimelineStamp)? = nil
        for line in timelineData.lines {
            for stamp in line.stamps where stamp.idTags.contains(where: { allowedTagIds.contains($0) }) {
                if best == nil || stamp.timeStartSeconds > best!.stamp.timeStartSeconds {
                    best = (line.id, stamp)
                }
            }
        }
        guard let target = best else { return }
        mergeLabels(labelIds, intoLineID: target.lineID, stamp: target.stamp)
    }

    /// Копит лейблы в активную интервальную запись (штампа ещё нет).
    private func appendPendingLabels(_ labelIds: [String], toIntervalAt idx: Int) {
        var pending = activeIntervalTags[idx].pendingLabelIds
        for lid in labelIds where !pending.contains(lid) { pending.append(lid) }
        activeIntervalTags[idx].pendingLabelIds = pending
    }

    /// Готовит движок связок к обработке нажатия: колбэки + гарантия, что связки ТЕКУЩЕЙ коллекции
    /// загружены. Второе — страховка от того, что `configure` не успел пройти по жизненному циклу
    /// вьюх (коллекцию только что создали/выбрали): без неё `bindings` оставался пустым и связки
    /// не работали до перезапуска приложения. Повторные вызовы для той же коллекции — no-op.
    private func prepareRuntimeForTap() {
        KeyBindingLog.log("— нажатие: режим=\(tagDisplayMode), коллекция='\(lastSelectedCollectionName ?? "-")', активных интервалов=\(activeIntervalTags.count)")
        wireRuntimeCallbacks()
        keyBindingRuntime.ensureConfiguredForCurrentCollection(
            playFields: cachedPlayFields?.fields ?? []
        )
    }

    /// Подключает колбэки движка к ЭТОМУ экземпляру вьюхи.
    ///
    /// Перевязываем на каждом нажатии, а не один раз за запуск. Колбэки захватывают `self` —
    /// структуру `TagLibraryView`, и её `@State` (`activeIntervalTags`, `tagDisplayMode`, …) живёт
    /// в боксах, привязанных к идентичности вьюхи. После `refreshID = UUID()` вьюха
    /// перемонтируется с НОВОЙ идентичностью, а колбэки продолжали писать в осиротевшие боксы
    /// прошлого экземпляра: `startIntervalRecording` добавлял запись в мёртвый
    /// `activeIntervalTags`, а `isKeyBindingsCanvasMode` мог читать там `.grouped` и вообще
    /// отваливаться по guard. Наружу это выглядело как «связки с интервальными не работают»,
    /// хотя прямое нажатие по тому же тегу (оно идёт из живой вьюхи) работало.
    private func wireRuntimeCallbacks() {
        guard isKeyBindingsCanvasMode else { return }
        keyBindingRuntime.onAddTag = { [self] tagId, overrideBefore, overrideAfter, labelIds, onAdded in
            guard let tag = resolveTag(id: tagId) else {
                KeyBindingLog.log("onAddTag: тег \(tagId) не найден ❌")
                onAdded?()
                return
            }
            let fullLabels = buildFullLabels(from: labelIds)
            KeyBindingLog.log("onAddTag: '\(tag.name)' isInterval=\(tag.isInterval ?? false) labels=\(labelIds.count)")
            if tag.isInterval ?? false {
                startIntervalRecording(tag: tag, labelIds: labelIds)
                onAdded?()
            } else {
                let isMapTag = tag.mapEnabled == true
                addTagToTimeline(
                    tag: tag, selectedLabels: fullLabels,
                    instantAnchorTime: isMapTag ? videoManager.currentTime : nil,
                    overrideTimeBefore: overrideBefore, overrideTimeAfter: overrideAfter,
                    useFieldMap: isMapTag,
                    lockWindowsDuringFieldMap: false,
                    onComplete: {
                        keyBindingRuntime.clearActivatedLabels()
                        onAdded?()
                    }
                )
            }
        }
        keyBindingRuntime.onStartIntervalTag = { [self] tagId in
            guard let tag = resolveTag(id: tagId),
                  tag.isInterval ?? false,
                  !activeIntervalTags.contains(where: { $0.tag.id == tagId }) else { return }
            let labelIds = keyBindingRuntime.takeActivatedLabels()
            startIntervalRecording(tag: tag, labelIds: labelIds)
        }
        keyBindingRuntime.onStopIntervalTag = { [self] tagId in
            guard let idx = activeIntervalTags.firstIndex(where: { $0.tag.id == tagId }) else { return }
            finishIntervalRecording(at: idx)
        }
        keyBindingRuntime.isIntervalTagActive = { [self] tagId in
            activeIntervalTags.contains(where: { $0.tag.id == tagId })
        }
        keyBindingRuntime.onAttachLabelsToAnchor = { [self] anchorTagId, labelIds, onDone in
            attachLabelsToAnchorStamp(anchorTagId: anchorTagId, labelIds: labelIds)
            onDone?()
        }
        keyBindingRuntime.onAttachTimeEventsToAnchor = { [self] anchorTagId, timeEventIds, onDone in
            attachTimeEventsToAnchorStamp(anchorTagId: anchorTagId, timeEventIds: timeEventIds)
            onDone?()
        }
        keyBindingRuntime.onAttachLabelsToLastStamp = { [self] labelIds, onDone in
            attachLabelsToLastTimelineStamp(labelIds: labelIds)
            onDone?()
        }
        keyBindingRuntime.onAttachLabelsIfTagMatches = { [self] labelIds, allowedTagIds, onDone in
            attachLabelsToLastStampIfTagMatches(labelIds: labelIds, allowedTagIds: allowedTagIds)
            onDone?()
        }
        keyBindingRuntime.onAttachMapPosition = { [self] fieldId, normalized, allowedTagIds, onDone in
            attachMapPosition(fieldId: fieldId, normalized: normalized, allowedTagIds: allowedTagIds)
            onDone?()
        }
    }

    private func effectiveTimeEventsForStamp() -> [String] {
        if tagDisplayMode == .free {
            return Array(keyBindingRuntime.pendingTimeEventIds)
        }
        return Array(tagLibrary.selectedTimeEvents)
    }

    /// Добавляет выбранные лейблы к якорному тегу (подсветка тег → лейблы). Независимо от режима/линии.
    private func attachLabelsToAnchorStamp(anchorTagId: String, labelIds: [String]) {
        guard !labelIds.isEmpty else { return }

        // Якорный тег ещё записывается как интервал — копим лейблы в его pendingLabelIds.
        if let idx = activeIntervalTags.firstIndex(where: { $0.tag.id == anchorTagId }) {
            appendPendingLabels(labelIds, toIntervalAt: idx)
            return
        }

        guard let (lineID, stamp) = locateLastStamp(containingTag: anchorTagId) else { return }
        mergeLabels(labelIds, intoLineID: lineID, stamp: stamp)
    }

    /// Добавляет выбранные общие события к последнему штампу якорного тега (подсветка тег → события).
    private func attachTimeEventsToAnchorStamp(anchorTagId: String, timeEventIds: [String]) {
        guard !timeEventIds.isEmpty,
              let (lineID, stamp) = locateLastStamp(containingTag: anchorTagId)
        else { return }

        var merged = stamp.timeEvents
        for eventId in timeEventIds where !merged.contains(eventId) {
            merged.append(eventId)
        }
        timelineData.updateStampTimeEvents(lineID: lineID, stampID: stamp.id, newEvents: merged)
    }

    private func buildFullLabels(from labelIds: [String]) -> [FullLabelWithGroup] {
        labelIds.compactMap { lid in
            let label = tagLibrary.labels.first(where: { $0.id == lid })
                ?? tagLibrary.allLabels.first(where: { $0.id == lid })
            guard let label else { return nil }

            let group = tagLibrary.labelGroups.first(where: { $0.lables.contains(lid) })
                ?? tagLibrary.allLabelGroups.first(where: { $0.lables.contains(lid) })
            guard let group else { return nil }

            return FullLabelWithGroup(
                id: label.id,
                name: label.name,
                description: label.description,
                lableGroupId: group.id
            )
        }
    }
}

struct TagButtonView: View, Equatable {
    let tag: Tag
    let isActive: Bool
    let isHovered: Bool
    let tagCount: Int
    let scaleFactor: CGFloat
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    
    static func == (lhs: TagButtonView, rhs: TagButtonView) -> Bool {
        return lhs.tag.id == rhs.tag.id &&
               lhs.isActive == rhs.isActive &&
               lhs.isHovered == rhs.isHovered &&
               lhs.tagCount == rhs.tagCount &&
               lhs.scaleFactor == rhs.scaleFactor
    }
    
    var body: some View {
        let hasHotkey = tag.hotkey != nil && !tag.hotkey!.isEmpty
        let isInterval = tag.isInterval ?? false
        let titleFontSize = 14 * scaleFactor
        let countFontSize = 12 * scaleFactor
        let iconFontSize = 12 * scaleFactor
        let smallIconFontSize = 10 * scaleFactor
        let titleRowHeight = 22 * scaleFactor
        let horizontalPadding = 8 * scaleFactor
        let verticalPadding = 4 * scaleFactor
        
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 1 * scaleFactor) {
                HStack(alignment: .center, spacing: 8 * scaleFactor) {
                    Text(tag.name)
                        .font(.system(size: titleFontSize, weight: isActive ? .bold : .medium))
                        .foregroundColor(isActive ? .white : Color(hex: tag.color).isDark ? .white : .black)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .minimumScaleFactor(0.5)
                    
                    if tagCount > 0 {
                        Text("\(tagCount)")
                            .font(.system(size: countFontSize, weight: .semibold))
                            .foregroundColor(isActive ? .white : Color(hex: tag.color).isDark ? .white : .black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isActive ? Color.white.opacity(0.3) : Color(hex: tag.color).isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                            )
                    }
                }
            .frame(height: titleRowHeight)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
                
                HStack {
                    Spacer()
                    HStack(spacing: 4 * scaleFactor) {
                        if isInterval {
                            Image(systemName: "timer")
                                .font(.system(size: iconFontSize, weight: .medium))
                                .foregroundColor(isActive ? .white : Color(hex: tag.color).isDark ? .white : .black)
                        }
                        
                        if tag.mapEnabled == true {
                            Image(systemName: "map")
                                .font(.system(size: iconFontSize, weight: .medium))
                                .foregroundColor(isActive ? .white : Color(hex: tag.color).isDark ? .white : .black)
                        }
                        
                        if hasHotkey {
                            HStack(spacing: 2 * scaleFactor) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: smallIconFontSize, weight: .medium))
                                Text(tag.hotkey!)
                                    .font(.system(size: smallIconFontSize, weight: .medium))
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
                                .font(.system(size: iconFontSize, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 4 * scaleFactor)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, verticalPadding)
                
                if isActive && isInterval {
                    HStack(spacing: 2 * scaleFactor) {
                        ForEach(0..<6) { _ in
                            Rectangle()
                                .frame(width: 2 * scaleFactor, height: 4 * scaleFactor)
                                .opacity(0.6)
                        }
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, verticalPadding)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10 * scaleFactor)
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
    var scaleFactor: CGFloat = 1.0
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
                                    scaleFactor: scaleFactor,
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
            .onChange(of: scaleFactor) { _ in
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
        let textFont = NSFont.systemFont(ofSize: 14 * scaleFactor, weight: .medium)
        let textAttributes = [NSAttributedString.Key.font: textFont]
        let textWidth = tag.name.size(withAttributes: textAttributes).width
        
        var totalWidth = textWidth
        
        totalWidth += 16 * scaleFactor
        
        if let tagCount = tagCounts[tag.id], tagCount > 0 {
            let countText = "\(tagCount)"
            let countFont = NSFont.systemFont(ofSize: 12 * scaleFactor, weight: .semibold)
            let countAttributes = [NSAttributedString.Key.font: countFont]
            let countWidth = countText.size(withAttributes: countAttributes).width
            totalWidth += countWidth + 12 * scaleFactor
        }
        
        totalWidth += 8 * scaleFactor
        
        return totalWidth
    }
    
    private func calculateTagButtonHeight(for tag: Tag) -> CGFloat {
        var height: CGFloat = 22 * scaleFactor
        
        let hasIndicators = (tag.isInterval == true) || 
                           (tag.mapEnabled == true) || 
                           (tag.hotkey != nil && !tag.hotkey!.isEmpty) ||
                           activeIntervalTags.contains(where: { $0.tag.id == tag.id })
        
        if hasIndicators {
            height += 16 * scaleFactor
        }
        
        if activeIntervalTags.contains(where: { $0.tag.id == tag.id }) && (tag.isInterval == true) {
            height += 8 * scaleFactor
        }
        
        height += 8 * scaleFactor
        
        return height
    }
    
    private func calculateTotalHeight() -> CGFloat {
        let maxHeightInGroup = calculateMaxHeightInGroup()
        let spacing: CGFloat = 8 * scaleFactor
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
        let font = NSFont.systemFont(ofSize: 14 * scaleFactor, weight: .medium)
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

