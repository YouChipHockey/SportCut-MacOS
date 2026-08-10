//
//  SportCutSlideCanvasEditor.swift
//  Youchip-Stat
//
//  Большой удобный редактор титульного слайда: холст 16:9 с произвольным числом
//  текстовых и графических слоёв — их можно двигать, менять размер, шрифт, цвет.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SportCutSlideCanvasEditor: View {

    let onSave: (SportCutSlide) -> Void
    let onCancel: () -> Void

    @State private var slide: SportCutSlide
    @State private var selectedID: UUID?
    @State private var bgColor: Color
    @State private var bgHex: String

    // Состояние жестов (как в редакторе свободной раскладки: отдельно drag и resize).
    @State private var draggingID: UUID?
    @State private var dragStartCenter: CGPoint = .zero
    @State private var resizingID: UUID?
    @State private var resizeStartElement: SportCutSlideElement?
    /// Кэш декодированных картинок, чтобы не декодировать Data на каждом кадре перетаскивания.
    @State private var imageCache = SlideImageCache()

    private static let coordSpace = "slideCanvas"
    /// Список семейств шрифтов вычисляется один раз (иначе перечисление шрифтов на каждом кадре — лаги).
    private static let fontFamilies = NSFontManager.shared.availableFontFamilies

    init(slide: SportCutSlide, onSave: @escaping (SportCutSlide) -> Void, onCancel: @escaping () -> Void) {
        let migrated = slide.migratedToElements()
        _slide = State(initialValue: migrated)
        _bgColor = State(initialValue: Color(hex: migrated.backgroundColorHex))
        _bgHex = State(initialValue: migrated.backgroundColorHex)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var selectedElement: SportCutSlideElement? {
        guard let id = selectedID else { return nil }
        return slide.elements.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                canvasArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.underPageBackgroundColor))
                Divider()
                inspector
                    .frame(width: 300)
                    .background(Color(NSColor.windowBackgroundColor))
            }
            Divider()
            footer
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.angled").foregroundColor(.purple)
            Text(^String.Titles.sportCutSlideEditTitle).font(.headline)
            Spacer()
            Button {
                addTextElement()
            } label: {
                SwiftUI.Label(^String.Titles.sportCutSlideAddText, systemImage: "textformat")
            }
            .buttonStyle(.bordered)

            Button {
                addImageElement()
            } label: {
                SwiftUI.Label(^String.Titles.sportCutSlideAddImage, systemImage: "photo.badge.plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            let canvas = fittedCanvasSize(in: geo.size)
            ZStack {
                Color.clear
                canvasContent(canvas)
                    .frame(width: canvas.width, height: canvas.height)
                    .background(bgColor)
                    .clipped()
                    .overlay(
                        Rectangle().stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = nil }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(20)
    }

    private func canvasContent(_ canvas: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(slide.elements) { element in
                elementView(element, canvas: canvas)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .coordinateSpace(name: Self.coordSpace)
    }

    private func elementView(_ element: SportCutSlideElement, canvas: CGSize) -> some View {
        let isSelected = element.id == selectedID
        let size = elementPixelSize(element, canvas: canvas)
        let center = CGPoint(x: element.centerX * canvas.width, y: element.centerY * canvas.height)

        return elementContent(element, canvas: canvas, size: size)
            .frame(width: size.width, height: size.height)
            .overlay(
                Rectangle()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .opacity(isSelected ? 1 : 0)
            )
            .contentShape(Rectangle())
            // Перемещение — на теле элемента, в СТАБИЛЬНОЙ системе координат холста (иначе при
            // изменении кадра во время ресайза координаты «плывут» и элемент прыгает).
            .gesture(moveGesture(element, canvas: canvas, size: size))
            // Ресайз — отдельная ручка со своим жестом (как в редакторе свободной раскладки),
            // поэтому угол уверенно «хватается» и не конфликтует с перемещением.
            .overlay(
                isSelected
                ? AnyView(resizeHandle(element, canvas: canvas)
                    .offset(x: size.width / 2 - 8, y: size.height / 2 - 8))
                : AnyView(EmptyView())
            )
            .position(center)
    }

    @ViewBuilder
    private func elementContent(_ element: SportCutSlideElement, canvas: CGSize, size: CGSize) -> some View {
        switch element.kind {
        case .image:
            if let img = imageCache.image(for: element) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.3))
            }
        case .text:
            Text(element.text.isEmpty ? " " : element.text)
                .font(canvasFont(element, canvas: canvas))
                .foregroundColor(Color(hex: element.colorHex))
                .multilineTextAlignment(textAlignment(element.alignment))
                .frame(width: size.width, height: size.height, alignment: .center)
        }
    }

    private func resizeHandle(_ element: SportCutSlideElement, canvas: CGSize) -> some View {
        Circle()
            .fill(Color.accentColor)
            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .gesture(resizeGesture(element, canvas: canvas))
    }

    // MARK: - Gestures (раздельные drag / resize, стабильная система координат холста)

    private func moveGesture(_ element: SportCutSlideElement, canvas: CGSize, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordSpace))
            .onChanged { value in
                guard canvas.width > 0, canvas.height > 0 else { return }
                if draggingID == nil {
                    draggingID = element.id
                    dragStartCenter = CGPoint(x: element.centerX, y: element.centerY)
                    selectedID = element.id
                }
                guard draggingID == element.id else { return }
                let halfW = (Double(size.width) / 2) / Double(canvas.width)
                let halfH = (Double(size.height) / 2) / Double(canvas.height)
                let nx = Double(dragStartCenter.x) + Double(value.translation.width) / Double(canvas.width)
                let ny = Double(dragStartCenter.y) + Double(value.translation.height) / Double(canvas.height)
                updateElement(element.id) {
                    $0.centerX = clampCenter(nx, half: halfW)
                    $0.centerY = clampCenter(ny, half: halfH)
                }
            }
            .onEnded { _ in draggingID = nil }
    }

    private func resizeGesture(_ element: SportCutSlideElement, canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordSpace))
            .onChanged { value in
                guard canvas.width > 0, canvas.height > 0 else { return }
                if resizingID == nil {
                    resizingID = element.id
                    resizeStartElement = element
                    selectedID = element.id
                }
                guard resizingID == element.id, let start = resizeStartElement else { return }
                switch element.kind {
                case .image:
                    let dw = Double(value.translation.width) / Double(canvas.width)
                    let dh = Double(value.translation.height) / Double(canvas.height)
                    updateElement(element.id) {
                        $0.width = min(max(start.width + dw, 0.04), 1)
                        $0.height = min(max(start.height + dh, 0.04), 1)
                        $0.centerX = clampCenter($0.centerX, half: $0.width / 2)
                        $0.centerY = clampCenter($0.centerY, half: $0.height / 2)
                    }
                case .text:
                    let deltaPt = Double(value.translation.height) * (1080.0 / Double(canvas.height))
                    updateElement(element.id) { $0.fontSize = min(max(start.fontSize + deltaPt, 10), 400) }
                }
            }
            .onEnded { _ in
                resizingID = nil
                resizeStartElement = nil
            }
    }

    private func clampCenter(_ value: Double, half: Double) -> Double {
        if half >= 0.5 { return 0.5 }
        return min(max(value, half), 1 - half)
    }

    /// Размер элемента в точках холста (для картинки — из долей, для текста — измеряется как в рендерере).
    private func elementPixelSize(_ element: SportCutSlideElement, canvas: CGSize) -> CGSize {
        switch element.kind {
        case .image:
            return CGSize(width: max(8, element.width * canvas.width), height: max(8, element.height * canvas.height))
        case .text:
            let px = max(6, element.fontSize * Double(canvas.height) / 1080.0)
            let font = SportCutSlideRenderer.font(name: element.fontName, size: CGFloat(px), bold: element.bold)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = element.alignment == 0 ? .left : (element.alignment == 2 ? .right : .center)
            paragraph.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
            let maxW = canvas.width * 0.94
            let text = element.text.isEmpty ? " " : element.text
            let b = (text as NSString).boundingRect(
                with: CGSize(width: maxW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            return CGSize(width: min(maxW, ceil(b.width) + 10), height: ceil(b.height) + 10)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let element = selectedElement {
                    if element.kind == .text {
                        textInspector(element)
                    } else {
                        imageInspector(element)
                    }
                    Divider()
                } else {
                    Text(^String.Titles.sportCutSlideSelectHint)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }

                slideInspector
            }
            .padding(16)
        }
    }

    private func textInspector(_ element: SportCutSlideElement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorHeader(^String.Titles.sportCutSlideTextElement, elementID: element.id)

            field(^String.Titles.sportCutSlideTitleField) {
                TextEditor(text: bindingText(element.id))
                    .font(.system(size: 13))
                    .frame(height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor), lineWidth: 1))
            }

            field(^String.Titles.sportCutSlideFont) {
                Menu {
                    Button(^String.Titles.sportCutSlideFontSystem) { updateElement(element.id) { $0.fontName = nil } }
                    Divider()
                    ForEach(Self.fontFamilies, id: \.self) { family in
                        Button(family) { updateElement(element.id) { $0.fontName = family } }
                    }
                } label: {
                    Text(element.fontName ?? ^String.Titles.sportCutSlideFontSystem)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            field(^String.Titles.sportCutSlideTextSize) {
                HStack {
                    Slider(value: bindingFontSize(element.id), in: 12...300, step: 2)
                    Text("\(Int(element.fontSize))").frame(width: 40).foregroundColor(.secondary)
                }
            }

            field(^String.Titles.sportCutSlideTextColor) {
                ColorPickerView(
                    selectedColor: bindingTextColor(element.id),
                    hexString: bindingTextHex(element.id)
                )
            }

            HStack(spacing: 12) {
                Toggle(^String.Titles.sportCutSlideBold, isOn: bindingBold(element.id))
                Spacer()
                Picker("", selection: bindingAlignment(element.id)) {
                    Image(systemName: "text.alignleft").tag(0)
                    Image(systemName: "text.aligncenter").tag(1)
                    Image(systemName: "text.alignright").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .labelsHidden()
            }
        }
    }

    private func imageInspector(_ element: SportCutSlideElement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorHeader(^String.Titles.sportCutSlideImageElement, elementID: element.id)

            if let data = element.imageData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 120)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }

            Button {
                pickImage(for: element.id)
            } label: {
                SwiftUI.Label(^String.Titles.sportCutSlideReplaceImage, systemImage: "photo")
            }
            .buttonStyle(.bordered)
        }
    }

    private var slideInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(^String.Titles.sportCutSlidesManage)
                .font(.system(size: 13, weight: .semibold))

            field(^String.Titles.sportCutSlideBackground) {
                ColorPickerView(selectedColor: $bgColor, hexString: $bgHex)
                    .onChange(of: bgHex) { slide.backgroundColorHex = $0 }
            }

            field(^String.Titles.sportCutSlideDuration) {
                Stepper(value: $slide.durationSeconds, in: 1...60, step: 1) {
                    Text(String.Titles.sportCutSlideDurationSec.format(Int(slide.durationSeconds)))
                }
            }
        }
    }

    private func inspectorHeader(_ title: String, elementID: UUID) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                slide.elements.removeAll { $0.id == elementID }
                selectedID = nil
            } label: {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
            .help(^String.Titles.delete)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button(^String.Titles.collectionsButtonCancel) { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button(^String.Titles.sportCutSlideSave) {
                slide.backgroundColorHex = bgHex
                onSave(slide)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: - Element actions

    private func addTextElement() {
        var el = SportCutSlideElement(kind: .text, centerX: 0.5, centerY: 0.5,
                                      text: ^String.Titles.sportCutSlideNewText,
                                      colorHex: "FFFFFF", bold: true, alignment: 1)
        el.fontSize = 96
        slide.elements.append(el)
        selectedID = el.id
    }

    private func addImageElement() {
        guard let data = pickImageData() else { return }
        let aspect = imageAspect(data)
        let baseW = 0.4
        let el = SportCutSlideElement(kind: .image, centerX: 0.5, centerY: 0.5,
                                      width: baseW, height: baseW * aspect,
                                      imageData: data)
        slide.elements.append(el)
        selectedID = el.id
    }

    private func pickImage(for id: UUID) {
        guard let data = pickImageData() else { return }
        let aspect = imageAspect(data)
        updateElement(id) {
            $0.imageData = data
            $0.height = $0.width * aspect
        }
        imageCache.invalidate(id)
    }

    // MARK: - Helpers

    private func fittedCanvasSize(in available: CGSize) -> CGSize {
        let pad: CGFloat = 40
        let w = max(1, available.width - pad)
        let h = max(1, available.height - pad)
        let targetAspect: CGFloat = 16.0 / 9.0
        if w / h > targetAspect {
            return CGSize(width: h * targetAspect, height: h)
        } else {
            return CGSize(width: w, height: w / targetAspect)
        }
    }

    private func canvasFont(_ element: SportCutSlideElement, canvas: CGSize) -> Font {
        let px = element.fontSize * Double(canvas.height) / 1080.0
        if let name = element.fontName, !name.isEmpty {
            return Font.custom(name, size: max(6, px)).weight(element.bold ? .bold : .regular)
        }
        return Font.system(size: max(6, px), weight: element.bold ? .bold : .regular)
    }

    private func textAlignment(_ raw: Int) -> TextAlignment {
        switch raw {
        case 0: return .leading
        case 2: return .trailing
        default: return .center
        }
    }

    private func updateElement(_ id: UUID, _ mutate: (inout SportCutSlideElement) -> Void) {
        guard let idx = slide.elements.firstIndex(where: { $0.id == id }) else { return }
        mutate(&slide.elements[idx])
    }

    private func imageAspect(_ data: Data) -> Double {
        guard let img = NSImage(data: data), img.size.width > 0 else { return 0.6 }
        return Double(img.size.height / img.size.width)
    }

    private func pickImageData() -> Data? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return nil }
        // Приводим к PNG, чтобы гарантированно переносилось в данные слайда.
        if let img = NSImage(data: data), let png = img.pngData() {
            return png
        }
        return data
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
            content()
        }
    }

    // MARK: - Bindings for selected text element

    private func bindingText(_ id: UUID) -> Binding<String> {
        Binding(
            get: { slide.elements.first(where: { $0.id == id })?.text ?? "" },
            set: { v in updateElement(id) { $0.text = v } }
        )
    }
    private func bindingFontSize(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { slide.elements.first(where: { $0.id == id })?.fontSize ?? 96 },
            set: { v in updateElement(id) { $0.fontSize = v } }
        )
    }
    private func bindingBold(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { slide.elements.first(where: { $0.id == id })?.bold ?? true },
            set: { v in updateElement(id) { $0.bold = v } }
        )
    }
    private func bindingAlignment(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { slide.elements.first(where: { $0.id == id })?.alignment ?? 1 },
            set: { v in updateElement(id) { $0.alignment = v } }
        )
    }
    private func bindingTextColor(_ id: UUID) -> Binding<Color> {
        Binding(
            get: { Color(hex: slide.elements.first(where: { $0.id == id })?.colorHex ?? "FFFFFF") },
            set: { _ in }
        )
    }
    private func bindingTextHex(_ id: UUID) -> Binding<String> {
        Binding(
            get: { slide.elements.first(where: { $0.id == id })?.colorHex ?? "FFFFFF" },
            set: { v in updateElement(id) { $0.colorHex = v } }
        )
    }
}

/// Кэш декодированных `NSImage` по id элемента — чтобы не декодировать Data на каждом кадре
/// перетаскивания/ресайза (иначе жёсткие лаги на больших картинках).
final class SlideImageCache {
    private var map: [UUID: NSImage] = [:]

    func image(for element: SportCutSlideElement) -> NSImage? {
        if let cached = map[element.id] { return cached }
        guard let data = element.imageData, let img = NSImage(data: data) else { return nil }
        map[element.id] = img
        return img
    }

    func invalidate(_ id: UUID) { map[id] = nil }
}
