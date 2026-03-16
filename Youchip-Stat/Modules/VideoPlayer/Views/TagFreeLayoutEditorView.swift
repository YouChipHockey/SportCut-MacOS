//
//  TagFreeLayoutEditorView.swift
//  Youchip-Stat
//
//  Редактор свободного отображения тегов коллекции.
//

import SwiftUI

struct TagFreeLayoutEditorView: View {
    
    let collectionId: String
    let collectionName: String
    let tags: [Tag]
    
    @Environment(\.presentationMode) private var presentationMode
    
    @State private var layout: TagFreeLayout
    @State private var selectedItemId: String? = nil
    @State private var draggingItemId: String? = nil
    @State private var resizingItemId: String? = nil
    @State private var rotatingItemId: String? = nil
    
    @State private var dragStartCenter: CGPoint = .zero
    @State private var resizeStartSize: CGSize = .zero
    @State private var rotateStartAngle: Double = 0
    
    @State private var showGrid: Bool = false
    @State private var snapToGrid: Bool = false
    private let gridStep: CGFloat = 50
    
    init(collectionId: String, collectionName: String, tags: [Tag]) {
        self.collectionId = collectionId
        self.collectionName = collectionName
        self.tags = tags
        
        if let stored = TagFreeLayoutStorage.loadLayoutIfExists(collectionId: collectionId, tags: tags) {
            _layout = State(initialValue: stored)
        } else {
            _layout = State(initialValue: TagFreeLayoutStorage.makeDefaultLayout(for: tags))
        }
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
                GeometryReader { geometry in
                    let availableWidth = max(geometry.size.width - 32, 300)
                    let scale = max(availableWidth / max(layout.canvasWidth, 1), 0.1)
                    let canvasHeight = layout.canvasHeight * scale
                    
                    ScrollView(.vertical) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                            
                            if showGrid {
                                gridOverlay(scale: scale)
                            }
                            
                            canvasView(scale: scale)
                        }
                        .frame(width: availableWidth, height: canvasHeight)
                        .padding(16)
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                }
                
                Divider()
                
                settingsPanel
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Свободное отображение тегов")
                    .font(.headline)
                Text(collectionName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Отмена") {
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.borderless)
            
            Button("Сбросить") {
                layout = TagFreeLayoutStorage.makeDefaultLayout(for: tags)
                selectedItemId = nil
            }
            .buttonStyle(.bordered)
            
