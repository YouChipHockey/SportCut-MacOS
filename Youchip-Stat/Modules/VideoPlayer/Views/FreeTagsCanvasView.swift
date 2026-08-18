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
    var playFields: [PlayField] = []
    let onTagTap: (Tag) -> Void
    let onLabelTap: ((Label, Bool) -> Void)?
    let onTimeEventTap: ((TimeEvent) -> Void)?
    /// Клик по зоне карты: id карты + нормализованная точка (0…1). Ставит позицию тегу.
    var onMapTap: ((_ fieldId: String, _ normalized: CGPoint) -> Void)? = nil
    var clocks: [ClockEntity] = []
    /// Клик по счётчику: старт/стоп (как активация интервального тега).
    var onClockTap: ((ClockEntity) -> Void)? = nil
    /// Ctrl+ЛКМ / ПКМ по кнопке: жест «сброс» — отрабатывают только связки сброса этой кнопки.
    var onResetTap: ((_ kind: CanvasButtonKind, _ elementId: String) -> Void)? = nil
    let activeIntervalTags: [TagLibraryView.ActiveIntervalTag]
    let hoveredTagID: String?
    let tagCounts: [String: Int]
    @ObservedObject var runtime: KeyBindingRuntimeManager
    var userScale: CGFloat = 1.0
    /// Показ связок: под/над кнопками — включён, скрыто — выключен.
    var arrowVisibility: KeyBindingArrowVisibility = .hidden

    @State private var layout: TagFreeLayout?
    @State private var fitScale: CGFloat = 1.0
    /// Составной ключ кнопки ("kind:id"), для которой показываются стрелки связок.
    @State private var selectedBindingButtonKey: String? = nil
    /// Карты, подгруженные самим канвасом — на случай, когда родитель ещё не закешировал их
    /// (например при открытии проекта): иначе инлайн-карта не рисуется до захода в редактор.
    @State private var selfLoadedPlayFields: [PlayField] = []
    /// То же для счётчиков: при открытии проекта кэш родителя пуст, и без своей подгрузки
    /// секундомеры/таймеры не рисовались до ручного переключения коллекции.
    @State private var selfLoadedClocks: [ClockEntity] = []
    // Ручной pan + зум к курсору (вместо ScrollView) — чтобы приближение шло к мыши, а не в угол.
    @State private var panOffset: CGSize = .zero
    @State private var hoverInViewport: CGPoint? = nil
    /// Последний ПОЛЬЗОВАТЕЛЬСКИЙ зум (userScale). Зум-к-курсору реагирует только на него,
    /// а не на изменения base-fit при ресайзе окна — иначе при первом открытии, когда
    /// геометрия «доезжает» до реального размера, контент улетал в угол.
    @State private var lastUserScale: CGFloat = 0
    @State private var scrollMonitor: Any? = nil

    /// Режим показа связок включён (стрелки под или над кнопками).
    private var showBindingsMode: Bool { arrowVisibility != .hidden }

    /// Карты для отрисовки: приоритет — переданные родителем, иначе подгруженные самим канвасом.
    private var effectivePlayFields: [PlayField] {
        !playFields.isEmpty ? playFields : selfLoadedPlayFields
    }

    /// Счётчики для отрисовки: приоритет — переданные родителем, иначе подгруженные самим канвасом.
    private var effectiveClocks: [ClockEntity] {
        !clocks.isEmpty ? clocks : selfLoadedClocks
    }

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
            // Библиотека ограничена итоговыми размерами/краями контента (в отличие от бесконечного редактора).
            let content = contentRect(of: effectiveLayout)
            let origin = CGPoint(x: content.minX, y: content.minY)
            // Базовый fit считаем реактивно от ТЕКУЩЕГО вьюпорта и контента — так весь холст
            // всегда помещается целиком, независимо от того, как был зумлен холст в редакторе.
            let baseFit = min(viewportWidth / max(content.width, 1), availableHeight / max(content.height, 1))
            let scale = baseFit * userScale
            let canvasWidth = content.width * scale
            let canvasHeight = content.height * scale

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    // В режиме показа связок фон холста снимает выделение по нажатию.
                    if showBindingsMode {
                        Color.clear
                            .frame(width: canvasWidth, height: canvasHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedBindingButtonKey = nil }
                            .zIndex(0)
                    } else {
                        Color.clear
                            .frame(width: canvasWidth, height: canvasHeight)
                            .allowsHitTesting(false)
                    }

                    ForEach(effectiveLayout.items) { item in
                        if isVisible(item: item) {
                            let viewWidth = item.size.width * scale
                            let viewHeight = item.size.height * scale
                            let isHighlighted = runtime.highlightModeActive
                                && runtime.highlightedButtonIds.contains(item.id)

                            runtimeItemView(item: item, scale: scale, isHighlighted: isHighlighted)
                                .frame(width: viewWidth, height: viewHeight)
                                // Ctrl+ЛКМ (он же вторичный клик) — жест «сброс». Ловим слоем
                                // поверх: обычный tap-gesture вторичное нажатие не видит.
                                .onSecondaryClick(enabled: needsSecondaryClick(in: effectiveLayout)) {
                                    onResetTap?(item.kind, item.elementId)
                                }
                                .offset(
                                    x: (item.center.x - origin.x) * scale - viewWidth / 2,
                                    y: (item.center.y - origin.y) * scale - viewHeight / 2
                                )
                                .zIndex(canvasZIndex(for: item, isHighlighted: isHighlighted))
                        }
                    }

                    // Стрелки связок выбранной кнопки, без хит-теста.
                    if showBindingsMode, let focus = selectedBindingButtonKey {
                        KeyBindingArrowLinesOverlay(
                            layout: effectiveLayout,
                            scale: scale,
                            origin: origin,
                            canvasPixelWidth: canvasWidth,
                            canvasPixelHeight: canvasHeight,
                            selectedGroupKey: nil,
                            focusedSourceKey: focus
                        )
                        .zIndex(arrowVisibility == .below ? 1 : 500)
                    }
                }
                .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
                .offset(x: panOffset.width, y: panOffset.height)
            }
            .frame(width: viewportWidth, height: availableHeight, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .modifier(CanvasHoverTracker { p in hoverInViewport = p })
            // Зум к курсору: реагируем ТОЛЬКО на пользовательский зум (пинч/слайдер), т.е. на
            // userScale. При ресайзе окна меняется base-fit (и `scale`), но пользовательский зум
            // прежний — тогда контент остаётся прижат к левому верхнему углу, а не улетает в угол.
            .onChange(of: userScale) { newUserScale in
                guard lastUserScale > 0 else { lastUserScale = newUserScale; return }
                let ratio = newUserScale / lastUserScale
                let pivot = hoverInViewport ?? CGPoint(x: viewportWidth / 2, y: availableHeight / 2)
                panOffset = CGSize(
                    width: pivot.x - (pivot.x - panOffset.width) * ratio,
                    height: pivot.y - (pivot.y - panOffset.height) * ratio
                )
                lastUserScale = newUserScale
            }
            .onAppear {
                loadLayoutIfNeeded()
                syncFitScale(
                    layoutKey: layoutKey,
                    viewportWidth: viewportWidth,
                    availableHeight: availableHeight,
                    layout: effectiveLayout
                )
                lastUserScale = userScale
                // Открываем коллекцию в левом верхнем углу — пользователь сам подвинет/приблизит.
                panOffset = .zero
                installScrollMonitor()
            }
            .onDisappear { removeScrollMonitor() }
            .onChange(of: currentCollectionId) { _ in
                loadLayoutIfNeeded()
                selectedBindingButtonKey = nil
            }
            .onChange(of: arrowVisibility) { mode in
                if mode == .hidden { selectedBindingButtonKey = nil }
            }
            .onChange(of: layoutKey) { newKey in
                syncFitScale(
                    layoutKey: newKey,
                    viewportWidth: viewportWidth,
                    availableHeight: availableHeight,
                    layout: effectiveLayout
                )
                // Новая раскладка/коллекция — показываем от левого верхнего угла.
                lastUserScale = userScale
                panOffset = .zero
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

    /// Прямоугольник контента раскладки строго по краям объектов (без лишнего пустого места).
    /// Библиотека показывает только его: от самого левого до самого правого, от верхнего до нижнего.
    private func contentRect(of layout: TagFreeLayout) -> CGRect {
        layout.contentRect(padding: 0)
            ?? CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight)
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

        let content = contentRect(of: layout)
        let computed = min(
            viewportWidth / max(content.width, 1),
            availableHeight / max(content.height, 1)
        )
        store.storeFitScale(computed, for: layoutKey)
        fitScale = computed
    }

    /// Нужен ли холсту перехват вторичного клика. Гранулярность намеренно грубая — на всю
    /// раскладку, а не на конкретную кнопку: сопоставлять ключи кнопки со связками здесь значит
    /// продублировать логику движка и молча потерять жест при любом расхождении. Решение о том,
    /// что сбрасывать, принимает `KeyBindingRuntimeManager.handleResetTap`.
    private func needsSecondaryClick(in layout: TagFreeLayout) -> Bool {
        layout.items.contains { $0.kind == .clock } || layout.bindings.contains { $0.type == .clockReset }
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
        case .map: return 1   // карта — фон-зона под кнопками
        case .clock: return 25
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
                    scale: scale,
                    isActive: activeIntervalTags.contains(where: { $0.tag.id == tag.id }),
                    isHovered: hoveredTagID == tag.id,
                    isHighlighted: isHighlighted,
                    tagCount: tagCounts[tag.id] ?? 0,
                    onTap: {
                        if showBindingsMode {
                            toggleBindingSelection(buttonKey)
                            return
                        }
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
                    scale: scale,
                    isHighlighted: isHighlighted,
                    isSelected: runtime.isLabelActivated(label.id),
                    onTap: {
                        if showBindingsMode {
                            toggleBindingSelection(buttonKey)
                            return
                        }
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
                    scale: scale,
                    isHighlighted: isHighlighted,
                    isSelected: runtime.pendingTimeEventIds.contains(event.id),
                    onTap: {
                        if showBindingsMode {
                            toggleBindingSelection(buttonKey)
                            return
                        }
                        runtime.applyRevertVisibilityIfNeeded(for: buttonKey)
                        onTimeEventTap?(event)
                    }
                )
            }

        case .map:
            if let field = effectivePlayFields.first(where: { $0.id == item.elementId }) {
                FreeMapRuntimeItemView(
                    field: field,
                    item: item,
                    scale: scale,
                    isHighlighted: isHighlighted,
                    showBindingsMode: showBindingsMode,
                    onSelectBinding: { toggleBindingSelection(buttonKey) },
                    onPick: { normalized in
                        runtime.applyRevertVisibilityIfNeeded(for: buttonKey)
                        onMapTap?(field.id, normalized)
                    }
                )
            }

        case .clock:
            if let clock = effectiveClocks.first(where: { $0.id == item.elementId }) {
                FreeClockRuntimeItemView(
                    clock: clock,
                    item: item,
                    scale: scale,
                    isHighlighted: isHighlighted,
                    showBindingsMode: showBindingsMode,
                    onSelectBinding: { toggleBindingSelection(buttonKey) },
                    onTap: {
                        runtime.applyRevertVisibilityIfNeeded(for: buttonKey)
                        onClockTap?(clock)
                    }
                )
            }
        }
    }

    /// Переключает выбор кнопки в режиме показа связок (повторное нажатие снимает выбор).
    private func toggleBindingSelection(_ key: String) {
        selectedBindingButtonKey = (selectedBindingButtonKey == key) ? nil : key
    }

    /// Панорама холста двухпальцевым скроллом, когда курсор над холстом.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard hoverInViewport != nil else { return event }
            panOffset.width += event.scrollingDeltaX
            panOffset.height += event.scrollingDeltaY
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
    }

    /// Асинхронно подгружает карты/счётчики текущей коллекции, когда родитель их ещё не передал
    /// (типовой случай — только что открытый проект: кэш в `TagLibraryView` ещё пуст).
    /// Счётчики заодно регистрируем в рантайме — без регистрации кнопка не запускается.
    private func loadSelfCollectionAssetsIfNeeded(needsFields: Bool, needsClocks: Bool) {
        guard needsFields || needsClocks,
              case .user(let name) = TagLibraryManager.shared.currentCollectionType else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = CustomCollectionManager()
            guard manager.loadCollectionFromBookmarks(named: name) else { return }
            let fields = manager.playFields
            let loadedClocks = manager.clocks
            DispatchQueue.main.async {
                if needsFields, !fields.isEmpty { selfLoadedPlayFields = fields }
                if needsClocks, !loadedClocks.isEmpty {
                    selfLoadedClocks = loadedClocks
                    ClockRuntimeManager.shared.register(loadedClocks)
                }
            }
        }
    }

    // MARK: - Load layout

    private func loadLayoutIfNeeded() {
        guard let collectionId = currentCollectionId else { return }
        if let stored = TagFreeLayoutStorage.loadLayoutIfExists(
            collectionId: collectionId, tags: tags, labels: labels, timeEvents: timeEvents, playFields: playFields
        ) {
            layout = stored
            runtime.configure(layout: stored, collectionId: collectionId)
            // Родитель мог ещё не закешировать карты/счётчики (при открытии проекта) — подгружаем сами.
            loadSelfCollectionAssetsIfNeeded(
                needsFields: playFields.isEmpty && stored.items.contains(where: { $0.kind == .map }),
                needsClocks: clocks.isEmpty && stored.items.contains(where: { $0.kind == .clock })
            )
        } else {
            let def = TagFreeLayoutStorage.makeDefaultLayout(for: tags)
            layout = def
            runtime.configure(layout: def)
        }
    }
}

