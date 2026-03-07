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
    @State private var dragVisualOffset: CGSize = .zero
    @State private var resizeStartSize: CGSize = .zero
    @State private var rotateStartAngle: Double = 0
    
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
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
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
                        
                        canvasView(scale: scale)
                    }
                    .frame(width: availableWidth, height: canvasHeight)
                    .padding(16)
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
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
            }
            .buttonStyle(.bordered)
            
            Button("Сохранить") {
                TagFreeLayoutStorage.saveLayout(layout, collectionId: collectionId)
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private func canvasView(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedItemId = nil
                }
            
            ForEach(layout.items) { item in
                if let tag = tags.first(where: { $0.id == item.tagId }) {
                    let viewSize = CGSize(width: item.size.width * scale, height: item.size.height * scale)
                    let viewCenter = CGPoint(x: item.center.x * scale, y: item.center.y * scale)
                    let offset = CGPoint(
                        x: viewCenter.x - viewSize.width / 2,
                        y: viewCenter.y - viewSize.height / 2
                    )
                    let isDraggingThis = draggingItemId == item.id
                    let visualOffset = isDraggingThis ? dragVisualOffset : CGSize.zero
                    
                    tagItemView(
                        item: item,
                        tag: tag,
                        scale: scale,
                        dragVisualOffset: $dragVisualOffset,
                        onDragStarted: { draggingItemId = item.id; dragStartCenter = item.center },
                        onDragEnded: { commitDrag(itemId: item.id, translation: $0, scale: scale) }
                    )
                    .offset(x: offset.x + visualOffset.width, y: offset.y + visualOffset.height)
                }
            }
        }
    }
    
    private func tagItemView(
        item: TagFreeLayoutItem,
        tag: Tag,
        scale: CGFloat,
        dragVisualOffset: Binding<CGSize>,
        onDragStarted: @escaping () -> Void,
        onDragEnded: @escaping (CGSize) -> Void
    ) -> some View {
        let isSelected = selectedItemId == item.id
        let viewSize = CGSize(width: item.size.width * scale, height: item.size.height * scale)
        
        // Базовый контент фигуры с подписью
        let content = TagFreeShapeView(shape: item.shape)
            .fill(Color(hex: tag.color))
            .overlay(
                Text(tag.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(4)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            )
            .frame(width: viewSize.width, height: viewSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.3),
                            style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isSelected ? [4, 3] : []))
            )
        
        return ZStack {
            content
            
            if isSelected {
                // Кружок поворота — по центру сверху фигуры
                rotationHandle(item: item, scale: scale)
                    .position(x: viewSize.width / 2, y: 0)
                
                // Квадрат изменения размера — в правом нижнем углу фигуры
                resizeHandle(item: item, scale: scale)
                    .position(x: viewSize.width, y: viewSize.height)
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .rotationEffect(.degrees(item.rotation))
        .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : Color.black.opacity(0.2),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedItemId = item.id
        }
        .gesture(
            isSelected ?
            DragGesture()
                .onChanged { value in
                    if draggingItemId == nil {
                        onDragStarted()
                    }
                    dragVisualOffset.wrappedValue = value.translation
                }
                .onEnded { value in
                    guard draggingItemId == item.id else { return }
                    onDragEnded(value.translation)
                }
            : nil
        )
        .contextMenu {
            Button("Квадрат") {
                setShape(.square, for: item.id)
            }
            Button("Круг") {
                setShape(.circle, for: item.id)
            }
            Button("Треугольник") {
                setShape(.triangle, for: item.id)
            }
            Button("Звезда") {
                setShape(.star, for: item.id)
            }
            Divider()
            Button("Перенести вперед") {
                bringToFront(id: item.id)
            }
            Button("Переместить назад") {
                sendToBack(id: item.id)
            }
        }
    }
    
    private func rotationHandle(item: TagFreeLayoutItem, scale: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
            )
            .frame(width: 14, height: 14)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if rotatingItemId == nil {
                            rotatingItemId = item.id
                            rotateStartAngle = item.rotation
                        }
                        guard rotatingItemId == item.id else { return }
                        let delta = value.translation.width / scale
                        updateItem(id: item.id) { mutable in
                            mutable.rotation = rotateStartAngle + Double(delta)
                        }
                    }
                    .onEnded { _ in
                        rotatingItemId = nil
                    }
            )
    }
    
    private func resizeHandle(item: TagFreeLayoutItem, scale: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white)
            .overlay(
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
            )
            .frame(width: 14, height: 14)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if resizingItemId == nil {
                            resizingItemId = item.id
                            resizeStartSize = item.size
                        }
                        guard resizingItemId == item.id else { return }
                        let deltaWidth = value.translation.width / scale
                        let deltaHeight = value.translation.height / scale
                        updateItem(id: item.id) { mutable in
                            let minSize: CGFloat = 40
                            let newWidth = max(minSize, resizeStartSize.width + deltaWidth)
                            let newHeight = max(minSize, resizeStartSize.height + deltaHeight)
                            mutable.size = CGSize(width: newWidth, height: newHeight)
                        }
                    }
                    .onEnded { _ in
                        resizingItemId = nil
                    }
            )
    }
    
    private func updateItem(id: String, _ update: (inout TagFreeLayoutItem) -> Void) {
        if let index = layout.items.firstIndex(where: { $0.id == id }) {
            var item = layout.items[index]
            update(&item)
            layout.items[index] = item
        }
    }
    
    private func setShape(_ shape: TagFreeLayoutShape, for id: String) {
        updateItem(id: id) { mutable in
            mutable.shape = shape
        }
    }

    private func commitDrag(itemId: String, translation: CGSize, scale: CGFloat) {
        let delta = CGPoint(x: translation.width / scale, y: translation.height / scale)
        updateItem(id: itemId) { mutable in
            let newCenter = CGPoint(x: dragStartCenter.x + delta.x, y: dragStartCenter.y + delta.y)
            let halfWidth = mutable.size.width / 2
            let halfHeight = mutable.size.height / 2
            let clampedX = min(max(halfWidth, newCenter.x), layout.canvasWidth - halfWidth)
            let clampedY = min(max(halfHeight, newCenter.y), layout.canvasHeight - halfHeight)
            mutable.center = CGPoint(x: clampedX, y: clampedY)
        }
        draggingItemId = nil
        dragVisualOffset = .zero
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
}

/// Примитивные фигуры для свободной раскладки.
struct TagFreeShapeView: Shape {
    let shape: TagFreeLayoutShape
    
    func path(in rect: CGRect) -> Path {
        switch shape {
        case .square:
            return Path(roundedRect: rect, cornerRadius: 8)
        case .circle:
            return Path(ellipseIn: rect)
        case .triangle:
            return trianglePath(in: rect)
        case .star:
            return starPath(in: rect)
        }
    }
    
    private func trianglePath(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        path.move(to: top)
        path.addLine(to: bottomLeft)
        path.addLine(to: bottomRight)
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
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