            Button("Сохранить") {
                TagFreeLayoutStorage.saveLayout(layout, collectionId: collectionId)
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Grid Overlay
    
    private func gridOverlay(scale: CGFloat) -> some View {
        Canvas { context, size in
            let step = gridStep * scale
            var x = step
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
                x += step
            }
            var y = step
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
                y += step
            }
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Canvas
    
    private func canvasView(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedItemId = nil
                }
            
            ForEach(layout.items) { item in
                if let tag = tags.first(where: { $0.id == item.tagId }) {
                    tagItemView(item: item, tag: tag, scale: scale)
                        .position(x: item.center.x * scale, y: item.center.y * scale)
                }
            }
        }
        .coordinateSpace(name: "canvas")
    }
    
    // MARK: - Tag Item View
    
    private func tagItemView(
        item: TagFreeLayoutItem,
        tag: Tag,
        scale: CGFloat
    ) -> some View {
        let isSelected = selectedItemId == item.id
        let viewSize = CGSize(width: item.size.width * scale, height: item.size.height * scale)
        let fillColor = Color(hex: tag.color).opacity(item.fillOpacity)
        let strokeCol = item.strokeColor.map { Color(hex: $0) } ?? Color.black.opacity(0.3)
        let strokeStyle = StrokeStyle(
            lineWidth: isSelected ? 2 : item.strokeWidth,
            dash: (isSelected ? true : item.strokeDashed) ? [4, 3] : []
        )
        let textCol = item.textColor.map { Color(hex: $0) } ?? Color.white
        let swiftFontWeight: Font.Weight = {
            switch item.fontWeight {
            case .regular: return .regular
            case .medium: return .medium
            case .bold: return .bold
            }
        }()
        
        let content = TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius)
            .fill(fillColor)
            .overlay(
                Group {
                    if item.showLabel {
                        Text(tag.name)
                            .font(.system(size: item.fontSize, weight: swiftFontWeight))
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
                    .stroke(isSelected ? Color.accentColor : strokeCol, style: strokeStyle)
            )
        
        return ZStack {
            content
            
            if isSelected {
                rotationHandle(item: item, scale: scale)
                    .position(x: viewSize.width / 2, y: 10)
                
                resizeHandle(item: item, scale: scale)
                    .position(x: viewSize.width - 10, y: viewSize.height - 10)
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .rotationEffect(.degrees(item.rotation))
        .shadow(
            color: item.shadowEnabled
                ? (isSelected ? Color.accentColor.opacity(0.4) : Color.black.opacity(item.shadowIntensity))
                : Color.clear,
            radius: item.shadowEnabled ? (isSelected ? 8 : 4) : 0,
            x: 0,
            y: item.shadowEnabled ? 2 : 0
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedItemId = item.id
        }
        .gesture(
            isSelected ?
            DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                .onChanged { value in
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
                    let halfW = item.size.width / 2
                    let halfH = item.size.height / 2
                    updateItem(id: item.id) { mutable in
                        mutable.center = CGPoint(
                            x: min(max(halfW, newX), layout.canvasWidth - halfW),
                            y: min(max(halfH, newY), layout.canvasHeight - halfH)
                        )
                    }
                }
                .onEnded { _ in
                    draggingItemId = nil
                }
            : nil
        )
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
                        if rotatingItemId == nil {
                            rotatingItemId = item.id
                            rotateStartAngle = item.rotation
                        }
                        guard rotatingItemId == item.id else { return }
                        let delta = value.translation.width / scale
                        updateItem(id: item.id) { $0.rotation = rotateStartAngle + Double(delta) }
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
                        if resizingItemId == nil {
                            resizingItemId = item.id
                            resizeStartSize = item.size
                        }
                        guard resizingItemId == item.id else { return }
                        let dw = value.translation.width / scale
                        let dh = value.translation.height / scale
                        updateItem(id: item.id) { mutable in
                            let minSize: CGFloat = 40
                            var newW = max(minSize, resizeStartSize.width + dw)
                            var newH = max(minSize, resizeStartSize.height + dh)
                            if mutable.aspectRatioLocked && resizeStartSize.height > 0 {
                                let ratio = resizeStartSize.width / resizeStartSize.height
                                let avgDelta = (dw + dh) / 2
                                newW = max(minSize, resizeStartSize.width + avgDelta)
                                newH = max(minSize, newW / ratio)
                            }
                            mutable.size = CGSize(width: newW, height: newH)
                        }
                    }
                    .onEnded { _ in resizingItemId = nil }
            )
    }
    
    // MARK: - Settings Panel
    
    private var settingsPanel: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let itemId = selectedItemId,
                   let index = layout.items.firstIndex(where: { $0.id == itemId }),
                   let tag = tags.first(where: { $0.id == itemId }) {
                    selectedItemSettings(index: index, tag: tag)
                } else {
                    canvasSettings
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 210)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Canvas-Level Settings (no selection)
    
    private var canvasSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Настройки холста")
                .font(.headline)
                .padding(.top, 4)
            
            Divider()
            
            Toggle("Показать сетку", isOn: $showGrid)
            Toggle("Привязка к сетке", isOn: $snapToGrid)
            
            Text("Выберите элемент\nдля настройки")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }
    
    // MARK: - Selected Item Settings
    
    private func selectedItemSettings(index: Int, tag: Tag) -> some View {
        let binding = $layout.items[index]
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tag.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: { selectedItemId = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
            
            Divider()
            
            // --- Shape Picker ---
            sectionHeader("Форма")
            shapePickerGrid(binding: binding)
            
            Divider()
            
            // --- Fill ---
            sectionHeader("Заливка")
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Прозрачность")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(binding.fillOpacity.wrappedValue * 100))%")
                        .font(.caption).foregroundColor(.secondary)
                }
                Slider(value: binding.fillOpacity, in: 0...1, step: 0.05)
                HStack(spacing: 4) {
                    Button("Прозрачный") { binding.fillOpacity.wrappedValue = 0 }
                        .font(.caption2).buttonStyle(.bordered)
                    Button("Непрозрачный") { binding.fillOpacity.wrappedValue = 1 }
                        .font(.caption2).buttonStyle(.bordered)
                }
            }
            
            Divider()
            
            // --- Stroke ---
            sectionHeader("Обводка")
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Цвет").font(.caption)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: {
                            binding.strokeColor.wrappedValue.map { Color(hex: $0) } ?? Color.black.opacity(0.3)
                        },
                        set: { newColor in
                            binding.strokeColor.wrappedValue = newColor.toHex() ?? "000000"
                        }
                    ))
                    .frame(width: 40, height: 24)
                }
                HStack {
                    Text("Толщина").font(.caption)
                    Spacer()
                    Text("\(Int(binding.strokeWidth.wrappedValue))pt").font(.caption).foregroundColor(.secondary)
                    Stepper("", value: binding.strokeWidth, in: 0...10, step: 1).labelsHidden()
                }
                HStack(spacing: 4) {
                    strokeStyleButton(label: "Сплошная", dashed: false, binding: binding.strokeDashed)
                    strokeStyleButton(label: "Пунктир", dashed: true, binding: binding.strokeDashed)
                }
            }
            
            Divider()
            
            // --- Text ---
            sectionHeader("Текст")
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Показывать подпись", isOn: binding.showLabel)
                
                if binding.showLabel.wrappedValue {
                    HStack {
                        Text("Цвет").font(.caption)
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: {
                                binding.textColor.wrappedValue.map { Color(hex: $0) } ?? Color.white
                            },
                            set: { newColor in
                                binding.textColor.wrappedValue = newColor.toHex() ?? "FFFFFF"
                            }
                        ))
                        .frame(width: 40, height: 24)
                    }
                    HStack {
                        Text("Размер").font(.caption)
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
            
            // --- Geometry ---
            sectionHeader("Геометрия")
            VStack(alignment: .leading, spacing: 6) {
                if binding.shape.wrappedValue == .square {
                    HStack {
                        Text("Скругление").font(.caption)
                        Spacer()
                        Text("\(Int(binding.cornerRadius.wrappedValue))").font(.caption).foregroundColor(.secondary)
                    }
                    Slider(value: binding.cornerRadius, in: 0...40, step: 1)
                }
                
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ш").font(.caption2).foregroundColor(.secondary)
                        TextField("", value: cgFloatBinding(binding.size.width), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 70)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("В").font(.caption2).foregroundColor(.secondary)
                        TextField("", value: cgFloatBinding(binding.size.height), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 70)
                    }
                }
                
                Toggle("Фиксировать пропорции", isOn: binding.aspectRatioLocked)
                    .font(.caption)
                
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("X").font(.caption2).foregroundColor(.secondary)
                        TextField("", value: cgFloatBinding(binding.center.x), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 70)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Y").font(.caption2).foregroundColor(.secondary)
                        TextField("", value: cgFloatBinding(binding.center.y), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 70)
                    }
                }
                
                HStack {
                    Text("Поворот").font(.caption)
                    Spacer()
                    Text("\(Int(binding.rotation.wrappedValue))°").font(.caption).foregroundColor(.secondary)
                }
                Slider(value: binding.rotation, in: -180...180, step: 1)
            }
            
            Divider()
            
            // --- Shadow ---
            sectionHeader("Тень")
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Включена", isOn: binding.shadowEnabled)
                if binding.shadowEnabled.wrappedValue {
                    HStack {
                        Text("Интенсивность").font(.caption)
                        Spacer()
                        Text("\(Int(binding.shadowIntensity.wrappedValue * 100))%").font(.caption).foregroundColor(.secondary)
                    }
                    Slider(value: binding.shadowIntensity, in: 0...1, step: 0.05)
                }
            }
            
            Divider()
            
            // --- Z-Order ---
            sectionHeader("Порядок")
            HStack(spacing: 4) {
                Button(action: { sendToBack(id: binding.id) }) {
                    Image(systemName: "square.3.layers.3d.bottom.filled")
                }
                .buttonStyle(.bordered).font(.caption)
                Button(action: { moveBackward(id: binding.id) }) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.bordered).font(.caption)
                Button(action: { moveForward(id: binding.id) }) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.bordered).font(.caption)
                Button(action: { bringToFront(id: binding.id) }) {
                    Image(systemName: "square.3.layers.3d.top.filled")
                }
                .buttonStyle(.bordered).font(.caption)
            }
            
            Divider()
            
            // --- Alignment ---
            sectionHeader("Выравнивание")
            HStack(spacing: 4) {
                Button("По центру ↔") {
                    updateItem(id: binding.id) { $0.center.x = layout.canvasWidth / 2 }
                }
                .font(.caption2).buttonStyle(.bordered)
                Button("По центру ↕") {
                    updateItem(id: binding.id) { $0.center.y = layout.canvasHeight / 2 }
                }
                .font(.caption2).buttonStyle(.bordered)
            }
            
            Divider()
            
            // --- Canvas settings (always visible at bottom) ---
            sectionHeader("Холст")
            Toggle("Показать сетку", isOn: $showGrid)
                .font(.caption)
            Toggle("Привязка к сетке", isOn: $snapToGrid)
                .font(.caption)
            
            Spacer(minLength: 20)
        }
    }
    
    // MARK: - Panel Helpers
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
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
            .font(.caption2)
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(binding.wrappedValue == dashed ? Color.accentColor.opacity(0.2) : Color.clear)
            )
    }
    
    private func fontWeightButton(label: String, weight: TagFreeLayoutFontWeight, binding: Binding<TagFreeLayoutFontWeight>) -> some View {
        let swiftWeight: Font.Weight = weight == .bold ? .bold : (weight == .medium ? .medium : .regular)
        return Button(label) { binding.wrappedValue = weight }
            .font(.system(size: 12, weight: swiftWeight))
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(binding.wrappedValue == weight ? Color.accentColor.opacity(0.2) : Color.clear)
            )
    }
    
    // MARK: - Helpers
    
    private func cgFloatBinding(_ source: Binding<CGFloat>) -> Binding<Double> {
        Binding<Double>(
            get: { Double(source.wrappedValue) },
            set: { source.wrappedValue = CGFloat($0) }
        )
    }
    
    // MARK: - Item Mutation
    
    private func updateItem(id: String, _ update: (inout TagFreeLayoutItem) -> Void) {
        if let index = layout.items.firstIndex(where: { $0.id == id }) {
            var item = layout.items[index]
            update(&item)
            layout.items[index] = item
        }
    }
    
    private func bringToFront(id: String) {
        if let index = layout.items.firstIndex(where: { $0.id == id }) {
            let item = layout.items.remove(at: index)
            layout.items.append(item)
        }
    }
    
    private func sendToBack(id: String) {
        if let index = layout.items.firstIndex(where: { $0.id == id }) {
            let item = layout.items.remove(at: index)
            layout.items.insert(item, at: 0)
        }
    }
    
    private func moveForward(id: String) {
        if let index = layout.items.firstIndex(where: { $0.id == id }), index < layout.items.count - 1 {
            layout.items.swapAt(index, index + 1)
        }
    }
    
    private func moveBackward(id: String) {
        if let index = layout.items.firstIndex(where: { $0.id == id }), index > 0 {
            layout.items.swapAt(index, index - 1)
        }
    }
}

// MARK: - Shape View

struct TagFreeShapeView: Shape {
    let shape: TagFreeLayoutShape
    var cornerRadius: CGFloat = 8
    
    func path(in rect: CGRect) -> Path {
        switch shape {
        case .square:
            return Path(roundedRect: rect, cornerRadius: cornerRadius)
        case .circle:
            return Path(ellipseIn: rect)
        case .triangle:
            return trianglePath(in: rect)
        case .star:
            return starPath(in: rect)
        case .diamond:
            return diamondPath(in: rect)
        case .hexagon:
            return hexagonPath(in: rect)
        case .capsule:
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
        }
    }
    
    private func trianglePath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
    
    private func starPath(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.45
        var path = Path()
        let points = 5
        for i in 0..<(points * 2) {
            let angle = Double(i) * .pi / Double(points)
            let radius = (i % 2 == 0) ? outerRadius : innerRadius
            let x = center.x + CGFloat(cos(angle - .pi / 2)) * radius
            let y = center.y + CGFloat(sin(angle - .pi / 2)) * radius
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
    
    private func diamondPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
    
    private func hexagonPath(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for i in 0..<6 {
            let angle = CGFloat(Double(i) * .pi / 3.0 - .pi / 2.0)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