/// Отслеживает курсор внутри канваса библиотеки (для зума к курсору). macOS 13+; на 12 — no-op.
private struct CanvasHoverTracker: ViewModifier {
    let onMove: (CGPoint?) -> Void
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p): onMove(p)
                case .ended: onMove(nil)
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Tag runtime item

private struct FreeTagRuntimeItemView: View {
    let tag: Tag
    let item: TagFreeLayoutItem
    var scale: CGFloat = 1.0
    let isActive: Bool
    let isHovered: Bool
    let isHighlighted: Bool
    let tagCount: Int
    let onTap: () -> Void

    /// Пульсация включается только для записи интервального тега — чтобы его было
    /// видно среди множества кнопок. Обычная активность подсвечивается без пульсации.
    @State private var pulsing = false
    private var shouldPulse: Bool { isActive && tag.isInterval == true }

    var body: some View {
        let s = max(scale, 0.01)
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
            lineWidth: (isActive || isHighlighted ? 2.5 : item.strokeWidth) * s,
            dash: item.strokeDashed ? [4 * s, 3 * s] : []
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
            TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius * s)
                .fill(baseColor)
                // Фон-картинка кнопки (если задана пользователем).
                .overlay(
                    Group {
                        if let bm = item.backgroundImageBookmark, let img = PlayFieldImageCache.shared.image(forBookmark: bm) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: item.size.width * s, height: item.size.height * s)
                                .clipShape(TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius * s))
                        }
                    }
                )
                // Синяя подсветка активной (записываемой) кнопки поверх заливки.
                .overlay(
                    TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius * s)
                        .fill(Color.accentColor.opacity(isActive ? 0.28 : 0))
                )
                .overlay(
                    TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius * s)
                        .stroke(strokeCol, style: strokeStyle)
                )

            if item.showLabel {
                VStack(spacing: 2 * s) {
                    Text(tag.name)
                        .font(.system(size: item.fontSize * s, weight: swiftWeight))
                        .foregroundColor(foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)

                    HStack(spacing: 4 * s) {
                        if tagCount > 0 {
                            Text("\(tagCount)")
                                .font(.system(size: 10 * s, weight: .semibold))
                                .foregroundColor(foreground)
                                .padding(.horizontal, 4 * s).padding(.vertical, 1 * s)
                                .background(Capsule().fill(Color.black.opacity(0.25)))
                        }
                        if tag.isInterval == true {
                            Image(systemName: "timer")
                                .font(.system(size: 10 * s, weight: .medium))
                                .foregroundColor(foreground.opacity(0.9))
                        }
                        if tag.mapEnabled == true {
                            Image(systemName: "map")
                                .font(.system(size: 10 * s, weight: .medium))
                                .foregroundColor(foreground.opacity(0.9))
                        }
                        if let hotkey = tag.hotkey, !hotkey.isEmpty {
                            HStack(spacing: 3 * s) {
                                Image(systemName: "keyboard").font(.system(size: 9 * s, weight: .medium))
                                Text(hotkey).font(.system(size: 9 * s, weight: .medium))
                            }
                            .padding(.horizontal, 3 * s).padding(.vertical, 1 * s)
                            .background(Capsule().fill(Color.black.opacity(0.25)))
                            .foregroundColor(foreground)
                        }
                    }
                }
                .padding(4 * s)
            }
        }
        .shadow(
            color: item.shadowEnabled ? Color.black.opacity(item.shadowIntensity * 0.3) : .clear,
            radius: item.shadowEnabled ? (isHovered || isActive || isHighlighted ? 6 : 3) : 0,
            x: 0, y: item.shadowEnabled ? 2 : 0
        )
        // Пульсирует сам тег: масштаб + синее свечение (не обводка). Визуал завязан
        // ТОЛЬКО на `pulsing` — тогда конечная анимация остановки полностью им управляет
        // и repeatForever гарантированно гасится (иначе тег «дрыгается» после записи).
        .shadow(
            color: pulsing ? Color.accentColor.opacity(0.9) : .clear,
            radius: pulsing ? 14 * s : 0
        )
        .scaleEffect(pulsing ? 1.06 : 1.0)
        .rotationEffect(.degrees(item.rotation))
        .contentShape(Rectangle())
        // Не `.onTapGesture`: он теряет первый клик по неактивному окну (нужно было сначала
        // «взять фокус», потом нажать). Ловим нажатие AppKit-слоем — см. FirstMouseHosting.
        .onFirstMouseTap { onTap() }
        .pointingHandCursor()
        .onAppear { updatePulsing(shouldPulse) }
        .onChange(of: shouldPulse) { updatePulsing($0) }
    }

    /// Явно запускает/останавливает пульсацию. Старт — бесконечная анимация,
    /// стоп — конечная, чтобы repeatForever не «зависал» и тег вернулся в покой.
    private func updatePulsing(_ active: Bool) {
        if active {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                pulsing = false
            }
        }
    }
}

