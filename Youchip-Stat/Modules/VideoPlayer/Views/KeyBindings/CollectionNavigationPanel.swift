//
//  CollectionNavigationPanel.swift
//  Youchip-Stat
//
//  Left navigation panel for key-bindings collection editor.
//

import SwiftUI

enum CollectionNavigationTab: String, CaseIterable, Identifiable {
    case tags
    case labels
    case events
    case map
    case clocks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tags: return ^String.Titles.tags
        case .labels: return ^String.Titles.labels
        case .events: return ^String.Titles.commonEvents
        case .map: return ^String.Titles.fieldMap
        case .clocks: return ^String.Titles.clockCountersTitle
        }
    }

    var icon: String {
        switch self {
        case .tags: return "tag.fill"
        case .labels: return "textformat"
        case .events: return "clock.fill"
        case .map: return "map.fill"
        case .clocks: return "stopwatch.fill"
        }
    }
}

struct CollectionNavigationPanel: View {

    @ObservedObject var collectionManager: CustomCollectionManager
    @Binding var layout: TagFreeLayout
    @Binding var selectedTab: CollectionNavigationTab
    @Binding var isEditingCollectionName: Bool
    var onCollapse: () -> Void

    @State private var expandedTagGroups: Set<String> = []
    @State private var expandedLabelGroups: Set<String> = []
    @State private var showCreateTagGroupSheet = false
    @State private var showCreateLabelGroupSheet = false
    @State private var newGroupName = ""
    @State private var tagToCreateInGroupID: String?
    @State private var tagToEdit: Tag?
    @State private var tagPendingDelete: Tag?
    @State private var labelPendingDelete: Label?
    @State private var editingLabelID: String?
    @State private var editingLabelName = ""
    @State private var capturingHotkeyTagID: String?
    @State private var showAddTimeEventSheet = false
    @State private var selectedTimeEventID: String?
    @State private var newTimeEventName = ""
    @State private var timeEventPendingDelete: TimeEvent?
    @State private var showLabelHotkeyConflictAlert = false
    /// Множественный выбор групп для дублирования в другую коллекцию.
    @State private var selectedTagGroupIDs: Set<String> = []
    @State private var selectedLabelGroupIDs: Set<String> = []
    /// Inline-редактирование имени прямо в левом столбце (как у лейблов) — вместо модальных окон.
    @State private var editingGroupID: String?
    @State private var editingGroupNameText = ""
    @State private var editingEventID: String?
    @State private var editingEventNameText = ""
    @State private var tagGroupPendingDelete: TagGroup?
    @State private var labelGroupPendingDelete: LabelGroupData?

    var body: some View {
        contentWithHotkeyAlert
    }

    // MARK: - Множественный выбор групп / дублирование в другую коллекцию

    private var duplicationTargets: [CollectionInfo] {
        CollectionsBookmarksManager.shared.loadCollections()
            .filter { $0.id != collectionManager.collectionID }
    }

    private var tagGroupSelectionChips: [GroupDuplicationBar.Chip] {
        collectionManager.tagGroups
            .filter { selectedTagGroupIDs.contains($0.id) }
            .map { GroupDuplicationBar.Chip(id: $0.id, name: $0.name) }
    }

    private var labelGroupSelectionChips: [GroupDuplicationBar.Chip] {
        collectionManager.labelGroups
            .filter { selectedLabelGroupIDs.contains($0.id) }
            .map { GroupDuplicationBar.Chip(id: $0.id, name: $0.name) }
    }

    private func toggleTagGroupSelection(_ id: String) {
        if selectedTagGroupIDs.contains(id) { selectedTagGroupIDs.remove(id) }
        else { selectedTagGroupIDs.insert(id) }
    }

    private func toggleLabelGroupSelection(_ id: String) {
        if selectedLabelGroupIDs.contains(id) { selectedLabelGroupIDs.remove(id) }
        else { selectedLabelGroupIDs.insert(id) }
    }

