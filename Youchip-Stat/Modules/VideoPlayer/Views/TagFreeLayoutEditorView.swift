//
//  TagFreeLayoutEditorView.swift
//  Youchip-Stat
//
//  Редактор свободного отображения тегов и лейблов коллекции.
//  Два режима: «Расположение» (drag/resize/style) и «Связки» (создание KeyBinding).
//

import SwiftUI

// MARK: - Editor mode

enum TagFreeLayoutEditorMode: String, CaseIterable {
    case layout
    case bindings
}

/// Глобальная видимость стрелок-связок на холсте редактора.
enum KeyBindingArrowVisibility: String, CaseIterable {
    case hidden   // скрыть все
    case above    // показать все над кнопками
    case below    // показать все под кнопками

    var titleKey: String.Titles {
        switch self {
        case .hidden: return .keyBindingsArrowsHidden
        case .above:  return .keyBindingsArrowsAbove
        case .below:  return .keyBindingsArrowsBelow
        }
    }

    var iconName: String {
        switch self {
        case .hidden: return "eye.slash"
        case .above:  return "chevron.up.square"
        case .below:  return "chevron.down.square"
        }
    }
}

enum TagFreeLayoutEditorPane {
    case canvas
    case settings
    case full
}

/// Запрос на открытие редактора элемента холста (двойной клик по кнопке в раскладке).
struct PendingCanvasEdit: Equatable, Identifiable {
    let kind: CanvasButtonKind
    let elementId: String
    var id: String { "\(kind.rawValue):\(elementId)" }
}

final class TagFreeLayoutEditorSession: ObservableObject {
    @Published var editorMode: TagFreeLayoutEditorMode = .layout
    /// «Основной» выбранный элемент — под него показываются ручки resize/rotate и панель справа.
    @Published var selectedItemId: String? = nil
    /// Все выбранные элементы (мультивыбор через Shift+ЛКМ). Двигаются вместе.
    @Published var selectedItemIds: Set<String> = []
    @Published var bindingSourceId: String? = nil
    @Published var selectedGroupKey: KeyBindingGroupKey? = nil
    /// Группы связок, подсвечиваемые на холсте (раскрытые в деталке кнопки справа).
    @Published var highlightedGroupKeys: Set<KeyBindingGroupKey> = []
    @Published var showGrid: Bool = false
    /// Глобальный режим показа стрелок-связок (скрыть / над кнопками / под кнопками).
    @Published var arrowVisibility: KeyBindingArrowVisibility = .above

    func resetSelection() {
        selectedItemId = nil
        selectedItemIds = []
        bindingSourceId = nil
        selectedGroupKey = nil
        highlightedGroupKeys = []
    }
}

/// Достаёт окно, в котором живёт холст: монитор клавиатуры должен реагировать только на события
/// своего окна, иначе редактор в фоне перехватывает ⌘C/⌘V у активного окна.
private struct CanvasWindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { self.window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if self.window !== nsView.window { self.window = nsView.window }
        }
    }
}

// MARK: - Embeddable editor content

struct TagFreeLayoutEditorContent: View {

    @ObservedObject var session: TagFreeLayoutEditorSession
    @Binding var layout: TagFreeLayout

    let tags: [Tag]
    let labels: [Label]
    let timeEvents: [TimeEvent]
    var playFields: [PlayField] = []
    var clocks: [ClockEntity] = []
    var pane: TagFreeLayoutEditorPane = .full
    var showsModePicker: Bool = true
    /// Панель настроек растягивается по ширине (иначе фиксированные 340pt).
    var settingsPaneFillsWidth: Bool = false
    /// Двойной клик по элементу холста — открыть редактирование самого тега/лейбла/события.
    var onEditElement: ((CanvasButtonKind, String) -> Void)? = nil
    /// Батч-изменение цвета самих выделенных тегов («цвет кнопки»). nil — недоступно.
    var onSetTagsColor: ((_ tagIds: [String], _ hex: String) -> Void)? = nil
    /// Дублирует сущность (тег/лейбл/событие) в коллекции для копипаста кнопок.
    /// Возвращает elementId новой сущности или nil, если недоступно.
    var onDuplicateElement: ((_ kind: CanvasButtonKind, _ sourceElementId: String) -> String?)? = nil
    /// Создаёт PlayField из файла (перетаскивание карты из Finder / выбор файла). nil — недоступно.
    var onCreatePlayFieldFromURL: ((_ url: URL) -> PlayField?)? = nil
    /// Экспорт выделенной части коллекции (набор ключей "kind:elementId"). nil — недоступно.
    var onExportSelected: ((_ selectedItemIds: Set<String>) -> Void)? = nil

    // Layout-mode drag / resize / rotate
    @State private var draggingItemId: String? = nil
    @State private var resizingItemId: String? = nil
    @State private var rotatingItemId: String? = nil
    @State private var dragStartCenter: CGPoint = .zero
    /// Стартовые центры всех перетаскиваемых элементов при групповом перемещении.
    @State private var dragStartCenters: [String: CGPoint] = [:]
    /// Замороженный охват контента на время трансформации — чтобы «бесконечный» холст
    /// не переразмечался под курсором и элемент шёл ровно 1:1 за мышью.
    @State private var frozenContentRect: CGRect? = nil
    @State private var resizeStartSize: CGSize = .zero
    @State private var rotateStartAngle: Double = 0
    /// Групповой ресайз/поворот: стартовые размеры/центры/повороты выделенных и центр группы.
    @State private var groupResizeStartSizes: [String: CGSize] = [:]
    @State private var groupResizeStartCenters: [String: CGPoint] = [:]
    @State private var groupResizeCentroid: CGPoint = .zero
    @State private var resizeStartBBoxWidth: CGFloat = 1
    @State private var groupRotateStartRotations: [String: Double] = [:]
    @State private var groupRotateStartCenters: [String: CGPoint] = [:]
    /// Рамка выделения (rubber-band) в пиксельных координатах холста.
    @State private var marqueeStart: CGPoint? = nil
    @State private var marqueeCurrent: CGPoint? = nil

    // Зум холста (как в Figma/Miro): пользовательский масштаб (пинч), панорама — нативным скроллом.
    @State private var canvasZoom: CGFloat = 1.0
    @State private var canvasZoomBase: CGFloat = 1.0
    @State private var didInitialFit = false
    // Ручной pan+zoom (без ScrollView) — чтобы зум к курсору был атомарным, без «прыжка».
    @State private var viewportSize: CGSize = .zero
    @State private var hoverInViewport: CGPoint? = nil
    @State private var panOffset: CGSize = .zero
    @State private var scrollMonitor: Any? = nil
    /// Буфер кнопок — наблюдаемый, иначе пункт «Вставить» не появляется после копирования.
    @ObservedObject private var clipboard = CanvasButtonClipboard.shared
    /// Монитор ⌘/⌃+C, ⌘/⌃+V и Delete. Работает только пока окно этого холста ключевое.
    @State private var keyMonitor: Any? = nil
    @State private var hostWindow: NSWindow? = nil
    // Автопанорама к только что созданному элементу (тег/лейбл/событие/карта). Новые элементы
    // кладутся ПОД существующими и оказываются за краем — камеру двигаем так, чтобы новый был по центру.
    @State private var lastKnownItemIds: Set<String> = []
    /// Взводится с задержкой после появления — чтобы стартовая нормализация/загрузка раскладки
    /// (может добавить элементы сразу) не дёргала камеру. Реагируем только на действия пользователя.
    @State private var autoCenterArmed = false
    // Нижняя граница уменьшена ~×3 — можно отдалять холст заметно дальше.
    private let canvasZoomRange: ClosedRange<CGFloat> = 0.067...3.0

    // Мелкий шаг сетки: теги в свободном режиме всегда выравниваются по нему,
    // чтобы в библиотеке тегов раскладка не «расползалась».
    private let gridStep: CGFloat = 10

    // MARK: - Body