// MARK: - Label runtime item

private struct FreeLabelRuntimeItemView: View {
    let label: Label
    let item: TagFreeLayoutItem
    var scale: CGFloat = 1.0
    let isHighlighted: Bool
    var isSelected: Bool = false
    let onTap: () -> Void

    var body: some View {
        let s = max(scale, 0.01)
        let strokeCol: Color = {
            if isHighlighted { return .yellow }
            if isSelected { return .accentColor }
            return item.strokeColor.map { Color(hex: $0) } ?? Color.secondary.opacity(0.3)
        }()
        let strokeStyle = StrokeStyle(
            lineWidth: (isHighlighted ? 2.5 : item.strokeWidth) * s,
            dash: item.strokeDashed ? [4 * s, 3 * s] : []
        )
        let textCol: Color = item.textColor.map { Color(hex: $0) } ?? .primary

        Button(action: onTap) {
            ZStack {
                TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius * s)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(item.fillOpacity))
                    .overlay(
                        TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius * s)
                            .stroke(strokeCol, style: strokeStyle)
                    )

                if item.showLabel {
                    HStack(spacing: 4 * s) {
                        Image(systemName: "textformat")
                            .font(.system(size: 9 * s, weight: .medium))
                            .foregroundColor(textCol.opacity(0.6))
                        Text(label.name)
                            .font(.system(size: item.fontSize * s))
                            .foregroundColor(textCol)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(4 * s)
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
        .pointingHandCursor()
    }
}

// MARK: - Time event runtime item

private struct FreeTimeEventRuntimeItemView: View {
    let event: TimeEvent
    let item: TagFreeLayoutItem
    var scale: CGFloat = 1.0
    let isHighlighted: Bool
    var isSelected: Bool = false
    let onTap: () -> Void