    private func tagsForGroup(_ groupID: String) -> [Tag] {
        guard let group = collectionManager.tagGroups.first(where: { $0.id == groupID }) else { return [] }
        let byID = Dictionary(collectionManager.tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return group.tags.compactMap { byID[$0] }
    }

    private func labelsForGroup(_ groupID: String) -> [Label] {
        guard let group = collectionManager.labelGroups.first(where: { $0.id == groupID }) else { return [] }
        let byID = Dictionary(collectionManager.labels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return group.lables.compactMap { byID[$0] }
    }

    private func duplicateSelectedTagGroups(to targetID: String) {
        let payloads = collectionManager.tagGroups
            .filter { selectedTagGroupIDs.contains($0.id) }
            .map { GroupDuplicationService.TagGroupPayload(group: $0, tags: tagsForGroup($0.id)) }
        guard !payloads.isEmpty else { return }
        GroupDuplicationService.duplicate(tagGroups: payloads, labelGroups: [], intoCollectionID: targetID)
        selectedTagGroupIDs.removeAll()
    }

    private func duplicateSelectedLabelGroups(to targetID: String) {
        let payloads = collectionManager.labelGroups
            .filter { selectedLabelGroupIDs.contains($0.id) }
            .map { GroupDuplicationService.LabelGroupPayload(group: $0, labels: labelsForGroup($0.id)) }
        guard !payloads.isEmpty else { return }
        GroupDuplicationService.duplicate(tagGroups: [], labelGroups: payloads, intoCollectionID: targetID)
        selectedLabelGroupIDs.removeAll()
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            tabBar
            Divider()

            ScrollView {
                tabContent
                    .padding(12)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var contentWithLifecycle: some View {
        mainContent
            .onAppear { seedExpandedGroups() }
            .onChange(of: collectionManager.tagGroups.count) { _ in seedExpandedTagGroups() }
            .onChange(of: collectionManager.labelGroups.count) { _ in seedExpandedLabelGroups() }
    }

    private var contentWithSheets: some View {
        contentWithLifecycle
            .sheet(isPresented: showTagCreateSheetBinding) {
                if let groupID = tagToCreateInGroupID {
                    TagCreateSheetView(
                        collectionManager: collectionManager,
                        groupID: groupID,
                        onDismiss: { tagToCreateInGroupID = nil }
                    )
                }
            }
            .sheet(item: $tagToEdit) { tag in
                TagEditSheetView(
                    collectionManager: collectionManager,
                    tag: tag,
                    onDismiss: { tagToEdit = nil }
                )
            }
            // Группы тегов/лейблов и события создаются inline в левом столбце (как лейблы),
            // модальные окна убраны.
    }

    private var contentWithDeleteAlerts: some View {
        contentWithSheets
            .alert(^String.Titles.keyBindingsDeleteTagTitle, isPresented: showTagDeleteAlertBinding) {
                Button(^String.Titles.deleteButtonTitle, role: .destructive) {
                    if let tag = tagPendingDelete {
                        collectionManager.deleteTag(id: tag.id)
                        tagPendingDelete = nil
                    }
                }
                Button(^String.Titles.collectionsButtonCancel, role: .cancel) {
                    tagPendingDelete = nil
                }
            } message: {
                Text(^String.Titles.keyBindingsDeleteTagMessage)
            }
            .alert(^String.Titles.keyBindingsDeleteLabelTitle, isPresented: showLabelDeleteAlertBinding) {
                Button(^String.Titles.deleteButtonTitle, role: .destructive) {
                    if let label = labelPendingDelete {
                        collectionManager.deleteLabel(id: label.id)
                        labelPendingDelete = nil
                    }
                }
                Button(^String.Titles.collectionsButtonCancel, role: .cancel) {
                    labelPendingDelete = nil
                }
            } message: {
                Text(^String.Titles.keyBindingsDeleteLabelMessage)
            }
            .alert(^String.Titles.keyBindingsDeleteEventTitle, isPresented: showEventDeleteAlertBinding) {
                Button(^String.Titles.deleteButtonTitle, role: .destructive) {
                    if let event = timeEventPendingDelete {
                        collectionManager.removeTimeEvent(id: event.id)
                        if selectedTimeEventID == event.id { selectedTimeEventID = nil }
                        timeEventPendingDelete = nil
                    }
                }
                Button(^String.Titles.collectionsButtonCancel, role: .cancel) {
                    timeEventPendingDelete = nil
                }
            } message: {
                Text(^String.Titles.keyBindingsDeleteEventMessage)
            }
            .alert(^String.Titles.deleteButtonTitle, isPresented: showTagGroupDeleteAlertBinding) {
                Button(^String.Titles.deleteButtonTitle, role: .destructive) {
                    if let group = tagGroupPendingDelete {
                        collectionManager.deleteTagGroup(id: group.id)
                        tagGroupPendingDelete = nil
                    }
                }
                Button(^String.Titles.collectionsButtonCancel, role: .cancel) {
                    tagGroupPendingDelete = nil
                }
            } message: {
                Text(^String.Titles.alertsAreYouSure)
            }
            .alert(^String.Titles.deleteButtonTitle, isPresented: showLabelGroupDeleteAlertBinding) {
                Button(^String.Titles.deleteButtonTitle, role: .destructive) {
                    if let group = labelGroupPendingDelete {
                        collectionManager.deleteLabelGroup(id: group.id)
                        labelGroupPendingDelete = nil
                    }
                }
                Button(^String.Titles.collectionsButtonCancel, role: .cancel) {
                    labelGroupPendingDelete = nil
                }
            } message: {
                Text(^String.Titles.alertsAreYouSure)
            }
    }

    private var showTagGroupDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { tagGroupPendingDelete != nil },
            set: { if !$0 { tagGroupPendingDelete = nil } }
        )
    }

    private var showLabelGroupDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { labelGroupPendingDelete != nil },
            set: { if !$0 { labelGroupPendingDelete = nil } }
        )
    }

