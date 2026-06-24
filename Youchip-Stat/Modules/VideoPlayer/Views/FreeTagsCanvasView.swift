//
//  FreeTagsCanvasView.swift
//  Youchip-Stat
//
//  Отображение тегов и лейблов по свободной раскладке коллекции.
//  Поддерживает режим подсветки связок клавиш.
//

import SwiftUI
import AppKit

struct FreeTagsCanvasView: View {

    let tags: [Tag]
    let labels: [Label]
    let timeEvents: [TimeEvent]
    let onTagTap: (Tag) -> Void
    let onLabelTap: ((Label, Bool) -> Void)?
    let onTimeEventTap: ((TimeEvent) -> Void)?
    let activeIntervalTags: [TagLibraryView.ActiveIntervalTag]
    let hoveredTagID: String?
    let tagCounts: [String: Int]
    @ObservedObject var runtime: KeyBindingRuntimeManager
    var userScale: CGFloat = 1.0

    @State private var layout: TagFreeLayout?
    @State private var fitScale: CGFloat = 1.0

    private var currentCollectionId: String? {
        if case .user(let name) = TagLibraryManager.shared.currentCollectionType {
            return CollectionsBookmarksManager.shared.loadCollections().first(where: { $0.name == name })?.id
        }
        return nil
    }

    var body: some View {
        GeometryReader { geometry in
            let viewportWidth = max(geometry.size.width, 1)
            let availableHeight = max(geometry.size.height, 1)
            let effectiveLayout = layout ?? TagFreeLayoutStorage.makeDefaultLayout(for: tags)
            let layoutKey = makeLayoutKey(for: effectiveLayout)
            let scale = fitScale * userScale
            let canvasWidth = effectiveLayout.canvasWidth * scale
            let canvasHeight = effectiveLayout.canvasHeight * scale

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .frame(width: canvasWidth, height: canvasHeight)
                                .allowsHitTesting(false)

                            ForEach(effectiveLayout.items) { item in
                                if isVisible(item: item) {
                                    let viewWidth = item.size.width * scale
                                    let viewHeight = item.size.height * scale
                                    let isHighlighted = runtime.highlightModeActive
                                        && runtime.highlightedButtonIds.contains(item.id)

                                    runtimeItemView(item: item, scale: scale, isHighlighted: isHighlighted)
                                        .frame(width: viewWidth, height: viewHeight)
                                        .offset(
                                            x: item.center.x * scale - viewWidth / 2,
                                            y: item.center.y * scale - viewHeight / 2
                                        )
                                        .zIndex(canvasZIndex(for: item, isHighlighted: isHighlighted))
                                }
                            }
                        }
                        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)