    var body: some View {
        let s = max(scale, 0.01)
        let strokeCol: Color = {
            if isHighlighted { return .yellow }
            if isSelected { return .accentColor }
            return item.strokeColor.map { Color(hex: $0) } ?? Color.secondary.opacity(0.3)
        }()
        let strokeStyle = StrokeStyle(
            lineWidth: (isHighlighted || isSelected ? 2.5 : item.strokeWidth) * s,
            dash: item.strokeDashed ? [4 * s, 3 * s] : []
        )
        let textCol: Color = item.textColor.map { Color(hex: $0) } ?? .primary

        ZStack {
            TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius * s)
                .fill(Color.orange.opacity(item.fillOpacity * 0.15))
                .overlay(
                    TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius * s)
                        .stroke(strokeCol, style: strokeStyle)
                )

            if item.showLabel {
                HStack(spacing: 4 * s) {
                    Image(systemName: isSelected ? "clock.fill" : "clock")
                        .font(.system(size: 9 * s, weight: .medium))
                        .foregroundColor(isSelected ? .accentColor : textCol.opacity(0.7))
                    Text(event.name)
                        .font(.system(size: item.fontSize * s, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(textCol)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                }
                .padding(4 * s)
            }
        }
        .shadow(
            color: item.shadowEnabled ? Color.black.opacity(item.shadowIntensity * 0.2) : .clear,
            radius: item.shadowEnabled ? (isHighlighted || isSelected ? 6 : 3) : 0,
            x: 0, y: item.shadowEnabled ? 1 : 0
        )
        .rotationEffect(.degrees(item.rotation))
        .contentShape(Rectangle())
        .onFirstMouseTap { onTap() }
        .pointingHandCursor()
    }
}

// MARK: - Map runtime item (zone)

/// Карта прямо на холсте: зона-изображение. Клик по точке ставит на карте временну́ю
/// точку (гаснет за ~3с) и через onPick передаёт нормализованные координаты — как у карты
/// в отдельном окне, но встроено в раскладку.
private struct FreeMapRuntimeItemView: View {
    let field: PlayField
    let item: TagFreeLayoutItem
    var scale: CGFloat = 1.0
    let isHighlighted: Bool
    let showBindingsMode: Bool
    let onSelectBinding: () -> Void
    let onPick: (_ normalized: CGPoint) -> Void

