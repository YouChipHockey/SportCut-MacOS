//
//  CreateCustomCollectionsView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI
import Foundation
import AppKit

// MARK: - Editable TextField Helper

struct AutoFocusTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        
        if !context.coordinator.didFocus {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                if let editor = nsView.currentEditor() as? NSTextView {
                    let length = editor.string.count
                    editor.selectedRange = NSRange(location: length, length: 0)
                }
                context.coordinator.didFocus = true
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onSubmit: () -> Void
        var didFocus = false
        
        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text = textField.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }
    }
}

struct CreateCustomCollectionsView: View {
    
    @StateObject private var collectionManager: CustomCollectionManager
    @State private var viewMode: ViewMode = .tagGroups
    @State private var showAddTagGroupSheet = false
    @State private var showAddLabelGroupSheet = false
    @State private var isEditingName: Bool = false
    @State private var isEditingGroupName: Bool = false
    @State private var isEditingCollectionName: Bool = false
    @State private var editingName: String = ""
    @State private var activeAlert: ActiveAlert? = nil
    @State private var showAddTagSheet = false
    @State private var showAddLabelSheet = false
    @State private var showAddTimeEventSheet = false
    @State private var newGroupName = ""
    @State private var selectedTagGroupID: String?
    @State private var selectedLabelGroupID: String?
    @State private var selectedTagID: String?
    @State private var selectedLabelID: String?
    @State private var selectedTimeEventID: String?
    @State private var isEditingTimeEvent = false
    @State private var tagFormData = TagFormData()
    @State private var newLabelName = ""
    @State private var newLabelDescription = ""
    @State private var newTimeEventName = ""
    @State private var showSaveSuccess = false
    @State private var isCapturingTagHotkey = false
    @State private var showCropSheet = false
    @State private var showFieldChangeAlert = false
    @State private var showFieldDeleteAlert = false
    @State private var activeTagsOnTimelines = 0
    @State private var tempImageURL: URL? = nil
    @State private var tempImageBookmark: Data? = nil
    @State private var isCapturingLabelHotkeys: [String: Bool] = [:]
    
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchScope: SearchScope = .all
    @State private var showTagLayoutEditor = false
    
    init() {
        _collectionManager = StateObject(wrappedValue: CustomCollectionManager())
    }
    init(existingCollection: CollectionBookmark) {
        _collectionManager = StateObject(wrappedValue: CustomCollectionManager(withBookmark: existingCollection))
    }
    
    enum ViewMode {
        case tagGroups
        case labelGroups
        case timeEvents
        case fieldMap
    }
    
    enum SearchScope: String, CaseIterable {
        case all = "all"
        case tags = "tags"
        case labels = "labels"
        case groups = "groups"
        
        var localizedTitle: String {
            switch self {
            case .all:
                return ^String.Titles.all
            case .tags:
                return ^String.Titles.tags
            case .labels:
                return ^String.Titles.labels
            case .groups:
                return ^String.Titles.groups
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            customToolbarView
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                )
            
            HStack(spacing: 0) {
                sidebarView
                    .frame(minWidth: 280, maxWidth: 350)
                    .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                    .frame(width: 1)
                
                detailView
                    .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .onDisappear {
            NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
        }
        .sheet(isPresented: $showCropSheet) {
            let tempImageBookmarkMemory = UserDefaults.standard.data(forKey: "tempImageBookmark")
            if let bookmarkData = tempImageBookmarkMemory {
                if let tempUrl = resolveBookmark(bookmarkData) {
                    CropImageView(imageURL: tempUrl) { croppedImage in
                        handleCroppedImage(croppedImage, tempUrl: tempUrl)
                    }
                }
            }
        }
        .alert(item: $activeAlert) { alertType in
            switch alertType {
            case .fieldChange:
                return Alert(
                    title: Text(^String.Titles.fieldMapChange),
                    message: Text(String(format: ^String.Titles.fieldMapChangeWarning, String(activeTagsOnTimelines))),
                    primaryButton: .default(Text(^String.Titles.resetPositions)) {
                        resetTagPositionsOnTimelines()
                        selectNewFieldImage()
                    },
                    secondaryButton: .destructive(Text(^String.Titles.savePositions)) {
                        selectNewFieldImage()
                    }
                )
            case .fieldDelete:
                return Alert(
                    title: Text(^String.Titles.deleteFieldMap),
                    message: Text(String(format: ^String.Titles.fieldMapChangeWarning, String(activeTagsOnTimelines))),
                    primaryButton: .destructive(Text(^String.Titles.deleteMap)) {
                        collectionManager.deleteFieldImage()
                        resetTagPositionsOnTimelines()
                    },
                    secondaryButton: .cancel(Text(^String.Titles.collectionsButtonCancel))
                )
            }
        }
        .sheet(isPresented: $showAddTagGroupSheet) {
            addTagGroupSheet()
        }
        .sheet(isPresented: $showAddLabelGroupSheet) {
            addLabelGroupSheet()
        }
        .sheet(isPresented: $showAddTagSheet) {
            addTagSheet()
        }
        .sheet(isPresented: $showAddLabelSheet) {
            addLabelSheet()
        }
        .sheet(isPresented: $showAddTimeEventSheet) {
            addTimeEventSheet()
        }
        .sheet(isPresented: $showTagLayoutEditor) {
            TagFreeLayoutEditorView(
                collectionId: collectionManager.collectionID,
                collectionName: collectionManager.collectionName,
                tags: collectionManager.tags
            )
        }
    }
    
    private func resolveBookmark(_ bookmark: Data) -> URL? {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if url.startAccessingSecurityScopedResource() {
                return url
            }
            return nil
        } catch {
            return nil
        }
    }
    