                        Spacer(minLength: 0)
                    }
                    .frame(minWidth: viewportWidth, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .frame(minHeight: availableHeight, alignment: .top)
            }
            .frame(width: viewportWidth, height: availableHeight)
            .onAppear {
                loadLayoutIfNeeded()
                syncFitScale(
                    layoutKey: layoutKey,
                    viewportWidth: viewportWidth,
                    availableHeight: availableHeight,
                    layout: effectiveLayout
                )
            }
            .onChange(of: currentCollectionId) { _ in
                loadLayoutIfNeeded()
            }
            .onChange(of: layoutKey) { newKey in
                syncFitScale(
                    layoutKey: newKey,
                    viewportWidth: viewportWidth,
                    availableHeight: availableHeight,
                    layout: effectiveLayout
                )
            }
            .onChange(of: geometry.size.width) { newWidth in
                captureInitialFitScaleIfNeeded(
                    layoutKey: layoutKey,
                    viewportWidth: max(newWidth, 1),
                    availableHeight: max(geometry.size.height, 1),
                    layout: effectiveLayout
                )
            }
            .onChange(of: geometry.size.height) { newHeight in
                captureInitialFitScaleIfNeeded(
                    layoutKey: layoutKey,
                    viewportWidth: max(geometry.size.width, 1),
                    availableHeight: max(newHeight, 1),
                    layout: effectiveLayout
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func currentProjectId() -> String {
        TimelineDataManager.shared.currentVideoId
            ?? WindowsManager.shared.currentVideoId
            ?? ""
    }

    private func makeLayoutKey(for layout: TagFreeLayout) -> String {
        TagLibraryFreeLayoutFitStore.shared.makeLayoutKey(
            projectId: currentProjectId(),
            collectionId: currentCollectionId ?? "none",
            layout: layout
        )
    }

    private func syncFitScale(
        layoutKey: String,
        viewportWidth: CGFloat,
        availableHeight: CGFloat,
        layout: TagFreeLayout
    ) {
        let store = TagLibraryFreeLayoutFitStore.shared
        store.resetForProject(currentProjectId())

        if let cached = store.fitScale(for: layoutKey) {
            fitScale = cached
            return
        }

        captureInitialFitScaleIfNeeded(
            layoutKey: layoutKey,
            viewportWidth: viewportWidth,
            availableHeight: availableHeight,
            layout: layout
        )
    }

    /// Сохраняет fit только если ещё нет в кэше (открытие проекта / смена коллекции).
    private func captureInitialFitScaleIfNeeded(
        layoutKey: String,
        viewportWidth: CGFloat,
        availableHeight: CGFloat,
        layout: TagFreeLayout
    ) {
        let store = TagLibraryFreeLayoutFitStore.shared
        guard store.fitScale(for: layoutKey) == nil else {
            fitScale = store.fitScale(for: layoutKey) ?? fitScale
            return
        }
        guard viewportWidth > 1, availableHeight > 1 else { return }

        let computed = min(
            viewportWidth / max(layout.canvasWidth, 1),
            availableHeight / max(layout.canvasHeight, 1)
        )
        store.storeFitScale(computed, for: layoutKey)
        fitScale = computed
    }

    // MARK: - Visibility check

    private func isVisible(item: TagFreeLayoutItem) -> Bool {
        // Runtime override wins over item.isVisible
        let key = item.id
        if let override = runtime.runtimeVisibility[key] { return override }
        return item.isVisible
    }

    // MARK: - Item view dispatch

    private func canvasZIndex(for item: TagFreeLayoutItem, isHighlighted: Bool) -> Double {
        if isHighlighted { return 100 }
        switch item.kind {
        case .label: return 30
        case .timeEvent: return 20
        case .tag: return 10
        }
    }

    @ViewBuilder
    private func runtimeItemView(item: TagFreeLayoutItem, scale: CGFloat, isHighlighted: Bool) -> some View {
        let buttonKey = item.id

        switch item.kind {
        case .tag:
            if let tag = tags.first(where: { $0.id == item.elementId }) {
                FreeTagRuntimeItemView(
                    tag: tag,
                    item: item,
                    isActive: activeIntervalTags.contains(where: { $0.tag.id == tag.id }),
                    isHovered: hoveredTagID == tag.id,
                    isHighlighted: isHighlighted,
                    tagCount: tagCounts[tag.id] ?? 0,
                    onTap: {
                        runtime.applyRevertVisibilityIfNeeded(for: buttonKey)
                        onTagTap(tag)
                    }
                )
            }

        case .label:
            if let label = labels.first(where: { $0.id == item.elementId }) {
                FreeLabelRuntimeItemView(
                    label: label,
                    item: item,
                    isHighlighted: isHighlighted,
                    isSelected: runtime.isLabelActivated(label.id),
                    onTap: {
                        runtime.applyRevertVisibilityIfNeeded(for: buttonKey)
                        let commandPressed = NSEvent.modifierFlags.contains(.command)
                        onLabelTap?(label, commandPressed)
                    }
                )
            }

        case .timeEvent:
            if let event = timeEvents.first(where: { $0.id == item.elementId }) {
                FreeTimeEventRuntimeItemView(
                    event: event,
                    item: item,
                    isHighlighted: isHighlighted,
                    isSelected: runtime.pendingTimeEventIds.contains(event.id),
                    onTap: {
                        runtime.applyRevertVisibilityIfNeeded(for: buttonKey)
                        onTimeEventTap?(event)
                    }
                )
            }
        }
    }

    // MARK: - Load layout

    private func loadLayoutIfNeeded() {
        guard let collectionId = currentCollectionId else { return }
        if let stored = TagFreeLayoutStorage.loadLayoutIfExists(
            collectionId: collectionId, tags: tags, labels: labels, timeEvents: timeEvents
        ) {
            layout = stored
            runtime.configure(layout: stored)
        } else {
            let def = TagFreeLayoutStorage.makeDefaultLayout(for: tags)
            layout = def
            runtime.configure(layout: def)
        }
    }
}

// MARK: - Tag runtime item

private struct FreeTagRuntimeItemView: View {
    let tag: Tag
    let item: TagFreeLayoutItem
    let isActive: Bool
    let isHovered: Bool
    let isHighlighted: Bool
    let tagCount: Int
    let onTap: () -> Void

    var body: some View {
        let baseColor = Color(hex: tag.color).opacity(item.fillOpacity)
        let foreground: Color = {
            if let hex = item.textColor { return Color(hex: hex) }
            return Color(hex: tag.color).isDark ? .white : .black
        }()
        let strokeCol: Color = {
            if isHighlighted { return Color.yellow }
            if isActive { return Color.accentColor }
            if isHovered { return Color.accentColor.opacity(0.6) }
            if let hex = item.strokeColor { return Color(hex: hex) }
            return Color.black.opacity(0.25)
        }()
        let strokeStyle = StrokeStyle(
            lineWidth: isActive || isHighlighted ? 2.5 : item.strokeWidth,
            dash: item.strokeDashed ? [4, 3] : []
        )
        let swiftWeight: Font.Weight = {
            if isActive { return .semibold }
            switch item.fontWeight {
            case .regular: return .regular
            case .medium: return .medium
            case .bold: return .bold
            }
        }()

        ZStack {
            TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius)
                .fill(baseColor)
                .overlay(
                    TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius)
                        .stroke(strokeCol, style: strokeStyle)
                )

            if item.showLabel {
                VStack(spacing: 2) {
                    Text(tag.name)
                        .font(.system(size: item.fontSize, weight: swiftWeight))
                        .foregroundColor(foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)

                    HStack(spacing: 4) {
                        if tagCount > 0 {
                            Text("\(tagCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(foreground)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(Color.black.opacity(0.25)))
                        }
                        if tag.isInterval == true {
                            Image(systemName: "timer")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(foreground.opacity(0.9))
                        }
                        if tag.mapEnabled == true {
                            Image(systemName: "map")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(foreground.opacity(0.9))
                        }
                        if let hotkey = tag.hotkey, !hotkey.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "keyboard").font(.system(size: 9, weight: .medium))
                                Text(hotkey).font(.system(size: 9, weight: .medium))
                            }
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Capsule().fill(Color.black.opacity(0.25)))
                            .foregroundColor(foreground)
                        }
                    }
                }
                .padding(4)
            }
        }
        .shadow(
            color: item.shadowEnabled ? Color.black.opacity(item.shadowIntensity * 0.3) : .clear,
            radius: item.shadowEnabled ? (isHovered || isActive || isHighlighted ? 6 : 3) : 0,
            x: 0, y: item.shadowEnabled ? 2 : 0
        )
        .rotationEffect(.degrees(item.rotation))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Label runtime item