    @State private var pointNormalized: CGPoint? = nil
    @State private var pointOpacity: Double = 0

    var body: some View {
        let s = max(scale, 0.01)
        let cr = item.cornerRadius * s
        let w = item.size.width * s
        let h = item.size.height * s
        let strokeCol: Color = isHighlighted ? .yellow : (item.strokeColor.map { Color(hex: $0) } ?? Color.secondary.opacity(0.4))

        ZStack {
            Group {
                if let img = PlayFieldImageCache.shared.image(for: field) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(NSColor.controlBackgroundColor)
                        .overlay(Image(systemName: "map").font(.system(size: 24 * s)).foregroundColor(.secondary))
                }
            }
            .frame(width: w, height: h)
            .clipShape(TagFreeShapeView(shape: item.shape, cornerRadius: cr))

            // Временна́я точка на карте — фиксированного размера, чтобы всегда была видна.
            if let p = pointNormalized {
                let dot: CGFloat = 26
                ZStack {
                    Circle().fill(Color.red).frame(width: dot, height: dot)
                    Circle().stroke(Color.white, lineWidth: 3).frame(width: dot, height: dot)
                }
                .position(x: p.x * w, y: p.y * h)
                .opacity(pointOpacity)
                .allowsHitTesting(false)
            }
        }
        .frame(width: w, height: h)
        .overlay(
            TagFreeShapeView(shape: item.shape, cornerRadius: cr)
                .stroke(strokeCol, lineWidth: (isHighlighted ? 2.5 : item.strokeWidth) * s)
        )
        .rotationEffect(.degrees(item.rotation))
        .contentShape(Rectangle())
        // Клик по зоне: важно КУДА нажали, а не сам факт. `DragGesture` здесь терял первый
        // клик по неактивному окну — ловим нажатие AppKit-слоем (см. FirstMouseHosting).
        .onFirstMouseTap(location: { point in
            if showBindingsMode { onSelectBinding(); return }
            guard w > 0, h > 0,
                  point.x >= 0, point.x <= w,
                  point.y >= 0, point.y <= h else { return }
            let norm = CGPoint(x: point.x / w, y: point.y / h)
            showTransientPoint(norm)
            onPick(norm)
        })
    }