    var body: some View {
        Group {
            switch pane {
            case .canvas:
                VStack(spacing: 0) {
                    if showsModePicker {
                        modePickerBar
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.windowBackgroundColor))
                        Divider()
                    }
                    canvasArea
                }
            case .settings:
                rightPanel
            case .full:
                VStack(spacing: 0) {
                    if showsModePicker {
                        modePickerBar
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.windowBackgroundColor))
                        Divider()
                    }
                    HStack(spacing: 0) {
                        canvasArea
                        Divider()
                        rightPanel
                    }
                }
            }
        }
    }

    private var canvasArea: some View {
        GeometryReader { geo in
                    let availableWidth = max(geo.size.width - 32, 300)
                    let availableHeight = max(geo.size.height - 32, 300)
                    // «Бесконечный» холст: виртуальная зона = охват контента + большие поля со всех сторон.
                    // Масштаб НЕ авто-подгоняется — это пользовательский зум (пинч); панорама — нативным скроллом.
                    // При вытаскивании элементов за край зона расширяется (как доска в Miro/Figma).
                    // Во время перетаскивания/ресайза используем замороженный охват — иначе
                    // холст переразмечается под курсором и движение выходит не 1:1.
                    let content = frozenContentRect
                        ?? layout.contentRect()
                        ?? CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight)
                    // Доска = контент + большой симметричный запас (infiniteMargin) со всех сторон.
                    let virtual = content.insetBy(dx: -infiniteMargin, dy: -infiniteMargin)
                    let origin = CGPoint(x: virtual.minX, y: virtual.minY)
                    let scale = canvasZoom
                    let canvasPixelWidth = virtual.width * scale
                    let canvasPixelHeight = virtual.height * scale

                    ZStack(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )

                            if session.showGrid {
                                gridOverlay(scale: scale)
                                    .frame(width: canvasPixelWidth, height: canvasPixelHeight)
                            }

                            // Стрелки «под кнопками» — рисуются ДО кнопок.
                            if session.editorMode == .bindings, session.arrowVisibility == .below {
                                arrowLinesOverlay(scale: scale, origin: origin, canvasPixelWidth: canvasPixelWidth, canvasPixelHeight: canvasPixelHeight)
                            }

                            canvasView(scale: scale, origin: origin, canvasPixelWidth: canvasPixelWidth, canvasPixelHeight: canvasPixelHeight)

                            if session.editorMode == .bindings {
                                // Стрелки «над кнопками» — рисуются ПОСЛЕ кнопок.
                                if session.arrowVisibility == .above {
                                    arrowLinesOverlay(scale: scale, origin: origin, canvasPixelWidth: canvasPixelWidth, canvasPixelHeight: canvasPixelHeight)
                                }

                                bindingsModeBanner
                                    .frame(width: canvasPixelWidth, alignment: .top)
                                    .padding(.top, 8)
                            }
                        }
                        .frame(width: canvasPixelWidth, height: canvasPixelHeight)
                        .offset(x: panOffset.width, y: panOffset.height)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipped()
                    .contentShape(Rectangle())
                    .background(Color(NSColor.windowBackgroundColor))
                    .modifier(HoverTracker { p in hoverInViewport = p })
                    .onChange(of: geo.size) { viewportSize = $0 }
                    // Пинч-зум к курсору (атомарно масштаб+смещение — без прыжка).
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                zoomAround(canvasZoomBase * value,
                                           viewportPoint: hoverInViewport ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                            }
                            .onEnded { _ in canvasZoomBase = canvasZoom }
                    )
                    .onChange(of: layout.items.map(\.id)) { ids in
                        handleItemsChange(ids)
                    }
                    .onAppear {
                        viewportSize = geo.size
                        installScrollMonitor()
                        installKeyMonitor()
                        // Базовый набор элементов — чтобы стартовые добавления не считались «новыми».
                        lastKnownItemIds = Set(layout.items.map(\.id))
                        // Взводим автопанораму чуть позже, когда стартовая нормализация уже отработала.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { autoCenterArmed = true }
                        // Один раз вписываем КОНТЕНТ и центрируем холст на объектах.
                        guard !didInitialFit else { return }
                        didInitialFit = true
                        let fit = min(availableWidth / max(content.width, 1), availableHeight / max(content.height, 1))
                        let z = min(1.0, max(canvasZoomRange.lowerBound, fit))
                        canvasZoom = z; canvasZoomBase = z
                        panOffset = CGSize(
                            width: geo.size.width / 2 - (content.midX - origin.x) * z,
                            height: geo.size.height / 2 - (content.midY - origin.y) * z
                        )
                    }
                    .onDisappear {
                        removeScrollMonitor()
                        removeKeyMonitor()
                    }
                    .background(CanvasWindowAccessor(window: $hostWindow))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        // Пустое место холста: правый клик — вставка скопированных кнопок.
        .contextMenu { canvasBackgroundContextMenu }
        // Перетаскивание карты-картинки из Finder прямо на холст.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in handleMapDrop(providers) }
        // Ползунок масштаба холста.
        .overlay(alignment: .bottom) { zoomControl }
    }

    private var zoomControl: some View {
        HStack(spacing: 8) {
            Button(action: { setZoom(canvasZoom - 0.1) }) {
                Image(systemName: "minus.magnifyingglass")
            }.buttonStyle(.plain)
            Slider(
                value: Binding(get: { Double(canvasZoom) }, set: { setZoom(CGFloat($0)) }),
                in: Double(canvasZoomRange.lowerBound)...Double(canvasZoomRange.upperBound)
            )
            .frame(width: 160)
            Button(action: { setZoom(canvasZoom + 0.1) }) {
                Image(systemName: "plus.magnifyingglass")
            }.buttonStyle(.plain)
            Text("\(Int(canvasZoom * 100))%")
                .font(.caption).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Color(NSColor.windowBackgroundColor).opacity(0.95)))
        .overlay(Capsule().stroke(Color.gray.opacity(0.2)))
        .padding(.bottom, 12)
    }

    /// Слайдер/кнопки масштаба — зумим вокруг центра вьюпорта (курсор в этот момент на контроле).
    private func setZoom(_ value: CGFloat) {
        zoomAround(value, viewportPoint: CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2))
        canvasZoomBase = canvasZoom
    }

    /// Масштабирует холст, удерживая заданную точку вьюпорта на месте (атомарно: масштаб + смещение).
    private func zoomAround(_ newScale: CGFloat, viewportPoint vp: CGPoint) {
        let clamped = min(canvasZoomRange.upperBound, max(canvasZoomRange.lowerBound, newScale))
        let old = canvasZoom
        guard old > 0 else { canvasZoom = clamped; return }
        let ratio = clamped / old
        panOffset = CGSize(
            width: vp.x - (vp.x - panOffset.width) * ratio,
            height: vp.y - (vp.y - panOffset.height) * ratio
        )
        canvasZoom = clamped
    }

    /// Реакция на изменение набора элементов раскладки: если пользователь добавил ОДИН новый
    /// элемент — плавно двигаем камеру так, чтобы он оказался по центру вьюпорта.
    private func handleItemsChange(_ currentIdsArray: [String]) {
        let current = Set(currentIdsArray)
        let added = current.subtracting(lastKnownItemIds)
        lastKnownItemIds = current
        // Только для панелей, реально рисующих холст (в панели настроек камеры нет).
        guard pane != .settings, autoCenterArmed else { return }
        // Реагируем лишь на одиночное добавление (массовые — импорт/нормализация — пропускаем).
        guard added.count == 1, let newId = currentIdsArray.last(where: { added.contains($0) }) else { return }
        // Даём раскладке применить изменение (contentRect включит новый элемент), затем центрируем.
        DispatchQueue.main.async { centerCameraOnItem(id: newId) }
    }

    /// Двигает камеру (только панорама, зум не меняем), чтобы элемент с данным id был по центру.
    private func centerCameraOnItem(id: String) {
        guard viewportSize.width > 0, viewportSize.height > 0,
              let item = layout.items.first(where: { $0.id == id }) else { return }
        let origin = originForContent(layout.contentRect()
            ?? CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight))
        let scale = canvasZoom
        let target = CGSize(
            width: viewportSize.width / 2 - (item.center.x - origin.x) * scale,
            height: viewportSize.height / 2 - (item.center.y - origin.y) * scale
        )
        withAnimation(.easeInOut(duration: 0.25)) {
            panOffset = target
        }
    }

    /// origin виртуального холста (как в canvasArea): контент + симметричные поля infiniteMargin.
    private func originForContent(_ content: CGRect) -> CGPoint {
        let virtual = content.insetBy(dx: -infiniteMargin, dy: -infiniteMargin)
        return CGPoint(x: virtual.minX, y: virtual.minY)
    }

    /// После перетаскивания охват контента (и origin) может сместиться — например, элемент
    /// вынесли левее/выше прежних границ. Тогда весь холст «прыгает». Компенсируем panOffset на
    /// смещение origin, чтобы визуально ничего не дёрнулось (камера НЕ перепрыгивает к элементу).
    private func compensatePanForContentShift(before: CGRect) {
        let after = layout.contentRect()
            ?? CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight)
        let originBefore = originForContent(before)
        let originAfter = originForContent(after)
        let scale = canvasZoom
        let dx = (originAfter.x - originBefore.x) * scale
        let dy = (originAfter.y - originBefore.y) * scale
        guard dx != 0 || dy != 0 else { return }
        panOffset = CGSize(width: panOffset.width + dx, height: panOffset.height + dy)
    }

    /// Камера следует за элементом ТОЛЬКО если после перетаскивания он оказался полностью за
    /// пределами вьюпорта — и то плавно. Пока элемент виден, камеру не трогаем.
    private func panToRevealIfOffscreen(id: String) {
        guard viewportSize.width > 0, viewportSize.height > 0,
              let item = layout.items.first(where: { $0.id == id }) else { return }
        let origin = originForContent(layout.contentRect()
            ?? CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight))
        let scale = canvasZoom
        let px = (item.center.x - origin.x) * scale + panOffset.width
        let py = (item.center.y - origin.y) * scale + panOffset.height
        let halfW = item.size.width * scale / 2
        let halfH = item.size.height * scale / 2
        let margin: CGFloat = 8
        let offscreen = px + halfW < margin
            || px - halfW > viewportSize.width - margin
            || py + halfH < margin
            || py - halfH > viewportSize.height - margin
        guard offscreen else { return }
        let target = CGSize(
            width: viewportSize.width / 2 - (item.center.x - origin.x) * scale,
            height: viewportSize.height / 2 - (item.center.y - origin.y) * scale
        )
        withAnimation(.easeInOut(duration: 0.3)) {
            panOffset = target
        }
    }

    /// Панорама холста двухпальцевым скроллом (когда курсор над холстом).
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

    // MARK: - Клавиатура холста (копировать / вставить / убрать)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleCanvasKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// true — событие наше, дальше его не пускаем.
    private func handleCanvasKeyDown(_ event: NSEvent) -> Bool {
        // Монитор локальный, но общий для приложения: реагируем только на события окна этого
        // холста, иначе редактор в фоне съедал бы ⌘C/⌘V у активного окна.
        guard let host = hostWindow, event.window === host else { return false }
        guard session.editorMode == .layout else { return false }
        // Идёт ввод текста (имя коллекции, поля панели) — клавиши не наши.
        if let responder = host.firstResponder {
            if responder is NSTextField { return false }
            if let textView = responder as? NSTextView, textView.isFieldEditor { return false }
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // ⌃ — как просили, ⌘ — привычный маковский вариант.
        let isCopyModifier = mods.contains(.command) || mods.contains(.control)
        let key = event.charactersIgnoringModifiers?.lowercased()

        if isCopyModifier, key == "c" || event.keyCode == 8 {
            guard !session.selectedItemIds.isEmpty else { return false }
            copySelectedButtons()
            return true
        }
        if isCopyModifier, key == "v" || event.keyCode == 9 {
            guard onDuplicateElement != nil, clipboard.hasContent else { return false }
            pasteButtons()
            return true
        }
        // Delete / Backspace — убрать выделенные кнопки с холста.
        if mods.isEmpty, event.keyCode == 51 || event.keyCode == 117 {
            guard !removableItemIds(in: session.selectedItemIds).isEmpty else { return false }
            removeSelectedFromCanvas()
            return true
        }
        return false
    }

    /// Обрабатывает перетаскивание файла-изображения на холст → создаёт карту и кладёт её.
    private func handleMapDrop(_ providers: [NSItemProvider]) -> Bool {
        guard session.editorMode == .layout, let create = onCreatePlayFieldFromURL,
              let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, ["png", "jpg", "jpeg", "tiff", "heic"].contains(url.pathExtension.lowercased()) else { return }
            DispatchQueue.main.async {
                if let field = create(url) {
                    TagFreeLayoutStorage.addMapToLayout(&layout, field: field)
                }
            }
        }
        return true
    }

    /// Поля «бесконечного» холста редактора со всех сторон (в координатах раскладки).
    /// Большой запас пустого места вокруг объектов; в библиотеке тегов эта зона обрезается.
    /// При вытаскивании элементов за этот запас зона расширяется по контенту.
    private let infiniteMargin: CGFloat = 6000

    // MARK: - Arrow overlays

    private func arrowLinesOverlay(scale: CGFloat, origin: CGPoint, canvasPixelWidth: CGFloat, canvasPixelHeight: CGFloat) -> some View {
        KeyBindingArrowLinesOverlay(
            layout: layout,
            scale: scale,
            origin: origin,
            canvasPixelWidth: canvasPixelWidth,
            canvasPixelHeight: canvasPixelHeight,
            selectedGroupKey: session.selectedGroupKey,
            highlightedGroupKeys: session.highlightedGroupKeys,
            focusedSourceKey: session.bindingSourceId
        )
    }

    // MARK: - Mode picker

    private var modePickerBar: some View {
        HStack {
            Picker("", selection: $session.editorMode) {
                SwiftUI.Label(^String.Titles.keyBindingsEditorModeLayout, systemImage: "move.3d").tag(TagFreeLayoutEditorMode.layout)
                SwiftUI.Label(^String.Titles.keyBindingsEditorModeBindings, systemImage: "arrow.triangle.branch").tag(TagFreeLayoutEditorMode.bindings)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .onChange(of: session.editorMode) { mode in
                session.resetSelection()
                if mode == .bindings {
                    layout = TagFreeLayoutStorage.normalizeLayout(layout, tags: tags, labels: labels, timeEvents: timeEvents)
                }
            }
            Spacer()
            if session.editorMode == .bindings {
                arrowVisibilityControl
            }
        }
    }

    /// Глобальный переключатель видимости всех стрелок-связок: скрыть / над кнопками / под кнопками.
    private var arrowVisibilityControl: some View {
        Menu {
            Picker("", selection: $session.arrowVisibility) {
                ForEach(KeyBindingArrowVisibility.allCases, id: \.self) { mode in
                    SwiftUI.Label(^mode.titleKey, systemImage: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            SwiftUI.Label(^session.arrowVisibility.titleKey, systemImage: session.arrowVisibility.iconName)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(^String.Titles.keyBindingsArrowsVisibilityTitle)
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

    private func canvasView(scale: CGFloat, origin: CGPoint, canvasPixelWidth: CGFloat, canvasPixelHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: canvasPixelWidth, height: canvasPixelHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    if session.editorMode == .layout {
                        session.selectedItemId = nil
                        session.selectedItemIds = []
                    } else {
                        session.bindingSourceId = nil
                        session.selectedGroupKey = nil
                    }
                }
                // Rubber-band выделение: тянем ЛКМ по пустому холсту (только в режиме раскладки).
                .gesture(marqueeGesture(scale: scale, origin: origin))

            // Перетаскивание за любую точку внутри рамки выделения (ПОД кнопками — чтобы
            // Shift/Cmd+ЛКМ по кнопкам проходили насквозь к ним и добавляли в выбор).
            if session.editorMode == .layout, marqueePixelRect == nil, let bbox = selectionBBoxCanvas {
                selectionMoveSurface(bbox: bbox, scale: scale, origin: origin)
            }

            ForEach(layout.items) { item in
                itemView(item: item, scale: scale)
                    .position(x: (item.center.x - origin.x) * scale, y: (item.center.y - origin.y) * scale)
                    .zIndex(editorZIndex(for: item))
            }

            // Общий bounding box выделения с ручками размера/поворота (поверх кнопок).
            if session.editorMode == .layout, marqueePixelRect == nil, let bbox = selectionBBoxCanvas {
                selectionHandlesOverlay(bbox: bbox, scale: scale, origin: origin,
                                        canvasPixelWidth: canvasPixelWidth, canvasPixelHeight: canvasPixelHeight)
            }

            // Визуальная рамка выделения поверх кнопок.
            if let rect = marqueePixelRect {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: canvasPixelWidth, height: canvasPixelHeight, alignment: .topLeading)
        .coordinateSpace(name: "canvas")
        // Объект мог исчезнуть не через холст (удалили сущность в левом столбце) — тогда в выделении
        // остаётся мёртвый id: рамка висит над пустым местом и её можно таскать.
        .onChange(of: layout.items.count) { _ in pruneSelectionToExistingItems() }
    }

    /// Порядок слоёв объектов на холсте редактора — тот же, что в библиотеке (`FreeTagsCanvasView`).
    ///
    /// Без него порядок определялся позицией в массиве: карта, добавленная последней, ложилась
    /// ПОВЕРХ кнопок и перехватывала клики по всей своей рамке — со стороны это выглядело так,
    /// будто она «ловит нажатия дальше своих границ» (на самом деле — по кнопкам, попавшим на неё).
    /// Карта — фон-зона под кнопками; выделенный объект поднимаем, чтобы его нельзя было потерять.
    private func editorZIndex(for item: TagFreeLayoutItem) -> Double {
        if session.selectedItemIds.contains(item.id) || session.selectedItemId == item.id { return 100 }
        switch item.kind {
        case .map:       return 1
        case .tag:       return 10
        case .timeEvent: return 20
        case .clock:     return 25
        case .label:     return 30
        }
    }

    /// Выкидывает из выделения id, которым больше не соответствует ни один объект холста.
    private func pruneSelectionToExistingItems() {
        let existing = Set(layout.items.map(\.id))
        if let selected = session.selectedItemId, !existing.contains(selected) {
            session.selectedItemId = nil
        }
        if !session.selectedItemIds.isSubset(of: existing) {
            session.selectedItemIds.formIntersection(existing)
        }
        if let source = session.bindingSourceId, !existing.contains(source) {
            session.bindingSourceId = nil
        }
    }

    /// Прямоугольник рамки выделения в пиксельных координатах холста (для отрисовки).
    private var marqueePixelRect: CGRect? {
        guard let s = marqueeStart, let c = marqueeCurrent else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                      width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    /// Rubber-band: тянем по пустому холсту → выделяем пересекаемые кнопки.
    private func marqueeGesture(scale: CGFloat, origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("canvas"))
            .onChanged { value in
                guard session.editorMode == .layout else { return }
                if marqueeStart == nil { marqueeStart = value.startLocation }
                marqueeCurrent = value.location
                selectItemsInMarquee(scale: scale, origin: origin)
            }
            .onEnded { _ in
                marqueeStart = nil
                marqueeCurrent = nil
            }
    }

    /// Выделяет элементы, чьи прямоугольники пересекаются с рамкой (в координатах виртуального холста).
    private func selectItemsInMarquee(scale: CGFloat, origin: CGPoint) {
        guard let px = marqueePixelRect else { return }
        // Переводим пиксельную рамку в координаты виртуального холста.
        let virtualRect = CGRect(
            x: origin.x + px.minX / scale,
            y: origin.y + px.minY / scale,
            width: px.width / scale,
            height: px.height / scale
        )
        let hit = layout.items.filter { item in
            let frame = CGRect(x: item.center.x - item.size.width / 2,
                               y: item.center.y - item.size.height / 2,
                               width: item.size.width, height: item.size.height)
            return frame.intersects(virtualRect)
        }
        session.selectedItemIds = Set(hit.map { $0.id })
        session.selectedItemId = hit.first?.id
    }

    // MARK: - Bindings mode banner

    private var bindingsModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: session.bindingSourceId != nil ? "1.circle.fill" : "1.circle")
                .foregroundColor(session.bindingSourceId != nil ? .orange : .secondary)
            Text(session.bindingSourceId != nil
                 ? ^String.Titles.keyBindingsTapTargetHint
                 : ^String.Titles.keyBindingsTapSourceHint)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
            if session.bindingSourceId != nil {
                Button(^String.Titles.cancelButtonTitle) {
                    session.bindingSourceId = nil
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
        let isSelected = session.selectedItemId == itemKey
        // Входит ли элемент в мультивыбор — по нему подсвечиваем все выбранные, не только основной.
        let isInSelection = session.selectedItemIds.contains(itemKey) || isSelected

        // Determine display name
        let displayName: String = {
            switch item.kind {
            case .tag:       return tags.first(where: { $0.id == item.elementId })?.name ?? item.elementId
            case .label:     return labels.first(where: { $0.id == item.elementId })?.name ?? item.elementId
            case .timeEvent: return timeEvents.first(where: { $0.id == item.elementId })?.name ?? item.elementId
            case .map:       return playFields.first(where: { $0.id == item.elementId })?.name ?? item.elementId
            case .clock:     return clocks.first(where: { $0.id == item.elementId })?.name ?? item.elementId
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
            case .map:
                return Color(NSColor.controlBackgroundColor).opacity(0.4)
            case .clock:
                return Color.clear   // счётчику фон не нужен — рисуем только сам циферблат
            }
        }()

        let viewSize = CGSize(width: item.size.width * scale, height: item.size.height * scale)
        let cr = item.cornerRadius * scale
        let strokeCol = item.strokeColor.map { Color(hex: $0) } ?? Color.black.opacity(0.3)
        let strokeStyle = StrokeStyle(
            lineWidth: (isInSelection ? 2 : item.strokeWidth) * scale,
            dash: (isInSelection ? true : item.strokeDashed) ? [4 * scale, 3 * scale] : []
        )
        let textCol = item.textColor.map { Color(hex: $0) } ?? Color.white
        let swiftWeight: Font.Weight = {
            switch item.fontWeight {
            case .regular: return .regular; case .medium: return .medium; case .bold: return .bold
            }
        }()

        // In bindings mode: highlight source/selected state
        let isBindingSource = session.editorMode == .bindings && session.bindingSourceId == itemKey
        let strokeOverride: Color = isBindingSource ? .orange : (isInSelection ? .accentColor : strokeCol)

        ZStack {
            TagFreeShapeView(shape: item.shape, cornerRadius: cr)
                .fill(fillColor)
                // Фон-картинка (карта — по PlayField; тег/лейбл — по своему bookmark).
                .overlay(
                    Group {
                        if item.kind == .map, let field = playFields.first(where: { $0.id == item.elementId }),
                           let img = PlayFieldImageCache.shared.image(for: field) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: viewSize.width, height: viewSize.height)
                                .clipShape(TagFreeShapeView(shape: item.shape, cornerRadius: cr))
                        } else if item.kind == .map {
                            Image(systemName: "map").font(.system(size: 24 * scale)).foregroundColor(.secondary)
                        } else if item.kind == .clock, let clock = clocks.first(where: { $0.id == item.elementId }) {
                            ClockDisplayView(
                                seconds: clock.mode == .timer ? clock.initialSeconds : 0,
                                appearance: clock.appearance,
                                showCentiseconds: clock.showCentiseconds,
                                style: ClockStyle(
                                    foreground: item.textColor.map { Color(hex: $0) } ?? .white,
                                    accent: .accentColor,
                                    cellBackground: Color.black.opacity(0.55),
                                    fontWeight: swiftWeight
                                ),
                                caption: clock.caption
                            )
                            .frame(width: viewSize.width, height: viewSize.height)
                            .padding(4 * scale)
                        } else if let bm = item.backgroundImageBookmark, let img = PlayFieldImageCache.shared.image(forBookmark: bm) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: viewSize.width, height: viewSize.height)
                                .clipShape(TagFreeShapeView(shape: item.shape, cornerRadius: cr))
                        }
                    }
                    // Картинка с `.fill` вылезает за рамку объекта; нажатия должны идти только по
                    // самой кнопке (её `contentShape` ниже), иначе карта ловит клики за своими краями.
                    .allowsHitTesting(false)
                )
                // Подпись поверх — только если включена (у карты и счётчика своя отрисовка).
                .overlay(
                    Group {
                        if item.kind != .map, item.kind != .clock, item.showLabel {
                            Text(displayName)
                                .font(.system(size: item.fontSize * scale, weight: swiftWeight))
                                .foregroundColor(textCol)
                                .padding(4 * scale)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.5)
                        }
                    }
                )
                .frame(width: viewSize.width, height: viewSize.height)
                .overlay(
                    TagFreeShapeView(shape: item.shape, cornerRadius: cr)
                        .stroke(strokeOverride, style: strokeStyle)
                )

            // Kind indicator (small icon in corner)
            if item.kind == .label || item.kind == .timeEvent || item.kind == .map {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: item.kind == .label ? "textformat" : (item.kind == .map ? "map" : "clock"))
                            .font(.system(size: 8 * scale, weight: .bold))
                            .foregroundColor(textCol.opacity(0.7))
                            .padding(3 * scale)
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
                            .font(.system(size: 8 * scale))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(3 * scale)
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
        // Двойной клик — открыть редактор самого элемента (объявляем до одиночного тапа).
        .onTapGesture(count: 2) { onEditElement?(item.kind, item.elementId) }
        .onTapGesture { handleItemTap(item: item) }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                .onChanged { value in
                    guard session.editorMode == .layout, isInSelection else { return }
                    if draggingItemId == nil {
                        draggingItemId = item.id
                        frozenContentRect = layout.contentRect()
                        // Двигаем всю выделенную группу (или один элемент, если он одиночный).
                        let moveIds: Set<String> = session.selectedItemIds.contains(item.id)
                            ? session.selectedItemIds
                            : [item.id]
                        dragStartCenters = Dictionary(uniqueKeysWithValues:
                            layout.items.filter { moveIds.contains($0.id) }.map { ($0.id, $0.center) }
                        )
                    }
                    guard draggingItemId == item.id else { return }
                    // Двигаем 1:1 за курсором (без привязки к сетке) — относительные позиции сохраняются.
                    let dx = value.translation.width / scale
                    let dy = value.translation.height / scale
                    // Холст бесконечный — без ограничения границами (можно вытаскивать в любую сторону).
                    for (id, start) in dragStartCenters {
                        updateItem(id: id) { m in
                            m.center = CGPoint(x: start.x + dx, y: start.y + dy)
                        }
                    }
                }
                .onEnded { _ in
                    let movedId = draggingItemId
                    let before = frozenContentRect
                    draggingItemId = nil
                    dragStartCenters = [:]
                    frozenContentRect = nil
                    // Сначала гасим «прыжок» холста от разморозки охвата, затем — плавно
                    // подводим элемент, только если он уехал за пределы вьюпорта.
                    if let before { compensatePanForContentShift(before: before) }
                    if let movedId { panToRevealIfOffscreen(id: movedId) }
                }
        )
        // Ручки размера/поворота рисуются один раз на общем bounding box выделения (см. selectionHandlesOverlay).
        .contextMenu { itemContextMenu(item: item) }
    }

    // MARK: - Item tap

    private func handleItemTap(item: TagFreeLayoutItem) {
        if session.editorMode == .layout {
            let flags = NSEvent.modifierFlags
            let multiSelect = flags.contains(.command) || flags.contains(.shift)
            if multiSelect {
                // Command/Shift+ЛКМ — добавить/убрать элемент из мультивыбора.
                if session.selectedItemIds.contains(item.id) {
                    session.selectedItemIds.remove(item.id)
                    if session.selectedItemId == item.id {
                        session.selectedItemId = session.selectedItemIds.first
                    }
                } else {
                    session.selectedItemIds.insert(item.id)
                    session.selectedItemId = item.id
                }
            } else {
                // Обычный клик — одиночный выбор (повторный по тому же снимает выделение).
                if session.selectedItemId == item.id && session.selectedItemIds.count <= 1 {
                    session.selectedItemId = nil
                    session.selectedItemIds = []
                } else {
                    session.selectedItemId = item.id
                    session.selectedItemIds = [item.id]
                }
            }
            return
        }
        // Bindings mode
        if let sourceKey = session.bindingSourceId {
            guard sourceKey != item.id else {
                // Повторное нажатие на сфокусированную кнопку — снимаем фокус.
                session.bindingSourceId = nil
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
            // Оставляем фокус на кнопке-источнике: справа показываются все её связки,
            // на холсте — только исходящие из неё стрелки. Можно продолжать добавлять цели.
            session.selectedGroupKey = nil
        } else {
            // Фокус на кнопке: показать все её связки и оставить только их стрелки.
            session.bindingSourceId = item.id
            session.selectedGroupKey = nil
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func itemContextMenu(item: TagFreeLayoutItem) -> some View {
        if session.editorMode == .bindings {
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
            // Layout mode: действия идут по всему выделению, а не только по кнопке под курсором.
            let targets = contextTargets(for: item)
            Button(String(format: ^String.Titles.canvasCopyButtons, targets.count)) {
                selectForContext(item)
                copySelectedButtons()
            }
            if onDuplicateElement != nil, clipboard.hasContent {
                Button(String(format: ^String.Titles.canvasPasteButtons, clipboard.items.count)) {
                    pasteButtons()
                }
            }
            if let onExport = onExportSelected {
                Divider()
                Button(^String.Titles.keyBindingsExportSelected) {
                    selectForContext(item)
                    onExport(session.selectedItemIds)
                }
            }
            let removable = removableItemIds(in: targets)
            if !removable.isEmpty {
                Divider()
                Button(String(format: ^String.Titles.canvasRemoveFromCanvas, removable.count), role: .destructive) {
                    selectForContext(item)
                    removeSelectedFromCanvas()
                }
            }
        }
    }

    /// Меню на пустом месте холста — чтобы скопированные кнопки было куда вставлять.
    @ViewBuilder
    private var canvasBackgroundContextMenu: some View {
        if session.editorMode == .layout, onDuplicateElement != nil, clipboard.hasContent {
            Button(String(format: ^String.Titles.canvasPasteButtons, clipboard.items.count)) {
                pasteButtons()
            }
        }
    }

    /// Правый клик по кнопке вне выделения работает как выбор её одной.
    private func contextTargets(for item: TagFreeLayoutItem) -> Set<String> {
        session.selectedItemIds.contains(item.id) ? session.selectedItemIds : [item.id]
    }

    private func selectForContext(_ item: TagFreeLayoutItem) {
        guard !session.selectedItemIds.contains(item.id) else { return }
        session.selectedItemIds = [item.id]
        session.selectedItemId = item.id
    }

    /// Кнопки, которые реально можно убрать с холста. Теги не убираем: нормализация раскладки
    /// возвращает их обратно (у каждого тега коллекции всегда есть кнопка).
    private func removableItemIds(in ids: Set<String>) -> Set<String> {
        Set(layout.items.filter { ids.contains($0.id) && $0.kind != .tag }.map { $0.id })
    }

    /// Убирает с холста ВСЕ выделенные кнопки (раньше удалялась только одна — та, по которой
    /// кликнули) вместе с их связками.
    private func removeSelectedFromCanvas() {
        let ids = removableItemIds(in: session.selectedItemIds)
        guard !ids.isEmpty else { return }
        layout.items.removeAll { ids.contains($0.id) }
        layout.bindings.removeAll { ids.contains($0.sourceButtonKey) || ids.contains($0.targetButtonKey) }
        session.selectedItemIds.subtract(ids)
        if let selected = session.selectedItemId, ids.contains(selected) {
            session.selectedItemId = session.selectedItemIds.first
        }
    }

    // MARK: - Handles

    /// Общий bounding box выделения в координатах виртуального холста — с учётом поворота
    /// каждого элемента (AABB по повёрнутым углам), чтобы рамка следовала за повёрнутыми кнопками.
    private var selectionBBoxCanvas: CGRect? {
        let sel = layout.items.filter { session.selectedItemIds.contains($0.id) }
        guard !sel.isEmpty else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for item in sel {
            let rad = item.rotation * .pi / 180
            let c = cos(rad), s = sin(rad)
            let hw = item.size.width / 2, hh = item.size.height / 2
            for (sx, sy) in [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)] {
                let x = item.center.x + sx * c - sy * s
                let y = item.center.y + sx * s + sy * c
                minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Прозрачная поверхность внутри рамки выделения (ПОД кнопками): перетаскивание за
    /// любую её точку двигает всю группу. Кнопки сверху — поэтому Shift/Cmd+ЛКМ по ним проходят к ним.
    private func selectionMoveSurface(bbox: CGRect, scale: CGFloat, origin: CGPoint) -> some View {
        let w = bbox.width * scale
        let h = bbox.height * scale
        let cx = (bbox.midX - origin.x) * scale
        let cy = (bbox.midY - origin.y) * scale
        return Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: w, height: h)
            .position(x: cx, y: cy)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        guard session.editorMode == .layout else { return }
                        if draggingItemId == nil {
                            draggingItemId = "selection-move"
                            frozenContentRect = layout.contentRect()
                            let ids = session.selectedItemIds
                            dragStartCenters = Dictionary(uniqueKeysWithValues:
                                layout.items.filter { ids.contains($0.id) }.map { ($0.id, $0.center) })
                        }
                        guard draggingItemId == "selection-move" else { return }
                        // 1:1 за курсором, без привязки к сетке.
                        let dx = value.translation.width / scale
                        let dy = value.translation.height / scale
                        for (id, start) in dragStartCenters {
                            updateItem(id: id) { $0.center = CGPoint(x: start.x + dx, y: start.y + dy) }
                        }
                    }
                    .onEnded { _ in
                        let movedIds = Array(dragStartCenters.keys)
                        let before = frozenContentRect
                        draggingItemId = nil
                        dragStartCenters = [:]
                        frozenContentRect = nil
                        if let before { compensatePanForContentShift(before: before) }
                        // Следуем за группой, только если её основной элемент уехал за вьюпорт.
                        if let anchor = session.selectedItemId ?? movedIds.first {
                            panToRevealIfOffscreen(id: anchor)
                        }
                    }
            )
    }

    /// Рамка выделения + ручки размера (квадрат) и поворота (круг) на общем bounding box.
    /// Ручки фиксированного экранного размера и вынесены ЗА рамку — не перекрывают элементы
    /// и не слипаются при отдалении холста.
    private func selectionHandlesOverlay(bbox: CGRect, scale: CGFloat, origin: CGPoint,
                                         canvasPixelWidth: CGFloat, canvasPixelHeight: CGFloat) -> some View {
        let px = CGRect(x: (bbox.minX - origin.x) * scale, y: (bbox.minY - origin.y) * scale,
                        width: bbox.width * scale, height: bbox.height * scale)
        let handle: CGFloat = 18
        let gap: CGFloat = 10
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: px.width, height: px.height)
                .offset(x: px.minX, y: px.minY)
                .allowsHitTesting(false)

            // Поворот (круг) — над правым-верхним углом.
            selectionRotateHandle(scale: scale)
                .frame(width: handle, height: handle)
                .offset(x: px.maxX + gap, y: px.minY - gap - handle)

            // Размер (квадрат) — под правым-нижним углом.
            selectionResizeHandle(bbox: bbox, scale: scale)
                .frame(width: handle, height: handle)
                .offset(x: px.maxX + gap, y: px.maxY + gap)
        }
        .frame(width: canvasPixelWidth, height: canvasPixelHeight, alignment: .topLeading)
    }

    private func selectionResizeHandle(bbox: CGRect, scale: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white)
            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        let ids = session.selectedItemIds
                        if resizingItemId == nil {
                            resizingItemId = "selection"
                            frozenContentRect = layout.contentRect()
                            beginSelectionResize(groupIds: ids, bbox: bbox)
                        }
                        guard resizingItemId == "selection" else { return }
                        let dw = value.translation.width / scale
                        let dh = value.translation.height / scale
                        if ids.count > 1 {
                            applyGroupResizeFactor(dw: dw)
                        } else if let id = ids.first {
                            applySingleResize(id: id, dw: dw, dh: dh)
                        }
                    }
                    .onEnded { _ in
                        let before = frozenContentRect
                        resizingItemId = nil
                        groupResizeStartSizes = [:]
                        groupResizeStartCenters = [:]
                        frozenContentRect = nil
                        if let before { compensatePanForContentShift(before: before) }
                    }
            )
    }

    private func selectionRotateHandle(scale: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        let ids = session.selectedItemIds
                        if rotatingItemId == nil {
                            rotatingItemId = "selection"
                            frozenContentRect = layout.contentRect()
                            beginSelectionRotate(groupIds: ids)
                        }
                        guard rotatingItemId == "selection" else { return }
                        let deltaDeg = Double(value.translation.width / scale)
                        if ids.count > 1 {
                            applyGroupRotate(deltaDeg: deltaDeg)
                        } else if let id = ids.first {
                            updateItem(id: id) { $0.rotation = (groupRotateStartRotations[id] ?? 0) + deltaDeg }
                        }
                    }
                    .onEnded { _ in
                        let before = frozenContentRect
                        rotatingItemId = nil
                        groupRotateStartRotations = [:]
                        groupRotateStartCenters = [:]
                        frozenContentRect = nil
                        if let before { compensatePanForContentShift(before: before) }
                    }
            )
    }

    // MARK: - Selection resize/rotate math

    private func beginSelectionResize(groupIds: Set<String>, bbox: CGRect) {
        let sel = layout.items.filter { groupIds.contains($0.id) }
        groupResizeStartSizes = Dictionary(uniqueKeysWithValues: sel.map { ($0.id, $0.size) })
        groupResizeStartCenters = Dictionary(uniqueKeysWithValues: sel.map { ($0.id, $0.center) })
        groupResizeCentroid = CGPoint(x: bbox.midX, y: bbox.midY)
        resizeStartBBoxWidth = max(bbox.width, 1)
        resizeStartSize = sel.first?.size ?? .zero
    }

    /// Групповой ресайз: масштабирует все выделенные одним коэффициентом (от ширины bounding box).
    private func applyGroupResizeFactor(dw: CGFloat) {
        let minSize: CGFloat = 40
        var factor = max(0.1, (resizeStartBBoxWidth + dw) / resizeStartBBoxWidth)
        let smallest = groupResizeStartSizes.values.map { min($0.width, $0.height) }.min() ?? minSize
        if smallest * factor < minSize { factor = minSize / smallest }
        for (id, startSize) in groupResizeStartSizes {
            guard let startCenter = groupResizeStartCenters[id] else { continue }
            updateItem(id: id) { m in
                m.size = CGSize(width: startSize.width * factor, height: startSize.height * factor)
                m.center = CGPoint(
                    x: groupResizeCentroid.x + (startCenter.x - groupResizeCentroid.x) * factor,
                    y: groupResizeCentroid.y + (startCenter.y - groupResizeCentroid.y) * factor
                )
            }
        }
    }

    /// Одиночный ресайз: независимо по ширине/высоте (с учётом фиксации пропорций).
    private func applySingleResize(id: String, dw: CGFloat, dh: CGFloat) {
        updateItem(id: id) { m in
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

    private func beginSelectionRotate(groupIds: Set<String>) {
        let sel = layout.items.filter { groupIds.contains($0.id) }
        groupRotateStartRotations = Dictionary(uniqueKeysWithValues: sel.map { ($0.id, $0.rotation) })
        groupRotateStartCenters = Dictionary(uniqueKeysWithValues: sel.map { ($0.id, $0.center) })
        let minX = sel.map { $0.center.x - $0.size.width / 2 }.min() ?? 0
        let minY = sel.map { $0.center.y - $0.size.height / 2 }.min() ?? 0
        let maxX = sel.map { $0.center.x + $0.size.width / 2 }.max() ?? 0
        let maxY = sel.map { $0.center.y + $0.size.height / 2 }.max() ?? 0
        groupResizeCentroid = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    /// Групповой поворот: каждый элемент вращается вокруг центра группы (орбита + собственный поворот).
    private func applyGroupRotate(deltaDeg: Double) {
        let rad = deltaDeg * .pi / 180
        let cosA = cos(rad), sinA = sin(rad)
        for (id, startRot) in groupRotateStartRotations {
            guard let sc = groupRotateStartCenters[id] else { continue }
            let dx = sc.x - groupResizeCentroid.x
            let dy = sc.y - groupResizeCentroid.y
            updateItem(id: id) { m in
                m.rotation = startRot + deltaDeg
                m.center = CGPoint(
                    x: groupResizeCentroid.x + dx * cosA - dy * sinA,
                    y: groupResizeCentroid.y + dx * sinA + dy * cosA
                )
            }
        }
    }

    // MARK: - Right panel

    @ViewBuilder
    private var rightPanel: some View {
        if session.editorMode == .bindings {
            KeyBindingSettingsPanel(
                layout: $layout,
                tags: tags,
                labels: labels,
                timeEvents: timeEvents,
                playFields: playFields,
                clocks: clocks,
                selectedGroupKey: session.selectedGroupKey,
                focusedSourceKey: session.bindingSourceId,
                onAddLabel: addLabelToCanvas,
                onAddTimeEvent: addTimeEventToCanvas,
                onDeselect: { session.selectedGroupKey = nil; session.bindingSourceId = nil },
                onHighlightGroups: { session.highlightedGroupKeys = $0 }
            )
        } else {
            layoutModeSettingsPanel
        }
    }

    // MARK: - Layout mode settings panel

    private var layoutModeSettingsPanel: some View {
        ScrollView {
            VStack(spacing: 0) {
                if session.selectedItemIds.count > 1 {
                    // Внешний вид правится батчем и для смешанного выделения (теги + лейблы):
                    // поля у всех кнопок общие, вид (kind) влияет только на заголовок и цвет тега.
                    batchItemSettings(kind: homogeneousSelectedKind)
                } else if let itemId = session.selectedItemId,
                   let index = layout.items.firstIndex(where: { $0.id == itemId }) {
                    selectedItemSettings(index: index)
                } else {
                    canvasSettings
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: settingsPaneFillsWidth ? .infinity : nil, alignment: .leading)
        }
        .frame(minWidth: settingsPaneFillsWidth ? nil : 340,
               maxWidth: settingsPaneFillsWidth ? .infinity : 340)
        .background(Color(NSColor.windowBackgroundColor))
    }

    /// Единый вид (kind) выделенных элементов, если он одинаков у всех; иначе nil.
    private var homogeneousSelectedKind: CanvasButtonKind? {
        let kinds = Set(layout.items.filter { session.selectedItemIds.contains($0.id) }.map { $0.kind })
        return kinds.count == 1 ? kinds.first : nil
    }

    /// Заголовок батч-панели: «3 Теги» для однородного выделения, «2 Теги + 1 Лейблы» для смешанного.
    private var batchSelectionTitle: String {
        let selected = layout.items.filter { session.selectedItemIds.contains($0.id) }
        let order: [CanvasButtonKind] = [.tag, .label, .timeEvent, .map]
        let parts = order.compactMap { kind -> String? in
            let count = selected.filter { $0.kind == kind }.count
            guard count > 0 else { return nil }
            return "\(count) \(kindTitle(kind))"
        }
        return parts.joined(separator: " + ")
    }

    private func kindTitle(_ kind: CanvasButtonKind) -> String {
        switch kind {
        case .tag:       return ^String.Titles.tags
        case .label:     return ^String.Titles.labels
        case .timeEvent: return ^String.Titles.commonEvents
        case .map:       return ^String.Titles.map
        case .clock:     return ^String.Titles.clockCountersTitle
        }
    }

    // MARK: - Canvas settings

    private var canvasSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(^String.Titles.freeLayoutCanvasSettings).font(.headline).padding(.top, 4)
            Divider()
            Toggle(^String.Titles.freeLayoutShowGrid, isOn: $session.showGrid)

            if onCreatePlayFieldFromURL != nil || !playFields.isEmpty {
                Divider()
                sectionHeader(^String.Titles.keyBindingsAddMap)
                Menu {
                    if onCreatePlayFieldFromURL != nil {
                        Button(^String.Titles.keyBindingsAddMapFromDisk) { pickMapFromDisk() }
                    }
                    if !playFields.isEmpty {
                        Divider()
                        Text(^String.Titles.keyBindingsLoadedMaps)
                        ForEach(playFields) { field in
                            Button(field.name) { addMapToCanvas(field) }
                        }
                    }
                } label: {
                    SwiftUI.Label(^String.Titles.keyBindingsAddMap, systemImage: "map").font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Text(^String.Titles.freeLayoutSelectElement)
                .font(.caption).foregroundColor(.secondary).padding(.top, 8)
        }
    }

    /// Выбор картинки-фона для кнопки через диалог.
    private func pickBackgroundImage(binding: Binding<TagFreeLayoutItem>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        guard panel.runModal() == .OK, let url = panel.url, let bookmark = url.makeBookmark() else { return }
        binding.backgroundImageBookmark.wrappedValue = bookmark
    }

    /// Выбор файла-карты через диалог и добавление её на холст.
    private func pickMapFromDisk() {
        guard let create = onCreatePlayFieldFromURL else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let field = create(url) {
            TagFreeLayoutStorage.addMapToLayout(&layout, field: field)
        }
    }

    // MARK: - Batch settings (несколько выделенных кнопок одного вида)

    /// Значение поля из первичной выделенной кнопки (для отображения в батч-контролах).
    private func batchValue<T>(_ keyPath: KeyPath<TagFreeLayoutItem, T>, default def: T) -> T {
        if let id = session.selectedItemId, let item = layout.items.first(where: { $0.id == id }) {
            return item[keyPath: keyPath]
        }
        return layout.items.first(where: { session.selectedItemIds.contains($0.id) })?[keyPath: keyPath] ?? def
    }

    /// Применяет изменение ко ВСЕМ выделенным кнопкам.
    private func updateSelectedItems(_ update: (inout TagFreeLayoutItem) -> Void) {
        for i in layout.items.indices where session.selectedItemIds.contains(layout.items[i].id) {
            var item = layout.items[i]; update(&item); layout.items[i] = item
        }
    }

    /// Batch-биндинг поля кнопки: читает из первичной, пишет во все выделенные.
    private func batchBinding<T>(_ keyPath: WritableKeyPath<TagFreeLayoutItem, T>, default def: T) -> Binding<T> {
        Binding(
            get: { batchValue(keyPath, default: def) },
            set: { newValue in updateSelectedItems { $0[keyPath: keyPath] = newValue } }
        )
    }

    /// `kind` = nil — выделены элементы разных видов; настройки внешнего вида применяются ко всем.
    private func batchItemSettings(kind: CanvasButtonKind?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: kind.map(itemIcon(for:)) ?? "square.on.square")
                    .foregroundColor(.secondary).frame(width: 14)
                Text(batchSelectionTitle)
                    .font(.headline).lineLimit(1)
                Spacer()
                Button(action: { session.selectedItemId = nil; session.selectedItemIds = [] }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.top, 4)

            Divider()
            copyPasteButtons

            // Удаление всего выделения (теги остаются: их кнопки восстанавливает нормализация).
            let removableSelected = removableItemIds(in: session.selectedItemIds)
            if !removableSelected.isEmpty {
                Button(role: .destructive, action: removeSelectedFromCanvas) {
                    SwiftUI.Label(String(format: ^String.Titles.canvasRemoveFromCanvas, removableSelected.count),
                                  systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            Divider()
            sectionHeader(^String.Titles.keyBindingsVisibilitySection)
            Toggle(^String.Titles.keyBindingsItemVisible,
                   isOn: batchBinding(\.isVisible, default: true)).font(.caption)

            // Цвет самой кнопки-тега (меняет цвет тега в коллекции). Для лейблов недоступно —
            // в смешанном выделении применяется только к выделенным тегам.
            if !selectedTagElementIds.isEmpty, onSetTagsColor != nil {
                Divider()
                sectionHeader(^String.Titles.freeLayoutSectionFill)
                HStack {
                    Text(^String.Titles.color).font(.caption)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: {
                            guard let firstTagId = selectedTagElementIds.first else { return Color(hex: "808080") }
                            let hex = tags.first(where: { $0.id == firstTagId })?.color ?? "808080"
                            return Color(hex: hex)
                        },
                        set: { newColor in
                            let hex = newColor.toHex() ?? "808080"
                            onSetTagsColor?(selectedTagElementIds, hex)
                        }
                    )).frame(width: 40, height: 24)
                }
            }

            Divider()
            sectionHeader(^String.Titles.freeLayoutSectionShape)
            batchShapeGrid

            Divider()
            sectionHeader(^String.Titles.freeLayoutSectionFill)
            HStack {
                Text(^String.Titles.freeLayoutOpacity).font(.caption)
                Spacer()
                Text("\(Int(batchValue(\.fillOpacity, default: 1) * 100))%").font(.caption).foregroundColor(.secondary)
            }
            Slider(value: batchBinding(\.fillOpacity, default: 1), in: 0...1, step: 0.05)

            Divider()
            sectionHeader(^String.Titles.freeLayoutSectionStroke)
            HStack {
                Text(^String.Titles.freeLayoutColor).font(.caption)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { batchValue(\.strokeColor, default: nil).map { Color(hex: $0) } ?? Color.black.opacity(0.3) },
                    set: { c in updateSelectedItems { $0.strokeColor = c.toHex() ?? "000000" } }
                )).frame(width: 40, height: 24)
            }
            HStack {
                Text(^String.Titles.freeLayoutThickness).font(.caption)
                Spacer()
                Text("\(Int(batchValue(\.strokeWidth, default: 1)))pt").font(.caption).foregroundColor(.secondary)
                Stepper("", value: batchBinding(\.strokeWidth, default: 1), in: 0...10, step: 1).labelsHidden()
            }
            HStack(spacing: 4) {
                strokeStyleButton(label: ^String.Titles.freeLayoutStrokeSolid, dashed: false, binding: batchBinding(\.strokeDashed, default: false))
                strokeStyleButton(label: ^String.Titles.freeLayoutStrokeDashed, dashed: true, binding: batchBinding(\.strokeDashed, default: false))
            }

            Divider()
            sectionHeader(^String.Titles.freeLayoutSectionText)
            Toggle(^String.Titles.freeLayoutShowLabel, isOn: batchBinding(\.showLabel, default: true))
            HStack {
                Text(^String.Titles.freeLayoutColor).font(.caption)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { batchValue(\.textColor, default: nil).map { Color(hex: $0) } ?? Color.white },
                    set: { c in updateSelectedItems { $0.textColor = c.toHex() ?? "FFFFFF" } }
                )).frame(width: 40, height: 24)
            }
            HStack {
                Text(^String.Titles.freeLayoutFontSize).font(.caption)
                Spacer()
                Text("\(Int(batchValue(\.fontSize, default: 12)))pt").font(.caption).foregroundColor(.secondary)
                Stepper("", value: batchBinding(\.fontSize, default: 12), in: 8...32, step: 1).labelsHidden()
            }
            HStack(spacing: 3) {
                fontWeightButton(label: "R", weight: .regular, binding: batchBinding(\.fontWeight, default: .medium))
                fontWeightButton(label: "M", weight: .medium, binding: batchBinding(\.fontWeight, default: .medium))
                fontWeightButton(label: "B", weight: .bold, binding: batchBinding(\.fontWeight, default: .medium))
            }

            Divider()
            sectionHeader(^String.Titles.freeLayoutSectionShadow)
            Toggle(^String.Titles.freeLayoutShadowEnabled, isOn: batchBinding(\.shadowEnabled, default: true))

            Spacer(minLength: 20)
        }
    }

    private var batchShapeGrid: some View {
        let shapes: [(TagFreeLayoutShape, String)] = [
            (.square, "square"), (.circle, "circle"), (.triangle, "triangle"),
            (.star, "star"), (.diamond, "diamond"), (.hexagon, "hexagon"), (.capsule, "capsule")
        ]
        let current = batchValue(\.shape, default: .square)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 6) {
            ForEach(shapes, id: \.0) { shape, name in
                Button(action: { updateSelectedItems { $0.shape = shape } }) {
                    TagFreeShapeView(shape: shape, cornerRadius: 4)
                        .fill(current == shape ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 32, height: 24)
                }
                .buttonStyle(.plain)
                .help(name.capitalized)
            }
        }
    }

    // MARK: - Copy / paste buttons

    /// elementId выделенных тегов.
    private var selectedTagElementIds: [String] {
        layout.items.filter { session.selectedItemIds.contains($0.id) && $0.kind == .tag }.map { $0.elementId }
    }

    @ViewBuilder
    private var copyPasteButtons: some View {
        let canDuplicate = onDuplicateElement != nil
        HStack(spacing: 6) {
            Button(action: copySelectedButtons) {
                SwiftUI.Label(String(format: ^String.Titles.canvasCopyButtons, session.selectedItemIds.count),
                              systemImage: "doc.on.doc").font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(session.selectedItemIds.isEmpty)

            if canDuplicate {
                Button(action: pasteButtons) {
                    SwiftUI.Label(String(format: ^String.Titles.canvasPasteButtons, clipboard.items.count),
                                  systemImage: "doc.on.clipboard").font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(!clipboard.hasContent)
            }
        }
    }

    /// Копирует выделенные кнопки в буфер (только визуал, без связок).
    private func copySelectedButtons() {
        let items = layout.items.filter { session.selectedItemIds.contains($0.id) }
        guard !items.isEmpty else { return }
        CanvasButtonClipboard.shared.copy(items)
    }

    /// Вставляет кнопки из буфера: дублирует сущности в коллекции, кладёт новые кнопки со смещением, без связок.
    private func pasteButtons() {
        guard let duplicate = onDuplicateElement, clipboard.hasContent else { return }
        let offset: CGFloat = 30
        var newIds = Set<String>()
        for source in clipboard.items {
            guard let newElementId = duplicate(source.kind, source.elementId) else { continue }
            var newItem = source
            newItem.elementId = newElementId
            newItem.center = CGPoint(x: source.center.x + offset, y: source.center.y + offset)
            // Не создаём дубликат поверх уже существующей кнопки той же сущности.
            guard !layout.items.contains(where: { $0.id == newItem.id }) else { continue }
            layout.items.append(newItem)
            newIds.insert(newItem.id)
        }
        if !newIds.isEmpty {
            session.selectedItemIds = newIds
            session.selectedItemId = newIds.first
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
            case .map:       return playFields.first(where: { $0.id == item.elementId })?.name ?? item.elementId
            case .clock:     return clocks.first(where: { $0.id == item.elementId })?.name ?? item.elementId
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: itemIcon(for: item.kind))
                    .foregroundColor(.secondary).frame(width: 14)
                Text(displayName).font(.headline).lineLimit(1)
                Spacer()
                Button(action: { session.selectedItemId = nil; session.selectedItemIds = [] }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.top, 4)

            Divider()
            copyPasteButtons

            Divider()

            // Visibility toggle
            sectionHeader(^String.Titles.keyBindingsVisibilitySection)
            Toggle(^String.Titles.keyBindingsItemVisible, isOn: binding.isVisible)
                .font(.caption)

            // У счётчика оформление своё (вариант циферблата, сотые и т.д.) — в его параметрах.
            // Общие «внешние» секции ему не подходят: фон/подпись/обводку он не рисует.
            if item.kind == .clock {
                Divider()
                Text(^String.Titles.clockAppearanceInOwnSettings)
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
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

                // Фон-картинка (только для тегов/лейблов; у карты фон — сама карта).
                if item.kind != .map {
                    Divider()
                    sectionHeader(^String.Titles.freeLayoutBackgroundImage)
                    HStack(spacing: 6) {
                        Button(item.backgroundImageBookmark == nil ? ^String.Titles.freeLayoutChooseImage : ^String.Titles.freeLayoutReplaceImage) {
                            pickBackgroundImage(binding: binding)
                        }
                        .font(.caption2).buttonStyle(.bordered)
                        if item.backgroundImageBookmark != nil {
                            Button(^String.Titles.reset) { binding.backgroundImageBookmark.wrappedValue = nil }
                                .font(.caption2).buttonStyle(.bordered)
                        }
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
            }

            Divider()

            // Geometry
            sectionHeader(^String.Titles.freeLayoutSectionGeometry)
            VStack(alignment: .leading, spacing: 6) {
                if item.kind != .clock, binding.shape.wrappedValue == .square {
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

            if item.kind != .clock {
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
            let removableHere = removableItemIds(in: contextTargets(for: item))
            if !removableHere.isEmpty {
                Button(role: .destructive, action: {
                    selectForContext(item)
                    removeSelectedFromCanvas()
                }) {
                    SwiftUI.Label(String(format: ^String.Titles.canvasRemoveFromCanvas, removableHere.count),
                                  systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                Divider()
            }

            sectionHeader(^String.Titles.freeLayoutCanvasSettings)
            Toggle(^String.Titles.freeLayoutShowGrid, isOn: $session.showGrid).font(.caption)

            Spacer(minLength: 20)
        }
    }

    // MARK: - Add label to canvas

    func addLabelToCanvas(_ label: Label) {
        TagFreeLayoutStorage.addLabelToLayout(&layout, label: label)
    }

    func addTimeEventToCanvas(_ event: TimeEvent) {
        TagFreeLayoutStorage.addTimeEventToLayout(&layout, event: event)
    }

    func addMapToCanvas(_ field: PlayField) {
        TagFreeLayoutStorage.addMapToLayout(&layout, field: field)
    }

    private func itemIcon(for kind: CanvasButtonKind) -> String {
        switch kind {
        case .tag:       return "tag.fill"
        case .label:     return "textformat"
        case .timeEvent: return "clock"
        case .map:       return "map"
        case .clock:     return "stopwatch"
        }
    }

    func addClockToCanvas(_ clock: ClockEntity) {
        TagFreeLayoutStorage.addClockToLayout(&layout, clock: clock)
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

// MARK: - Legacy sheet wrapper

struct TagFreeLayoutEditorView: View {

    let collectionId: String
    let collectionName: String
    let tags: [Tag]
    let labels: [Label]
    let timeEvents: [TimeEvent]
    /// Двойной клик по элементу холста — открыть редактирование самого тега/лейбла/события.
    var onEditElement: ((CanvasButtonKind, String) -> Void)? = nil

    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var session = TagFreeLayoutEditorSession()
    @State private var layout: TagFreeLayout

    init(collectionId: String, collectionName: String, tags: [Tag], labels: [Label] = [], timeEvents: [TimeEvent] = [], onEditElement: ((CanvasButtonKind, String) -> Void)? = nil) {
        self.collectionId = collectionId
        self.collectionName = collectionName
        self.tags = tags
        self.labels = labels
        self.timeEvents = timeEvents
        self.onEditElement = onEditElement

        let stored = TagFreeLayoutStorage.loadLayoutIfExists(
            collectionId: collectionId, tags: tags, labels: labels, timeEvents: timeEvents
        )
        _layout = State(initialValue: stored ?? TagFreeLayoutStorage.makeDefaultLayout(for: tags))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(^String.Titles.freeLayoutTitle).font(.headline)
                    Text(collectionName).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button(^String.Titles.cancelButtonTitle) {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderless)
                Button(^String.Titles.sportCutReset) {
                    layout = TagFreeLayoutStorage.makeDefaultLayout(for: tags)
                    session.resetSelection()
                }
                .buttonStyle(.bordered)
                Button(^String.Titles.saveButtonTitle) {
                    TagFreeLayoutStorage.saveLayout(layout, collectionId: collectionId)
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            TagFreeLayoutEditorContent(
                session: session,
                layout: $layout,
                tags: tags,
                labels: labels,
                timeEvents: timeEvents,
                pane: .full,
                showsModePicker: true,
                onEditElement: onEditElement
            )
        }
        .frame(minWidth: 960, minHeight: 600)
    }
}

// MARK: - TagFreeShapeView (reused in editor + canvas)

/// Отслеживает положение курсора внутри вью (для зума к курсору). macOS 13+; на 12 — no-op.
private struct HoverTracker: ViewModifier {
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
