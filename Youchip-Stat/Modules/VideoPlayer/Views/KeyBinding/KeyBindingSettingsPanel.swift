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
    var playFields: [PlayField] = []
    /// Ключ выбранной группы стрелок (source → target).
    let selectedGroupKey: KeyBindingGroupKey?
    /// Составной ключ сфокусированной кнопки ("kind:id"). Когда задан — показываются все её связки.
    var focusedSourceKey: String? = nil
    /// Все элементы холста (для отображения имён).
    var onAddLabel: (Label) -> Void
    var onAddTimeEvent: (TimeEvent) -> Void
    var onDeselect: () -> Void
    /// Сообщает наружу, какие группы связок подсвечивать на холсте (раскрытые в деталке кнопки).
    var onHighlightGroups: (Set<KeyBindingGroupKey>) -> Void = { _ in }

    @State private var isCapturingHotkeyForBindingId: String? = nil
    @State private var showPasteAlert = false
    /// Развёрнутые связки в деталке кнопки. В деталке связки всё всегда развёрнуто (это состояние не используется).
    @State private var expandedBindingIds: Set<String> = []
    /// Снимок id всех связок для детекции только что добавленной связки.
    @State private var previousBindingIds: Set<String> = []

    private func bindings(for key: KeyBindingGroupKey) -> [KeyBinding] {
        layout.bindings.filter { $0.groupKey == key }
    }

    /// Группы связок, ИСХОДЯЩИХ из сфокусированной кнопки, отсортированные по имени цели.
    private var outgoingGroupKeys: [KeyBindingGroupKey] {
        guard let focus = focusedSourceKey else { return [] }
        let keys = Set(layout.bindings.filter { $0.sourceButtonKey == focus }.map { $0.groupKey })
        return keys.sorted {
            name(for: $0.targetId, kind: $0.targetKind)
                .localizedCaseInsensitiveCompare(name(for: $1.targetId, kind: $1.targetKind)) == .orderedAscending
        }
    }

    /// Группы связок, ВХОДЯЩИХ в сфокусированную кнопку (source ≠ focus), отсортированные по имени источника.
    private var incomingGroupKeys: [KeyBindingGroupKey] {
        guard let focus = focusedSourceKey else { return [] }
        let keys = Set(layout.bindings
            .filter { $0.targetButtonKey == focus && $0.sourceButtonKey != focus }
            .map { $0.groupKey })
        return keys.sorted {
            name(for: $0.sourceId, kind: $0.sourceKind)
                .localizedCaseInsensitiveCompare(name(for: $1.sourceId, kind: $1.sourceKind)) == .orderedAscending
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    canvasSummarySection

                    if !timeEvents.isEmpty {
                        Divider()
                        sectionHeader(^String.Titles.keyBindingsPaletteTitle)
                        timeEventsPalette
                    }

                    Divider()

                    if let focus = focusedSourceKey {
                        focusedButtonPanel(sourceKey: focus)
                    } else if let key = selectedGroupKey {
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
            .onAppear { previousBindingIds = Set(layout.bindings.map { $0.id }) }
            // Смена сфокусированной кнопки — все связки снова свёрнуты.
            .onChange(of: focusedSourceKey) { _ in expandedBindingIds = [] }
            // Появилась новая связка — раскрываем и пролистываем только к ней.
            .onChange(of: layout.bindings.map { $0.id }) { ids in
                handleBindingsChanged(ids, proxy: proxy)
            }
            // Раскрытые связки подсвечиваются на холсте.
            .onChange(of: expandedBindingIds) { _ in reportHighlightedGroups() }
        }
        .frame(width: 340)
        .background(Color(NSColor.windowBackgroundColor))
    }

    /// Определяет только что добавленную связку, разворачивает её (свернув остальные) и пролистывает к ней.
    private func handleBindingsChanged(_ ids: [String], proxy: ScrollViewProxy) {
        let current = Set(ids)
        let added = current.subtracting(previousBindingIds)
        previousBindingIds = current
        guard focusedSourceKey != nil, !added.isEmpty else { return }
        // Из добавленных берём связку, относящуюся к сфокусированной кнопке.
        guard let newId = ids.last(where: { added.contains($0) }) else { return }
        expandedBindingIds = [newId]
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(newId, anchor: .center) }
        }
    }

    /// Передаёт наружу группы связок, соответствующие раскрытым в панели связкам.
    private func reportHighlightedGroups() {
        let groups = Set(expandedBindingIds.compactMap { id in
            layout.bindings.first(where: { $0.id == id })?.groupKey
        })
        onHighlightGroups(groups)
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

    // MARK: - Focused button panel (все связки одной кнопки)

    private func focusedButtonPanel(sourceKey: String) -> some View {
        let parts = sourceKey.split(separator: ":", maxSplits: 1)
        let kind = parts.first.flatMap { CanvasButtonKind(rawValue: String($0)) } ?? .tag
        let elementId = parts.count == 2 ? String(parts[1]) : sourceKey
        let outgoing = outgoingGroupKeys
        let incoming = incomingGroupKeys

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(for: elementId, kind: kind))
                        .font(.subheadline).fontWeight(.semibold)
                    Text(^String.Titles.keyBindingsButtonAllBindings)
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                // Удалить сразу ВСЕ связки этой кнопки (исходящие + входящие).
                if !(outgoing.isEmpty && incoming.isEmpty) {
                    Button(role: .destructive, action: { deleteAllBindings(forButtonKey: sourceKey) }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help(^String.Titles.keyBindingsDeleteAllForButton)
                }
                Button(action: onDeselect) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)

            Divider()

            if outgoing.isEmpty && incoming.isEmpty {
                Text(^String.Titles.keyBindingsTapTargetHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } else {
                // Исходящие связки (кнопка → цель).
                ForEach(outgoing, id: \.self) { key in
                    bindingGroupSection(
                        key: key,
                        headerName: name(for: key.targetId, kind: key.targetKind),
                        incoming: false,
                        collapsible: true
                    )
                    Divider()
                }
                // Входящие связки (источник → кнопка).
                ForEach(incoming, id: \.self) { key in
                    bindingGroupSection(
                        key: key,
                        headerName: name(for: key.sourceId, kind: key.sourceKind),
                        incoming: true,
                        collapsible: true
                    )
                    Divider()
                }
            }

            Spacer(minLength: 20)
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

            // Деталка связки: всегда развёрнуто, без заголовка и без сворачивания.
            bindingGroupSection(key: key, headerName: nil, incoming: false, collapsible: false)

            Spacer(minLength: 20)
        }
    }

    // MARK: - Binding group section (связки одной пары source→target)

    /// - Parameters:
    ///   - headerName: имя «другой» кнопки пары; nil — заголовок не показывается (деталка связки).
    ///   - incoming: связка входящая (источник → сфокусированная кнопка). Влияет только на стрелку заголовка.
    ///   - collapsible: связки можно сворачивать/разворачивать (деталка кнопки). Иначе всегда развёрнуто.
    private func bindingGroupSection(key: KeyBindingGroupKey, headerName: String?, incoming: Bool, collapsible: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let headerName = headerName {
                HStack(spacing: 4) {
                    Image(systemName: incoming ? "arrow.left" : "arrow.right")
                        .font(.caption2).foregroundColor(.secondary)
                    Text(headerName)
                        .font(.caption).fontWeight(.semibold)
                }
            }

            // Binding accordions
            ForEach(bindings(for: key)) { binding in
                bindingAccordion(binding: binding, collapsible: collapsible)
                    .id(binding.id)
                Divider()
            }

            // Add / copy-paste buttons
            HStack(spacing: 8) {
                Button(action: { addBinding(key: key) }) {
                    SwiftUI.Label(^String.Titles.keyBindingsAdd, systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(action: { copyBindings(key: key) }) {
                    SwiftUI.Label(^String.Titles.keyBindingsCopy, systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                if KeyBindingClipboard.hasContent {
                    Button(action: { pasteBindings(key: key) }) {
                        SwiftUI.Label(^String.Titles.keyBindingsPaste, systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Single binding accordion

    private func bindingAccordion(binding: KeyBinding, collapsible: Bool) -> some View {
        // В деталке связки (collapsible == false) всё всегда развёрнуто.
        // В деталке кнопки (collapsible == true) связки можно сворачивать/разворачивать.
        let isExpanded = !collapsible || expandedBindingIds.contains(binding.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                if collapsible {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 10)
                }
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(localizedTypeName(binding.type))
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if let delay = binding.delaySeconds, delay > 0 {
                    Text("+\(Int(delay))s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                // Кнопка удаления прямо в свёрнутой строке — не нужно раскрывать связку,
                // чтобы её удалить (в раскрытом виде удаление есть в деталке).
                if collapsible && !isExpanded {
                    Button(role: .destructive, action: { deleteBinding(binding) }) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help(^String.Titles.keyBindingsDelete)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                guard collapsible else { return }
                if expandedBindingIds.contains(binding.id) {
                    expandedBindingIds.remove(binding.id)
                } else {
                    expandedBindingIds.insert(binding.id)
                }
            }

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

    private func addBinding(key: KeyBindingGroupKey) {
        let nb = KeyBinding(
            sourceId: key.sourceId,
            sourceKind: key.sourceKind,
            targetId: key.targetId,
            targetKind: key.targetKind,
            type: .highlight
        )
        layout.bindings.append(nb)
    }

    private func deleteBinding(_ binding: KeyBinding) {
        layout.bindings.removeAll { $0.id == binding.id }
    }

    /// Удаляет все связки кнопки — где она источник ИЛИ цель (исходящие + входящие).
    private func deleteAllBindings(forButtonKey key: String) {
        layout.bindings.removeAll { $0.sourceButtonKey == key || $0.targetButtonKey == key }
        expandedBindingIds = []
    }

    private func duplicateBinding(_ binding: KeyBinding) {
        let dupes = KeyBindingClipboard.duplicate([binding])
        layout.bindings.append(contentsOf: dupes)
    }

    private func copyBindings(key: KeyBindingGroupKey) {
        KeyBindingClipboard.copy(bindings(for: key))
    }

    private func pasteBindings(key: KeyBindingGroupKey) {
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
        case .map:
            return playFields.first(where: { $0.id == elementId })?.name ?? elementId
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