    private func showTransientPoint(_ norm: CGPoint) {
        pointNormalized = norm
        withAnimation(.easeIn(duration: 0.1)) { pointOpacity = 1 }
        // Держим ~3 секунды, затем плавно гасим.
        withAnimation(.easeOut(duration: 0.6).delay(2.4)) { pointOpacity = 0 }
    }
}

// MARK: - Clock runtime item (секундомер / таймер)

/// Живой счётчик на холсте библиотеки: показывает текущее время из ClockRuntimeManager,
/// клик = старт/стоп (как активация интервального тега). Активный — подсвечен рамкой.
private struct FreeClockRuntimeItemView: View {
    let clock: ClockEntity
    let item: TagFreeLayoutItem
    var scale: CGFloat = 1.0
    let isHighlighted: Bool
    let showBindingsMode: Bool
    let onSelectBinding: () -> Void
    let onTap: () -> Void

    @ObservedObject private var runtime = ClockRuntimeManager.shared

    var body: some View {
        let s = max(scale, 0.01)
        let cr = item.cornerRadius * s
        let w = item.size.width * s
        let h = item.size.height * s
        let isActive = runtime.activeIDs.contains(clock.id)
        let value = runtime.displaySeconds[clock.id] ?? (clock.mode == .timer ? clock.initialSeconds : 0)
        let strokeCol: Color = isHighlighted ? .yellow : (isActive ? .green : (item.strokeColor.map { Color(hex: $0) } ?? Color.secondary.opacity(0.4)))

        ClockDisplayView(
            seconds: value,
            appearance: clock.appearance,
            showCentiseconds: clock.showCentiseconds,
            style: ClockStyle(
                foreground: item.textColor.map { Color(hex: $0) } ?? .white,
                accent: .accentColor,
                cellBackground: Color.black.opacity(0.55),
                fontWeight: .semibold
            ),
            progress: clock.appearance == .ring ? runtime.progressFraction(clock.id) : nil,
            caption: clock.caption
        )
        .padding(4 * s)
        .frame(width: w, height: h)
        // Фон объекту не нужен — рисуем только сам счётчик; рамку показываем лишь при
        // подсветке/активности (обратная связь), в покое — ничего.
        .overlay(
            Group {
                if isHighlighted || isActive {
                    TagFreeShapeView(shape: item.shape, cornerRadius: cr)
                        .stroke(strokeCol, lineWidth: 2.5 * s)
                }
            }
        )
        .rotationEffect(.degrees(item.rotation))
        .contentShape(Rectangle())
        .onFirstMouseTap {
            if showBindingsMode { onSelectBinding() } else { onTap() }
        }
        .pointingHandCursor()
    }
}
