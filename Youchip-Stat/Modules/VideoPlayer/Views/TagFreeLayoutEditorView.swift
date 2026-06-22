//
//  TagFreeLayoutEditorView.swift
//  Youchip-Stat
//
//  Редактор свободного отображения тегов и лейблов коллекции.
//  Два режима: «Расположение» (drag/resize/style) и «Связки» (создание KeyBinding).
//

import SwiftUI

// MARK: - Editor mode

private enum EditorMode: String, CaseIterable {
    case layout
    case bindings
}

// MARK: - Main view

struct TagFreeLayoutEditorView: View {

    let collectionId: String
    let collectionName: String
    let tags: [Tag]
    let labels: [Label]
    let timeEvents: [TimeEvent]

    @Environment(\.presentationMode) private var presentationMode

    @State private var layout: TagFreeLayout
    @State private var editorMode: EditorMode = .layout

    // Layout-mode selection
    @State private var selectedItemId: String? = nil

    // Layout-mode drag / resize / rotate
    @State private var draggingItemId: String? = nil
    @State private var resizingItemId: String? = nil
    @State private var rotatingItemId: String? = nil
    @State private var dragStartCenter: CGPoint = .zero
    @State private var resizeStartSize: CGSize = .zero
    @State private var rotateStartAngle: Double = 0

    // Bindings-mode
    @State private var bindingSourceId: String? = nil       // "kind:elementId"
    @State private var selectedGroupKey: KeyBindingGroupKey? = nil

    // Canvas settings
    @State private var showGrid: Bool = false
    @State private var snapToGrid: Bool = false
    private let gridStep: CGFloat = 50

    // MARK: Init

