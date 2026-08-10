//
//  EditorImagesOverlay.swift
//  Youchip-Stat
//
//  Слой пользовательских картинок поверх рисовалки в самостоятельном редакторе.
//  Картинки ведут себя как фигуры: перетаскивание, изменение размера (за угол,
//  с сохранением пропорций) и поворот (за верхнюю ручку). Взаимодействие активно
//  только при выбранном инструменте «Картинки».
//

import SwiftUI

struct EditorImagesOverlay: View {
    @ObservedObject var drawingState: EditorDrawingState
    /// Скрыть выделение/ручки (для рендера итоговой картинки).
    var renderMode: Bool = false

    private let coordSpace = "imageEditorCanvas"
    private let handleSize: CGFloat = 20

    // Живое состояние жестов.
    @State private var dragStartPosition: CGPoint?
    @State private var resizeStartSize: CGSize?
    @State private var resizeStartDistance: CGFloat?
    @State private var rotateStartAngle: CGFloat?
    @State private var rotateStartRotation: CGFloat?

    private var isImageTool: Bool { drawingState.currentTool == .image }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(drawingState.images) { obj in
                imageView(obj)
            }
        }
        .coordinateSpace(name: coordSpace)
        // В режиме картинок пустой тап снимает выделение; иначе слой не мешает рисовать.
        .allowsHitTesting(isImageTool && !renderMode)
    }

    @ViewBuilder
    private func imageView(_ obj: EditorImageObject) -> some View {
        let isSelected = drawingState.selectedImageId == obj.id && isImageTool && !renderMode

        Group {
            if let image = obj.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: obj.size.width, height: obj.size.height)
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
                    .frame(width: obj.size.width, height: obj.size.height)
            }
        }
        .overlay(selectionChrome(obj, isSelected: isSelected))
        .rotationEffect(.radians(Double(obj.rotation)))
        .position(obj.position)
        .gesture(bodyDrag(obj))
    }

    @ViewBuilder
    private func selectionChrome(_ obj: EditorImageObject, isSelected: Bool) -> some View {
        if isSelected {
            ZStack {
                Rectangle()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

                // Ручка поворота — сверху по центру.
                Circle().fill(Color.accentColor)
                    .frame(width: handleSize, height: handleSize)
                    .overlay(Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.white))
                    .position(x: obj.size.width / 2, y: -handleSize)
                    .gesture(rotateDrag(obj))

                // Кнопка удаления — левый верхний угол.
                Button(action: {
                    drawingState.selectedImageId = obj.id
                    drawingState.deleteSelectedImage()
                }) {
                    Circle().fill(Color.red)
                        .frame(width: handleSize, height: handleSize)
                        .overlay(Image(systemName: "trash")
                            .font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                }
                .buttonStyle(.plain)
                .position(x: -handleSize / 2, y: -handleSize / 2)

                // Ручка масштаба — правый нижний угол.
                Circle().fill(Color.accentColor)
                    .frame(width: handleSize, height: handleSize)
                    .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.white))
                    .position(x: obj.size.width + handleSize / 2, y: obj.size.height + handleSize / 2)
                    .gesture(resizeDrag(obj))
            }
            .frame(width: obj.size.width, height: obj.size.height)
        }
    }

    // MARK: - Жесты

    private func bodyDrag(_ obj: EditorImageObject) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordSpace))
            .onChanged { value in
                guard isImageTool, !renderMode else { return }
                if drawingState.selectedImageId != obj.id { drawingState.selectedImageId = obj.id }
                if dragStartPosition == nil { dragStartPosition = obj.position }
                guard let start = dragStartPosition else { return }
                update(obj.id) {
                    $0.position = CGPoint(x: start.x + value.translation.width,
                                          y: start.y + value.translation.height)
                }
            }
            .onEnded { _ in dragStartPosition = nil }
    }

    private func resizeDrag(_ obj: EditorImageObject) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordSpace))
            .onChanged { value in
                guard isImageTool, !renderMode else { return }
                let center = obj.position
                let dist = hypot(value.location.x - center.x, value.location.y - center.y)
                if resizeStartSize == nil {
                    resizeStartSize = obj.size
                    resizeStartDistance = max(dist, 1)
                }
                guard let startSize = resizeStartSize, let startDist = resizeStartDistance else { return }
                let scale = max(0.1, dist / startDist)
                update(obj.id) {
                    $0.size = CGSize(width: max(20, startSize.width * scale),
                                     height: max(20, startSize.height * scale))
                }
            }
            .onEnded { _ in resizeStartSize = nil; resizeStartDistance = nil }
    }

    private func rotateDrag(_ obj: EditorImageObject) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordSpace))
            .onChanged { value in
                guard isImageTool, !renderMode else { return }
                let center = obj.position
                let angle = atan2(value.location.y - center.y, value.location.x - center.x)
                if rotateStartAngle == nil {
                    rotateStartAngle = angle
                    rotateStartRotation = obj.rotation
                }
                guard let startAngle = rotateStartAngle, let startRot = rotateStartRotation else { return }
                update(obj.id) { $0.rotation = startRot + (angle - startAngle) }
            }
            .onEnded { _ in rotateStartAngle = nil; rotateStartRotation = nil }
    }

    private func update(_ id: UUID, _ mutate: (inout EditorImageObject) -> Void) {
        guard let idx = drawingState.images.firstIndex(where: { $0.id == id }) else { return }
        mutate(&drawingState.images[idx])
    }
}
