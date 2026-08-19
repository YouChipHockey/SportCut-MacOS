//
//  CollectionTagEditorSheets.swift
//  Youchip-Stat
//
//  Tag create/edit sheets reused by key-bindings collection editor.
//

import SwiftUI

struct TagCreateSheetView: View {

    @ObservedObject var collectionManager: CustomCollectionManager
    let groupID: String
    var onDismiss: () -> Void

    @State private var formData = TagFormData()
    @State private var isCapturingHotkey = false
    @State private var showHotkeyConflict = false

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    nameField
                    descriptionField
                    colorField
                    timeSliders
                    intervalToggle
                    hotkeySection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 620)
        .onAppear {
            formData = TagFormData()
            isCapturingHotkey = false
        }
        .alert(^String.Titles.hotkeyAlreadyUsed, isPresented: $showHotkeyConflict) {
            Button(^String.Titles.alertsOkTitle, role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "tag.fill").foregroundColor(.blue)
            Text(^String.Titles.addNewTag).font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(20)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(^String.Titles.name).font(.caption).foregroundColor(.secondary)
            FocusAwareTextField(
                text: $formData.name,
                placeholder: ^String.Titles.title,
                autoFocus: true,
                onSubmit: { saveTag() }
            )
            .textFieldStyle(ModernNewTextFieldStyle())
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(^String.Titles.description).font(.caption).foregroundColor(.secondary)
            TextEditor(text: $formData.description)
                .frame(minHeight: 72)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        }
    }

    private var colorField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(^String.Titles.color).font(.caption).foregroundColor(.secondary)
            ColorPickerView(selectedColor: $formData.color, hexString: $formData.hexColor)
        }
    }

    private var timeSliders: some View {
        VStack(spacing: 16) {
            sliderRow(title: ^String.Titles.collectionsTagTimeBefore, value: $formData.defaultTimeBefore)
            sliderRow(title: ^String.Titles.collectionsTagTimeAfter, value: $formData.defaultTimeAfter)
        }
    }

    private func sliderRow(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(^String.Titles.collectionsTagTimeFormat)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Slider(value: value, in: 0...30, step: 1)
        }
    }

    private var intervalToggle: some View {
        Toggle(^String.Titles.collectionsTagIsInterval, isOn: $formData.isInterval)
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(^String.Titles.hotkeys).font(.caption).foregroundColor(.secondary)
            HStack(spacing: 8) {
                ZStack {
                    Button(action: { isCapturingHotkey = true }) {
                        HStack {
                            Image(systemName: "keyboard")
                            Text(formData.hotkey ?? ^String.Titles.assign)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    if isCapturingHotkey {
                        KeyCaptureView(keyString: $formData.hotkey, isCapturing: $isCapturingHotkey)
                            .allowsHitTesting(false)
                    }
                }
                if let hk = formData.hotkey, !hk.isEmpty, !isCapturingHotkey {
                    Button(action: { formData.hotkey = nil }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(^String.Titles.reset)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(^String.Titles.collectionsButtonCancel) {
                onDismiss()
                presentationMode.wrappedValue.dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Spacer()
            Button(^String.Titles.collectionsButtonAdd) {
                saveTag()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(formData.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private func saveTag() {
        if let hotkey = formData.hotkey, !hotkey.isEmpty,
           collectionManager.isHotkeyAssigned(hotkey) {
            showHotkeyConflict = true
            return
        }
        _ = collectionManager.createTag(
            name: formData.name,
            description: formData.description,
            color: formData.hexColor,
            defaultTimeBefore: formData.defaultTimeBefore,
            defaultTimeAfter: formData.defaultTimeAfter,
            inGroup: groupID,
            hotkey: formData.hotkey,
            isInterval: formData.isInterval
        )
        onDismiss()
        presentationMode.wrappedValue.dismiss()
    }
}

struct TagEditSheetView: View {

    @ObservedObject var collectionManager: CustomCollectionManager
    let tag: Tag
    var onDismiss: () -> Void

    @State private var formData: TagFormData
    @State private var isCapturingHotkey = false
    @State private var isCapturingLabelHotkeys: [String: Bool] = [:]
    @State private var showHotkeyConflict = false
    /// Primary Counter тега — счётчик, чья запись всегда выводится на видео для момента тега.
    @State private var primaryClockId: String?

    @Environment(\.presentationMode) private var presentationMode

    init(collectionManager: CustomCollectionManager, tag: Tag, onDismiss: @escaping () -> Void) {
        self.collectionManager = collectionManager
        self.tag = tag
        self.onDismiss = onDismiss
        _formData = State(initialValue: TagFormData(from: tag))
        _primaryClockId = State(initialValue: tag.primaryClockId)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(Color(hex: tag.color)).frame(width: 20, height: 20)
                Text(^String.Titles.tagInfo).font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(20)
            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    TagCreateSheetView.NameDescriptionColorSection(formData: $formData)
                    timeSliders
                    mapToggle
                    intervalToggle
                    hotkeySection
                    primaryCounterSection
                    if !collectionManager.isKeyBindingsMode {
                        labelGroupsSection
                    }
                }
                .padding(24)
            }

            Divider()
            HStack {
                Button(^String.Titles.collectionsButtonCancel) {
                    onDismiss()
                    presentationMode.wrappedValue.dismiss()
                }
                Spacer()
                Button(^String.Titles.collectionsButtonSaveChanges) { saveChanges() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 600, height: 700)
        .alert(^String.Titles.hotkeyAlreadyUsed, isPresented: $showHotkeyConflict) {
            Button(^String.Titles.alertsOkTitle, role: .cancel) {}
        } message: {
            Text(^String.Titles.collectionsLabelHotkeyUsed)
        }
    }

    private var timeSliders: some View {
        VStack(spacing: 16) {
            sliderRow(^String.Titles.collectionsTagTimeBefore, $formData.defaultTimeBefore)
            sliderRow(^String.Titles.collectionsTagTimeAfter, $formData.defaultTimeAfter)
        }
    }

    private func sliderRow(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text("\(Int(value.wrappedValue))s").font(.caption).foregroundColor(.secondary)
            }
            Slider(value: value, in: 0...30, step: 1)
        }
    }

    private var mapToggle: some View {
        Toggle(isOn: $formData.mapEnabled) {
            Text(^String.Titles.collectionsTagUseWithMap)
        }
        .disabled(collectionManager.playField == nil)
    }

    private var intervalToggle: some View {
        Toggle(^String.Titles.collectionsTagIsInterval, isOn: $formData.isInterval)
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(^String.Titles.hotkeys).font(.caption).foregroundColor(.secondary)
            HStack(spacing: 8) {
                ZStack {
                    Button(action: { isCapturingHotkey = true }) {
                        HStack {
                            Image(systemName: "keyboard")
                            Text(formData.hotkey ?? ^String.Titles.assign)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    if isCapturingHotkey {
                        KeyCaptureView(keyString: $formData.hotkey, isCapturing: $isCapturingHotkey)
                            .allowsHitTesting(false)
                    }
                }
                if let hk = formData.hotkey, !hk.isEmpty, !isCapturingHotkey {
                    Button(action: { formData.hotkey = nil }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(^String.Titles.reset)
                }
            }
        }
    }

    private var labelGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(^String.Titles.labelGroups).font(.headline)
            ForEach(collectionManager.labelGroups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(group.name, isOn: Binding(
                        get: { formData.selectedLabelGroups.contains(group.id) },
                        set: { on in
                            if on { formData.selectedLabelGroups.append(group.id) }
                            else { formData.selectedLabelGroups.removeAll { $0 == group.id } }
                        }
                    ))
                    if formData.selectedLabelGroups.contains(group.id) {
                        ForEach(labelsInGroup(group)) { label in
                            HStack {
                                Text(label.name).font(.caption)
                                Spacer()
                                labelHotkeyButton(label: label)
                            }
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
            }
        }
    }

    private func labelHotkeyButton(label: Label) -> some View {
        ZStack {
            Button(action: {
                isCapturingHotkey = false
                isCapturingLabelHotkeys = [:]
                isCapturingLabelHotkeys[label.id] = true
            }) {
                Text(formData.labelHotkeys[label.id] ?? ^String.Titles.assign)
                    .font(.caption2)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
            }
            .buttonStyle(.plain)
            if isCapturingLabelHotkeys[label.id] == true {
                KeyCaptureView(
                    keyString: Binding(
                        get: { formData.labelHotkeys[label.id] },
                        set: { newValue in
                            if formData.isLabelHotkeyUsed(newValue, exceptLabel: label.id) ||
                                collectionManager.hasLabelHotkeyConflict(newValue, labelID: label.id, excludingTagID: tag.id) {
                                showHotkeyConflict = true
                            } else {
                                _ = formData.assignLabelHotkey(labelID: label.id, hotkey: newValue)
                            }
                            isCapturingLabelHotkeys[label.id] = false
                        }
                    ),
                    isCapturing: Binding(
                        get: { isCapturingLabelHotkeys[label.id] == true },
                        set: { isCapturingLabelHotkeys[label.id] = $0 }
                    )
                )
                .allowsHitTesting(false)
            }
        }
    }

    private func labelsInGroup(_ group: LabelGroupData) -> [Label] {
        collectionManager.labels.filter { group.lables.contains($0.id) }
    }

    /// Выбор Primary Counter — счётчика коллекции, чья запись всегда выводится на видео для момента
    /// этого тега (пересмотр/экспорт), даже если у счётчика нет флага «Показывать на видео».
    @ViewBuilder
    private var primaryCounterSection: some View {
        if !collectionManager.clocks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(^String.Titles.tagPrimaryCounter).font(.caption).foregroundColor(.secondary)
                Picker("", selection: $primaryClockId) {
                    Text(^String.Titles.tagPrimaryCounterNone).tag(String?.none)
                    ForEach(collectionManager.clocks) { clock in
                        Text(ClockTimelineRecorder.displayName(for: clock)).tag(String?.some(clock.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Text(^String.Titles.tagPrimaryCounterHint)
                    .font(.caption2).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func saveChanges() {
        if collectionManager.hasAnyLabelHotkeyConflicts(labelHotkeys: formData.labelHotkeys, excludingTagID: tag.id) {
            showHotkeyConflict = true
            return
        }
        let labelGroupIDs = collectionManager.isKeyBindingsMode
            ? collectionManager.labelGroups.map(\.id)
            : formData.selectedLabelGroups
        let success = collectionManager.updateTag(
            id: tag.id,
            primaryID: tag.primaryID,
            name: formData.name,
            description: formData.description,
            color: formData.hexColor,
            defaultTimeBefore: formData.defaultTimeBefore,
            defaultTimeAfter: formData.defaultTimeAfter,
            labelGroupIDs: labelGroupIDs,
            hotkey: formData.hotkey,
            labelHotkeys: formData.labelHotkeys,
            isInterval: formData.isInterval,
            mapEnabled: formData.mapEnabled
        )
        if success {
            collectionManager.updateTagPrimaryClock(id: tag.id, clockId: primaryClockId)
            onDismiss()
            presentationMode.wrappedValue.dismiss()
        } else {
            showHotkeyConflict = true
        }
    }
}

// Shared form section
extension TagCreateSheetView {
    struct NameDescriptionColorSection: View {
        @Binding var formData: TagFormData

        var body: some View {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(^String.Titles.name).font(.caption).foregroundColor(.secondary)
                    FocusAwareTextField(text: $formData.name, placeholder: ^String.Titles.title)
                        .textFieldStyle(ModernNewTextFieldStyle())
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(^String.Titles.description).font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $formData.description)
                        .frame(minHeight: 72)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(^String.Titles.color).font(.caption).foregroundColor(.secondary)
                    ColorPickerView(selectedColor: $formData.color, hexString: $formData.hexColor)
                }
            }
        }
    }
}