    init(collectionId: String, collectionName: String, tags: [Tag], labels: [Label] = [], timeEvents: [TimeEvent] = []) {
        self.collectionId = collectionId
        self.collectionName = collectionName
        self.tags = tags
        self.labels = labels
        self.timeEvents = timeEvents

        let stored = TagFreeLayoutStorage.loadLayoutIfExists(
            collectionId: collectionId, tags: tags, labels: labels, timeEvents: timeEvents
        )
        _layout = State(initialValue: stored ?? TagFreeLayoutStorage.makeDefaultLayout(for: tags))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HStack(spacing: 0) {
                GeometryReader { geo in
                    let availableWidth = max(geo.size.width - 32, 300)
                    let fitScale = availableWidth / max(layout.canvasWidth, 1)
                    let scale = min(1.0, max(fitScale, 0.1))
                    let canvasPixelWidth = layout.canvasWidth * scale
                    let canvasPixelHeight = layout.canvasHeight * scale

                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )

                            if showGrid {
                                gridOverlay(scale: scale)
                                    .frame(width: canvasPixelWidth, height: canvasPixelHeight)
                            }

                            canvasView(scale: scale, canvasPixelWidth: canvasPixelWidth, canvasPixelHeight: canvasPixelHeight)

                            if editorMode == .bindings {
                                KeyBindingArrowOverlay(
                                    layout: layout,
                                    scale: scale,
                                    canvasPixelWidth: canvasPixelWidth,
                                    canvasPixelHeight: canvasPixelHeight,
                                    selectedGroupKey: selectedGroupKey,
                                    onSelectGroup: { key in
                                        selectedGroupKey = key
                                        selectedItemId = nil
                                        bindingSourceId = nil
                                    }
                                )
                                .frame(width: canvasPixelWidth, height: canvasPixelHeight)

                                bindingsModeBanner
                                    .frame(width: canvasPixelWidth, alignment: .top)
                                    .padding(.top, 8)
                            }
                        }
                        .frame(width: canvasPixelWidth, height: canvasPixelHeight)
                        .padding(16)
                        .frame(minWidth: availableWidth, minHeight: canvasPixelHeight + 32, alignment: .center)
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                Divider()

                rightPanel
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 960, minHeight: 600)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(^String.Titles.freeLayoutTitle).font(.headline)
                Text(collectionName).font(.subheadline).foregroundColor(.secondary)
            }

            Spacer()

            // Mode picker
            Picker("", selection: $editorMode) {
                SwiftUI.Label(^String.Titles.keyBindingsEditorModeLayout, systemImage: "move.3d").tag(EditorMode.layout)
                SwiftUI.Label(^String.Titles.keyBindingsEditorModeBindings, systemImage: "arrow.triangle.branch").tag(EditorMode.bindings)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .onChange(of: editorMode) { mode in
                selectedItemId = nil
                bindingSourceId = nil
                selectedGroupKey = nil
                if mode == .bindings {
                    layout = TagFreeLayoutStorage.normalizeLayout(layout, tags: tags, labels: labels, timeEvents: timeEvents)
                }
            }

            Spacer()

            Button(^String.Titles.cancelButtonTitle) {
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.borderless)

            Button(^String.Titles.sportCutReset) {
                layout = TagFreeLayoutStorage.makeDefaultLayout(for: tags)
                selectedItemId = nil
                bindingSourceId = nil
                selectedGroupKey = nil
            }
            .buttonStyle(.bordered)

            Button(^String.Titles.saveButtonTitle) {
                TagFreeLayoutStorage.saveLayout(layout, collectionId: collectionId)
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Grid overlay

    private func gridOverlay(scale: CGFloat) -> some View {
        Canvas { context, size in
            let step = gridStep * scale
            var x = step
            while x < size.width {
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(p, with: .color(.gray.opacity(0.15)), lineWidth: 0.5); x += step
            }
            var y = step
            while y < size.height {
                var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(p, with: .color(.gray.opacity(0.15)), lineWidth: 0.5); y += step
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Canvas

    private func canvasView(scale: CGFloat, canvasPixelWidth: CGFloat, canvasPixelHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: canvasPixelWidth, height: canvasPixelHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    if editorMode == .layout {
                        selectedItemId = nil
                    } else {
                        bindingSourceId = nil
                        selectedGroupKey = nil
                    }
                }

            ForEach(layout.items) { item in
                itemView(item: item, scale: scale)
                    .position(x: item.center.x * scale, y: item.center.y * scale)
            }
        }
        .frame(width: canvasPixelWidth, height: canvasPixelHeight, alignment: .topLeading)
        .coordinateSpace(name: "canvas")
    }

    // MARK: - Bindings mode banner

    private var bindingsModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: bindingSourceId != nil ? "1.circle.fill" : "1.circle")
                .foregroundColor(bindingSourceId != nil ? .orange : .secondary)
            Text(bindingSourceId != nil
                 ? ^String.Titles.keyBindingsTapTargetHint
                 : ^String.Titles.keyBindingsTapSourceHint)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
            if bindingSourceId != nil {
                Button(^String.Titles.cancelButtonTitle) {
                    bindingSourceId = nil
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.92))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        )
        .padding(.horizontal, 12)
    }

    // MARK: - Single item view

    @ViewBuilder
    private func itemView(item: TagFreeLayoutItem, scale: CGFloat) -> some View {
        let itemKey = item.id
        let isSelected = selectedItemId == itemKey

        // Determine display name
        let displayName: String = {
            switch item.kind {
            case .tag:       return tags.first(where: { $0.id == item.elementId })?.name ?? item.elementId
            case .label:     return labels.first(where: { $0.id == item.elementId })?.name ?? item.elementId
            case .timeEvent: return timeEvents.first(where: { $0.id == item.elementId })?.name ?? item.elementId
            }
        }()

        // Determine fill color
        let fillColor: Color = {
            switch item.kind {
            case .label:
                return Color(NSColor.controlBackgroundColor).opacity(item.fillOpacity)
            case .timeEvent:
                return Color.orange.opacity(item.fillOpacity * 0.15)
            case .tag:
                let hex = tags.first(where: { $0.id == item.elementId })?.color ?? "808080"
                return Color(hex: hex).opacity(item.fillOpacity)
            }
        }()

        let viewSize = CGSize(width: item.size.width * scale, height: item.size.height * scale)
        let strokeCol = item.strokeColor.map { Color(hex: $0) } ?? Color.black.opacity(0.3)
        let strokeStyle = StrokeStyle(
            lineWidth: isSelected ? 2 : item.strokeWidth,
            dash: (isSelected ? true : item.strokeDashed) ? [4, 3] : []
        )
        let textCol = item.textColor.map { Color(hex: $0) } ?? Color.white
        let swiftWeight: Font.Weight = {
            switch item.fontWeight {
            case .regular: return .regular; case .medium: return .medium; case .bold: return .bold
            }
        }()

        // In bindings mode: highlight source/selected state
        let isBindingSource = editorMode == .bindings && bindingSourceId == itemKey
        let strokeOverride: Color = isBindingSource ? .orange : (isSelected ? .accentColor : strokeCol)

        ZStack {
            TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius)
                .fill(fillColor)
                .overlay(
                    Group {
                        if item.showLabel {
                            Text(displayName)
                                .font(.system(size: item.fontSize, weight: swiftWeight))
                                .foregroundColor(textCol)
                                .padding(4)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.5)
                        }
                    }
                )
                .frame(width: viewSize.width, height: viewSize.height)
                .overlay(
                    TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius)
                        .stroke(strokeOverride, style: strokeStyle)
                )

            // Kind indicator (small icon in corner)
            if item.kind == .label || item.kind == .timeEvent {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: item.kind == .label ? "textformat" : "clock")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(textCol.opacity(0.7))
                            .padding(3)
                    }
                    Spacer()
                }
                .frame(width: viewSize.width, height: viewSize.height)
            }

            // Visibility badge
            if !item.isVisible {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(3)
                        Spacer()
                    }
                }
                .frame(width: viewSize.width, height: viewSize.height)
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .rotationEffect(.degrees(item.rotation))
        .shadow(
            color: item.shadowEnabled
                ? (isSelected ? Color.accentColor.opacity(0.4) : Color.black.opacity(item.shadowIntensity))
                : Color.clear,
            radius: item.shadowEnabled ? (isSelected ? 8 : 4) : 0,
            x: 0, y: item.shadowEnabled ? 2 : 0
        )
        .opacity(item.isVisible ? 1.0 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture { handleItemTap(item: item) }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                .onChanged { value in
                    guard editorMode == .layout, isSelected else { return }
                    if draggingItemId == nil {
                        draggingItemId = item.id
                        dragStartCenter = item.center
                    }
                    guard draggingItemId == item.id else { return }
                    var newX = dragStartCenter.x + value.translation.width / scale
                    var newY = dragStartCenter.y + value.translation.height / scale
                    if snapToGrid {
                        newX = (newX / gridStep).rounded() * gridStep
                        newY = (newY / gridStep).rounded() * gridStep
                    }
                    let halfW = item.size.width / 2, halfH = item.size.height / 2
                    updateItem(id: item.id) { m in
                        m.center = CGPoint(
                            x: min(max(halfW, newX), layout.canvasWidth - halfW),
                            y: min(max(halfH, newY), layout.canvasHeight - halfH)
                        )
                    }
                }
                .onEnded { _ in draggingItemId = nil }
        )
        // Resize/rotate handles only in layout mode
        .overlay(
            editorMode == .layout && isSelected
            ? AnyView(resizeHandle(item: item, scale: scale)
                        .offset(x: viewSize.width / 2 - 10, y: viewSize.height / 2 - 10))
            : AnyView(EmptyView())
        )
        .overlay(
            editorMode == .layout && isSelected
            ? AnyView(rotationHandle(item: item, scale: scale)
                        .offset(x: viewSize.width / 2 - 10, y: -viewSize.height / 2 + 10))
            : AnyView(EmptyView())
        )
        .contextMenu { itemContextMenu(item: item) }
    }

    // MARK: - Item tap

    private func handleItemTap(item: TagFreeLayoutItem) {
        if editorMode == .layout {
            selectedItemId = selectedItemId == item.id ? nil : item.id
            return
        }
        // Bindings mode
        if let sourceKey = bindingSourceId {
            guard sourceKey != item.id else {
                bindingSourceId = nil
                return
            }
            // Create binding source→target
            let srcParts = sourceKey.split(separator: ":", maxSplits: 1)
            guard srcParts.count == 2,
                  let srcKind = CanvasButtonKind(rawValue: String(srcParts[0])) else {
                return
            }
            let srcId = String(srcParts[1])
            let newBinding = KeyBinding(
                sourceId: srcId, sourceKind: srcKind,
                targetId: item.elementId, targetKind: item.kind
            )
            layout.bindings.append(newBinding)
            let key = newBinding.groupKey
            selectedGroupKey = key
            bindingSourceId = nil
        } else {
            // Select as source
            bindingSourceId = item.id
            selectedGroupKey = nil
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func itemContextMenu(item: TagFreeLayoutItem) -> some View {
        if editorMode == .bindings {
            let outgoing = layout.bindings.filter { $0.sourceButtonKey == item.id }
            if !outgoing.isEmpty {
                Button(^String.Titles.keyBindingsCopyAll) {
                    KeyBindingClipboard.copy(outgoing)
                }
            }
            if KeyBindingClipboard.hasContent {
                Button(^String.Titles.keyBindingsPaste) {
                    if let pasted = KeyBindingClipboard.paste(newSourceId: item.elementId, newSourceKind: item.kind) {
                        layout.bindings.append(contentsOf: pasted)
                    }
                }
            }
        } else {
            // Layout mode
            if item.kind == .label || item.kind == .timeEvent {
                Button(^String.Titles.keyBindingsRemoveFromCanvas) {
                    removePaletteItem(item: item)
                }
            }
        }
    }

    private func removePaletteItem(item: TagFreeLayoutItem) {
        layout.items.removeAll { $0.id == item.id }
        // Remove bindings involving this item
        layout.bindings.removeAll { $0.sourceButtonKey == item.id || $0.targetButtonKey == item.id }
        if selectedItemId == item.id { selectedItemId = nil }
    }

    // MARK: - Handles

    private func rotationHandle(item: TagFreeLayoutItem, scale: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: 20, height: 20)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        if rotatingItemId == nil { rotatingItemId = item.id; rotateStartAngle = item.rotation }
                        guard rotatingItemId == item.id else { return }
                        updateItem(id: item.id) { $0.rotation = rotateStartAngle + Double(value.translation.width / scale) }
                    }
                    .onEnded { _ in rotatingItemId = nil }
            )
    }

    private func resizeHandle(item: TagFreeLayoutItem, scale: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white)
            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: 20, height: 20)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        if resizingItemId == nil { resizingItemId = item.id; resizeStartSize = item.size }
                        guard resizingItemId == item.id else { return }
                        let dw = value.translation.width / scale
                        let dh = value.translation.height / scale
                        updateItem(id: item.id) { m in
                            let minSize: CGFloat = 40
                            var nw = max(minSize, resizeStartSize.width + dw)
                            var nh = max(minSize, resizeStartSize.height + dh)
                            if m.aspectRatioLocked, resizeStartSize.height > 0 {
                                let ratio = resizeStartSize.width / resizeStartSize.height
                                let avg = (dw + dh) / 2
                                nw = max(minSize, resizeStartSize.width + avg)
                                nh = max(minSize, nw / ratio)
                            }
                            m.size = CGSize(width: nw, height: nh)
                        }
                    }
                    .onEnded { _ in resizingItemId = nil }
            )
    }

    // MARK: - Right panel

    @ViewBuilder
    private var rightPanel: some View {
        if editorMode == .bindings {
            KeyBindingSettingsPanel(
                layout: $layout,
                tags: tags,
                labels: labels,
                timeEvents: timeEvents,
                selectedGroupKey: selectedGroupKey,
                onAddLabel: addLabelToCanvas,
                onAddTimeEvent: addTimeEventToCanvas,
                onDeselect: { selectedGroupKey = nil; bindingSourceId = nil }
            )
        } else {
            layoutModeSettingsPanel
        }
    }

    // MARK: - Layout mode settings panel

    private var layoutModeSettingsPanel: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let itemId = selectedItemId,
                   let index = layout.items.firstIndex(where: { $0.id == itemId }) {
                    selectedItemSettings(index: index)
                } else {
                    canvasSettings
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Canvas settings

    private var canvasSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(^String.Titles.freeLayoutCanvasSettings).font(.headline).padding(.top, 4)
            Divider()
            Toggle(^String.Titles.freeLayoutShowGrid, isOn: $showGrid)
            Toggle(^String.Titles.freeLayoutSnapToGrid, isOn: $snapToGrid)
            Text(^String.Titles.freeLayoutSelectElement)
                .font(.caption).foregroundColor(.secondary).padding(.top, 8)
        }
    }

    // MARK: - Selected item settings

    private func selectedItemSettings(index: Int) -> some View {
        let binding = $layout.items[index]
        let item = layout.items[index]
        let displayName: String = {
            switch item.kind {
            case .tag:       return tags.first(where: { $0.id == item.elementId })?.name ?? item.elementId
            case .label:     return labels.first(where: { $0.id == item.elementId })?.name ?? item.elementId
            case .timeEvent: return timeEvents.first(where: { $0.id == item.elementId })?.name ?? item.elementId
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: itemIcon(for: item.kind))
                    .foregroundColor(.secondary).frame(width: 14)
                Text(displayName).font(.headline).lineLimit(1)
                Spacer()
                Button(action: { selectedItemId = nil }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.top, 4)

            Divider()

            // Visibility toggle
            sectionHeader(^String.Titles.keyBindingsVisibilitySection)
            Toggle(^String.Titles.keyBindingsItemVisible, isOn: binding.isVisible)
                .font(.caption)

            Divider()

            // Shape picker
            sectionHeader(^String.Titles.freeLayoutSectionShape)
            shapePickerGrid(binding: binding)

            Divider()

            // Fill
            sectionHeader(^String.Titles.freeLayoutSectionFill)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(^String.Titles.freeLayoutOpacity).font(.caption)
                    Spacer()
                    Text("\(Int(binding.fillOpacity.wrappedValue * 100))%").font(.caption).foregroundColor(.secondary)
                }
                Slider(value: binding.fillOpacity, in: 0...1, step: 0.05)
                HStack(spacing: 4) {
                    Button(^String.Titles.freeLayoutTransparent) { binding.fillOpacity.wrappedValue = 0 }
                        .font(.caption2).buttonStyle(.bordered)
                    Button(^String.Titles.freeLayoutOpaque) { binding.fillOpacity.wrappedValue = 1 }
                        .font(.caption2).buttonStyle(.bordered)
                }
            }

            Divider()

            // Stroke
            sectionHeader(^String.Titles.freeLayoutSectionStroke)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(^String.Titles.freeLayoutColor).font(.caption)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { binding.strokeColor.wrappedValue.map { Color(hex: $0) } ?? Color.black.opacity(0.3) },
                        set: { binding.strokeColor.wrappedValue = $0.toHex() ?? "000000" }
                    )).frame(width: 40, height: 24)
                }
                HStack {
                    Text(^String.Titles.freeLayoutThickness).font(.caption)
                    Spacer()
                    Text("\(Int(binding.strokeWidth.wrappedValue))pt").font(.caption).foregroundColor(.secondary)
                    Stepper("", value: binding.strokeWidth, in: 0...10, step: 1).labelsHidden()
                }
                HStack(spacing: 4) {
                    strokeStyleButton(label: ^String.Titles.freeLayoutStrokeSolid, dashed: false, binding: binding.strokeDashed)
                    strokeStyleButton(label: ^String.Titles.freeLayoutStrokeDashed, dashed: true, binding: binding.strokeDashed)
                }
            }

            Divider()

            // Text
            sectionHeader(^String.Titles.freeLayoutSectionText)
            VStack(alignment: .leading, spacing: 6) {
                Toggle(^String.Titles.freeLayoutShowLabel, isOn: binding.showLabel)
                if binding.showLabel.wrappedValue {
                    HStack {
                        Text(^String.Titles.freeLayoutColor).font(.caption)
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { binding.textColor.wrappedValue.map { Color(hex: $0) } ?? Color.white },
                            set: { binding.textColor.wrappedValue = $0.toHex() ?? "FFFFFF" }
                        )).frame(width: 40, height: 24)
                    }
                    HStack {
                        Text(^String.Titles.freeLayoutFontSize).font(.caption)
                        Spacer()
                        Text("\(Int(binding.fontSize.wrappedValue))pt").font(.caption).foregroundColor(.secondary)
                        Stepper("", value: binding.fontSize, in: 8...32, step: 1).labelsHidden()
                    }
                    HStack(spacing: 3) {
                        fontWeightButton(label: "R", weight: .regular, binding: binding.fontWeight)
                        fontWeightButton(label: "M", weight: .medium, binding: binding.fontWeight)
                        fontWeightButton(label: "B", weight: .bold, binding: binding.fontWeight)
                    }
                }
            }

            Divider()

            // Geometry
            sectionHeader(^String.Titles.freeLayoutSectionGeometry)
            VStack(alignment: .leading, spacing: 6) {
                if binding.shape.wrappedValue == .square {
                    HStack {
                        Text(^String.Titles.freeLayoutCornerRadius).font(.caption)
                        Spacer()
                        Text("\(Int(binding.cornerRadius.wrappedValue))").font(.caption).foregroundColor(.secondary)
                    }
                    Slider(value: binding.cornerRadius, in: 0...40, step: 1)
                }
                Toggle(^String.Titles.freeLayoutLockAspect, isOn: binding.aspectRatioLocked).font(.caption)
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("X").font(.caption2).foregroundColor(.secondary)
                        TextField("", value: Binding<Double>(
                            get: { Double(binding.center.wrappedValue.x) },
                            set: { binding.center.wrappedValue.x = CGFloat($0) }
                        ), format: .number)
                            .textFieldStyle(.roundedBorder).font(.caption).frame(width: 70)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Y").font(.caption2).foregroundColor(.secondary)
                        TextField("", value: Binding<Double>(
                            get: { Double(binding.center.wrappedValue.y) },
                            set: { binding.center.wrappedValue.y = CGFloat($0) }
                        ), format: .number)
                            .textFieldStyle(.roundedBorder).font(.caption).frame(width: 70)
                    }
                }
            }

            Divider()

            // Shadow
            sectionHeader(^String.Titles.freeLayoutSectionShadow)
            VStack(alignment: .leading, spacing: 6) {
                Toggle(^String.Titles.freeLayoutShadowEnabled, isOn: binding.shadowEnabled)
                if binding.shadowEnabled.wrappedValue {
                    HStack {
                        Text(^String.Titles.freeLayoutShadowIntensity).font(.caption)
                        Spacer()
                        Text("\(Int(binding.shadowIntensity.wrappedValue * 100))%").font(.caption).foregroundColor(.secondary)
                    }
                    Slider(value: binding.shadowIntensity, in: 0...1, step: 0.05)
                }
            }

            Divider()

            // Z-order
            sectionHeader(^String.Titles.freeLayoutSectionOrder)
            HStack(spacing: 4) {
                Button(action: { sendToBack(id: item.id) }) {
                    Image(systemName: "square.3.layers.3d.bottom.filled")
                }.buttonStyle(.bordered).font(.caption)
                Button(action: { moveBackward(id: item.id) }) {
                    Image(systemName: "chevron.down")
                }.buttonStyle(.bordered).font(.caption)
                Button(action: { moveForward(id: item.id) }) {
                    Image(systemName: "chevron.up")
                }.buttonStyle(.bordered).font(.caption)
                Button(action: { bringToFront(id: item.id) }) {
                    Image(systemName: "square.3.layers.3d.top.filled")
                }.buttonStyle(.bordered).font(.caption)
            }

            Divider()

            // Alignment
            sectionHeader(^String.Titles.freeLayoutSectionAlignment)
            HStack(spacing: 4) {
                Button(^String.Titles.freeLayoutCenterHorizontal) {
                    updateItem(id: item.id) { $0.center.x = layout.canvasWidth / 2 }
                }.font(.caption2).buttonStyle(.bordered)
                Button(^String.Titles.freeLayoutCenterVertical) {
                    updateItem(id: item.id) { $0.center.y = layout.canvasHeight / 2 }
                }.font(.caption2).buttonStyle(.bordered)
            }

            Divider()

            // Remove palette item from canvas
            if item.kind == .label || item.kind == .timeEvent {
                Button(role: .destructive, action: { removePaletteItem(item: item) }) {
                    SwiftUI.Label(^String.Titles.keyBindingsRemoveFromCanvas, systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                Divider()
            }

            sectionHeader(^String.Titles.freeLayoutCanvasSettings)
            Toggle(^String.Titles.freeLayoutShowGrid, isOn: $showGrid).font(.caption)
            Toggle(^String.Titles.freeLayoutSnapToGrid, isOn: $snapToGrid).font(.caption)

            Spacer(minLength: 20)
        }
    }

    // MARK: - Add label to canvas

    private func addLabelToCanvas(_ label: Label) {
        guard !layout.items.contains(where: { $0.elementId == label.id && $0.kind == .label }) else { return }
        // Position below existing items
        let maxY = layout.items.map { $0.center.y + $0.size.height / 2 }.max() ?? 100
        let newItem = TagFreeLayoutItem(
            elementId: label.id,
            kind: .label,
            center: CGPoint(x: layout.canvasWidth / 2, y: maxY + 80),
            size: CGSize(width: 160, height: 55),
            rotation: 0,
            shape: .capsule,
            fillOpacity: 0.85,
            strokeWidth: 1.0,
            fontSize: 12,
            fontWeight: .medium,
            showLabel: true,
            cornerRadius: 8
        )
        layout.items.append(newItem)
    }

    private func addTimeEventToCanvas(_ event: TimeEvent) {
        guard !layout.items.contains(where: { $0.elementId == event.id && $0.kind == .timeEvent }) else { return }
        let maxY = layout.items.map { $0.center.y + $0.size.height / 2 }.max() ?? 100
        let newItem = TagFreeLayoutItem(
            elementId: event.id,
            kind: .timeEvent,
            center: CGPoint(x: layout.canvasWidth / 2, y: maxY + 80),
            size: CGSize(width: 160, height: 55),
            rotation: 0,
            shape: .capsule,
            fillOpacity: 0.85,
            strokeWidth: 1.0,
            fontSize: 12,
            fontWeight: .medium,
            showLabel: true,
            cornerRadius: 8
        )
        layout.items.append(newItem)
    }

    private func itemIcon(for kind: CanvasButtonKind) -> String {
        switch kind {
        case .tag:       return "tag.fill"
        case .label:     return "textformat"
        case .timeEvent: return "clock"
        }
    }

    // MARK: - Panel helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.subheadline).fontWeight(.semibold)
    }

    private func shapePickerGrid(binding: Binding<TagFreeLayoutItem>) -> some View {
        let shapes: [(TagFreeLayoutShape, String)] = [
            (.square, "square"), (.circle, "circle"), (.triangle, "triangle"),
            (.star, "star"), (.diamond, "diamond"), (.hexagon, "hexagon"), (.capsule, "capsule")
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 6) {
            ForEach(shapes, id: \.0) { shape, name in
                Button(action: { binding.shape.wrappedValue = shape }) {
                    TagFreeShapeView(shape: shape, cornerRadius: 4)
                        .fill(binding.shape.wrappedValue == shape ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 32, height: 24)
                        .overlay(
                            TagFreeShapeView(shape: shape, cornerRadius: 4)
                                .stroke(binding.shape.wrappedValue == shape ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .help(name.capitalized)
            }
        }
    }

    private func strokeStyleButton(label: String, dashed: Bool, binding: Binding<Bool>) -> some View {
        Button(label) { binding.wrappedValue = dashed }
            .font(.caption2).buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(binding.wrappedValue == dashed ? Color.accentColor.opacity(0.2) : Color.clear)
            )
    }

    private func fontWeightButton(label: String, weight: TagFreeLayoutFontWeight, binding: Binding<TagFreeLayoutFontWeight>) -> some View {
        let sw: Font.Weight = weight == .bold ? .bold : (weight == .medium ? .medium : .regular)
        return Button(label) { binding.wrappedValue = weight }
            .font(.system(size: 12, weight: sw)).buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(binding.wrappedValue == weight ? Color.accentColor.opacity(0.2) : Color.clear)
            )
    }

    // MARK: - Item mutation

    private func updateItem(id: String, _ update: (inout TagFreeLayoutItem) -> Void) {
        if let idx = layout.items.firstIndex(where: { $0.id == id }) {
            var item = layout.items[idx]; update(&item); layout.items[idx] = item
        }
    }

    private func bringToFront(id: String) {
        if let idx = layout.items.firstIndex(where: { $0.id == id }) {
            let item = layout.items.remove(at: idx); layout.items.append(item)
        }
    }

    private func sendToBack(id: String) {
        if let idx = layout.items.firstIndex(where: { $0.id == id }) {
            let item = layout.items.remove(at: idx); layout.items.insert(item, at: 0)
        }
    }

    private func moveForward(id: String) {
        if let idx = layout.items.firstIndex(where: { $0.id == id }), idx < layout.items.count - 1 {
            layout.items.swapAt(idx, idx + 1)
        }
    }

    private func moveBackward(id: String) {
        if let idx = layout.items.firstIndex(where: { $0.id == id }), idx > 0 {
            layout.items.swapAt(idx, idx - 1)
        }
    }
}

// MARK: - TagFreeShapeView (reused in editor + canvas)

struct TagFreeShapeView: Shape {
    let shape: TagFreeLayoutShape
    var cornerRadius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        switch shape {
        case .square:   return Path(roundedRect: rect, cornerRadius: cornerRadius)
        case .circle:   return Path(ellipseIn: rect)
        case .triangle: return trianglePath(in: rect)
        case .star:     return starPath(in: rect)
        case .diamond:  return diamondPath(in: rect)
        case .hexagon:  return hexagonPath(in: rect)
        case .capsule:  return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
        }
    }

    private func trianglePath(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath(); return p
    }

    private func starPath(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.45
        var p = Path()
        for i in 0..<10 {
            let angle = Double(i) * .pi / 5
            let r = (i % 2 == 0) ? outer : inner
            let pt = CGPoint(x: c.x + CGFloat(cos(angle - .pi / 2)) * r,
                             y: c.y + CGFloat(sin(angle - .pi / 2)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath(); return p
    }

    private func diamondPath(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath(); return p
    }

    private func hexagonPath(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<6 {
            let angle = CGFloat(Double(i) * .pi / 3.0 - .pi / 2.0)
            let pt = CGPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath(); return p
    }
}