private struct FreeLabelRuntimeItemView: View {
    let label: Label
    let item: TagFreeLayoutItem
    let isHighlighted: Bool
    var isSelected: Bool = false
    let onTap: () -> Void

    var body: some View {
        let strokeCol: Color = {
            if isHighlighted { return .yellow }
            if isSelected { return .accentColor }
            return item.strokeColor.map { Color(hex: $0) } ?? Color.secondary.opacity(0.3)
        }()
        let strokeStyle = StrokeStyle(
            lineWidth: isHighlighted ? 2.5 : item.strokeWidth,
            dash: item.strokeDashed ? [4, 3] : []
        )
        let textCol: Color = item.textColor.map { Color(hex: $0) } ?? .primary

        Button(action: onTap) {
            ZStack {
                TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(item.fillOpacity))
                    .overlay(
                        TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius)
                            .stroke(strokeCol, style: strokeStyle)
                    )

                if item.showLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(textCol.opacity(0.6))
                        Text(label.name)
                            .font(.system(size: item.fontSize))
                            .foregroundColor(textCol)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(4)
                }
            }
            .shadow(
                color: item.shadowEnabled ? Color.black.opacity(item.shadowIntensity * 0.2) : .clear,
                radius: item.shadowEnabled ? (isHighlighted ? 6 : 3) : 0,
                x: 0, y: item.shadowEnabled ? 1 : 0
            )
            .rotationEffect(.degrees(item.rotation))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Time event runtime item

private struct FreeTimeEventRuntimeItemView: View {
    let event: TimeEvent
    let item: TagFreeLayoutItem
    let isHighlighted: Bool
    var isSelected: Bool = false
    let onTap: () -> Void

    var body: some View {
        let strokeCol: Color = {
            if isHighlighted { return .yellow }
            if isSelected { return .accentColor }
            return item.strokeColor.map { Color(hex: $0) } ?? Color.secondary.opacity(0.3)
        }()
        let strokeStyle = StrokeStyle(
            lineWidth: isHighlighted || isSelected ? 2.5 : item.strokeWidth,
            dash: item.strokeDashed ? [4, 3] : []
        )
        let textCol: Color = item.textColor.map { Color(hex: $0) } ?? .primary

        ZStack {
            TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius)
                .fill(Color.orange.opacity(item.fillOpacity * 0.15))
                .overlay(
                    TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius)
                        .stroke(strokeCol, style: strokeStyle)
                )

            if item.showLabel {
                HStack(spacing: 4) {
                    Image(systemName: isSelected ? "clock.fill" : "clock")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isSelected ? .accentColor : textCol.opacity(0.7))
                    Text(event.name)
                        .font(.system(size: item.fontSize, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(textCol)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                }
                .padding(4)
            }
        }
        .shadow(
            color: item.shadowEnabled ? Color.black.opacity(item.shadowIntensity * 0.2) : .clear,
            radius: item.shadowEnabled ? (isHighlighted || isSelected ? 6 : 3) : 0,
            x: 0, y: item.shadowEnabled ? 1 : 0
        )
        .rotationEffect(.degrees(item.rotation))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