    var customToolbarView: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(^String.Titles.collection)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if isEditingCollectionName || !collectionManager.isEditingExisting {
                    AutoFocusTextField(text: $collectionManager.collectionName, placeholder: ^String.Titles.collectionName) {
                        saveCollectionData()
                    }
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        )
                } else {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                        Text(collectionManager.collectionName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Button(action: {
                            isEditingCollectionName = true
                        }) {
                            Image(systemName: "pencil")
                                .foregroundStyle(Color.blue)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
            }
            .frame(width: 250)
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    saveCollectionData()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: showSaveSuccess ? "checkmark.circle.fill" : (collectionManager.isEditingExisting ? "arrow.clockwise" : "square.and.arrow.down"))
                        .foregroundColor(.white)
                    Text(collectionManager.isEditingExisting ? ^String.Titles.updateCollection : ^String.Titles.saveCollection)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(showSaveSuccess ? Color.green : Color.blue)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(showSaveSuccess ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: showSaveSuccess)
            
            Button(action: {
                if let exportedURL = collectionManager.exportCollection() {
                    print("Collection exported to: \(exportedURL.path)")
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.white)
                    Text(^String.Titles.fieldMapButtonExport)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            if viewMode == .tagGroups {
                Button(action: {
                    showTagLayoutEditor = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.3.offgrid")
                        Text(^String.Titles.collectionsTagLayout)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(collectionManager.tags.isEmpty)
            }
            
            Picker("", selection: $viewMode) {
                Text(^String.Titles.tagGroups)
                    .tag(ViewMode.tagGroups)
                Text(^String.Titles.labelGroups)
                    .tag(ViewMode.labelGroups)
                Text(^String.Titles.commonEvents)
                    .tag(ViewMode.timeEvents)
                Text(^String.Titles.fieldMap)
                    .tag(ViewMode.fieldMap)
            }
            .pickerStyle(.segmented)
            .frame(width: 600)
        }
    }
    
    var sidebarView: some View {
        VStack(spacing: 0) {
            searchBarView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            List {
                if viewMode == .tagGroups {
                    tagGroupsListSection
                    
                    if let groupID = selectedTagGroupID {
                        tagsInGroupSection(groupID: groupID)
                    }
                } else if viewMode == .labelGroups {
                    labelGroupsListSection
                    
                    if let groupID = selectedLabelGroupID {
                        labelsInGroupSection(groupID: groupID)
                    }
                } else if viewMode == .timeEvents {
                    timeEventsListSection
                } else if viewMode == .fieldMap {
                    fieldMapSection
                }
            }
            .listStyle(PlainListStyle())
        }
    }
    
    var searchBarView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField(^String.Titles.search, text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onTapGesture {
                        isSearching = true
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        isSearching = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSearching ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
            
            if !searchText.isEmpty {
                Picker(searchScope.localizedTitle, selection: $searchScope) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        Text(scope.localizedTitle).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
    
    var fieldMapSection: some View {
        Section {
            Text(^String.Titles.fieldMapSettings)
                .font(.headline)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
        } header: {
            Text(^String.Titles.fieldMap)
        }
    }
    
    var tagGroupsListSection: some View {
        Section {
            ForEach(filteredTagGroups) { group in
                tagGroupRowView(group: group)
            }
            
            addTagGroupButton
        } header: {
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(.blue)
                Text(^String.Titles.tagGroups)
                    .font(.headline)
                Spacer()
                Text("\(collectionManager.tagGroups.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
            }
            .padding(.vertical, 4)
        }
    }
    
    var timeEventsListSection: some View {
        Section {
            ForEach(filteredTimeEvents) { event in
                timeEventRowView(event: event)
            }
            
            addTimeEventButton
        } header: {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.orange)
                Text(^String.Titles.commonEvents)
                    .font(.headline)
                Spacer()
                Text("\(collectionManager.timeEvents.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
            }
            .padding(.vertical, 4)
        }
    }
    
    func timeEventRowView(event: TimeEvent) -> some View {
        HStack {
            Image(systemName: "clock")
                .foregroundColor(.orange)
                .frame(width: 16)
            
            if selectedTimeEventID == event.id && isEditingTimeEvent {
                AutoFocusTextField(
                    text: $newTimeEventName,
                    placeholder: ^String.Titles.eventName,
                    onSubmit: {
                        collectionManager.renameTimeEvent(id: event.id, newName: newTimeEventName)
                        isEditingTimeEvent = false
                    }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        )
                )
                .onAppear {
                    newTimeEventName = event.name
                }
            } else {
                Text(event.name)
                    .font(.body)
            }
            
            Spacer()
            
            if selectedTimeEventID == event.id && !isEditingTimeEvent {
                HStack(spacing: 8) {
                    Button(action: {
                        newTimeEventName = event.name
                        isEditingTimeEvent = true
                    }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(^String.Titles.renameEvent)
                    
                    Button(action: {
                        collectionManager.deleteTimeEvent(id: event.id)
                        if selectedTimeEventID == event.id {
                            selectedTimeEventID = nil
                        }
                        
                        _ = collectionManager.saveCollectionToFiles()
                        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedTimeEventID == event.id ? Color.blue.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedTimeEventID == event.id ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingTimeEvent {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTimeEventID = event.id
                    selectedTagID = nil
                    selectedLabelID = nil
                    newTimeEventName = event.name
                }
            }

        }
    }
    
    var addTimeEventButton: some View {
        Button(action: {
            newTimeEventName = ""
            showAddTimeEventSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.orange)
                Text(^String.Titles.addEvent)
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func tagGroupRowView(group: TagGroup) -> some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
                .frame(width: 16)
            
            if selectedTagGroupID == group.id && isEditingGroupName {
                AutoFocusTextField(
                    text: $newGroupName,
                    placeholder: ^String.Titles.groupName,
                    onSubmit: {
                        collectionManager.renameTagGroup(id: group.id, newName: newGroupName)
                        isEditingGroupName = false
                    }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        )
                )
                .onAppear {
                    newGroupName = group.name
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(getTagsForGroup(groupID: group.id).count) \(^String.Titles.tagsInGroup)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if selectedTagGroupID == group.id && !isEditingGroupName {
                HStack(spacing: 8) {
                    Button(action: {
                        newGroupName = group.name
                        isEditingGroupName = true
                    }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(^String.Titles.renameGroup)
                    
                    Button(action: {
                        collectionManager.deleteTagGroup(id: group.id)
                        if selectedTagGroupID == group.id {
                            selectedTagGroupID = nil
                            selectedTagID = nil
                        }
                        
                        _ = collectionManager.saveCollectionToFiles()
                        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedTagGroupID == group.id ? Color.blue.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedTagGroupID == group.id ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingGroupName {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTagGroupID = group.id
                    selectedLabelGroupID = nil
                    selectedTagID = nil
                    selectedLabelID = nil
                    isEditingGroupName = false
                }
            }
        }
    }
    
    var addTagGroupButton: some View {
        Button(action: {
            newGroupName = ""
            showAddTagGroupSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
                Text(^String.Titles.addGroup)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func tagsInGroupSection(groupID: String) -> some View {
        Group {
            if let group = collectionManager.tagGroups.first(where: { $0.id == groupID }) {
                let groupTags = getTagsForGroup(groupID: groupID)
                let filteredTags = filteredTagsInGroup(groupTags: groupTags)
                
                Section {
                    ForEach(filteredTags) { tag in
                        tagRowView(tag: tag)
                    }
                    
                    addTagButton
                } header: {
                    HStack {
                        Image(systemName: "tag")
                            .foregroundColor(.blue)
                        Text("\(^String.Titles.tagsInGroup) \"\(group.name)\"")
                            .font(.subheadline)
                        Spacer()
                        Text("\(filteredTags.count)/\(groupTags.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
    
    private func saveCollectionData() {
        if collectionManager.saveCollectionToFiles() {
            showSaveSuccess = true
            isEditingCollectionName = false
            NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSaveSuccess = false
                }
            }
        }
    }
    
    private func countActiveMapTagsOnTimelines() -> Int {
        let timelineData = TimelineDataManager.shared
        let currentCollectionName = collectionManager.collectionName
        
        return timelineData.lines.flatMap { $0.stamps }.filter { stamp in
            guard let tag = collectionManager.tags.first(where: { $0.id == stamp.idTag }) else {
                return false
            }
            return stamp.position != nil && (stamp.isActiveForMapView ?? false)
        }.count
    }

    private func resetTagPositionsOnTimelines() {
        let timelineData = TimelineDataManager.shared
        let currentCollectionName = collectionManager.collectionName
        
        for lineIndex in timelineData.lines.indices {
            for stampIndex in timelineData.lines[lineIndex].stamps.indices {
                let stamp = timelineData.lines[lineIndex].stamps[stampIndex]
                
                if collectionManager.tags.contains(where: { $0.id == stamp.idTag }) {
                    timelineData.lines[lineIndex].stamps[stampIndex].isActiveForMapView = false
                }
            }
        }
        
        timelineData.updateTimelines()
    }
    
    var addTagButton: some View {
        Button(action: {
            showAddTagSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
                Text(^String.Titles.addTag)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func getTagsForGroup(groupID: String) -> [Tag] {
        if let group = collectionManager.tagGroups.first(where: { $0.id == groupID }) {
            return collectionManager.tags.filter { tag in
                group.tags.contains(tag.id)
            }
        }
        return []
    }
    
    func tagRowView(tag: Tag) -> some View {
        HStack {
            Circle()
                .fill(Color(hex: tag.color))
                .frame(width: 12, height: 12)
            
            if selectedTagID == tag.id && isEditingName {
                AutoFocusTextField(
                    text: $editingName,
                    placeholder: ^String.Titles.tagName,
                    onSubmit: {
                        tagFormData.name = editingName
                        let success = collectionManager.updateTag(
                            id: tag.id,
                            primaryID: tag.primaryID,
                            name: editingName,
                            description: tag.description,
                            color: tag.color,
                            defaultTimeBefore: tag.defaultTimeBefore,
                            defaultTimeAfter: tag.defaultTimeAfter,
                            labelGroupIDs: tag.lablesGroup,
                            hotkey: tag.hotkey,
                            labelHotkeys: tag.labelHotkeys ?? [:],
                            isInterval: tag.isInterval ?? false,
                            mapEnabled: tag.mapEnabled ?? false
                        )
                        
                        if success, let updatedTag = collectionManager.tags.first(where: { $0.name == editingName }) {
                            selectedTagID = updatedTag.id
                            tagFormData = TagFormData(from: updatedTag)
                            
                            _ = collectionManager.saveCollectionToFiles()
                            NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                        }
                        
                        isEditingName = false
                    }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        )
                )
                .onAppear {
                    editingName = tag.name
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.name)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    if !tag.description.isEmpty {
                        Text(tag.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            if let hotkey = tag.hotkey, !hotkey.isEmpty {
                Text("⌨️ \(hotkey)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
            
            if selectedTagID == tag.id && !isEditingName {
                HStack(spacing: 8) {
                    Button(action: {
                        editingName = tag.name
                        isEditingName = true
                    }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(^String.Titles.renameTag)
                    
                    Button(action: {
                        collectionManager.deleteTag(id: tag.id)
                        if selectedTagID == tag.id {
                            selectedTagID = nil
                        }
                        
                        _ = collectionManager.saveCollectionToFiles()
                        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedTagID == tag.id ? Color.blue.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedTagID == tag.id ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingName {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTagID = tag.id
                    selectedLabelID = nil
                    tagFormData = TagFormData(from: tag)
                    isEditingName = false
                }
            }
        }
    }
    
    var labelGroupsListSection: some View {
        Section {
            ForEach(filteredLabelGroups) { group in
                labelGroupRowView(group: group)
            }
            
            addLabelGroupButton
        } header: {
            HStack {
                Image(systemName: "label.fill")
                    .foregroundColor(.green)
                Text(^String.Titles.labelGroups)
                    .font(.headline)
                Spacer()
                Text("\(collectionManager.labelGroups.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
            }
            .padding(.vertical, 4)
        }
    }
    
    func labelGroupRowView(group: LabelGroupData) -> some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(.green)
                .frame(width: 16)
            
            if selectedLabelGroupID == group.id && isEditingGroupName {
                AutoFocusTextField(
                    text: $newGroupName,
                    placeholder: ^String.Titles.groupName,
                    onSubmit: {
                        collectionManager.renameLabelGroup(id: group.id, newName: newGroupName)
                        isEditingGroupName = false
                    }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.green.opacity(0.5), lineWidth: 1)
                        )
                )
                .onAppear {
                    newGroupName = group.name
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(getLabelsForGroup(groupID: group.id).count) лейблов")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if selectedLabelGroupID == group.id && !isEditingGroupName {
                HStack(spacing: 8) {
                    Button(action: {
                        newGroupName = group.name
                        isEditingGroupName = true
                    }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.green)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(^String.Titles.renameGroup)
                    
                    Button(action: {
                        collectionManager.deleteLabelGroup(id: group.id)
                        if selectedLabelGroupID == group.id {
                            selectedLabelGroupID = nil
                            selectedLabelID = nil
                        }
                        
                        _ = collectionManager.saveCollectionToFiles()
                        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedLabelGroupID == group.id ? Color.green.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedLabelGroupID == group.id ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingGroupName {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedLabelGroupID = group.id
                    selectedTagGroupID = nil
                    selectedTagID = nil
                    selectedLabelID = nil
                    isEditingGroupName = false
                }
            }
        }
    }
    
    var addLabelGroupButton: some View {
        Button(action: {
            newGroupName = ""
            showAddLabelGroupSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.green)
                Text(^String.Titles.addGroup)
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func labelsInGroupSection(groupID: String) -> some View {
        Group {
            if let group = collectionManager.labelGroups.first(where: { $0.id == groupID }) {
                let groupLabels = getLabelsForGroup(groupID: groupID)
                let filteredLabels = filteredLabelsInGroup(groupLabels: groupLabels)
                
                Section {
                    ForEach(filteredLabels) { label in
                        labelRowView(label: label)
                    }
                    
                    addLabelButton
                } header: {
                    HStack {
                        Image(systemName: "label")
                            .foregroundColor(.green)
                        Text(String(format: ^String.Titles.collectionsLabelGroupName, group.name))
                            .font(.subheadline)
                        Spacer()
                        Text("\(filteredLabels.count)/\(groupLabels.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
    
    var addLabelButton: some View {
        Button(action: {
            newLabelName = ""
            newLabelDescription = ""
            showAddLabelSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.green)
                Text(^String.Titles.collectionsButtonAddLabel)
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func getLabelsForGroup(groupID: String) -> [Label] {
        if let group = collectionManager.labelGroups.first(where: { $0.id == groupID }) {
            return collectionManager.labels.filter { label in
                group.lables.contains(label.id)
            }
        }
        return []
    }
    
    func labelRowView(label: Label) -> some View {
        HStack {
            Image(systemName: "label")
                .foregroundColor(.green)
                .frame(width: 16)
            
            if selectedLabelID == label.id && isEditingName {
                AutoFocusTextField(
                    text: $editingName,
                    placeholder: ^String.Titles.renameLabelPlaceholder,
                    onSubmit: {
                        collectionManager.updateLabel(
                            id: label.id,
                            name: editingName,
                            description: label.description
                        )
                        newLabelName = editingName
                        
                        _ = collectionManager.saveCollectionToFiles()
                        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                        
                        isEditingName = false
                    }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.green.opacity(0.5), lineWidth: 1)
                        )
                )
                .onAppear {
                    editingName = label.name
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.name)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    if !label.description.isEmpty {
                        Text(label.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            if selectedLabelID == label.id && !isEditingName {
                HStack(spacing: 8) {
                    Button(action: {
                        editingName = label.name
                        isEditingName = true
                    }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.green)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(^String.Titles.helpRenameLabel)
                    
                    Button(action: {
                        collectionManager.deleteLabel(id: label.id)
                        if selectedLabelID == label.id {
                            selectedLabelID = nil
                        }
                        
                        _ = collectionManager.saveCollectionToFiles()
                        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedLabelID == label.id ? Color.green.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedLabelID == label.id ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingName {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedLabelID = label.id
                    selectedTagID = nil
                    newLabelName = label.name
                    newLabelDescription = label.description
                    isEditingName = false
                }
            }
        }
    }
    
    var detailView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewMode == .fieldMap {
                    fieldMapDetailView
                } else if let tagID = selectedTagID,
                          let tag = collectionManager.tags.first(where: { $0.id == tagID })
                {
                    tagDetailView(tag: tag)
                }
                else if let labelID = selectedLabelID,
                        let label = collectionManager.labels.first(where: { $0.id == labelID })
                {
                    labelDetailView(label: label)
                }
                else if let timeEventID = selectedTimeEventID,
                        let event = collectionManager.timeEvents.first(where: { $0.id == timeEventID })
                {
                    timeEventDetailView(event: event)
                }
                else if selectedTagGroupID != nil || selectedLabelGroupID != nil {
                    emptyStateView
                }
                else {
                    welcomeView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: viewMode == .tagGroups ? "tag" : "label")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(viewMode == .tagGroups ? ^String.Titles.collectionsTagEmpty : ^String.Titles.collectionsLabelEmpty)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text(^String.Titles.selectElementFromLeftList)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    var welcomeView: some View {
        VStack(spacing: 24) {
            Image(systemName: getWelcomeIcon())
                .font(.system(size: 80))
                .foregroundColor(getWelcomeColor())
            
            VStack(spacing: 8) {
                Text(getWelcomeTitle())
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            if viewMode == .timeEvents && !collectionManager.timeEvents.isEmpty {
                Text(^String.Titles.selectTimeEventForEditing)
                    .font(.headline)
                    .foregroundColor(.blue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    private func getWelcomeIcon() -> String {
        switch viewMode {
        case .tagGroups: return "tag.fill"
        case .labelGroups: return "label.fill"
        case .timeEvents: return "clock.fill"
        case .fieldMap: return "map.fill"
        }
    }
    
    private func getWelcomeColor() -> Color {
        switch viewMode {
        case .tagGroups: return .blue
        case .labelGroups: return .green
        case .timeEvents: return .orange
        case .fieldMap: return .purple
        }
    }
    
    private func getWelcomeTitle() -> String {
        switch viewMode {
        case .tagGroups: return ^String.Titles.collectionsGroupEmpty
        case .labelGroups: return ^String.Titles.CollectionsLabelGroupEmpty
        case .timeEvents: return collectionManager.timeEvents.isEmpty ? ^String.Titles.collectionsEventEmpty : ^String.Titles.selectTimeEventForEditing
        case .fieldMap: return ^String.Titles.fieldMapSettings
        }
    }
    
    func saveFieldImage(_ image: NSImage) {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".png"
        let tempUrl = tempDir.appendingPathComponent(fileName)
        
        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            try? pngData.write(to: tempUrl)
            
            _ = collectionManager.setFieldImage(from: tempUrl)
            
            try? FileManager.default.removeItem(at: tempUrl)
        }
    }
    
    var fieldMapDetailView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "map.fill")
                            .foregroundColor(.purple)
                            .font(.title2)
                        
                        Text(^String.Titles.fieldMapSettings)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                    }
                    
                    Divider()
                }
                
                if let playField = collectionManager.playField {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(^String.Titles.fieldMap)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    activeTagsOnTimelines = countActiveMapTagsOnTimelines()
                                    if activeTagsOnTimelines > 0 {
                                        activeAlert = .fieldChange
                                    } else {
                                        selectNewFieldImage()
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text(^String.Titles.replace)
                                    }
                                    .font(.subheadline)
                                }
                                .buttonStyle(ModernSecondaryButtonStyle())
                                
                                Button(action: {
                                    activeTagsOnTimelines = countActiveMapTagsOnTimelines()
                                    if activeTagsOnTimelines > 0 {
                                        activeAlert = .fieldDelete
                                    } else {
                                        collectionManager.deleteFieldImage()
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash")
                                        Text(^String.Titles.delete)
                                    }
                                    .font(.subheadline)
                                }
                                .buttonStyle(ModernDestructiveButtonStyle())
                            }
                        }
                        
                        VStack(spacing: 16) {
                            if let imageBookmark = collectionManager.playField?.imageBookmark,
                               let imageURL = createImageUrl(imageBookmark),
                               let nsImage = NSImage(contentsOf: imageURL) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                        )
                                    
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 400)
                                        .cornerRadius(16)
                                }
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                            } else {
                                VStack(spacing: 16) {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .font(.system(size: 48))
                                        .foregroundColor(.orange)
                                    
                                    Text(^String.Titles.failedToLoadImage)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text(^String.Titles.failedToLoadFieldMapImage)
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(40)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text(^String.Titles.fieldDimensions)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "arrow.up.and.down")
                                            .foregroundColor(.blue)
                                        Text(^String.Titles.collectionsFieldWidth)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    
                                    HStack(spacing: 8) {
                                        TextField("", value: Binding(
                                            get: { playField.width },
                                            set: { collectionManager.updateFieldDimensions(width: $0, height: playField.height) }
                                        ), formatter: NumberFormatter())
                                        .textFieldStyle(ModernNewTextFieldStyle())
                                        .frame(width: 80)
                                        
                                        Stepper("", value: Binding(
                                            get: { playField.width },
                                            set: { collectionManager.updateFieldDimensions(width: $0, height: playField.height) }
                                        ), in: 1...1000, step: 1)
                                        .labelsHidden()
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.windowBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "arrow.left.and.right")
                                            .foregroundColor(.green)
                                        Text(^String.Titles.collectionsFieldHeight)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    
                                    HStack(spacing: 8) {
                                        TextField("", value: Binding(
                                            get: { playField.height },
                                            set: { collectionManager.updateFieldDimensions(width: playField.width, height: $0) }
                                        ), formatter: NumberFormatter())
                                        .textFieldStyle(ModernNewTextFieldStyle())
                                        .frame(width: 80)
                                        
                                        Stepper("", value: Binding(
                                            get: { playField.height },
                                            set: { collectionManager.updateFieldDimensions(width: playField.width, height: $0) }
                                        ), in: 1...1000, step: 1)
                                        .labelsHidden()
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.windowBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.green.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                
                                Spacer()
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                            )
                    )
                    
                } else {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            Image(systemName: "map")
                                .font(.system(size: 80))
                                .foregroundColor(.purple.opacity(0.6))
                            
                            VStack(spacing: 8) {
                                Text(^String.Titles.fieldMapNotSet)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text(^String.Titles.uploadFieldMapHint)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(nil)
                            }
                        }
                        
                        Button(action: {
                            selectNewFieldImage()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "photo.badge.plus")
                                Text(^String.Titles.uploadFieldMap)
                            }
                            .font(.headline)
                        }
                        .buttonStyle(ModernPrimaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(60)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.purple.opacity(0.2), lineWidth: 2)
                            )
                    )
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.blue)
                        
                        Text(^String.Titles.collectionsTagsForMap)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(String.Titles.collectionsTagsCount.format(enabledTagsForMap.count, allTagsForMap.count))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.1))
                            )
                    }
                    
                    tagsForFieldMapList
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                        )
                )
            }
            .padding(24)
        }
    }
    
    func createImageUrl(_ bookmark: Data) -> URL? {
        do {
            var isStale = false
            let restoredUrl = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            guard restoredUrl.startAccessingSecurityScopedResource() else { return nil }
            return restoredUrl
        } catch {
            return nil
        }
    }
    
    private var allTagsForMap: [Tag] {
        collectionManager.tags
    }
    
    private var enabledTagsForMap: [Tag] {
        collectionManager.tags.filter { $0.mapEnabled ?? false }
    }
    
    var tagsForFieldMapList: some View {
        let groupsWithTags = collectionManager.tagGroups.map { group -> (TagGroup, [Tag]) in
            let groupTags = collectionManager.tags.filter { tag in
                group.tags.contains(tag.id)
            }
            return (group, groupTags)
        }
        
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(groupsWithTags, id: \.0.id) { groupInfo in
                    let group = groupInfo.0
                    let groupTags = groupInfo.1
                    
                    if !groupTags.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                
                                Text(group.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                let enabledInGroup = groupTags.filter { $0.mapEnabled ?? false }.count
                                Text("\(enabledInGroup)/\(groupTags.count)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.blue.opacity(0.1))
                                    )
                            }
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)
                            ], spacing: 8) {
                                ForEach(groupTags) { tag in
                                    tagMapToggleCard(tag: tag)
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 400)
    }

    private func tagMapToggleCard(tag: Tag) -> some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(Color(hex: tag.color))
                    .frame(width: 20, height: 20)
                
                Text(tag.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer()
            }
            
            if !tag.description.isEmpty {
                Text(tag.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack {
                Text(^String.Titles.useOnMap)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { tag.mapEnabled ?? false },
                    set: { collectionManager.updateTagMapEnabled(id: tag.id, mapEnabled: $0) }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .labelsHidden()
                .disabled(collectionManager.playField == nil)
                .opacity(collectionManager.playField == nil ? 0.6 : 1)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            (tag.mapEnabled ?? false) ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect((tag.mapEnabled ?? false) ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: tag.mapEnabled)
    }
    
    private func tagMapToggleRow(tag: Tag) -> some View {
        HStack {
            Rectangle()
                .fill(Color(hex: tag.color))
                .frame(width: 16, height: 16)
            
            Text(tag.name)
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { tag.mapEnabled ?? false },
                set: { collectionManager.updateTagMapEnabled(id: tag.id, mapEnabled: $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(collectionManager.playField == nil)
            .opacity(collectionManager.playField == nil ? 0.6 : 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    func selectNewFieldImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["png", "jpg", "jpeg"]
        
        if panel.runModal() == .OK, let url = panel.url {
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = UUID().uuidString + "." + url.pathExtension
            let tempUrl = tempDir.appendingPathComponent(fileName)
            
            do {
                try FileManager.default.copyItem(at: url, to: tempUrl)
                let bookmarkData = try tempUrl.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                self.tempImageBookmark = bookmarkData
                
                UserDefaults.standard.setValue(bookmarkData, forKey: "tempImageBookmark")
                
                self.showCropSheet = true
            } catch {
                print(error)
            }
        }
    }

    func handleCroppedImage(_ image: NSImage, tempUrl: URL) {
        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: tempUrl)
                _ = collectionManager.setFieldImage(from: tempUrl)
            } catch {
                print(error)
            }
        }
        
        tempUrl.stopAccessingSecurityScopedResource()
        try? FileManager.default.removeItem(at: tempUrl)
        tempImageBookmark = nil
    }
    
    func tagDetailView(tag: Tag) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    HStack {
                        Circle()
                            .fill(Color(hex: tag.color))
                            .frame(width: 24, height: 24)
                        
                        Text(^String.Titles.tagInfo)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                    }
                    
                    Divider()
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text(^String.Titles.basicInformation)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(^String.Titles.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            FocusAwareTextField(text: $tagFormData.name, placeholder: ^String.Titles.title)
                                .textFieldStyle(ModernNewTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(^String.Titles.description)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $tagFormData.description)
                                .frame(minHeight: 80)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                        )
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(^String.Titles.color)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            ColorPickerView(selectedColor: $tagFormData.color, hexString: $tagFormData.hexColor)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                        )
                                )
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
                
                if true/*!tagFormData.isInterval*/ {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(^String.Titles.timeSettings)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(^String.Titles.collectionsTagTimeBefore)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Text("\(Int(tagFormData.defaultTimeBefore)) \(^String.Titles.collectionsTagTimeFormat)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                }
                                
                                Slider(value: $tagFormData.defaultTimeBefore, in: 0...30, step: 1)
                                    .accentColor(.blue)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(^String.Titles.collectionsTagTimeAfter)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Text("\(Int(tagFormData.defaultTimeAfter)) \(^String.Titles.collectionsTagTimeFormat)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                }
                                
                                Slider(value: $tagFormData.defaultTimeAfter, in: 0...30, step: 1)
                                    .accentColor(.blue)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(NSColor.windowBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text(^String.Titles.additionalSettings)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(^String.Titles.collectionsTagUseWithMap)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text(^String.Titles.collectionsTagMapHelp)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $tagFormData.mapEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                                .disabled(collectionManager.playField == nil)
                                .opacity(collectionManager.playField == nil ? 0.6 : 1)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(^String.Titles.collectionsTagIsInterval)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text(^String.Titles.collectionsTagIsIntervalHelp)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $tagFormData.isInterval)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text(^String.Titles.hotkeys)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(^String.Titles.collectionsTagHotkey)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        ZStack {
                            Button(action: {
                                isCapturingTagHotkey = true
                            }) {
                                HStack {
                                    Image(systemName: "keyboard")
                                        .foregroundColor(.blue)
                                    
                                    Text(tagFormData.hotkey ?? ^String.Titles.collectionsTagNoHotkey)
                                        .foregroundColor(isCapturingTagHotkey ? .blue : .primary)
                                    
                                    Spacer()
                                    
                                    if tagFormData.hotkey != nil {
                                        Button(action: {
                                            tagFormData.hotkey = nil
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.gray)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(isCapturingTagHotkey ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .disabled(isCapturingTagHotkey)
                            
                            if isCapturingTagHotkey {
                                KeyCaptureView(keyString: $tagFormData.hotkey, isCapturing: $isCapturingTagHotkey)
                                    .allowsHitTesting(false)
                            }
                        }
                        
                        if let hotkey = tagFormData.hotkey,
                           collectionManager.isHotkeyAssigned(hotkey, excludingTagID: tag.id) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(^String.Titles.collectionsLabelHotkeyUsed)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.orange.opacity(0.1))
                            )
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text(^String.Titles.collectionsLabelLabelGroups)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 12) {
                        ForEach(collectionManager.labelGroups) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.green)
                                    
                                    Text(group.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { tagFormData.selectedLabelGroups.contains(group.id) },
                                        set: { isSelected in
                                            if isSelected {
                                                tagFormData.selectedLabelGroups.append(group.id)
                                            } else {
                                                tagFormData.selectedLabelGroups.removeAll { $0 == group.id }
                                            }
                                        }
                                    ))
                                    .toggleStyle(SwitchToggleStyle(tint: .green))
                                }
                                
                                if tagFormData.selectedLabelGroups.contains(group.id) {
                                    VStack(spacing: 8) {
                                        ForEach(getLabelsForGroup(groupID: group.id)) { label in
                                            HStack {
                                                Image(systemName: "label")
                                                    .foregroundColor(.green)
                                                
                                                Text(label.name)
                                                    .font(.body)
                                                
                                                Spacer()
                                                
                                                ZStack {
                                                    Button(action: {
                                                        isCapturingTagHotkey = false
                                                        for (key, _) in isCapturingLabelHotkeys {
                                                            isCapturingLabelHotkeys[key] = false
                                                        }
                                                        isCapturingLabelHotkeys[label.id] = true
                                                    }) {
                                                        HStack {
                                                            Image(systemName: "keyboard")
                                                                .foregroundColor(.blue)
                                                            
                                                            Text(tagFormData.labelHotkeys[label.id] ?? ^String.Titles.assign)
                                                                .foregroundColor(isCapturingLabelHotkeys[label.id] == true ? .blue : .primary)
                                                                .lineLimit(1)
                                                            
                                                            if tagFormData.labelHotkeys[label.id] != nil {
                                                                Button(action: {
                                                                    tagFormData.labelHotkeys.removeValue(forKey: label.id)
                                                                }) {
                                                                    Image(systemName: "xmark.circle.fill")
                                                                        .foregroundColor(.gray)
                                                                }
                                                                .buttonStyle(BorderlessButtonStyle())
                                                            }
                                                        }
                                                        .padding(8)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 8)
                                                                .fill(Color(NSColor.controlBackgroundColor))
                                                                .overlay(
                                                                    RoundedRectangle(cornerRadius: 8)
                                                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                                                )
                                                        )
                                                    }
                                                    .buttonStyle(BorderlessButtonStyle())
                                                    .disabled(isCapturingLabelHotkeys[label.id] == true)
                                                    
                                                    if isCapturingLabelHotkeys[label.id] == true {
                                                        KeyCaptureView(
                                                            keyString: Binding(
                                                                get: { tagFormData.labelHotkeys[label.id] },
                                                                set: { tagFormData.labelHotkeys[label.id] = $0 }
                                                            ),
                                                            isCapturing: Binding(
                                                                get: { isCapturingLabelHotkeys[label.id] == true },
                                                                set: { isCapturingLabelHotkeys[label.id] = $0 }
                                                            )
                                                        )
                                                        .allowsHitTesting(false)
                                                    }
                                                }
                                                
                                                if let hotkey = tagFormData.labelHotkeys[label.id],
                                                   tagFormData.isLabelHotkeyUsed(hotkey, exceptLabel: label.id) {
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .foregroundColor(.orange)
                                                        .help(^String.Titles.hotkeyAlreadyUsed)
                                                }
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                        }
                                    }
                                    .padding(.leading, 20)
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
                
                Button(^String.Titles.collectionsButtonSaveChanges) {
                    let success = collectionManager.updateTag(
                        id: tag.id,
                        primaryID: tag.primaryID,
                        name: tagFormData.name,
                        description: tagFormData.description,
                        color: tagFormData.hexColor,
                        defaultTimeBefore: tagFormData.defaultTimeBefore,
                        defaultTimeAfter: tagFormData.defaultTimeAfter,
                        labelGroupIDs: tagFormData.selectedLabelGroups,
                        hotkey: tagFormData.hotkey,
                        labelHotkeys: tagFormData.labelHotkeys,
                        isInterval: tagFormData.isInterval,
                        mapEnabled: tagFormData.mapEnabled
                    )
                    
                    if success, let updatedTag = collectionManager.tags.first(where: { $0.name == tagFormData.name }) {
                        selectedTagID = updatedTag.id
                        tagFormData = TagFormData(from: updatedTag)
                        
                        _ = collectionManager.saveCollectionToFiles()
                        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                    }
                }
                .buttonStyle(ModernPrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding(24)
        }
        .onAppear {
            isCapturingLabelHotkeys = [:]
            for groupID in tagFormData.selectedLabelGroups {
                for label in getLabelsForGroup(groupID: groupID) {
                    isCapturingLabelHotkeys[label.id] = false
                }
            }
        }
    }
    
    func labelDetailView(label: Label) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "label.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        
                        Text(^String.Titles.labelInfo)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                    }
                    
                    Divider()
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text(^String.Titles.basicInformation)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(^String.Titles.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            FocusAwareTextField(text: $newLabelName, placeholder: ^String.Titles.title)
                                .textFieldStyle(ModernNewTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(^String.Titles.description)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $newLabelDescription)
                                .frame(minHeight: 80)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                        )
                                )
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text(^String.Titles.relatedTags)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    let relatedTags = collectionManager.tags.filter { tag in
                        tag.lablesGroup.contains { groupID in
                            if let group = collectionManager.labelGroups.first(where: { $0.id == groupID }) {
                                return group.lables.contains(label.id)
                            }
                            return false
                        }
                    }
                    
                    if relatedTags.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tag.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            
                            Text(^String.Titles.noRelatedTags)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text(^String.Titles.collectionsLabelTagAssociations)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 12) {
                            ForEach(relatedTags) { tag in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: tag.color))
                                        .frame(width: 12, height: 12)
                                    
                                    Text(tag.name)
                                        .font(.body)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                        )
                                )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(NSColor.windowBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                }
                
                Button(^String.Titles.collectionsButtonSaveChanges) {
                    if let index = collectionManager.labels.firstIndex(where: { $0.id == label.id }) {
                        collectionManager.labels[index] = Label(
                            id: label.id,
                            name: newLabelName,
                            description: newLabelDescription
                        )
                        
                        _ = collectionManager.saveCollectionToFiles()
                        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                    }
                }
                .buttonStyle(ModernPrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding(24)
        }
    }
    
    func timeEventDetailView(event: TimeEvent) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                        
                        Text(^String.Titles.eventInfo)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                    }
                    
                    Divider()
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text(^String.Titles.basicInformation)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(^String.Titles.eventName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            FocusAwareTextField(text: $newTimeEventName, placeholder: ^String.Titles.title)
                                .textFieldStyle(ModernNewTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(^String.Titles.description)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            Text(^String.Titles.commonEventsDescription)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.orange.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                                        )
                                )
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
                
                VStack(spacing: 16) {
                    Button(^String.Titles.collectionsButtonSaveChanges) {
                        if let index = collectionManager.timeEvents.firstIndex(where: { $0.id == event.id }) {
                            collectionManager.timeEvents[index] = TimeEvent(
                                id: event.id,
                                name: newTimeEventName
                            )
                            
                            _ = collectionManager.saveCollectionToFiles()
                            NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                        }
                    }
                    .buttonStyle(ModernPrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    
                    Button(^String.Titles.deleteEvent) {
                        collectionManager.removeTimeEvent(id: event.id)
                        selectedTimeEventID = nil
                        _ = collectionManager.saveCollectionToFiles()
                        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                    }
                    .buttonStyle(ModernDestructiveButtonStyle())
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
    }
    
    func addTagGroupSheet() -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text(^String.Titles.addTagGroup)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.groupNameLabel)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                FocusAwareTextField(text: $newGroupName, placeholder: ^String.Titles.groupName)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
            .padding(.horizontal, 24)
            
            HStack(spacing: 16) {
                Button(^String.Titles.collectionsButtonCancel) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAddTagGroupSheet = false
                        newGroupName = ""
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button(^String.Titles.collectionsButtonAdd) {
                    let _ = collectionManager.createTagGroup(name: newGroupName)
                    
                    _ = collectionManager.saveCollectionToFiles()
                    NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                    
                    newGroupName = ""
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAddTagGroupSheet = false
                    }
                }
                .disabled(newGroupName.isEmpty)
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 450)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    func addLabelGroupSheet() -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "label.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
                
                Text(^String.Titles.addLabelGroup)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.groupNameLabel)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                FocusAwareTextField(text: $newGroupName, placeholder: ^String.Titles.groupName)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
            .padding(.horizontal, 24)
            
            HStack(spacing: 16) {
                Button(^String.Titles.collectionsButtonCancel) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAddLabelGroupSheet = false
                        newGroupName = ""
                    }
                }
                .keyboardShortcut(.escape)
                .buttonStyle(SecondaryButtonStyle())
                
                Button(^String.Titles.collectionsButtonAdd) {
                    let _ = collectionManager.createLabelGroup(name: newGroupName)
                    
                    _ = collectionManager.saveCollectionToFiles()
                    NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                    
                    newGroupName = ""
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAddLabelGroupSheet = false
                    }
                }
                .disabled(newGroupName.isEmpty)
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 450)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    func addGroupSheet(title: String, onAdd: @escaping () -> Void) -> some View {
        let isLabelGroup = title.localizedCaseInsensitiveContains("label")
        return VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: isLabelGroup ? "label.fill" : "tag.fill")
                    .font(.system(size: 40))
                    .foregroundColor(isLabelGroup ? .green : .blue)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.groupNameLabel)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                FocusAwareTextField(text: $newGroupName, placeholder: ^String.Titles.groupName)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
            .padding(.horizontal, 24)
            
            HStack(spacing: 16) {
                Button(^String.Titles.collectionsButtonCancel) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isLabelGroup {
                            showAddLabelGroupSheet = false
                        } else {
                            showAddTagGroupSheet = false
                        }
                    }
                }
                .keyboardShortcut(.escape)
                .buttonStyle(SecondaryButtonStyle())
                
                Button(^String.Titles.collectionsButtonAdd) {
                    onAdd()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isLabelGroup {
                            showAddLabelGroupSheet = false
                        } else {
                            showAddTagGroupSheet = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newGroupName.isEmpty)
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 450)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    func addTagSheet() -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "tag.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                    
                    Text(^String.Titles.addNewTag)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                
                Divider()
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))
            
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(^String.Titles.basicInformation)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(^String.Titles.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                FocusAwareTextField(text: $tagFormData.name, placeholder: ^String.Titles.title)
                                    .textFieldStyle(ModernNewTextFieldStyle())
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(^String.Titles.description)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                TextEditor(text: $tagFormData.description)
                                    .frame(minHeight: 80)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(^String.Titles.color)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                ColorPickerView(selectedColor: $tagFormData.color, hexString: $tagFormData.hexColor)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(NSColor.windowBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                    
                    if true/*!tagFormData.isInterval*/ {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(^String.Titles.timeSettings)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 20) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(^String.Titles.collectionsTagTimeBefore)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Text("\(Int(tagFormData.defaultTimeBefore)) \(^String.Titles.collectionsTagTimeFormat)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.blue.opacity(0.1))
                                            )
                                    }
                                    
                                    Slider(value: $tagFormData.defaultTimeBefore, in: 0...30, step: 1)
                                        .accentColor(.blue)
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(^String.Titles.collectionsTagTimeAfter)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Text("\(Int(tagFormData.defaultTimeAfter)) \(^String.Titles.collectionsTagTimeFormat)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.blue.opacity(0.1))
                                            )
                                    }
                                    
                                    Slider(value: $tagFormData.defaultTimeAfter, in: 0...30, step: 1)
                                        .accentColor(.blue)
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(NSColor.windowBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text(^String.Titles.additionalSettings)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(^String.Titles.collectionsTagIsInterval)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Text(^String.Titles.collectionsTagIsIntervalHelp)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $tagFormData.isInterval)
                                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            )
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(^String.Titles.collectionsTagHotkey)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                ZStack {
                                    Button(action: {
                                        isCapturingTagHotkey = true
                                    }) {
                                        HStack {
                                            Image(systemName: "keyboard")
                                                .foregroundColor(.blue)
                                            
                                            Text(tagFormData.hotkey ?? ^String.Titles.collectionsTagNoHotkey)
                                                .foregroundColor(isCapturingTagHotkey ? .blue : .primary)
                                            
                                            Spacer()
                                            
                                            if tagFormData.hotkey != nil {
                                                Button(action: {
                                                    tagFormData.hotkey = nil
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.gray)
                                                }
                                                .buttonStyle(BorderlessButtonStyle())
                                            }
                                        }
                                        .padding(16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(NSColor.controlBackgroundColor))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(isCapturingTagHotkey ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .disabled(isCapturingTagHotkey)
                                    
                                    if isCapturingTagHotkey {
                                        KeyCaptureView(keyString: $tagFormData.hotkey, isCapturing: $isCapturingTagHotkey)
                                            .allowsHitTesting(false)
                                    }
                                }
                                
                                if let hotkey = tagFormData.hotkey,
                                   collectionManager.isHotkeyAssigned(hotkey) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text(^String.Titles.collectionsLabelHotkeyUsed)
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.orange.opacity(0.1))
                                    )
                                }
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(NSColor.windowBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(24)
            }
            
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 16) {
                    Button(^String.Titles.collectionsButtonCancel) {
                        showAddTagSheet = false
                        tagFormData = TagFormData()
                    }
                    .keyboardShortcut(.escape)
                    .buttonStyle(ModernSecondaryButtonStyle())
                    
                    Button(^String.Titles.collectionsButtonAdd) {
                        if let groupID = selectedTagGroupID {
                            let newTag = collectionManager.createTag(
                                name: tagFormData.name,
                                description: tagFormData.description,
                                color: tagFormData.hexColor,
                                defaultTimeBefore: tagFormData.defaultTimeBefore,
                                defaultTimeAfter: tagFormData.defaultTimeAfter,
                                inGroup: groupID,
                                hotkey: tagFormData.hotkey,
                                isInterval: tagFormData.isInterval
                            )
                            
                            if !tagFormData.selectedLabelGroups.isEmpty {
                                collectionManager.updateTag(
                                    id: newTag.id,
                                    primaryID: newTag.primaryID,
                                    name: newTag.name,
                                    description: newTag.description,
                                    color: newTag.color,
                                    defaultTimeBefore: newTag.defaultTimeBefore,
                                    defaultTimeAfter: newTag.defaultTimeAfter,
                                    labelGroupIDs: tagFormData.selectedLabelGroups,
                                    hotkey: newTag.hotkey,
                                    labelHotkeys: tagFormData.labelHotkeys,
                                    isInterval: newTag.isInterval ?? false,
                                    mapEnabled: newTag.mapEnabled ?? false
                                )
                            }
                            
                            _ = collectionManager.saveCollectionToFiles()
                            NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                            
                            tagFormData = TagFormData()
                        }
                        showAddTagSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(tagFormData.name.isEmpty || selectedTagGroupID == nil)
                    .buttonStyle(ModernPrimaryButtonStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 600, height: 700)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
        .onAppear {
            tagFormData = TagFormData()
            isCapturingTagHotkey = false
            isCapturingLabelHotkeys = [:]
        }
    }
    
    func addLabelSheet() -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "label.fill")
                        .font(.title)
                        .foregroundColor(.green)
                    
                    Text(^String.Titles.collectionsDialogAddLabel)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                
                Divider()
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))
            
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(^String.Titles.basicInformation)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(^String.Titles.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                FocusAwareTextField(text: $newLabelName, placeholder: ^String.Titles.title)
                                    .textFieldStyle(ModernNewTextFieldStyle())
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(^String.Titles.description)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                TextEditor(text: $newLabelDescription)
                                    .frame(minHeight: 80)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(^String.Titles.informationLabel)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                Text(^String.Titles.labelsDescriptionText)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.green.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.green.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(NSColor.windowBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(24)
            }
            
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 16) {
                    Button(^String.Titles.collectionsButtonCancel) {
                        showAddLabelSheet = false
                        newLabelName = ""
                        newLabelDescription = ""
                    }
                    .keyboardShortcut(.escape)
                    .buttonStyle(ModernSecondaryButtonStyle())
                    
                    Button(^String.Titles.collectionsButtonAdd) {
                        if let groupID = selectedLabelGroupID {
                            collectionManager.createLabel(
                                name: newLabelName,
                                description: newLabelDescription,
                                inGroup: groupID
                            )
                            
                            _ = collectionManager.saveCollectionToFiles()
                            NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                            
                            newLabelName = ""
                            newLabelDescription = ""
                        }
                        showAddLabelSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newLabelName.isEmpty || selectedLabelGroupID == nil)
                    .buttonStyle(ModernPrimaryButtonStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 500, maxWidth: 500, minHeight: 500, maxHeight: 500)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
    }
    
    func addTimeEventSheet() -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.title)
                        .foregroundColor(.orange)
                    
                    Text(^String.Titles.collectionsDialogAddTimeEvent)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                
                Divider()
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))
            
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(^String.Titles.basicInformation)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(^String.Titles.eventName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                FocusAwareTextField(text: $newTimeEventName, placeholder: ^String.Titles.title)
                                    .textFieldStyle(ModernNewTextFieldStyle())
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(^String.Titles.informationLabel)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                Text(^String.Titles.commonEventsDescriptionExtended)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.orange.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(NSColor.windowBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(24)
            }
            
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 16) {
                    Button(^String.Titles.collectionsButtonCancel) {
                        showAddTimeEventSheet = false
                        newTimeEventName = ""
                    }
                    .keyboardShortcut(.escape)
                    .buttonStyle(ModernSecondaryButtonStyle())
                    
                    Button(^String.Titles.collectionsButtonAdd) {
                        collectionManager.createTimeEvent(name: newTimeEventName)
                        
                        _ = collectionManager.saveCollectionToFiles()
                        NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                        
                        newTimeEventName = ""
                        showAddTimeEventSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTimeEventName.isEmpty)
                    .buttonStyle(ModernPrimaryButtonStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 500, maxWidth: 500, minHeight: 500, maxHeight: 500)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
    }
        
    var filteredTagGroups: [TagGroup] {
        if searchText.isEmpty {
            return collectionManager.tagGroups
        }
        
        switch searchScope {
        case .all, .groups:
            return collectionManager.tagGroups.filter { group in
                group.name.localizedCaseInsensitiveContains(searchText)
            }
        default:
            return collectionManager.tagGroups
        }
    }
    
    var filteredTimeEvents: [TimeEvent] {
        if searchText.isEmpty {
            return collectionManager.timeEvents
        }
        
        switch searchScope {
        case .all, .groups:
            return collectionManager.timeEvents.filter { event in
                event.name.localizedCaseInsensitiveContains(searchText)
            }
        default:
            return collectionManager.timeEvents
        }
    }
    
    func filteredTagsInGroup(groupTags: [Tag]) -> [Tag] {
        if searchText.isEmpty {
            return groupTags
        }
        
        switch searchScope {
        case .all, .tags:
            return groupTags.filter { tag in
                tag.name.localizedCaseInsensitiveContains(searchText) ||
                tag.description.localizedCaseInsensitiveContains(searchText)
            }
        default:
            return groupTags
        }
    }
    
    var filteredLabelGroups: [LabelGroupData] {
        if searchText.isEmpty {
            return collectionManager.labelGroups
        }
        
        switch searchScope {
        case .all, .groups:
            return collectionManager.labelGroups.filter { group in
                group.name.localizedCaseInsensitiveContains(searchText)
            }
        default:
            return collectionManager.labelGroups
        }
    }
    
    func filteredLabelsInGroup(groupLabels: [Label]) -> [Label] {
        if searchText.isEmpty {
            return groupLabels
        }
        
        switch searchScope {
        case .all, .labels:
            return groupLabels.filter { label in
                label.name.localizedCaseInsensitiveContains(searchText) ||
                label.description.localizedCaseInsensitiveContains(searchText)
            }
        default:
            return groupLabels
        }
    }
}

struct ModernPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            )
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ModernSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundColor(.primary)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            )
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ModernDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                    .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            )
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ModernNewTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
            .font(.body)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue)
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