    private var contentWithHotkeyAlert: some View {
        contentWithDeleteAlerts
            .alert(^String.Titles.hotkeyAlreadyUsed, isPresented: $showLabelHotkeyConflictAlert) {
                Button(^String.Titles.alertsOkTitle, role: .cancel) {}
            } message: {
                Text(^String.Titles.collectionsLabelHotkeyUsed)
            }
    }

    private var showTagCreateSheetBinding: Binding<Bool> {
        Binding(
            get: { tagToCreateInGroupID != nil },
            set: { if !$0 { tagToCreateInGroupID = nil } }
        )
    }

    private var showTagDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { tagPendingDelete != nil },
            set: { if !$0 { tagPendingDelete = nil } }
        )
    }

    private var showLabelDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { labelPendingDelete != nil },
            set: { if !$0 { labelPendingDelete = nil } }
        )
    }

    private var showEventDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { timeEventPendingDelete != nil },
            set: { if !$0 { timeEventPendingDelete = nil } }
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 8) {
            if isEditingCollectionName || !collectionManager.isEditingExisting {
                AutoFocusTextField(
                    text: $collectionManager.collectionName,
                    placeholder: ^String.Titles.collectionName,
                    onSubmit: { isEditingCollectionName = false }
                )
                .textFieldStyle(.roundedBorder)
            } else {
                Text(collectionManager.collectionName)
                    .font(.headline)
                    .lineLimit(1)

                Button(action: { isEditingCollectionName = true }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(action: onCollapse) {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .help(^String.Titles.keyBindingsHideNavigation)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(CollectionNavigationTab.allCases) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.caption)
                        Text(tab.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    // Кликабельна вся зона кнопки, а не только текст/иконка (прозрачный фон иначе не ловит тап).
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .tags: tagsTabContent
        case .labels: labelsTabContent
        case .events: eventsTabContent
        case .map: mapTabContent
        case .clocks: clocksTabContent
        }
    }

    // MARK: - Clocks tab (секундомеры / таймеры)

    private var clocksTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Button(action: { addClock(mode: .stopwatch) }) {
                    SwiftUI.Label(^String.Titles.clockAddStopwatch, systemImage: "stopwatch")
                }
                .buttonStyle(.plain).foregroundColor(.blue)
                Button(action: { addClock(mode: .timer) }) {
                    SwiftUI.Label(^String.Titles.clockAddTimer, systemImage: "timer")
                }
                .buttonStyle(.plain).foregroundColor(.blue)
            }
            .font(.subheadline)

            Text(^String.Titles.clockTabHint)
                .font(.caption).foregroundColor(.secondary)

            if collectionManager.clocks.isEmpty {
                Text(^String.Titles.clockNoCounters).font(.caption).foregroundColor(.secondary)
            }

            ForEach(collectionManager.clocks) { clock in
                HStack(spacing: 8) {
                    Image(systemName: clock.mode == .timer ? "timer" : "stopwatch")
                        .foregroundColor(.secondary)
                    Text(clock.name).font(.subheadline).lineLimit(1)
                    Spacer()
                    Button(action: { TagFreeLayoutStorage.addClockToLayout(&layout, clock: clock) }) {
                        Image(systemName: "plus.rectangle.on.rectangle")
                    }
                    .buttonStyle(.plain).foregroundColor(.blue)
                    .help(^String.Titles.clockAddToCanvas)
                    Button(action: { deleteClock(clock) }) {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 4)
    }

    /// Удаление счётчика убирает и его объект с холста вместе со связками. Иначе на холсте
    /// оставался «призрак»: сущности нет, а кнопка рисуется рамкой, выделяется и таскается.
    private func deleteClock(_ clock: ClockEntity) {
        let itemKey = "\(CanvasButtonKind.clock.rawValue):\(clock.id)"
        layout.items.removeAll { $0.kind == .clock && $0.elementId == clock.id }
        layout.bindings.removeAll { $0.sourceButtonKey == itemKey || $0.targetButtonKey == itemKey }

        collectionManager.removeClock(id: clock.id)
        _ = collectionManager.saveCollectionToFiles()
        TagFreeLayoutStorage.saveLayout(layout, collectionId: collectionManager.collectionID)
        ClockRuntimeManager.shared.register(collectionManager.clocks)
    }

    private func addClock(mode: ClockMode) {
        let name = mode == .timer ? ^String.Titles.clockModeTimer : ^String.Titles.clockModeStopwatch
        let clock = collectionManager.createClock(name: name, mode: mode)
        _ = collectionManager.saveCollectionToFiles()
        ClockRuntimeManager.shared.register(collectionManager.clocks)
        TagFreeLayoutStorage.addClockToLayout(&layout, clock: clock)
    }

    // MARK: - Tags tab

    private var tagsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { addInlineTagGroup() }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(^String.Titles.keyBindingsCreateGroup)
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)

            if !selectedTagGroupIDs.isEmpty {
                GroupDuplicationBar(
                    chips: tagGroupSelectionChips,
                    targets: duplicationTargets,
                    accent: .blue,
                    onRemoveChip: { selectedTagGroupIDs.remove($0) },
                    onClear: { selectedTagGroupIDs.removeAll() },
                    onDuplicate: { duplicateSelectedTagGroups(to: $0) }
                )
            }

            if collectionManager.tagGroups.isEmpty {
                Text(^String.Titles.keyBindingsNoTagGroups)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(collectionManager.tagGroups) { group in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedTagGroups.contains(group.id) },
                        set: { expanded in
                            if expanded { expandedTagGroups.insert(group.id) }
                            else { expandedTagGroups.remove(group.id) }
                        }
                    ),
                    content: {
                        VStack(spacing: 8) {
                            Button(action: { tagToCreateInGroupID = group.id }) {
                                HStack {
                                    Image(systemName: "plus")
                                    Text(^String.Titles.keyBindingsAddTag)
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)

                            ForEach(tagsInGroup(group)) { tag in
                                tagCard(tag)
                            }
                        }
                        .padding(.top, 8)
                    },
                    label: {
                        groupSelectableLabel(
                            groupID: group.id,
                            name: group.name,
                            isSelected: selectedTagGroupIDs.contains(group.id),
                            accent: .blue,
                            onRename: { collectionManager.renameTagGroup(id: group.id, newName: $0) },
                            onDelete: { tagGroupPendingDelete = group },
                            toggle: { toggleTagGroupSelection(group.id) }
                        )
                    }
                )
            }
        }
    }

    /// Заголовок группы с чекбоксом множественного выбора (для дублирования в другую коллекцию).
    private func groupSelectableLabel(groupID: String, name: String, isSelected: Bool, accent: Color, onRename: @escaping (String) -> Void, onDelete: @escaping () -> Void, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundColor(isSelected ? accent : .secondary)
            }
            .buttonStyle(.plain)
            .help(^String.Titles.collectionMultiSelectHint)

            if editingGroupID == groupID {
                // Inline-ввод имени прямо в списке (как у лейблов). Enter — сохранить.
                AutoFocusTextField(
                    text: $editingGroupNameText,
                    placeholder: ^String.Titles.groupNameLabel,
                    onSubmit: {
                        onRename(editingGroupNameText.trimmingCharacters(in: .whitespacesAndNewlines))
                        editingGroupID = nil
                    }
                )
                .textFieldStyle(.roundedBorder)
            } else {
                Text(name.isEmpty ? ^String.Titles.groupNameLabel : name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isSelected ? accent : .primary)
                    .onTapGesture(count: 2) {
                        editingGroupID = groupID
                        editingGroupNameText = name
                    }
            }

            Spacer(minLength: 4)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help(^String.Titles.deleteButtonTitle)
        }
    }

    private func tagCard(_ tag: Tag) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: tag.color))
                .frame(width: 10, height: 10)

            Text(tag.name)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            Button(action: { tagToEdit = tag }) {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            hotkeyField(for: tag)

            Button(action: { tagPendingDelete = tag }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
        )
        .contextMenu {
            if !isOnCanvas(elementId: tag.id, kind: .tag) {
                Button {
                    TagFreeLayoutStorage.addTagToLayout(&layout, tag: tag)
                } label: {
                    SwiftUI.Label(^String.Titles.keyBindingsReturnToCanvas, systemImage: "plus.rectangle.on.rectangle")
                }
            }
        }
    }

    /// Элемент сейчас размещён на холсте раскладки.
    private func isOnCanvas(elementId: String, kind: CanvasButtonKind) -> Bool {
        layout.items.contains { $0.elementId == elementId && $0.kind == kind }
    }

    private func hotkeyField(for tag: Tag) -> some View {
        HStack(spacing: 4) {
            ZStack {
                Button(action: {
                    capturingHotkeyTagID = tag.id
                }) {
                    Text(tag.hotkey ?? ^String.Titles.assign)
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                        )
                }
                .buttonStyle(.plain)
                .disabled(capturingHotkeyTagID == tag.id)

                if capturingHotkeyTagID == tag.id {
                    KeyCaptureView(
                        keyString: Binding(
                            get: { tag.hotkey },
                            set: { newValue in
                                applyTagHotkey(tag: tag, hotkey: newValue)
                                capturingHotkeyTagID = nil
                            }
                        ),
                        isCapturing: Binding(
                            get: { capturingHotkeyTagID == tag.id },
                            set: { if !$0 { capturingHotkeyTagID = nil } }
                        )
                    )
                    .allowsHitTesting(false)
                }
            }

            // Сброс хоткея — виден только когда он задан и мы не в режиме захвата.
            if let hk = tag.hotkey, !hk.isEmpty, capturingHotkeyTagID != tag.id {
                Button(action: { applyTagHotkey(tag: tag, hotkey: nil) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(^String.Titles.reset)
            }
        }
    }

    private func applyTagHotkey(tag: Tag, hotkey: String?) {
        let trimmed = hotkey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty == false) ? trimmed : nil
        if let value, collectionManager.isHotkeyAssigned(value, excludingTagID: tag.id) {
            showLabelHotkeyConflictAlert = true
            return
        }
        _ = collectionManager.updateTag(
            id: tag.id,
            primaryID: tag.primaryID,
            name: tag.name,
            description: tag.description,
            color: tag.color,
            defaultTimeBefore: tag.defaultTimeBefore,
            defaultTimeAfter: tag.defaultTimeAfter,
            labelGroupIDs: tag.lablesGroup,
            hotkey: value,
            labelHotkeys: tag.labelHotkeys ?? [:],
            isInterval: tag.isInterval ?? false,
            mapEnabled: tag.mapEnabled ?? false
        )
    }

    // MARK: - Labels tab

    private var labelsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { addInlineLabelGroup() }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(^String.Titles.keyBindingsCreateGroup)
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundColor(.green)

            if !selectedLabelGroupIDs.isEmpty {
                GroupDuplicationBar(
                    chips: labelGroupSelectionChips,
                    targets: duplicationTargets,
                    accent: .green,
                    onRemoveChip: { selectedLabelGroupIDs.remove($0) },
                    onClear: { selectedLabelGroupIDs.removeAll() },
                    onDuplicate: { duplicateSelectedLabelGroups(to: $0) }
                )
            }

            ForEach(collectionManager.labelGroups) { group in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedLabelGroups.contains(group.id) },
                        set: { expanded in
                            if expanded { expandedLabelGroups.insert(group.id) }
                            else { expandedLabelGroups.remove(group.id) }
                        }
                    ),
                    content: {
                        VStack(spacing: 8) {
                            Button(action: { addInlineLabel(to: group.id) }) {
                                HStack {
                                    Image(systemName: "plus")
                                    Text(^String.Titles.keyBindingsAddLabel)
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.green)

                            ForEach(labelsInGroup(group)) { label in
                                labelCard(label)
                            }
                        }
                        .padding(.top, 8)
                    },
                    label: {
                        groupSelectableLabel(
                            groupID: group.id,
                            name: group.name,
                            isSelected: selectedLabelGroupIDs.contains(group.id),
                            accent: .green,
                            onRename: { collectionManager.renameLabelGroup(id: group.id, newName: $0) },
                            onDelete: { labelGroupPendingDelete = group },
                            toggle: { toggleLabelGroupSelection(group.id) }
                        )
                    }
                )
            }
        }
    }

    private func labelCard(_ label: Label) -> some View {
        HStack(spacing: 8) {
            if editingLabelID == label.id {
                AutoFocusTextField(
                    text: $editingLabelName,
                    placeholder: ^String.Titles.title,
                    onSubmit: {
                        collectionManager.updateLabel(id: label.id, name: editingLabelName, description: label.description)
                        editingLabelID = nil
                    }
                )
                .textFieldStyle(.roundedBorder)
            } else {
                Text(label.name.isEmpty ? ^String.Titles.title : label.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .onTapGesture {
                        editingLabelID = label.id
                        editingLabelName = label.name
                    }
            }

            Spacer()

            Button(action: { labelPendingDelete = label }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
        )
        .contextMenu {
            if !isOnCanvas(elementId: label.id, kind: .label) {
                Button {
                    TagFreeLayoutStorage.addLabelToLayout(&layout, label: label)
                } label: {
                    SwiftUI.Label(^String.Titles.keyBindingsReturnToCanvas, systemImage: "plus.rectangle.on.rectangle")
                }
            }
        }
    }

    private func addInlineLabel(to groupID: String) {
        let label = collectionManager.createLabel(name: "", description: "", inGroup: groupID)
        TagFreeLayoutStorage.addLabelToLayout(&layout, label: label)
        editingLabelID = label.id
        editingLabelName = ""
    }

    /// Создаёт группу/событие СРАЗУ с пустым именем и открывает inline-поле для ввода имени
    /// прямо в левом столбце (как при создании лейбла), вместо модального окна.
    private func addInlineTagGroup() {
        let group = collectionManager.createTagGroup(name: "")
        expandedTagGroups.insert(group.id)
        editingGroupID = group.id
        editingGroupNameText = ""
    }

    private func addInlineLabelGroup() {
        let group = collectionManager.createLabelGroup(name: "")
        expandedLabelGroups.insert(group.id)
        editingGroupID = group.id
        editingGroupNameText = ""
    }

    private func addInlineTimeEvent() {
        let event = collectionManager.createTimeEvent(name: "")
        editingEventID = event.id
        editingEventNameText = ""
    }

    // MARK: - Events tab

    private var eventsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { addInlineTimeEvent() }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(^String.Titles.collectionsDialogAddTimeEvent)
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundColor(.orange)

            if collectionManager.timeEvents.isEmpty {
                Text(^String.Titles.collectionsEventEmpty)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(collectionManager.timeEvents) { event in
                timeEventRow(event)
            }

            if let selectedID = selectedTimeEventID,
               let event = collectionManager.timeEvents.first(where: { $0.id == selectedID }) {
                Divider().padding(.vertical, 8)
                timeEventEditor(event)
            }
        }
    }

    private func timeEventRow(_ event: TimeEvent) -> some View {
        HStack {
            Image(systemName: "clock")
                .foregroundColor(.orange)
            if editingEventID == event.id {
                // Inline-ввод имени прямо в строке (как у лейблов). Enter — сохранить.
                AutoFocusTextField(
                    text: $editingEventNameText,
                    placeholder: ^String.Titles.eventName,
                    onSubmit: {
                        collectionManager.renameTimeEvent(id: event.id, newName: editingEventNameText.trimmingCharacters(in: .whitespacesAndNewlines))
                        editingEventID = nil
                    }
                )
                .textFieldStyle(.roundedBorder)
            } else {
                Text(event.name.isEmpty ? ^String.Titles.eventName : event.name)
                    .font(.subheadline)
                    .onTapGesture(count: 2) {
                        editingEventID = event.id
                        editingEventNameText = event.name
                    }
            }
            Spacer()
            Button(action: { editingEventID = event.id; editingEventNameText = event.name }) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            Button(action: { timeEventPendingDelete = event }) {
                Image(systemName: "xmark")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .contextMenu {
            if !isOnCanvas(elementId: event.id, kind: .timeEvent) {
                Button {
                    TagFreeLayoutStorage.addTimeEventToLayout(&layout, event: event)
                } label: {
                    SwiftUI.Label(^String.Titles.keyBindingsReturnToCanvas, systemImage: "plus.rectangle.on.rectangle")
                }
            }
        }
    }

    private func timeEventEditor(_ event: TimeEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(^String.Titles.eventInfo)
                .font(.headline)
            FocusAwareTextField(text: $newTimeEventName, placeholder: ^String.Titles.eventName)
                .textFieldStyle(.roundedBorder)
            Button(^String.Titles.collectionsButtonSaveChanges) {
                collectionManager.renameTimeEvent(id: event.id, newName: newTimeEventName)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var addTimeEventSheet: some View {
        VStack(spacing: 16) {
            Text(^String.Titles.collectionsDialogAddTimeEvent)
                .font(.headline)
            FocusAwareTextField(text: $newTimeEventName, placeholder: ^String.Titles.eventName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(^String.Titles.collectionsButtonCancel) {
                    showAddTimeEventSheet = false
                    newTimeEventName = ""
                }
                Spacer()
                Button(^String.Titles.collectionsButtonAdd) {
                    let name = newTimeEventName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        // Сразу кладём новое событие на холст (как это делают лейблы),
                        // иначе оно есть в списке, но не появляется на канвасе.
                        let event = collectionManager.createTimeEvent(name: name)
                        TagFreeLayoutStorage.addTimeEventToLayout(&layout, event: event)
                    }
                    showAddTimeEventSheet = false
                    newTimeEventName = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newTimeEventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Map tab (summary in nav; full editor in center)

    private var mapTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(^String.Titles.fieldMapSettings)
                .font(.headline)

            if collectionManager.playField != nil {
                SwiftUI.Label(^String.Titles.fieldMap, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
            } else {
                SwiftUI.Label(^String.Titles.fieldMapNotSet, systemImage: "exclamationmark.circle")
                    .foregroundColor(.orange)
                    .font(.subheadline)
            }

            Text(^String.Titles.keyBindingsMapTabHint)
                .font(.caption)
                .foregroundColor(.secondary)

            let enabled = collectionManager.tags.filter { $0.mapEnabled ?? false }.count
            Text(String.Titles.collectionsTagsCount.format(enabled, collectionManager.tags.count))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func seedExpandedGroups() {
        seedExpandedTagGroups()
        seedExpandedLabelGroups()
    }

    private func seedExpandedTagGroups() {
        for group in collectionManager.tagGroups {
            expandedTagGroups.insert(group.id)
        }
    }

    private func seedExpandedLabelGroups() {
        for group in collectionManager.labelGroups {
            expandedLabelGroups.insert(group.id)
        }
    }

    private func tagsInGroup(_ group: TagGroup) -> [Tag] {
        collectionManager.tags.filter { group.tags.contains($0.id) }
    }

    private func labelsInGroup(_ group: LabelGroupData) -> [Label] {
        collectionManager.labels.filter { group.lables.contains($0.id) }
    }

    private func createGroupSheet(title: String, onCreate: @escaping (String) -> Void) -> some View {
        VStack(spacing: 16) {
            Text(title).font(.headline)
            FocusAwareTextField(text: $newGroupName, placeholder: ^String.Titles.groupNameLabel)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(^String.Titles.collectionsButtonCancel) {
                    newGroupName = ""
                    showCreateTagGroupSheet = false
                    showCreateLabelGroupSheet = false
                }
                Spacer()
                Button(^String.Titles.collectionsButtonAdd) {
                    let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { onCreate(name) }
                    newGroupName = ""
                    showCreateTagGroupSheet = false
                    showCreateLabelGroupSheet = false
                }
                .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { newGroupName = "" }
    }
}