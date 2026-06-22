//
//  KeyBindingSettingsPanel.swift
//  Youchip-Stat
//
//  Правая панель редактора в режиме «Связки»:
//  - список лейблов для добавления на холст
//  - аккордеоны настроек связок для выбранной пары кнопок
//

import SwiftUI

// MARK: - Panel

struct KeyBindingSettingsPanel: View {

    @Binding var layout: TagFreeLayout
    let tags: [Tag]
    let labels: [Label]
    let timeEvents: [TimeEvent]
    /// Ключ выбранной группы стрелок (source → target).
    let selectedGroupKey: KeyBindingGroupKey?
    /// Все элементы холста (для отображения имён).
    var onAddLabel: (Label) -> Void
    var onAddTimeEvent: (TimeEvent) -> Void
    var onDeselect: () -> Void

    @State private var expandedBindingId: String? = nil
    @State private var isCapturingHotkeyForBindingId: String? = nil
    @State private var showPasteAlert = false

    private var bindingsForGroup: [KeyBinding] {
        guard let key = selectedGroupKey else { return [] }
        return layout.bindings.filter { $0.groupKey == key }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                canvasSummarySection

                Divider()

                sectionHeader(^String.Titles.keyBindingsPaletteTitle)
                labelsPalette

                if !timeEvents.isEmpty {
                    Divider()
                    timeEventsPalette
                }

                Divider()

                if let key = selectedGroupKey {
                    bindingGroupPanel(key: key)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(^String.Titles.keyBindingsTapSourceHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(^String.Titles.keyBindingsSelectArrowHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Canvas summary

    private var canvasSummarySection: some View {
        let tagCount = layout.items.filter { $0.kind == .tag }.count
        let labelCount = layout.items.filter { $0.kind == .label }.count
        let timeEventCount = layout.items.filter { $0.kind == .timeEvent }.count

        return VStack(alignment: .leading, spacing: 6) {
            sectionHeader(^String.Titles.keyBindingsCanvasSummary)
            Text(String(format: ^String.Titles.keyBindingsCanvasTagsCount, tagCount))
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: ^String.Titles.keyBindingsCanvasLabelsCount, labelCount))
                .font(.caption)
                .foregroundColor(.secondary)
            if timeEventCount > 0 {
                Text(String(format: ^String.Titles.keyBindingsCanvasTimeEventsCount, timeEventCount))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if tagCount == 0 {
                Text(^String.Titles.keyBindingsNoTagsOnCanvas)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - No selection (removed — palette always visible)

    // MARK: - Labels palette

    private var labelsPalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            if labels.isEmpty {
                Text(^String.Titles.keyBindingsNoLabels)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(^String.Titles.keyBindingsAddLabelHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(labels) { label in
                    let alreadyOnCanvas = layout.items.contains { $0.elementId == label.id && $0.kind == .label }
                    HStack {
                        Image(systemName: "textformat")
                            .foregroundColor(.secondary)
                            .frame(width: 14)
                        Text(label.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if alreadyOnCanvas {
                            Text(^String.Titles.keyBindingsOnCanvas)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Button(action: { onAddLabel(label) }) {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    // MARK: - Time events palette

    private var timeEventsPalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(^String.Titles.keyBindingsAddTimeEventHint)
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(timeEvents) { event in
                let alreadyOnCanvas = layout.items.contains { $0.elementId == event.id && $0.kind == .timeEvent }
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .frame(width: 14)
                    Text(event.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    if alreadyOnCanvas {
                        Text(^String.Titles.keyBindingsOnCanvas)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Button(action: { onAddTimeEvent(event) }) {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Binding group panel

    private func bindingGroupPanel(key: KeyBindingGroupKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(for: key.sourceId, kind: key.sourceKind))
                        .font(.caption).foregroundColor(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2).foregroundColor(.secondary)
                    Text(name(for: key.targetId, kind: key.targetKind))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onDeselect) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)

            Divider()

            // Binding accordions
            ForEach(bindingsForGroup) { binding in
                bindingAccordion(binding: binding)
                Divider()
            }

            // Add / copy-paste buttons
            HStack(spacing: 8) {
                Button(action: addBinding) {
                    SwiftUI.Label(^String.Titles.keyBindingsAdd, systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(action: copyBindings) {
                    SwiftUI.Label(^String.Titles.keyBindingsCopy, systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                if KeyBindingClipboard.hasContent {
                    Button(action: pasteBindings) {
                        SwiftUI.Label(^String.Titles.keyBindingsPaste, systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 20)
        }
    }

    // MARK: - Single binding accordion

    private func bindingAccordion(binding: KeyBinding) -> some View {
        let isExpanded = expandedBindingId == binding.id
        return VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedBindingId = isExpanded ? nil : binding.id
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(localizedTypeName(binding.type))
                        .font(.caption)
                    Spacer()
                    if let delay = binding.delaySeconds, delay > 0 {
                        Text("+\(Int(delay))s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                bindingDetails(binding: binding)
                    .padding(.leading, 12)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Binding detail fields

    @ViewBuilder
    private func bindingDetails(binding: KeyBinding) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            // Type picker
            sectionHeader(^String.Titles.keyBindingsType)
            Picker("", selection: bindingTypeBinding(id: binding.id)) {
                ForEach(KeyBindingType.allCases, id: \.self) { type in
                    Text(localizedTypeName(type)).tag(type)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Divider()

            // Delay
            sectionHeader(^String.Titles.keyBindingsDelay)
            HStack {
                Text(^String.Titles.keyBindingsDelaySec).font(.caption)
                Spacer()
                TextField("0", value: bindingDelayBinding(id: binding.id), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    .font(.caption)
            }

            // Override time before/after (for highlight and activation)
            if binding.type == .highlight || binding.type == .activation {
                Divider()
                sectionHeader(^String.Titles.keyBindingsOverrideTime)
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(^String.Titles.keyBindingsTimeBefore).font(.caption2).foregroundColor(.secondary)
                        TextField(^String.Titles.keyBindingsTimeDefault,
                                  value: bindingOptDoubleBinding(id: binding.id, \.overrideTimeBefore),
                                  format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(^String.Titles.keyBindingsTimeAfter).font(.caption2).foregroundColor(.secondary)
                        TextField(^String.Titles.keyBindingsTimeDefault,
                                  value: bindingOptDoubleBinding(id: binding.id, \.overrideTimeAfter),
                                  format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .font(.caption)
                    }
                }
            }

            // Highlight-specific options
            if binding.type == .highlight {
                Divider()
                sectionHeader(^String.Titles.keyBindingsHighlightOptions)

                Toggle(^String.Titles.keyBindingsShowTarget, isOn: bindingBoolBinding(id: binding.id, \.showTargetOnHighlight))
                    .font(.caption)

                Toggle(^String.Titles.keyBindingsRevertAfterPress, isOn: bindingBoolBinding(id: binding.id, \.revertVisibilityAfterPress))
                    .font(.caption)

                HStack {
                    Text(^String.Titles.keyBindingsHighlightHotkey).font(.caption)
                    Spacer()
                    hotkeyCapture(bindingId: binding.id,
                                  current: binding.highlightHotkey)
                }
            }

            // Visibility / invisibility-specific
            if binding.type == .visibility || binding.type == .invisibility {
                Divider()
                Toggle(^String.Titles.keyBindingsRevertAfterPress,
                       isOn: bindingBoolBinding(id: binding.id, \.revertVisibilityAfterPress))
                    .font(.caption)
            }

            Divider()

            // Duplicate / Delete
            HStack(spacing: 8) {
                Button(action: { duplicateBinding(binding) }) {
                    SwiftUI.Label(^String.Titles.keyBindingsDuplicate, systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                Button(role: .destructive, action: { deleteBinding(binding) }) {
                    SwiftUI.Label(^String.Titles.keyBindingsDelete, systemImage: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Hotkey capture inline

    @ViewBuilder
    private func hotkeyCapture(bindingId: String, current: String?) -> some View {
        let isCapturing = isCapturingHotkeyForBindingId == bindingId
        ZStack {
            KeyCaptureView(
                keyString: Binding(
                    get: { current },
                    set: { newVal in setHighlightHotkey(bindingId: bindingId, value: newVal) }
                ),
                isCapturing: Binding(
                    get: { isCapturing },
                    set: { if !$0 { isCapturingHotkeyForBindingId = nil } }
                )
            )
            .frame(width: 0, height: 0)

            Button(action: {
                isCapturingHotkeyForBindingId = isCapturing ? nil : bindingId
            }) {
                Text(isCapturing ? ^String.Titles.keyBindingsPressKey
                     : (current ?? ^String.Titles.assign))
                    .font(.caption)
                    .foregroundColor(isCapturing ? .accentColor : (current != nil ? .primary : .secondary))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isCapturing ? Color.accentColor : Color.secondary.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bindings (SwiftUI Binding helpers)

    private func bindingTypeBinding(id: String) -> Binding<KeyBindingType> {
        Binding(
            get: { layout.bindings.first(where: { $0.id == id })?.type ?? .highlight },
            set: { val in updateBinding(id: id) { $0.type = val } }
        )
    }

    private func bindingDelayBinding(id: String) -> Binding<Double> {
        Binding(
            get: { layout.bindings.first(where: { $0.id == id })?.delaySeconds ?? 0 },
            set: { val in updateBinding(id: id) { $0.delaySeconds = val > 0 ? val : nil } }
        )
    }

    private func bindingOptDoubleBinding(id: String, _ kp: WritableKeyPath<KeyBinding, Double?>) -> Binding<Double?> {
        Binding(
            get: { layout.bindings.first(where: { $0.id == id })?[keyPath: kp] },
            set: { val in updateBinding(id: id) { $0[keyPath: kp] = val } }
        )
    }

    private func bindingBoolBinding(id: String, _ kp: WritableKeyPath<KeyBinding, Bool?>) -> Binding<Bool> {
        Binding(
            get: { layout.bindings.first(where: { $0.id == id })?[keyPath: kp] ?? false },
            set: { val in updateBinding(id: id) { $0[keyPath: kp] = val } }
        )
    }

    private func updateBinding(id: String, _ update: (inout KeyBinding) -> Void) {
        guard let idx = layout.bindings.firstIndex(where: { $0.id == id }) else { return }
        update(&layout.bindings[idx])
    }

    private func setHighlightHotkey(bindingId: String, value: String?) {
        updateBinding(id: bindingId) { $0.highlightHotkey = value }
        isCapturingHotkeyForBindingId = nil
    }

    // MARK: - Actions

    private func addBinding() {
        guard let key = selectedGroupKey else { return }
        let nb = KeyBinding(
            sourceId: key.sourceId,
            sourceKind: key.sourceKind,
            targetId: key.targetId,
            targetKind: key.targetKind,
            type: .highlight
        )
        layout.bindings.append(nb)
        expandedBindingId = nb.id
    }

    private func deleteBinding(_ binding: KeyBinding) {
        layout.bindings.removeAll { $0.id == binding.id }
        if expandedBindingId == binding.id { expandedBindingId = nil }
    }

    private func duplicateBinding(_ binding: KeyBinding) {
        let dupes = KeyBindingClipboard.duplicate([binding])
        layout.bindings.append(contentsOf: dupes)
    }

    private func copyBindings() {
        KeyBindingClipboard.copy(bindingsForGroup)
    }

    private func pasteBindings() {
        guard let key = selectedGroupKey else { return }
        if let pasted = KeyBindingClipboard.paste(newSourceId: key.sourceId, newSourceKind: key.sourceKind) {
            layout.bindings.append(contentsOf: pasted)
        }
    }

    // MARK: - Utilities

    private func name(for elementId: String, kind: CanvasButtonKind) -> String {
        switch kind {
        case .tag:
            return tags.first(where: { $0.id == elementId })?.name ?? elementId
        case .label:
            return labels.first(where: { $0.id == elementId })?.name ?? elementId
        case .timeEvent:
            return timeEvents.first(where: { $0.id == elementId })?.name ?? elementId
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
    }

    private func localizedTypeName(_ type: KeyBindingType) -> String {
        NSLocalizedString(type.localizationKey.capitalizeFirstLetter(), comment: "")
    }
}
