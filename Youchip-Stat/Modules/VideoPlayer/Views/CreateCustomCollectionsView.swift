//
//  CreateCustomCollectionsView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI
import Foundation

struct CreateCustomCollectionsView: View {
    @StateObject private var collectionManager: CustomCollectionManager
    @State private var viewMode: ViewMode = .tagGroups
    @State private var showAddTagGroupSheet = false
    @State private var showAddLabelGroupSheet = false
    @State private var isEditingName: Bool = false
    @State private var isEditingGroupName: Bool = false
    @State private var editingName: String = ""
    @State private var showAddTagSheet = false
    @State private var showAddLabelSheet = false
    @State private var showAddTimeEventSheet = false
    @State private var newGroupName = ""
    @State private var selectedTagGroupID: String?
    @State private var selectedLabelGroupID: String?
    @State private var selectedTagID: String?
    @State private var selectedLabelID: String?
    @State private var selectedTimeEventID: String?
    @State private var tagFormData = TagFormData()
    @State private var newLabelName = ""
    @State private var newLabelDescription = ""
    @State private var newTimeEventName = ""
    @State private var showSaveSuccess = false
    @State private var isCapturingTagHotkey = false
    @State private var isCapturingLabelHotkeys: [String: Bool] = [:]
    
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
    }
    
    var body: some View {
        VStack(spacing: 0) {
            customToolbarView
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .border(Color.gray.opacity(0.2), width: 0.5)
            
            NavigationView {
                sidebarView
                detailView
            }
        }
        .onDisappear {
            NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
        }
        .sheet(isPresented: $showAddTagGroupSheet) {
            addGroupSheet(title: "Добавить группу тегов") {
                let _ = collectionManager.createTagGroup(name: newGroupName)
                newGroupName = ""
            }
        }
        .sheet(isPresented: $showAddLabelGroupSheet) {
            addGroupSheet(title: "Добавить группу лейблов") {
                let _ = collectionManager.createLabelGroup(name: newGroupName)
                newGroupName = ""
            }
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
    }
    
    var customToolbarView: some View {
        HStack {
            if collectionManager.isEditingExisting {
                Text(collectionManager.collectionName)
                    .frame(width: 200, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 5)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(5)
            } else {
                FocusAwareTextField(text: $collectionManager.collectionName, placeholder: "Имя коллекции")
                    .frame(width: 200)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            Button(action: {
                if collectionManager.saveCollectionToFiles() {
                    showSaveSuccess = true
                    NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showSaveSuccess = false
                    }
                }
            }) {
                Text(collectionManager.isEditingExisting ? "Обновить коллекцию" : "Сохранить коллекцию")
            }
            .buttonStyle(CompatibilityButtonStyle())
            
            if showSaveSuccess {
                Text("Сохранено!")
                    .foregroundColor(.green)
            }
            
            Spacer()
            
            Picker("", selection: $viewMode) {
                Text("Группы тегов").tag(ViewMode.tagGroups)
                Text("Группы лейблов").tag(ViewMode.labelGroups)
                Text("Общие события").tag(ViewMode.timeEvents)
            }
            .pickerStyle(.segmented)
            .frame(width: 700)
        }
        .padding(.horizontal)
    }
    
    var sidebarView: some View {
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
            }
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 250)
    }
    
    var tagGroupsListSection: some View {
        Section {
            ForEach(collectionManager.tagGroups) { group in
                tagGroupRowView(group: group)
            }
            
            addTagGroupButton
        } header: {
            Text("Группы тегов")
        }
    }
    
    var timeEventsListSection: some View {
        Section {
            ForEach(collectionManager.timeEvents) { event in
                timeEventRowView(event: event)
            }
            
            addTimeEventButton
        } header: {
            Text("Общие события")
        }
    }
    
    func timeEventRowView(event: TimeEvent) -> some View {
        Text(event.name)
            .padding(.vertical, 2)
            .onTapGesture {
                selectedTimeEventID = event.id
                selectedTagID = nil
                selectedLabelID = nil
                newTimeEventName = event.name
            }
            .background(selectedTimeEventID == event.id ? Color.blue.opacity(0.2) : Color.clear)
    }
    
    var addTimeEventButton: some View {
        Button(action: {
            newTimeEventName = ""
            showAddTimeEventSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle")
                Text("Добавить событие")
            }
        }
    }
    
    func tagGroupRowView(group: TagGroup) -> some View {
        HStack {
            if selectedTagGroupID == group.id && isEditingGroupName {
                FocusAwareTextField(text: $newGroupName, placeholder: "Название группы")
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        newGroupName = group.name
                    }
                    .onSubmit {
                        collectionManager.renameTagGroup(id: group.id, newName: newGroupName)
                        isEditingGroupName = false
                    }
            } else {
                Text(group.name)
                    .font(.headline)
                    .padding(.vertical, 2)
            }
            
            Spacer()
            
            if selectedTagGroupID == group.id && !isEditingGroupName {
                Button(action: {
                    newGroupName = group.name
                    isEditingGroupName = true
                }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Переименовать группу")
            }
            
            Button(action: {
                collectionManager.deleteTagGroup(id: group.id)
                if selectedTagGroupID == group.id {
                    selectedTagGroupID = nil
                    selectedTagID = nil
                }
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingGroupName {
                selectedTagGroupID = group.id
                selectedLabelGroupID = nil
                selectedTagID = nil
                selectedLabelID = nil
                isEditingGroupName = false
            }
        }
        .background(selectedTagGroupID == group.id ? Color.blue.opacity(0.2) : Color.clear)
    }
    
    var addTagGroupButton: some View {
        Button(action: {
            newGroupName = ""
            showAddTagGroupSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle")
                Text("Добавить группу")
            }
        }
    }
    
    func tagsInGroupSection(groupID: String) -> some View {
        Group {
            if let group = collectionManager.tagGroups.first(where: { $0.id == groupID }) {
                Section {
                    let groupTags = getTagsForGroup(groupID: groupID)
                    
                    ForEach(groupTags) { tag in
                        tagRowView(tag: tag)
                    }
                    
                    addTagButton
                } header: {
                    Text("Теги в группе \"\(group.name)\"")
                }
            }
        }
    }
    
    var addTagButton: some View {
        Button(action: {
            showAddTagSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle")
                Text("Добавить тег")
            }
        }
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
            Rectangle()
                .fill(Color(hex: tag.color))
                .frame(width: 16, height: 16)
            
            if selectedTagID == tag.id && isEditingName {
                FocusAwareTextField(text: $editingName, placeholder: "Название тега")
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        editingName = tag.name
                    }
                    .onSubmit {
                        tagFormData.name = editingName
                        collectionManager.updateTag(
                            id: tag.id,
                            name: editingName,
                            description: tag.description,
                            color: tag.color,
                            defaultTimeBefore: tag.defaultTimeBefore,
                            defaultTimeAfter: tag.defaultTimeAfter,
                            labelGroupIDs: tag.lablesGroup,
                            hotkey: tag.hotkey,
                            labelHotkeys: tag.labelHotkeys ?? [:]
                        )
                        isEditingName = false
                    }
            } else {
                Text(tag.name)
                    .padding(.vertical, 2)
            }
            
            Spacer()
            
            if let hotkey = tag.hotkey, !hotkey.isEmpty {
                Text("⌨️ \(hotkey)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            
            if selectedTagID == tag.id && !isEditingName {
                Button(action: {
                    editingName = tag.name
                    isEditingName = true
                }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Переименовать тег")
            }
            
            Button(action: {
                collectionManager.deleteTag(id: tag.id)
                if selectedTagID == tag.id {
                    selectedTagID = nil
                }
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingName {
                selectedTagID = tag.id
                selectedLabelID = nil
                tagFormData = TagFormData(from: tag)
                isEditingName = false
            }
        }
        .background(selectedTagID == tag.id ? Color.blue.opacity(0.2) : Color.clear)
    }
    
    var labelGroupsListSection: some View {
        Section {
            ForEach(collectionManager.labelGroups) { group in
                labelGroupRowView(group: group)
            }
            
            addLabelGroupButton
        } header: {
            Text("Группы лейблов")
        }
    }
    
    func labelGroupRowView(group: LabelGroupData) -> some View {
        HStack {
            if selectedLabelGroupID == group.id && isEditingGroupName {
                FocusAwareTextField(text: $newGroupName, placeholder: "Название группы")
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        newGroupName = group.name
                    }
                    .onSubmit {
                        collectionManager.renameLabelGroup(id: group.id, newName: newGroupName)
                        isEditingGroupName = false
                    }
            } else {
                Text(group.name)
                    .font(.headline)
                    .padding(.vertical, 2)
            }
            
            Spacer()
            
            if selectedLabelGroupID == group.id && !isEditingGroupName {
                Button(action: {
                    newGroupName = group.name
                    isEditingGroupName = true
                }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Переименовать группу")
            }
            
            Button(action: {
                collectionManager.deleteLabelGroup(id: group.id)
                if selectedLabelGroupID == group.id {
                    selectedLabelGroupID = nil
                    selectedLabelID = nil
                }
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingGroupName {
                selectedLabelGroupID = group.id
                selectedTagGroupID = nil
                selectedTagID = nil
                selectedLabelID = nil
                isEditingGroupName = false
            }
        }
        .background(selectedLabelGroupID == group.id ? Color.blue.opacity(0.2) : Color.clear)
    }
    
    var addLabelGroupButton: some View {
        Button(action: {
            newGroupName = ""
            showAddLabelGroupSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle")
                Text("Добавить группу")
            }
        }
    }
    
    func labelsInGroupSection(groupID: String) -> some View {
        Group {
            if let group = collectionManager.labelGroups.first(where: { $0.id == groupID }) {
                Section {
                    let groupLabels = getLabelsForGroup(groupID: groupID)
                    
                    ForEach(groupLabels) { label in
                        labelRowView(label: label)
                    }
                    
                    addLabelButton
                } header: {
                    Text("Лейблы в группе \"\(group.name)\"")
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
                Image(systemName: "plus.circle")
                Text("Добавить лейбл")
            }
        }
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
            if selectedLabelID == label.id && isEditingName {
                FocusAwareTextField(text: $editingName, placeholder: "Название лейбла")
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        editingName = label.name
                    }
                    .onSubmit {
                        collectionManager.updateLabel(
                            id: label.id,
                            name: editingName,
                            description: label.description
                        )
                        newLabelName = editingName
                        isEditingName = false
                    }
            } else {
                Text(label.name)
                    .padding(.vertical, 2)
            }
            
            Spacer()
            
            if selectedLabelID == label.id && !isEditingName {
                Button(action: {
                    editingName = label.name
                    isEditingName = true
                }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Переименовать лейбл")
            }
            
            Button(action: {
                collectionManager.deleteLabel(id: label.id)
                if selectedLabelID == label.id {
                    selectedLabelID = nil
                }
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingName {
                selectedLabelID = label.id
                selectedTagID = nil
                newLabelName = label.name
                newLabelDescription = label.description
                isEditingName = false
            }
        }
        .background(selectedLabelID == label.id ? Color.blue.opacity(0.2) : Color.clear)
    }
    
    var detailView: some View {
        ScrollView {
            VStack {
                if let tagID = selectedTagID,
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
                    if viewMode == .tagGroups {
                        Text("Выберите тег или создайте новый")
                            .font(.headline)
                    } else if viewMode == .labelGroups {
                        Text("Выберите лейбл или создайте новый")
                            .font(.headline)
                    }
                }
                else {
                    if viewMode == .tagGroups {
                        Text("Выберите группу тегов или создайте новую")
                            .font(.headline)
                    } else if viewMode == .labelGroups {
                        Text("Выберите группу лейблов или создайте новую")
                            .font(.headline)
                    } else if viewMode == .timeEvents {
                        if collectionManager.timeEvents.isEmpty {
                            Text("Добавьте временное событие")
                                .font(.headline)
                        } else {
                            Text("Выберите временное событие для редактирования")
                                .font(.headline)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    func tagDetailView(tag: Tag) -> some View {
        Form {
            Section(header: Text("Информация о теге")) {
                FocusAwareTextField(text: $tagFormData.name, placeholder: "Название")
                
                TextEditor(text: $tagFormData.description)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.vertical, 4)
                
                ColorPickerView(selectedColor: $tagFormData.color, hexString: $tagFormData.hexColor)
                
                HStack {
                    Text("Время до:")
                    Slider(value: $tagFormData.defaultTimeBefore, in: 0...30, step: 1) {
                        Text("\(Int(tagFormData.defaultTimeBefore)) сек")
                    }
                    Text("\(Int(tagFormData.defaultTimeBefore)) сек")
                        .frame(width: 60, alignment: .trailing)
                }
                
                HStack {
                    Text("Время после:")
                    Slider(value: $tagFormData.defaultTimeAfter, in: 0...30, step: 1) {
                        Text("\(Int(tagFormData.defaultTimeAfter)) сек")
                    }
                    Text("\(Int(tagFormData.defaultTimeAfter)) сек")
                        .frame(width: 60, alignment: .trailing)
                }
                
                HStack {
                    Text("Горячая клавиша:")
                    
                    ZStack {
                        Button(action: {
                            isCapturingTagHotkey = true
                        }) {
                            HStack {
                                Text(tagFormData.hotkey ?? "Нажмите для назначения")
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
                            .frame(width: 200)
                            .padding(6)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(5)
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
                        Text("Этот хоткей уже используется")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            
            Section(header: Text("Связанные группы лейблов")) {
                VStack(spacing: 12) {
                    ForEach(collectionManager.labelGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(group.name)
                                    .font(.headline)
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
                                .labelsHidden()
                            }
                            
                            if tagFormData.selectedLabelGroups.contains(group.id) {
                                ForEach(getLabelsForGroup(groupID: group.id)) { label in
                                    HStack {
                                        Text("• \(label.name)")
                                            .padding(.leading, 10)
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
                                                    Text(tagFormData.labelHotkeys[label.id] ?? "Назначить")
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
                                                        .padding(.leading, 4)
                                                    }
                                                }
                                                .frame(width: 120)
                                                .padding(4)
                                                .background(Color.gray.opacity(0.2))
                                                .cornerRadius(4)
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
                                                .help("Этот хоткей уже используется другим лейблом")
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Button("Сохранить изменения") {
                let success = collectionManager.updateTag(
                    id: tag.id,
                    name: tagFormData.name,
                    description: tagFormData.description,
                    color: tagFormData.hexColor,
                    defaultTimeBefore: tagFormData.defaultTimeBefore,
                    defaultTimeAfter: tagFormData.defaultTimeAfter,
                    labelGroupIDs: tagFormData.selectedLabelGroups,
                    hotkey: tagFormData.hotkey,
                    labelHotkeys: tagFormData.labelHotkeys
                )
            }
            .buttonStyle(CompatibilityButtonStyle())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top)
        }
        .padding()
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
        Form {
            Section(header: Text("Информация о лейбле")) {
                FocusAwareTextField(text: $newLabelName, placeholder: "Название")
                
                TextEditor(text: $newLabelDescription)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.vertical, 4)
            }
            
            Section(header: Text("Связанные теги")) {
                List {
                    ForEach(collectionManager.tags.filter { tag in
                        tag.lablesGroup.contains { groupID in
                            if let group = collectionManager.labelGroups.first(where: { $0.id == groupID }) {
                                return group.lables.contains(label.id)
                            }
                            return false
                        }
                    }) { tag in
                        HStack {
                            Rectangle()
                                .fill(Color(hex: tag.color))
                                .frame(width: 16, height: 16)
                            
                            Text(tag.name)
                        }
                    }
                }
                .frame(height: 150)
                
                Text("Для изменения связей, выберите тег и добавьте группу лейблов к нему.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Button("Сохранить изменения") {
                if let index = collectionManager.labels.firstIndex(where: { $0.id == label.id }) {
                    collectionManager.labels[index] = Label(
                        id: label.id,
                        name: newLabelName,
                        description: newLabelDescription
                    )
                }
            }
            .buttonStyle(CompatibilityButtonStyle())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top)
        }
        .padding()
    }
    
    func timeEventDetailView(event: TimeEvent) -> some View {
        Form {
            Section(header: Text("Информация о событии")) {
                FocusAwareTextField(text: $newTimeEventName, placeholder: "Название")
            }
            
            Button("Сохранить изменения") {
                if let index = collectionManager.timeEvents.firstIndex(where: { $0.id == event.id }) {
                    collectionManager.timeEvents[index] = TimeEvent(
                        id: event.id,
                        name: newTimeEventName
                    )
                }
            }
            .buttonStyle(CompatibilityButtonStyle())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top)
            
            Button("Удалить событие") {
                collectionManager.removeTimeEvent(id: event.id)
                selectedTimeEventID = nil
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top)
        }
        .padding()
    }
    
    func addGroupSheet(title: String, onAdd: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .padding(.top)
            
            FocusAwareTextField(text: $newGroupName, placeholder: "Название группы")
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            HStack {
                Button("Отмена") {
                    if title.contains("тегов") {
                        showAddTagGroupSheet = false
                    } else {
                        showAddLabelGroupSheet = false
                    }
                }
                .keyboardShortcut(.escape)
                
                Button("Добавить") {
                    onAdd()
                    if title.contains("тегов") {
                        showAddTagGroupSheet = false
                    } else {
                        showAddLabelGroupSheet = false
                    }
                }
                .keyboardShortcut(.return)
                .disabled(newGroupName.isEmpty)
                .buttonStyle(CompatibilityButtonStyle())
            }
            .padding()
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    func addTagSheet() -> some View {
        VStack(spacing: 16) {
            Text("Добавить новый тег")
                .font(.headline)
                .padding(.top)
            
            Form {
                FocusAwareTextField(text: $tagFormData.name, placeholder: "Название")
                
                TextEditor(text: $tagFormData.description)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.vertical, 4)
                
                ColorPickerView(selectedColor: $tagFormData.color, hexString: $tagFormData.hexColor)
                
                HStack {
                    Text("Время до:")
                    Slider(value: $tagFormData.defaultTimeBefore, in: 0...30, step: 1)
                    Text("\(Int(tagFormData.defaultTimeBefore)) сек")
                        .frame(width: 60, alignment: .trailing)
                }
                
                HStack {
                    Text("Время после:")
                    Slider(value: $tagFormData.defaultTimeAfter, in: 0...30, step: 1)
                    Text("\(Int(tagFormData.defaultTimeAfter)) сек")
                        .frame(width: 60, alignment: .trailing)
                }
                
                HStack {
                    Text("Горячая клавиша:")
                    
                    ZStack {
                        Button(action: {
                            isCapturingTagHotkey = true
                        }) {
                            HStack {
                                Text(tagFormData.hotkey ?? "Нажмите для назначения")
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
                            .frame(width: 200)
                            .padding(6)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(5)
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
                        Text("Этот хоткей уже используется")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .padding()
            
            HStack {
                Button("Отмена") {
                    showAddTagSheet = false
                    tagFormData = TagFormData()
                }
                .keyboardShortcut(.escape)
                
                Button("Добавить") {
                    if let groupID = selectedTagGroupID {
                        let newTag = collectionManager.createTag(
                            name: tagFormData.name,
                            description: tagFormData.description,
                            color: tagFormData.hexColor,
                            defaultTimeBefore: tagFormData.defaultTimeBefore,
                            defaultTimeAfter: tagFormData.defaultTimeAfter,
                            inGroup: groupID,
                            hotkey: tagFormData.hotkey
                        )
                        
                        if !tagFormData.selectedLabelGroups.isEmpty {
                            collectionManager.updateTag(
                                id: newTag.id,
                                name: newTag.name,
                                description: newTag.description,
                                color: newTag.color,
                                defaultTimeBefore: newTag.defaultTimeBefore,
                                defaultTimeAfter: newTag.defaultTimeAfter,
                                labelGroupIDs: tagFormData.selectedLabelGroups,
                                hotkey: newTag.hotkey,
                                labelHotkeys: tagFormData.labelHotkeys
                            )
                        }
                        tagFormData = TagFormData()
                    }
                    showAddTagSheet = false
                }
                .keyboardShortcut(.return)
                .disabled(tagFormData.name.isEmpty || selectedTagGroupID == nil)
                .buttonStyle(CompatibilityButtonStyle())
            }
            .padding()
        }
        .frame(width: 500)
        .onAppear {
            tagFormData = TagFormData()
            isCapturingTagHotkey = false
            isCapturingLabelHotkeys = [:]
        }
    }
    
    func addLabelSheet() -> some View {
        VStack(spacing: 16) {
            Text("Добавить новый лейбл")
                .font(.headline)
                .padding(.top)
            
            Form {
                FocusAwareTextField(text: $newLabelName, placeholder: "Название")
                
                TextEditor(text: $newLabelDescription)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.vertical, 4)
            }
            .padding()
            
            HStack {
                Button("Отмена") {
                    showAddLabelSheet = false
                    newLabelName = ""
                    newLabelDescription = ""
                }
                .keyboardShortcut(.escape)
                
                Button("Добавить") {
                    if let groupID = selectedLabelGroupID {
                        collectionManager.createLabel(
                            name: newLabelName,
                            description: newLabelDescription,
                            inGroup: groupID
                        )
                        newLabelName = ""
                        newLabelDescription = ""
                    }
                    showAddLabelSheet = false
                }
                .keyboardShortcut(.return)
                .disabled(newLabelName.isEmpty || selectedLabelGroupID == nil)
                .buttonStyle(CompatibilityButtonStyle())
            }
            .padding()
        }
        .frame(width: 500)
    }
    
    func addTimeEventSheet() -> some View {
        VStack(spacing: 16) {
            Text("Добавить новое временное событие")
                .font(.headline)
                .padding(.top)
            
            Form {
                FocusAwareTextField(text: $newTimeEventName, placeholder: "Название")
            }
            .padding()
            
            HStack {
                Button("Отмена") {
                    showAddTimeEventSheet = false
                    newTimeEventName = ""
                }
                .keyboardShortcut(.escape)
                
                Button("Добавить") {
                    collectionManager.createTimeEvent(name: newTimeEventName)
                    newTimeEventName = ""
                    showAddTimeEventSheet = false
                }
                .keyboardShortcut(.return)
                .disabled(newTimeEventName.isEmpty)
                .buttonStyle(CompatibilityButtonStyle())
            }
            .padding()
        }
        .frame(width: 500)
    }
}

extension UserDefaults {
    private enum Keys {
        static let collections = "savedCollections"
    }
    
    func saveCollectionBookmark(_ bookmark: CollectionBookmark) {
        var collections = getCollectionBookmarks()
        if let index = collections.firstIndex(where: { $0.name == bookmark.name }) {
            collections[index] = bookmark
        } else {
            collections.append(bookmark)
        }
        
        if let encoded = try? JSONEncoder().encode(collections) {
            set(encoded, forKey: Keys.collections)
        }
    }
    
    func getCollectionBookmarks() -> [CollectionBookmark] {
        guard let data = data(forKey: Keys.collections),
              let collections = try? JSONDecoder().decode([CollectionBookmark].self, from: data) else {
            return []
        }
        return collections
    }
    
    func removeCollectionBookmark(named name: String) {
        var collections = getCollectionBookmarks()
        collections.removeAll { $0.name == name }
        
        if let encoded = try? JSONEncoder().encode(collections) {
            set(encoded, forKey: Keys.collections)
        }
    }
}
