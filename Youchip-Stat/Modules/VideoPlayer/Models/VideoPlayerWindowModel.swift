//
//  VideoPlayerWindowModel.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa

// MARK: - Joystick Models

enum JoystickDirection {
    case up, down, left, right
}

// MARK: - Video Player State

struct VideoPlayerState {
    var videoScale: CGFloat = 1.0
    var videoOffset: CGSize = .zero
    var lastDragValue: CGSize = .zero
    
    var showScreenshotNameSheet: Bool = false
    var tempScreenshotImage: NSImage? = nil
    var currentScreenshotName: String = ""
    var screenshotImage: URL? = nil
    
    var detectionTimer: Timer? = nil
    var isDetectionEnabled: Bool = false
    
    // Editor Mode
    var isEditorMode: Bool = false
    /// Редактируем уже сохранённый рисунок (открыли через «Редактировать» на таймлайне): при сохранении — обновление, без нового тега.
    var isEditingExistingScreenshot: Bool = false
    var editorScreenshotName: String = ""
    var editorSaveAsTag: Bool = false
    var editorDisplayDuration: Double = 3.0
    var editorDrawingState: EditorDrawingState = EditorDrawingState()
    var savedWindowFrame: CGRect? = nil
    var editorScreenshotVideoTime: Double = 0.0
    var showTagSelectionSheet: Bool = false
    
    // Screenshot Display
    var isShowingScreenshot: Bool = false
    var displayedScreenshotImage: NSImage? = nil
    var screenshotDisplayTimer: Timer? = nil
    var lastShownScreenshotName: String? = nil
    var lastCheckedVideoTime: Double = 0.0
}

// MARK: - Screenshot Data

struct ScreenshotData {
    let image: NSImage
    let name: String
    let url: URL
}

// MARK: - Copy/Paste for Cursor Context Menu

/// Результат hit-test под курсором для контекстного меню ПКМ.
enum CursorMenuHit {
    case telestration(DrawableObject)
    case shape(EditorShape)
    case textBox(EditorTextBox)
    case empty
}

/// Элемент буфера обмена редактора (только для инструмента «Курсор», ПКМ).
enum CopiedEditorItem: Identifiable {
    case telestration(DrawableObject)
    case shape(EditorShape)
    case textBox(EditorTextBox)
    
    var id: UUID {
        switch self {
        case .telestration(let o): return o.id
        case .shape(let s): return s.id
        case .textBox(let t): return t.id
        }
    }
    
    var shortLabel: String {
        switch self {
        case .telestration(let o): return "\(o.type.displayName)"
        case .shape(let s): return s.type.displayName
        case .textBox: return ^String.Titles.editorTextBox
        }
    }
}

// MARK: - Editor Drawing State

class EditorDrawingState: ObservableObject {
    /// Максимум элементов в буфере копирования (ПКМ → Вставить).
    static let copyBufferMaxCount = 5
    
    @Published var currentTool: EditorTool = .pencil
    @Published var currentPath: EditorDrawingPath = EditorDrawingPath()
    @Published var completedPaths: [EditorDrawingPath] = []
    @Published var textBoxes: [EditorTextBox] = []
    @Published var selectedTextBoxId: UUID? = nil
    @Published var isEditingTextBox: Bool = false
    @Published var settings = EditorDrawingSettings()
    @Published var viewSize: CGSize = .zero
    var initialViewSize: CGSize = .zero
    
    // Telestration state
    @Published var isCreatingTelestrationObject: Bool = false
    @Published var currentTelestrationType: ObjectType? = nil
    @Published var telestrationVertices: [CGPoint] = []
    @Published var showingTelestrationTypeSelection: Bool = false
    @Published var pendingTelestrationObject: DrawableObject? = nil
    @Published var telestrationCustomization = ObjectCustomization()
    @Published var telestrationObjects: [DrawableObject] = []
    @Published var selectedTelestrationObjectId: UUID? = nil
    /// Режим «Добавить точку»: следующий клик по холсту добавит точку к текущему объекту телестрации (зона/линия).
    @Published var isAddingPointToTelestration: Bool = false
    /// Индексы точек, добавленных в режиме «Добавить точку» (порядок добавления). Back удаляет по этому порядку.
    var telestrationPointUndoStack: [Int] = []
    var lastTelestrationDragStartPositions: [CGPoint]? = nil
    /// Индекс вершины при перетаскивании одной вершины; nil = перемещение всего объекта.
    var lastTelestrationDragVertexIndex: Int? = nil
    /// Перетаскивание центральной ручки закруглённой стрелки (кружок по середине кривой).
    var isDraggingCurvedArrowMiddle: Bool = false
    
    /// Буфер копирования для ПКМ (курсор): последние 5 скопированных объектов.
    @Published var copyBuffer: [CopiedEditorItem] = []
    
    // Shapes state
    @Published var shapes: [EditorShape] = []
    @Published var selectedShapeId: UUID? = nil
    @Published var isCreatingShape: Bool = false
    @Published var currentShapeType: ShapeType? = nil
    @Published var pendingShape: EditorShape? = nil
    
    // TextBox state
    @Published var isCreatingTextBox: Bool = false
    @Published var pendingTextBox: EditorTextBox? = nil
    /// Сохранённый угол поворота перед входом в режим редактирования текста; при выходе восстанавливается.
    var savedTextBoxRotationBeforeEdit: CGFloat? = nil
    
    /// Вызывать при входе в режим редактирования: сохраняет текущий поворот и выставляет 0 (прямо).
    func startTextBoxEditing() {
        if var p = pendingTextBox {
            savedTextBoxRotationBeforeEdit = p.rotation
            p.rotation = 0
            pendingTextBox = p
        } else if let id = selectedTextBoxId, let idx = textBoxes.firstIndex(where: { $0.id == id }) {
            savedTextBoxRotationBeforeEdit = textBoxes[idx].rotation
            textBoxes[idx].rotation = 0
        }
    }
    
    /// Вызывать при выходе из режима редактирования: восстанавливает сохранённый поворот.
    func endTextBoxEditing() {
        defer { savedTextBoxRotationBeforeEdit = nil }
        guard let saved = savedTextBoxRotationBeforeEdit else { return }
        if var p = pendingTextBox {
            p.rotation = saved
            pendingTextBox = p
        } else if let id = selectedTextBoxId, let idx = textBoxes.firstIndex(where: { $0.id == id }) {
            textBoxes[idx].rotation = saved
        }
    }
    
    func updateViewSize(_ newSize: CGSize) {
        if initialViewSize == .zero {
            initialViewSize = newSize
        }
        viewSize = newSize
        
        // Масштабируем существующие пути если размер изменился
        if initialViewSize != .zero && initialViewSize != newSize {
            let scaleX = newSize.width / initialViewSize.width
            let scaleY = newSize.height / initialViewSize.height
            
            completedPaths = completedPaths.map { path in
                var newPath = path
                newPath.points = path.points.map { point in
                    CGPoint(x: point.x * scaleX, y: point.y * scaleY)
                }
                return newPath
            }
            
            // Масштабируем объекты телестрации
            telestrationObjects = telestrationObjects.map { object in
                var newObject = object
                newObject.positions = object.positions.map { point in
                    CGPoint(x: point.x * scaleX, y: point.y * scaleY)
                }
                // Масштабируем радиус для objectHighlight
                if object.type == .objectHighlight {
                    newObject.radius = object.radius * max(scaleX, scaleY)
                }
                // Масштабируем контрольную точку и высоту кривизны для закруглённой стрелки
                if object.type == .curvedArrow {
                    if let cp = object.controlPoint {
                        newObject.controlPoint = CGPoint(x: cp.x * scaleX, y: cp.y * scaleY)
                    }
                    newObject.curveHeight = object.curveHeight * max(scaleX, scaleY)
                }
                return newObject
            }
            
            // Масштабируем pending объект телестрации (после нажатия done, но до apply)
            if var pendingObject = pendingTelestrationObject {
                pendingObject.positions = pendingObject.positions.map { point in
                    CGPoint(x: point.x * scaleX, y: point.y * scaleY)
                }
                // Масштабируем радиус для objectHighlight
                if pendingObject.type == .objectHighlight {
                    pendingObject.radius = pendingObject.radius * max(scaleX, scaleY)
                }
                // Масштабируем контрольную точку и высоту кривизны для закруглённой стрелки
                if pendingObject.type == .curvedArrow {
                    if let cp = pendingObject.controlPoint {
                        pendingObject.controlPoint = CGPoint(x: cp.x * scaleX, y: cp.y * scaleY)
                    }
                    pendingObject.curveHeight = pendingObject.curveHeight * max(scaleX, scaleY)
                }
                self.pendingTelestrationObject = pendingObject
            }
            
            // Масштабируем вершины при создании
            telestrationVertices = telestrationVertices.map { point in
                CGPoint(x: point.x * scaleX, y: point.y * scaleY)
            }
            
            // Масштабируем фигуры
            shapes = shapes.map { shape in
                var newShape = shape
                newShape.position = CGPoint(x: shape.position.x * scaleX, y: shape.position.y * scaleY)
                newShape.size = CGSize(width: shape.size.width * scaleX, height: shape.size.height * scaleY)
                return newShape
            }
            
            // Масштабируем pending фигуру (после создания, но до apply)
            if var pendingShape = pendingShape {
                pendingShape.position = CGPoint(x: pendingShape.position.x * scaleX, y: pendingShape.position.y * scaleY)
                pendingShape.size = CGSize(width: pendingShape.size.width * scaleX, height: pendingShape.size.height * scaleY)
                self.pendingShape = pendingShape
            }
            
            // Масштабируем текстовые боксы
            textBoxes = textBoxes.map { textBox in
                var newTextBox = textBox
                newTextBox.position = CGPoint(x: textBox.position.x * scaleX, y: textBox.position.y * scaleY)
                newTextBox.size = CGSize(width: textBox.size.width * scaleX, height: textBox.size.height * scaleY)
                return newTextBox
            }
            
            // Масштабируем pending текстовый бокс (после создания, но до apply)
            if var pendingTextBox = pendingTextBox {
                pendingTextBox.position = CGPoint(x: pendingTextBox.position.x * scaleX, y: pendingTextBox.position.y * scaleY)
                pendingTextBox.size = CGSize(width: pendingTextBox.size.width * scaleX, height: pendingTextBox.size.height * scaleY)
                self.pendingTextBox = pendingTextBox
            }
            
            initialViewSize = newSize
        }
    }
    
    func startNewPath(at point: CGPoint) {
        if currentTool == .pencil {
            currentPath = EditorDrawingPath()
            currentPath.points = [point]
            currentPath.color = settings.currentColor
            currentPath.lineWidth = settings.lineWidth
            currentPath.lineStyle = settings.lineStyle
            currentPath.hasArrow = false
        } else if currentTool == .arrow {
            currentPath = EditorDrawingPath()
            currentPath.points = [point]
            currentPath.color = settings.currentColor
            currentPath.lineWidth = settings.lineWidth
            currentPath.lineStyle = settings.lineStyle
            currentPath.hasArrow = true
        } else if currentTool == .eraser {
            eraseAt(point)
        }
    }
    
    func addPointToPath(_ point: CGPoint) {
        if currentTool == .pencil || currentTool == .arrow {
            currentPath.points.append(point)
        } else if currentTool == .eraser {
            eraseAt(point)
        }
    }
    
    func finishPath() {
        if (currentTool == .pencil || currentTool == .arrow) && !currentPath.points.isEmpty {
            completedPaths.append(currentPath)
            currentPath = EditorDrawingPath()
        }
    }
    
    func eraseAt(_ point: CGPoint) {
        let eraserRadius = settings.eraserWidth / 2
        completedPaths.removeAll { path in
            path.points.contains { pathPoint in
                let distance = hypot(pathPoint.x - point.x, pathPoint.y - point.y)
                return distance < eraserRadius
            }
        }
        
        // Стираем объекты телестрации: если ластик пересекает вершину или любой отрезок линии
        telestrationObjects.removeAll { object in
            eraserHitsTelestrationObject(object, point: point, eraserRadius: eraserRadius)
        }
        
        // Стираем текстбоксы (попадание центра ластика в прямоугольник бокса)
        if let pending = pendingTextBox {
            let rect = textBoxRect(center: pending.position, size: pending.size)
            if rect.contains(point) {
                pendingTextBox = nil
                isCreatingTextBox = false
            }
        }
        textBoxes.removeAll { box in
            let rect = textBoxRect(center: box.position, size: box.size)
            if rect.contains(point) {
                if box.id == selectedTextBoxId { selectedTextBoxId = nil }
                return true
            }
            return false
        }
        
        // Стираем фигуры
        shapes.removeAll { shape in
            let shapeRect = CGRect(
                x: shape.position.x - shape.size.width / 2,
                y: shape.position.y - shape.size.height / 2,
                width: shape.size.width,
                height: shape.size.height
            )
            return shapeRect.contains(point)
        }
    }
    
    private func textBoxRect(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
    
    /// Проверяет, попадает ли ластик в объект телестрации (вершина или любой отрезок линии).
    private func eraserHitsTelestrationObject(_ object: DrawableObject, point: CGPoint, eraserRadius: CGFloat) -> Bool {
        let positions = object.positions
        if positions.isEmpty { return false }
        // Попадание в вершину
        for p in positions {
            if hypot(p.x - point.x, p.y - point.y) < eraserRadius { return true }
        }
        // Попадание в отрезок между вершинами
        let closed: Bool
        switch object.type {
        case .zoneBetweenObjects, .simpleZone, .objectHighlight:
            closed = (object.type == .zoneBetweenObjects || object.type == .simpleZone)
        case .lineBetweenObjects, .lineWithArrow, .curvedArrow:
            closed = false
        }
        let n = positions.count
        guard n >= 2 else { return false }
        for i in 0..<n {
            let next = closed ? (i + 1) % n : i + 1
            guard next < n || (closed && next == 0) else { continue }
            let a = positions[i]
            let b = positions[next]
            if distanceFromPointToSegment(point, a, b) < eraserRadius { return true }
        }
        // objectHighlight: один сегмент не рисуется, но можно считать «линию» нулевой длины — уже проверено по вершине
        return false
    }
    
    private func distanceFromPointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x, aby = b.y - a.y
        let apx = p.x - a.x, apy = p.y - a.y
        let abLenSq = abx * abx + aby * aby
        if abLenSq == 0 { return hypot(apx, apy) }
        let t = max(0, min(1, (apx * abx + apy * aby) / abLenSq))
        let proj = CGPoint(x: a.x + t * abx, y: a.y + t * aby)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
    
    /// Эффективная контрольная точка закруглённой стрелки для hit-test (контекстное меню ПКМ).
    private static func effectiveControlPointForCurvedArrow(_ object: DrawableObject) -> CGPoint {
        guard object.positions.count >= 2 else { return .zero }
        let start = object.positions[0]
        let end = object.positions[1]
        if let cp = object.controlPoint { return cp }
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        if length == 0 { return CGPoint(x: midX, y: midY) }
        let perpX = -dy / length
        let perpY = dx / length
        return CGPoint(x: midX + perpX * object.curveHeight, y: midY + perpY * object.curveHeight)
    }
    
    /// Минимальное расстояние от точки до квадратичной кривой Безье (для hit-test закруглённой стрелки).
    private static func distanceFromPointToQuadCurve(_ point: CGPoint, start: CGPoint, control: CGPoint, end: CGPoint) -> CGFloat {
        let steps = 32
        var minD: CGFloat = .greatestFiniteMagnitude
        var prev = start
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let mt = 1 - t
            let pt = CGPoint(
                x: mt*mt*start.x + 2*mt*t*control.x + t*t*end.x,
                y: mt*mt*start.y + 2*mt*t*control.y + t*t*end.y
            )
            minD = min(minD, distanceFromPointToSegment(point, prev, pt))
            prev = pt
        }
        return minD
    }
    
    private static func distanceFromPointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x, aby = b.y - a.y
        let apx = p.x - a.x, apy = p.y - a.y
        let abLenSq = abx * abx + aby * aby
        if abLenSq == 0 { return hypot(apx, apy) }
        let t = max(0, min(1, (apx * abx + apy * aby) / abLenSq))
        let proj = CGPoint(x: a.x + t * abx, y: a.y + t * aby)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
    
    func clearDrawing() {
        completedPaths.removeAll()
        currentPath = EditorDrawingPath()
        textBoxes.removeAll()
        selectedTextBoxId = nil
        telestrationObjects.removeAll()
        selectedTelestrationObjectId = nil
        isAddingPointToTelestration = false
        shapes.removeAll()
        selectedShapeId = nil
        initialViewSize = .zero
        viewSize = .zero
    }
    
    func undo() {
        // Если создается объект телестрации - отменяем его
        if isCreatingTelestrationObject || pendingTelestrationObject != nil {
            if !telestrationVertices.isEmpty {
                telestrationVertices.removeLast()
            } else {
                cancelTelestrationObjectCreation()
            }
        } else if isCreatingShape || pendingShape != nil {
            // Отменяем создание фигуры
            cancelShapeCreation()
        } else if isCreatingTextBox || pendingTextBox != nil {
            // Отменяем создание текстового бокса
            cancelTextBoxCreation()
        } else if !shapes.isEmpty {
            // Удаляем последнюю добавленную фигуру
            shapes.removeLast()
        } else if !telestrationObjects.isEmpty {
            // Удаляем последний добавленный объект телестрации
            telestrationObjects.removeLast()
        } else if !textBoxes.isEmpty {
            // Удаляем последний добавленный текстовый бокс
            let removedId = textBoxes.removeLast().id
            if selectedTextBoxId == removedId { selectedTextBoxId = nil }
        } else if !completedPaths.isEmpty {
            // Удаляем последний путь
            completedPaths.removeLast()
        }
    }
    
    var hasDrawing: Bool {
        return !completedPaths.isEmpty || !currentPath.points.isEmpty || !telestrationObjects.isEmpty || !shapes.isEmpty || !textBoxes.isEmpty || pendingTextBox != nil
    }
    
    // MARK: - Telestration Methods
    
    func startCreatingTelestrationObject(type: ObjectType) {
        currentTelestrationType = type
        isCreatingTelestrationObject = true
        telestrationVertices.removeAll()
        showingTelestrationTypeSelection = false
        selectedTelestrationObjectId = nil
        isAddingPointToTelestration = false
    }
    
    func addTelestrationVertex(at point: CGPoint) {
        guard let objectType = currentTelestrationType else { return }
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        guard point.x >= 0, point.y >= 0,
              point.x <= viewSize.width, point.y <= viewSize.height else { return }
        
        switch objectType {
        case .objectHighlight:
            telestrationVertices = [point]
            finishCreatingTelestrationObject()
        case .curvedArrow:
            if telestrationVertices.isEmpty {
                // Первая точка
                telestrationVertices.append(point)
            } else if telestrationVertices.count == 1 {
                // Вторая точка - автоматически создаем объект (только 2 точки, контрольная точка вычисляется на основе curveHeight)
                telestrationVertices.append(point)
                finishCreatingTelestrationObject()
            }
        case .zoneBetweenObjects, .simpleZone, .lineBetweenObjects, .lineWithArrow:
            telestrationVertices.append(point)
        }
    }
    
    func finishCreatingTelestrationObject() {
        guard let objectType = currentTelestrationType,
              !telestrationVertices.isEmpty else { return }
        
        var newObject = DrawableObject(number: 1, type: objectType)
        newObject.positions = telestrationVertices
        
        switch objectType {
        case .objectHighlight:
            newObject.radius = telestrationCustomization.radius
            newObject.glowColor = telestrationCustomization.glowColor
            newObject.glowOpacity = telestrationCustomization.glowOpacity
        default:
            newObject.edgeColor = telestrationCustomization.edgeColor
            newObject.vertexColor = telestrationCustomization.vertexColor
            newObject.fillColor = telestrationCustomization.fillColor
        }
        newObject.lineStyle = telestrationCustomization.lineStyle
        if objectType == .curvedArrow {
            newObject.curveHeight = telestrationCustomization.curveHeight
            newObject.strokeWidth = telestrationCustomization.strokeWidth
        }
        if objectType == .lineBetweenObjects || objectType == .lineWithArrow {
            newObject.strokeWidth = telestrationCustomization.strokeWidth
        }
        
        pendingTelestrationObject = newObject
        isCreatingTelestrationObject = false
        telestrationVertices.removeAll()
        currentTelestrationType = nil
        selectedTelestrationObjectId = nil
        isAddingPointToTelestration = false
    }
    
    /// Применяет telestrationCustomization к pending-объекту или к выбранному объекту в telestrationObjects.
    func applyTelestrationCustomization() {
        if var object = pendingTelestrationObject {
            object.edgeColor = telestrationCustomization.edgeColor
            object.vertexColor = telestrationCustomization.vertexColor
            object.fillColor = telestrationCustomization.fillColor
            object.lineStyle = telestrationCustomization.lineStyle
            object.glowColor = telestrationCustomization.glowColor
            object.radius = telestrationCustomization.radius
            if object.type == .objectHighlight { object.glowOpacity = telestrationCustomization.glowOpacity }
            if object.type == .curvedArrow {
                object.curveHeight = telestrationCustomization.curveHeight
                object.strokeWidth = telestrationCustomization.strokeWidth
            }
            if object.type == .lineBetweenObjects || object.type == .lineWithArrow {
                object.strokeWidth = telestrationCustomization.strokeWidth
            }
            pendingTelestrationObject = object
            return
        }
        guard let id = selectedTelestrationObjectId,
              let idx = telestrationObjects.firstIndex(where: { $0.id == id }) else { return }
        var object = telestrationObjects[idx]
        object.edgeColor = telestrationCustomization.edgeColor
        object.vertexColor = telestrationCustomization.vertexColor
        object.fillColor = telestrationCustomization.fillColor
        object.lineStyle = telestrationCustomization.lineStyle
        object.glowColor = telestrationCustomization.glowColor
        object.radius = telestrationCustomization.radius
        if object.type == .objectHighlight { object.glowOpacity = telestrationCustomization.glowOpacity }
        if object.type == .curvedArrow {
            object.curveHeight = telestrationCustomization.curveHeight
            object.strokeWidth = telestrationCustomization.strokeWidth
        }
        if object.type == .lineBetweenObjects || object.type == .lineWithArrow {
            object.strokeWidth = telestrationCustomization.strokeWidth
        }
        telestrationObjects[idx] = object
    }
    
    func updatePendingTelestrationObjectFromCustomization() {
        applyTelestrationCustomization()
    }
    
    /// Копирует свойства выбранного объекта в telestrationCustomization для редактирования в панели.
    func syncTelestrationCustomizationFromSelectedObject() {
        guard let id = selectedTelestrationObjectId,
              let object = telestrationObjects.first(where: { $0.id == id }) else { return }
        telestrationCustomization.edgeColor = object.edgeColor
        telestrationCustomization.vertexColor = object.vertexColor
        telestrationCustomization.fillColor = object.fillColor
        telestrationCustomization.lineStyle = object.lineStyle
        telestrationCustomization.glowColor = object.glowColor
        telestrationCustomization.glowOpacity = object.glowOpacity
        telestrationCustomization.radius = object.radius
        telestrationCustomization.curveHeight = object.curveHeight
        telestrationCustomization.strokeWidth = object.strokeWidth
    }
    
    func deleteSelectedTelestrationObject() {
        guard let id = selectedTelestrationObjectId else { return }
        telestrationObjects.removeAll { $0.id == id }
        selectedTelestrationObjectId = nil
        isAddingPointToTelestration = false
        telestrationPointUndoStack = []
    }
    
    // MARK: - Cursor context menu (right-click): copy / delete / paste
    
    /// Удалить объект телестрации по id (из контекстного меню ПКМ).
    func deleteTelestrationObject(id: UUID) {
        telestrationObjects.removeAll { $0.id == id }
        if selectedTelestrationObjectId == id {
            selectedTelestrationObjectId = nil
            isAddingPointToTelestration = false
            telestrationPointUndoStack = []
        }
    }
    
    /// Удалить фигуру по id (из контекстного меню ПКМ).
    func deleteShape(id: UUID) {
        shapes.removeAll { $0.id == id }
        if selectedShapeId == id { selectedShapeId = nil }
    }
    
    /// Удалить текстовый бокс по id (из контекстного меню ПКМ).
    func deleteTextBox(id: UUID) {
        textBoxes.removeAll { $0.id == id }
        if selectedTextBoxId == id { selectedTextBoxId = nil }
    }
    
    /// Добавить объект в буфер копирования (макс. copyBufferMaxCount).
    func addToCopyBuffer(_ item: CopiedEditorItem) {
        copyBuffer.insert(item, at: 0)
        if copyBuffer.count > Self.copyBufferMaxCount {
            copyBuffer.removeLast()
        }
    }
    
    /// Hit-test для контекстного меню ПКМ (только при currentTool == .cursor). Порядок: текстбокс → фигура → телестрация.
    func hitTestForCursorContextMenu(at point: CGPoint) -> CursorMenuHit {
        for textBox in textBoxes.reversed() {
            let r = CGRect(x: textBox.position.x - textBox.size.width / 2, y: textBox.position.y - textBox.size.height / 2, width: textBox.size.width, height: textBox.size.height)
            if r.contains(point) { return .textBox(textBox) }
        }
        for shape in shapes.reversed() {
            let hw = shape.size.width / 2 + 5, hh = shape.size.height / 2 + 5
            let r = CGRect(x: shape.position.x - hw, y: shape.position.y - hh, width: hw * 2, height: hh * 2)
            if r.contains(point) { return .shape(shape) }
        }
        for object in telestrationObjects.reversed() {
            if Self.telestrationContainsForHitTest(point, object) { return .telestration(object) }
        }
        return .empty
    }
    
    private static func telestrationContainsForHitTest(_ point: CGPoint, _ object: DrawableObject) -> Bool {
        switch object.type {
        case .zoneBetweenObjects, .simpleZone:
            guard object.positions.count >= 3 else { return false }
            if pointInPolygonForHitTest(point, object.positions) { return true }
            return distanceToPolygonForHitTest(point, object.positions, closed: true) < 15
        case .lineBetweenObjects, .lineWithArrow:
            guard object.positions.count >= 2 else { return false }
            return distanceToPolygonForHitTest(point, object.positions, closed: false) < 15
        case .curvedArrow:
            guard object.positions.count >= 2 else { return false }
            let start = object.positions[0]
            let end = object.positions[1]
            let control = effectiveControlPointForCurvedArrow(object)
            return distanceFromPointToQuadCurve(point, start: start, control: control, end: end) < 20
        case .objectHighlight:
            guard let p = object.positions.first else { return false }
            let r = object.radius
            let rect = CGRect(x: p.x - r/2 - 10, y: p.y - r*2 - 10, width: r + 20, height: r*2 + r*0.6 + 20)
            return rect.contains(point)
        }
    }
    
    private static func pointInPolygonForHitTest(_ point: CGPoint, _ polygon: [CGPoint]) -> Bool {
        var inside = false
        let n = polygon.count
        var j = n - 1
        for i in 0..<n {
            let xi = polygon[i].x, yi = polygon[i].y
            let xj = polygon[j].x, yj = polygon[j].y
            if ((yi > point.y) != (yj > point.y)) && (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi) { inside.toggle() }
            j = i
        }
        return inside
    }
    
    private static func distanceToPolygonForHitTest(_ point: CGPoint, _ pts: [CGPoint], closed: Bool) -> CGFloat {
        var d: CGFloat = .greatestFiniteMagnitude
        for i in 0..<(pts.count - 1) {
            d = min(d, distanceFromPointToSegment(point, pts[i], pts[i + 1]))
        }
        if closed, pts.count >= 3 {
            d = min(d, distanceFromPointToSegment(point, pts[pts.count - 1], pts[0]))
        }
        return d
    }
    
    /// Вставить объект из буфера по индексу в заданную точку (центр/опорная точка).
    func pasteFromBuffer(at point: CGPoint, bufferIndex: Int) {
        guard bufferIndex >= 0, bufferIndex < copyBuffer.count else { return }
        switch copyBuffer[bufferIndex] {
        case .telestration(let obj):
            let copy = DrawableObject(copying: obj)
            if copy.positions.isEmpty {
                telestrationObjects.append(copy)
                return
            }
            let cx = copy.positions.map(\.x).reduce(0, +) / CGFloat(copy.positions.count)
            let cy = copy.positions.map(\.y).reduce(0, +) / CGFloat(copy.positions.count)
            var newObj = copy
            newObj.positions = copy.positions.map { CGPoint(x: $0.x + (point.x - cx), y: $0.y + (point.y - cy)) }
            telestrationObjects.append(newObj)
        case .shape(let s):
            let copy = EditorShape(copying: s)
            var newShape = copy
            newShape.position = point
            shapes.append(newShape)
        case .textBox(let t):
            var copy = t
            copy.id = UUID()
            copy.position = point
            textBoxes.append(copy)
        }
    }
    
    func startMovingTelestrationObject(vertexIndex: Int? = nil) {
        guard let id = selectedTelestrationObjectId,
              let obj = telestrationObjects.first(where: { $0.id == id }) else { return }
        lastTelestrationDragVertexIndex = vertexIndex
        if let vi = vertexIndex, vi >= 0, vi < obj.positions.count {
            lastTelestrationDragStartPositions = [obj.positions[vi]]
        } else {
            lastTelestrationDragStartPositions = obj.positions
        }
    }
    
    func startMovingPendingTelestrationObject(vertexIndex: Int? = nil) {
        guard let obj = pendingTelestrationObject else { return }
        lastTelestrationDragVertexIndex = vertexIndex
        if let vi = vertexIndex, vi >= 0, vi < obj.positions.count {
            lastTelestrationDragStartPositions = [obj.positions[vi]]
        } else {
            lastTelestrationDragStartPositions = obj.positions
        }
    }
    
    func movePendingTelestrationObject(by translation: CGSize) {
        guard var obj = pendingTelestrationObject,
              let start = lastTelestrationDragStartPositions else { return }
        if let vi = lastTelestrationDragVertexIndex, vi >= 0, vi < obj.positions.count, start.count == 1 {
            obj.positions[vi] = CGPoint(x: start[0].x + translation.width, y: start[0].y + translation.height)
        } else if lastTelestrationDragVertexIndex == nil, start.count == obj.positions.count {
            for i in 0..<obj.positions.count {
                obj.positions[i] = CGPoint(x: start[i].x + translation.width, y: start[i].y + translation.height)
            }
        } else { return }
        pendingTelestrationObject = obj
    }
    
    func moveSelectedTelestrationObject(by translation: CGSize) {
        guard let id = selectedTelestrationObjectId,
              let arrIdx = telestrationObjects.firstIndex(where: { $0.id == id }),
              let start = lastTelestrationDragStartPositions else { return }
        var obj = telestrationObjects[arrIdx]
        if let vi = lastTelestrationDragVertexIndex, vi >= 0, vi < obj.positions.count, start.count == 1 {
            obj.positions[vi] = CGPoint(x: start[0].x + translation.width, y: start[0].y + translation.height)
        } else if lastTelestrationDragVertexIndex == nil, start.count == obj.positions.count {
            for i in 0..<obj.positions.count {
                obj.positions[i] = CGPoint(x: start[i].x + translation.width, y: start[i].y + translation.height)
            }
        } else { return }
        telestrationObjects[arrIdx] = obj
    }
    
    func endMovingTelestrationObject() {
        lastTelestrationDragStartPositions = nil
        lastTelestrationDragVertexIndex = nil
    }
    
    /// Контрольная точка квадратичной Безье по желаемой точке на середине кривой: B(0.5) = middle => control = 2*middle - 0.5*start - 0.5*end.
    static func controlPoint(fromMiddlePoint middle: CGPoint, start: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(
            x: 2 * middle.x - 0.5 * start.x - 0.5 * end.x,
            y: 2 * middle.y - 0.5 * start.y - 0.5 * end.y
        )
    }
    
    func startDraggingCurvedArrowMiddle() {
        isDraggingCurvedArrowMiddle = true
    }
    
    func moveCurvedArrowMiddle(to newMiddle: CGPoint) {
        guard isDraggingCurvedArrowMiddle else { return }
        func apply(to obj: inout DrawableObject) {
            guard obj.type == .curvedArrow, obj.positions.count >= 2 else { return }
            let start = obj.positions[0]
            let end = obj.positions[1]
            obj.controlPoint = Self.controlPoint(fromMiddlePoint: newMiddle, start: start, end: end)
        }
        if let id = selectedTelestrationObjectId,
           let arrIdx = telestrationObjects.firstIndex(where: { $0.id == id }) {
            var obj = telestrationObjects[arrIdx]
            apply(to: &obj)
            telestrationObjects[arrIdx] = obj
        } else if var pending = pendingTelestrationObject,
                  pending.type == .curvedArrow,
                  pending.positions.count >= 2 {
            apply(to: &pending)
            pendingTelestrationObject = pending
        }
    }
    
    func endDraggingCurvedArrowMiddle() {
        isDraggingCurvedArrowMiddle = false
    }
    
    /// Типы объектов телестрации, к которым можно добавлять точки (зоны и линии с вершинами).
    private static let telestrationTypesSupportingAddPoint: Set<ObjectType> = [.zoneBetweenObjects, .lineBetweenObjects, .lineWithArrow, .simpleZone]
    
    /// Добавляет точку к текущему объекту телестрации (pending или выбранному). Точка вставляется на ближайший сегмент контура/линии.
    func addPointToTelestrationObject(at point: CGPoint) -> Bool {
        let closed: Bool
        let positions: [CGPoint]
        if var obj = pendingTelestrationObject {
            guard Self.telestrationTypesSupportingAddPoint.contains(obj.type) else { return false }
            closed = (obj.type == .zoneBetweenObjects || obj.type == .simpleZone)
            positions = obj.positions
            guard positions.count >= 2 else { return false }
            let idx = Self.indexToInsertPoint(point, in: positions, closed: closed)
            obj.positions.insert(point, at: idx)
            pendingTelestrationObject = obj
            telestrationPointUndoStack.append(idx)
            return true
        }
        guard let id = selectedTelestrationObjectId,
              let idxArr = telestrationObjects.firstIndex(where: { $0.id == id }) else { return false }
        var obj = telestrationObjects[idxArr]
        guard Self.telestrationTypesSupportingAddPoint.contains(obj.type) else { return false }
        closed = (obj.type == .zoneBetweenObjects || obj.type == .simpleZone)
        positions = obj.positions
        guard positions.count >= 2 else { return false }
        let insertIdx = Self.indexToInsertPoint(point, in: positions, closed: closed)
        obj.positions.insert(point, at: insertIdx)
        telestrationObjects[idxArr] = obj
        telestrationPointUndoStack.append(insertIdx)
        return true
    }
    
    /// Минимальное число точек для типа объекта (меньше нельзя откатывать).
    private static func minPointsForTelestrationType(_ type: ObjectType) -> Int {
        switch type {
        case .zoneBetweenObjects, .simpleZone: return 3
        case .lineBetweenObjects, .lineWithArrow: return 2
        case .curvedArrow, .objectHighlight: return 1
        }
    }
    
    /// Можно ли откатить последнюю точку (показать кнопку «Назад»).
    var canRemoveLastTelestrationPoint: Bool {
        if isCreatingTelestrationObject, let type = currentTelestrationType {
            if type == .objectHighlight || type == .curvedArrow { return false }
            return !telestrationVertices.isEmpty
        }
        // В режиме настроек (pending/выбранный) — только если есть точки, добавленные в этой сессии
        if pendingTelestrationObject != nil || selectedTelestrationObjectId != nil {
            return !telestrationPointUndoStack.isEmpty
        }
        return false
    }
    
    /// Откатывает последнюю добавленную точку телестрации (по порядку добавления, а не по краю объекта).
    func removeLastTelestrationPoint() {
        if isCreatingTelestrationObject, !telestrationVertices.isEmpty {
            telestrationVertices.removeLast()
            return
        }
        guard let idxToRemove = telestrationPointUndoStack.popLast() else { return }
        if var obj = pendingTelestrationObject, Self.telestrationTypesSupportingAddPoint.contains(obj.type), idxToRemove < obj.positions.count {
            obj.positions.remove(at: idxToRemove)
            pendingTelestrationObject = obj
            // Индексы в стеке, большие удалённого, сдвигаются на -1
            telestrationPointUndoStack = telestrationPointUndoStack.map { $0 > idxToRemove ? $0 - 1 : $0 }
            return
        }
        guard let id = selectedTelestrationObjectId,
              let arrIdx = telestrationObjects.firstIndex(where: { $0.id == id }) else { return }
        var obj = telestrationObjects[arrIdx]
        guard Self.telestrationTypesSupportingAddPoint.contains(obj.type), idxToRemove < obj.positions.count else { return }
        obj.positions.remove(at: idxToRemove)
        telestrationObjects[arrIdx] = obj
        telestrationPointUndoStack = telestrationPointUndoStack.map { $0 > idxToRemove ? $0 - 1 : $0 }
    }
    
    /// Индекс, после которого вставить новую точку (вставка на ближайший сегмент).
    private static func indexToInsertPoint(_ point: CGPoint, in positions: [CGPoint], closed: Bool) -> Int {
        guard positions.count >= 2 else { return positions.count }
        var bestIndex = 1
        var bestD: CGFloat = .greatestFiniteMagnitude
        let n = positions.count
        for i in 0..<n {
            let next = closed ? (i + 1) % n : i + 1
            guard next < n || (closed && next == 0) else { continue }
            let a = positions[i]
            let b = positions[next]
            let d = distanceFromPointToSegment(point, a, b)
            if d < bestD {
                bestD = d
                bestIndex = i + 1
            }
        }
        return bestIndex
    }
    
    func confirmTelestrationObjectCreation() -> DrawableObject? {
        guard var object = pendingTelestrationObject else { return nil }
        
        object.edgeColor = telestrationCustomization.edgeColor
        object.vertexColor = telestrationCustomization.vertexColor
        object.fillColor = telestrationCustomization.fillColor
        object.lineStyle = telestrationCustomization.lineStyle
        object.glowColor = telestrationCustomization.glowColor
        object.radius = telestrationCustomization.radius
        if object.type == .objectHighlight {
            object.glowOpacity = telestrationCustomization.glowOpacity
        }
        
        // Для закругленной стрелки сохраняем только толщину линии; изгиб (curveHeight/controlPoint) не перезаписываем — он уже задан перетаскиванием кружка или при создании
        if object.type == .curvedArrow {
            object.strokeWidth = telestrationCustomization.strokeWidth
        }
        // Для линии между объектами и линии со стрелкой — толщину линии
        if object.type == .lineBetweenObjects || object.type == .lineWithArrow {
            object.strokeWidth = telestrationCustomization.strokeWidth
        }
        
        telestrationObjects.append(object)
        
        pendingTelestrationObject = nil
        telestrationCustomization = ObjectCustomization()
        isAddingPointToTelestration = false
        telestrationPointUndoStack = []
        
        return object
    }
    
    func cancelTelestrationObjectCreation() {
        pendingTelestrationObject = nil
        isCreatingTelestrationObject = false
        telestrationVertices.removeAll()
        currentTelestrationType = nil
        telestrationCustomization = ObjectCustomization()
        isAddingPointToTelestration = false
        telestrationPointUndoStack = []
    }
    
    // MARK: - Shapes Methods
    
    func startCreatingShape(type: ShapeType) {
        currentShapeType = type
        isCreatingShape = true
    }
    
    func createShape(at point: CGPoint) {
        guard let type = currentShapeType else { return }
        let defaultSize = CGSize(width: 100, height: 100)
        let newShape = EditorShape(type: type, position: point, size: defaultSize)
        pendingShape = newShape
        isCreatingShape = false
        currentShapeType = nil
    }
    
    func confirmShapeCreation() {
        guard let shape = pendingShape else { return }
        shapes.append(shape)
        pendingShape = nil
        selectedShapeId = nil // Убираем выделение после apply
    }
    
    func cancelShapeCreation() {
        pendingShape = nil
        isCreatingShape = false
        currentShapeType = nil
    }
    
    // MARK: - TextBox Methods
    
    func startCreatingTextBox() {
        isCreatingTextBox = true
    }
    
    /// Ограничивает центр текстбокса так, чтобы он целиком помещался в viewSize.
    func clampTextBoxPosition(_ position: CGPoint, size: CGSize) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0 else { return position }
        let hw = size.width / 2, hh = size.height / 2
        return CGPoint(
            x: max(hw, min(position.x, viewSize.width - hw)),
            y: max(hh, min(position.y, viewSize.height - hh))
        )
    }
    
    func createTextBox(at point: CGPoint) {
        var newTextBox = EditorTextBox(position: point, size: CGSize(width: 100, height: 40))
        newTextBox.text = ^String.Titles.editorTextBoxDefaultText
        updateTextBoxSizeToFit(&newTextBox)
        newTextBox.position = clampTextBoxPosition(newTextBox.position, size: newTextBox.size)
        pendingTextBox = newTextBox
        isCreatingTextBox = false
        startTextBoxEditing()
        isEditingTextBox = true
        NotificationCenter.default.post(name: .textBoxEditingChanged, object: true)
    }
    
    /// Подгоняет размер текстового бокса под текст (с учётом шрифта, многострочности и отступов).
    func updateTextBoxSizeToFit(_ textBox: inout EditorTextBox) {
        let font = NSFont(name: textBox.fontName, size: textBox.fontSize) ?? NSFont.systemFont(ofSize: textBox.fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let rect = (textBox.text as NSString).boundingRect(
            with: CGSize(width: 10000, height: 10000),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        let textSize = CGSize(width: ceil(rect.width), height: ceil(rect.height))
        let padding: CGFloat = 20
        textBox.size = CGSize(
            width: max(50, textSize.width + padding),
            height: max(30, textSize.height + padding)
        )
    }
    
    /// Обновляет pending-текстбокс (например, текст/шрифт) и подгоняет размер под текст.
    func updatePendingTextBox(apply: (inout EditorTextBox) -> Void) {
        guard var u = pendingTextBox else { return }
        apply(&u)
        updateTextBoxSizeToFit(&u)
        u.position = clampTextBoxPosition(u.position, size: u.size)
        pendingTextBox = u
    }
    
    func confirmTextBoxCreation() {
        guard let textBox = pendingTextBox else { return }
        textBoxes.append(textBox)
        pendingTextBox = nil
        selectedTextBoxId = nil // Убираем выделение после apply
        
        // Если инструмент textBox все еще выбран, автоматически начинаем создание нового
        if currentTool == .textBox {
            isCreatingTextBox = true
        }
    }
    
    func cancelTextBoxCreation() {
        pendingTextBox = nil
        isCreatingTextBox = false
        savedTextBoxRotationBeforeEdit = nil
    }
    
    /// Обработка Enter в режиме редактирования: аналог нажатия Done/Apply для телестрации, фигур и текстбоксов.
    func handleEditorEnterKey() {
        if isCreatingTelestrationObject, let type = currentTelestrationType, !telestrationVertices.isEmpty {
            finishCreatingTelestrationObject()
            return
        }
        if pendingTelestrationObject != nil {
            confirmTelestrationObjectCreation()
            currentTool = .cursor
            return
        }
        if selectedTelestrationObjectId != nil {
            selectedTelestrationObjectId = nil
            isAddingPointToTelestration = false
            telestrationPointUndoStack = []
            currentTool = .cursor
            return
        }
        if pendingShape != nil {
            confirmShapeCreation()
            currentTool = .cursor
            return
        }
        if selectedShapeId != nil {
            selectedShapeId = nil
            currentTool = .cursor
            return
        }
        if pendingTextBox != nil {
            confirmTextBoxCreation()
            if currentTool == .textBox {
                startCreatingTextBox()
            }
            return
        }
        if selectedTextBoxId != nil {
            selectedTextBoxId = nil
            if currentTool == .textBox {
                startCreatingTextBox()
            }
            return
        }
    }
    
    func updateSelectedTextBox(text: String? = nil, textColor: Color? = nil, fontSize: CGFloat? = nil, fontName: String? = nil, backgroundColor: Color? = nil, borderColor: Color? = nil, borderWidth: CGFloat? = nil) {
        guard let textBoxId = selectedTextBoxId,
              let index = textBoxes.firstIndex(where: { $0.id == textBoxId }) else { return }
        
        if let text = text {
            textBoxes[index].text = text
        }
        if let textColor = textColor {
            textBoxes[index].textColor = textColor
        }
        if let fontSize = fontSize {
            textBoxes[index].fontSize = fontSize
        }
        if let fontName = fontName {
            textBoxes[index].fontName = fontName
        }
        if let backgroundColor = backgroundColor {
            textBoxes[index].backgroundColor = backgroundColor
        }
        if let borderColor = borderColor {
            textBoxes[index].borderColor = borderColor
        }
        if let borderWidth = borderWidth {
            textBoxes[index].borderWidth = borderWidth
        }
        if text != nil || fontSize != nil || fontName != nil {
            updateTextBoxSizeToFit(&textBoxes[index])
            textBoxes[index].position = clampTextBoxPosition(textBoxes[index].position, size: textBoxes[index].size)
        }
    }
    
    @Published var lastTextBoxDragValue: CGPoint = .zero
    
    func startMovingTextBox() {
        if let textBoxId = selectedTextBoxId,
           let textBox = textBoxes.first(where: { $0.id == textBoxId }) {
            lastTextBoxDragValue = textBox.position
        } else if let textBox = pendingTextBox {
            lastTextBoxDragValue = textBox.position
        }
    }
    
    func startMovingPendingTextBox() {
        guard let textBox = pendingTextBox else { return }
        lastTextBoxDragValue = textBox.position
    }
    
    func moveSelectedTextBox(by translation: CGSize) {
        guard let textBoxId = selectedTextBoxId,
              let index = textBoxes.firstIndex(where: { $0.id == textBoxId }) else { return }
        let newPos = CGPoint(x: lastTextBoxDragValue.x + translation.width, y: lastTextBoxDragValue.y + translation.height)
        textBoxes[index].position = clampTextBoxPosition(newPos, size: textBoxes[index].size)
    }
    
    func movePendingTextBox(by translation: CGSize) {
        guard var textBox = pendingTextBox else { return }
        let newPos = CGPoint(x: lastTextBoxDragValue.x + translation.width, y: lastTextBoxDragValue.y + translation.height)
        textBox.position = clampTextBoxPosition(newPos, size: textBox.size)
        pendingTextBox = textBox
    }
    
    func endMovingTextBox() {
        lastTextBoxDragValue = .zero
    }
    
    func rotateSelectedTextBox(angle: CGFloat) {
        guard let textBoxId = selectedTextBoxId,
              let index = textBoxes.firstIndex(where: { $0.id == textBoxId }) else { return }
        
        textBoxes[index].rotation = angle
    }
    
    func rotatePendingTextBox(angle: CGFloat) {
        guard var textBox = pendingTextBox else { return }
        textBox.rotation = angle
        pendingTextBox = textBox
    }
    
    func updateSelectedShape(fillColor: Color? = nil, fillOpacity: Double? = nil, strokeColor: Color? = nil, strokeWidth: CGFloat? = nil, lineStyle: EditorLineStyle? = nil) {
        guard let shapeId = selectedShapeId,
              let index = shapes.firstIndex(where: { $0.id == shapeId }) else { return }
        
        if let fillColor = fillColor {
            shapes[index].fillColor = fillColor
        }
        if let fillOpacity = fillOpacity {
            shapes[index].fillOpacity = fillOpacity
        }
        if let strokeColor = strokeColor {
            shapes[index].strokeColor = strokeColor
        }
        if let strokeWidth = strokeWidth {
            shapes[index].strokeWidth = strokeWidth
        }
        if let lineStyle = lineStyle {
            shapes[index].lineStyle = lineStyle
        }
    }
    
    @Published var lastShapeDragValue: CGPoint = .zero
    
    func startMovingShape() {
        if let shapeId = selectedShapeId,
           let shape = shapes.first(where: { $0.id == shapeId }) {
            lastShapeDragValue = shape.position
        } else if let shape = pendingShape {
            lastShapeDragValue = shape.position
        }
    }
    
    func moveSelectedShape(by translation: CGSize) {
        guard let shapeId = selectedShapeId,
              let index = shapes.firstIndex(where: { $0.id == shapeId }) else { return }
        
        shapes[index].position = CGPoint(
            x: lastShapeDragValue.x + translation.width,
            y: lastShapeDragValue.y + translation.height
        )
    }
    
    func movePendingShape(by translation: CGSize) {
        guard var shape = pendingShape else { return }
        shape.position = CGPoint(
            x: lastShapeDragValue.x + translation.width,
            y: lastShapeDragValue.y + translation.height
        )
        pendingShape = shape
    }
    
    func endMovingShape() {
        if let shapeId = selectedShapeId,
           let shape = shapes.first(where: { $0.id == shapeId }) {
            lastShapeDragValue = shape.position
        } else if let shape = pendingShape {
            lastShapeDragValue = shape.position
        }
    }
    
    func resizeSelectedShape(newSize: CGSize) {
        guard let shapeId = selectedShapeId,
              let index = shapes.firstIndex(where: { $0.id == shapeId }) else { return }
        
        shapes[index].size = newSize
    }
    
    func resizePendingShape(newSize: CGSize) {
        guard var shape = pendingShape else { return }
        shape.size = newSize
        pendingShape = shape
    }
    
    func rotateSelectedShape(angle: CGFloat) {
        guard let shapeId = selectedShapeId,
              let index = shapes.firstIndex(where: { $0.id == shapeId }) else { return }
        
        shapes[index].rotation = angle
    }
    
    func rotatePendingShape(angle: CGFloat) {
        guard var shape = pendingShape else { return }
        shape.rotation = angle
        pendingShape = shape
    }
    
    func startMovingPendingShape() {
        guard let shape = pendingShape else { return }
        lastShapeDragValue = shape.position
    }
}

// MARK: - Editor Models

enum EditorTool {
    case cursor
    case pencil
    case arrow
    case eraser
    case telestration
    case shapes
    case textBox
}

enum ShapeType: String, CaseIterable {
    case triangle = "triangle"
    case square = "square"
    case rectangle = "rectangle"
    case circle = "circle"
    case star = "star"
    case hexagon = "hexagon"
    
    var displayName: String {
        switch self {
        case .triangle: return ^String.Titles.editorShapeTriangle
        case .square: return ^String.Titles.editorShapeSquare
        case .rectangle: return ^String.Titles.editorShapeRectangle
        case .circle: return ^String.Titles.editorShapeCircle
        case .star: return ^String.Titles.editorShapeStar
        case .hexagon: return ^String.Titles.editorShapeHexagon
        }
    }
    
    var iconName: String {
        switch self {
        case .triangle: return "triangle.fill"
        case .square: return "square.fill"
        case .rectangle: return "rectangle.fill"
        case .circle: return "circle.fill"
        case .star: return "star.fill"
        case .hexagon: return "hexagon.fill"
        }
    }
}

struct EditorShape: Identifiable {
    let id: UUID
    var type: ShapeType
    var position: CGPoint
    var size: CGSize
    var rotation: CGFloat = 0.0
    
    var fillColor: Color = .blue
    /// Прозрачность заливки (0 — прозрачный фон, 1 — непрозрачный).
    var fillOpacity: Double = 1.0
    var strokeColor: Color = .white
    var strokeWidth: CGFloat = 2.0
    var lineStyle: EditorLineStyle = .solid
    
    init(type: ShapeType, position: CGPoint, size: CGSize = CGSize(width: 100, height: 100)) {
        self.id = UUID()
        self.type = type
        self.position = position
        self.size = size
    }
    
    /// Копия с новым id (для вставки из буфера).
    init(copying other: EditorShape) {
        self.id = UUID()
        self.type = other.type
        self.position = other.position
        self.size = other.size
        self.rotation = other.rotation
        self.fillColor = other.fillColor
        self.fillOpacity = other.fillOpacity
        self.strokeColor = other.strokeColor
        self.strokeWidth = other.strokeWidth
        self.lineStyle = other.lineStyle
    }
    
    /// Восстановление из снимка (с заданным id).
    init(id: UUID, type: ShapeType, position: CGPoint, size: CGSize, rotation: CGFloat = 0, fillColor: Color = .blue, fillOpacity: Double = 1, strokeColor: Color = .white, strokeWidth: CGFloat = 2, lineStyle: EditorLineStyle = .solid) {
        self.id = id
        self.type = type
        self.position = position
        self.size = size
        self.rotation = rotation
        self.fillColor = fillColor
        self.fillOpacity = fillOpacity
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.lineStyle = lineStyle
    }
}

struct EditorDrawingPath {
    var points: [CGPoint] = []
    var color: Color = .red
    var lineWidth: CGFloat = 3.0
    var lineStyle: EditorLineStyle = .solid
    var hasArrow: Bool = false // Флаг для стрелочки на конце
}

enum EditorLineStyle {
    case solid
    case dashed
    
    var dashPattern: [CGFloat]? {
        switch self {
        case .solid:
            return nil
        case .dashed:
            return [10, 5]
        }
    }
}

struct EditorTextBox: Identifiable {
    var id = UUID()
    var text: String = ^String.Titles.editorTextBoxDefaultText
    var position: CGPoint
    var size: CGSize = CGSize(width: 150, height: 60)
    var rotation: CGFloat = 0.0
    
    // Text styling
    var textColor: Color = .white
    var fontSize: CGFloat = 20
    var fontName: String = "Helvetica"
    
    // Box styling
    var backgroundColor: Color = .clear
    var borderColor: Color = .white
    var borderWidth: CGFloat = 2.0
    
    init(position: CGPoint, size: CGSize = CGSize(width: 150, height: 60)) {
        self.position = position
        self.size = size
    }
}

struct EditorDrawingSettings {
    var currentColor: Color = .red
    var lineWidth: CGFloat = 3.0
    var lineStyle: EditorLineStyle = .solid
    var eraserWidth: CGFloat = 20.0
    
    static let availableColors: [Color] = [
        .red, .blue, .green, .yellow, .orange, .purple, .pink, .white, .black, .clear
    ]
    
    static let availableWidths: [CGFloat] = [1, 2, 3, 5, 8, 12]
    static let availableEraserWidths: [CGFloat] = [10, 20, 30, 50]
}

// MARK: - Editor State Snapshot (Codable, for saving/restoring editor with screenshot)

struct EditorStateSnapshot: Codable {
    var viewSizeWidth: Double
    var viewSizeHeight: Double
    var completedPaths: [SnapshotPath] = []
    var shapes: [SnapshotShape] = []
    var textBoxes: [SnapshotTextBox] = []
    var telestrationObjects: [SnapshotTelestration] = []
    var currentToolRaw: String? = nil // "pencil", "arrow", "cursor", etc.
    
    struct SnapshotPath: Codable {
        var points: [[Double]] // [[x,y], ...]
        var colorHex: String
        var lineWidth: Double
        var lineStyleRaw: String // "solid", "dashed"
        var hasArrow: Bool
    }
    
    struct SnapshotShape: Codable {
        var id: UUID
        var typeRaw: String // ShapeType.rawValue
        var positionX: Double
        var positionY: Double
        var sizeWidth: Double
        var sizeHeight: Double
        var rotation: Double
        var fillColorHex: String
        var fillOpacity: Double
        var strokeColorHex: String
        var strokeWidth: Double
        var lineStyleRaw: String
    }
    
    struct SnapshotTextBox: Codable {
        var id: UUID
        var text: String
        var positionX: Double
        var positionY: Double
        var sizeWidth: Double
        var sizeHeight: Double
        var rotation: Double
        var textColorHex: String
        var fontSize: Double
        var fontName: String
        var backgroundColorHex: String
        var borderColorHex: String
        var borderWidth: Double
    }
    
    struct SnapshotTelestration: Codable {
        var id: UUID
        var number: Int
        var typeRaw: String // ObjectType.rawValue
        var positions: [[Double]]
        var edgeColorHex: String
        var vertexColorHex: String
        var fillColorHex: String
        var lineStyleRaw: String
        var glowColorHex: String
        var glowOpacity: Double
        var radius: Double
        var curveHeight: Double
        var controlPointX: Double?
        var controlPointY: Double?
        var strokeWidth: Double
    }
    
    static func from(drawingState: EditorDrawingState) -> EditorStateSnapshot {
        func hex(_ color: Color) -> String {
            if color == Color.clear { return "clear" }
            return color.toHex() ?? "000000"
        }
        func lineStyleRaw(_ s: EditorLineStyle) -> String {
            switch s { case .solid: return "solid"; case .dashed: return "dashed" }
        }
        
        var paths: [SnapshotPath] = []
        for path in drawingState.completedPaths {
            paths.append(SnapshotPath(
                points: path.points.map { [Double($0.x), Double($0.y)] },
                colorHex: hex(path.color),
                lineWidth: Double(path.lineWidth),
                lineStyleRaw: lineStyleRaw(path.lineStyle),
                hasArrow: path.hasArrow
            ))
        }
        if !drawingState.currentPath.points.isEmpty {
            paths.append(SnapshotPath(
                points: drawingState.currentPath.points.map { [Double($0.x), Double($0.y)] },
                colorHex: hex(drawingState.currentPath.color),
                lineWidth: Double(drawingState.currentPath.lineWidth),
                lineStyleRaw: lineStyleRaw(drawingState.currentPath.lineStyle),
                hasArrow: drawingState.currentPath.hasArrow
            ))
        }
        
        var shapes: [SnapshotShape] = []
        for s in drawingState.shapes {
            shapes.append(SnapshotShape(
                id: s.id,
                typeRaw: s.type.rawValue,
                positionX: Double(s.position.x),
                positionY: Double(s.position.y),
                sizeWidth: Double(s.size.width),
                sizeHeight: Double(s.size.height),
                rotation: Double(s.rotation),
                fillColorHex: hex(s.fillColor),
                fillOpacity: s.fillOpacity,
                strokeColorHex: hex(s.strokeColor),
                strokeWidth: Double(s.strokeWidth),
                lineStyleRaw: lineStyleRaw(s.lineStyle)
            ))
        }
        
        var boxes: [SnapshotTextBox] = []
        for t in drawingState.textBoxes {
            boxes.append(SnapshotTextBox(
                id: t.id,
                text: t.text,
                positionX: Double(t.position.x),
                positionY: Double(t.position.y),
                sizeWidth: Double(t.size.width),
                sizeHeight: Double(t.size.height),
                rotation: Double(t.rotation),
                textColorHex: hex(t.textColor),
                fontSize: Double(t.fontSize),
                fontName: t.fontName,
                backgroundColorHex: hex(t.backgroundColor),
                borderColorHex: hex(t.borderColor),
                borderWidth: Double(t.borderWidth)
            ))
        }
        
        var tels: [SnapshotTelestration] = []
        for o in drawingState.telestrationObjects {
            tels.append(SnapshotTelestration(
                id: o.id,
                number: o.number,
                typeRaw: o.type.rawValue,
                positions: o.positions.map { [Double($0.x), Double($0.y)] },
                edgeColorHex: hex(o.edgeColor),
                vertexColorHex: hex(o.vertexColor),
                fillColorHex: hex(o.fillColor),
                lineStyleRaw: o.lineStyle.rawValue,
                glowColorHex: hex(o.glowColor),
                glowOpacity: o.glowOpacity,
                radius: Double(o.radius),
                curveHeight: Double(o.curveHeight),
                controlPointX: o.controlPoint.map { Double($0.x) },
                controlPointY: o.controlPoint.map { Double($0.y) },
                strokeWidth: Double(o.strokeWidth)
            ))
        }
        
        let toolRaw: String? = {
            switch drawingState.currentTool {
            case .cursor: return "cursor"
            case .pencil: return "pencil"
            case .arrow: return "arrow"
            case .eraser: return "eraser"
            case .telestration: return "telestration"
            case .shapes: return "shapes"
            case .textBox: return "textBox"
            }
        }()
        
        return EditorStateSnapshot(
            viewSizeWidth: Double(drawingState.viewSize.width),
            viewSizeHeight: Double(drawingState.viewSize.height),
            completedPaths: paths,
            shapes: shapes,
            textBoxes: boxes,
            telestrationObjects: tels,
            currentToolRaw: toolRaw
        )
    }
    
    func apply(to drawingState: EditorDrawingState) {
        func color(from hex: String) -> Color {
            if hex == "clear" { return .clear }
            return Color(hex: hex)
        }
        func lineStyle(from raw: String) -> EditorLineStyle {
            raw == "dashed" ? .dashed : .solid
        }
        
        drawingState.clearDrawing()
        
        for p in completedPaths {
            var path = EditorDrawingPath()
            path.points = p.points.compactMap { arr in
                guard arr.count >= 2 else { return nil }
                return CGPoint(x: arr[0], y: arr[1])
            }
            path.color = color(from: p.colorHex)
            path.lineWidth = CGFloat(p.lineWidth)
            path.lineStyle = lineStyle(from: p.lineStyleRaw)
            path.hasArrow = p.hasArrow
            if !path.points.isEmpty {
                drawingState.completedPaths.append(path)
            }
        }
        
        for s in shapes {
            guard let type = ShapeType(rawValue: s.typeRaw) else { continue }
            let shape = EditorShape(
                id: s.id,
                type: type,
                position: CGPoint(x: s.positionX, y: s.positionY),
                size: CGSize(width: s.sizeWidth, height: s.sizeHeight),
                rotation: CGFloat(s.rotation),
                fillColor: color(from: s.fillColorHex),
                fillOpacity: s.fillOpacity,
                strokeColor: color(from: s.strokeColorHex),
                strokeWidth: CGFloat(s.strokeWidth),
                lineStyle: lineStyle(from: s.lineStyleRaw)
            )
            drawingState.shapes.append(shape)
        }
        
        for t in textBoxes {
            var box = EditorTextBox(position: CGPoint(x: t.positionX, y: t.positionY), size: CGSize(width: t.sizeWidth, height: t.sizeHeight))
            box.id = t.id
            box.text = t.text
            box.rotation = CGFloat(t.rotation)
            box.textColor = color(from: t.textColorHex)
            box.fontSize = CGFloat(t.fontSize)
            box.fontName = t.fontName
            box.backgroundColor = color(from: t.backgroundColorHex)
            box.borderColor = color(from: t.borderColorHex)
            box.borderWidth = CGFloat(t.borderWidth)
            drawingState.textBoxes.append(box)
        }
        
        for o in telestrationObjects {
            guard let type = ObjectType(rawValue: o.typeRaw) else { continue }
            let positions = o.positions.compactMap { arr -> CGPoint? in
                guard arr.count >= 2 else { return nil }
                return CGPoint(x: arr[0], y: arr[1])
            }
            let control: CGPoint? = (o.controlPointX != nil && o.controlPointY != nil) ? CGPoint(x: o.controlPointX!, y: o.controlPointY!) : nil
            let obj = DrawableObject(
                id: o.id,
                number: o.number,
                type: type,
                positions: positions,
                edgeColor: color(from: o.edgeColorHex),
                vertexColor: color(from: o.vertexColorHex),
                fillColor: color(from: o.fillColorHex),
                lineStyle: o.lineStyleRaw == "dashed" ? .dashed : .solid,
                glowColor: color(from: o.glowColorHex),
                glowOpacity: o.glowOpacity,
                radius: CGFloat(o.radius),
                curveHeight: CGFloat(o.curveHeight),
                controlPoint: control,
                strokeWidth: CGFloat(o.strokeWidth)
            )
            drawingState.telestrationObjects.append(obj)
        }
        
        if viewSizeWidth > 0 && viewSizeHeight > 0 {
            drawingState.viewSize = CGSize(width: viewSizeWidth, height: viewSizeHeight)
            if drawingState.initialViewSize == .zero {
                drawingState.initialViewSize = drawingState.viewSize
            }
        }
        
        if let raw = currentToolRaw {
            switch raw {
            case "cursor": drawingState.currentTool = .cursor
            case "pencil": drawingState.currentTool = .pencil
            case "arrow": drawingState.currentTool = .arrow
            case "eraser": drawingState.currentTool = .eraser
            case "telestration": drawingState.currentTool = .telestration
            case "shapes": drawingState.currentTool = .shapes
            case "textBox": drawingState.currentTool = .textBox
            default: drawingState.currentTool = .pencil
            }
        }
    }
}

// MARK: - Screenshot Metadata

struct ScreenshotMetadata: Codable {
    let screenshotName: String
    let videoTime: Double
    let createdAt: Date
    let saveAsTag: Bool
    let displayDuration: Double // How long to show screenshot during export (default 3.0 for backward compatibility)
    let relatedStampIds: [UUID] // IDs of timeline stamps this screenshot is associated with
    let editorState: EditorStateSnapshot? // Optional: full editor state to restore drawing layers
    
    var fileName: String {
        return "\(screenshotName).json"
    }
    
    enum CodingKeys: String, CodingKey {
        case screenshotName
        case videoTime
        case createdAt
        case saveAsTag
        case displayDuration
        case relatedStampIds
        case editorState
    }
    
    // Custom decoder for backward compatibility with old screenshots without displayDuration / editorState
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        screenshotName = try container.decode(String.self, forKey: .screenshotName)
        videoTime = try container.decode(Double.self, forKey: .videoTime)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        saveAsTag = try container.decode(Bool.self, forKey: .saveAsTag)
        displayDuration = try container.decodeIfPresent(Double.self, forKey: .displayDuration) ?? 3.0
        relatedStampIds = try container.decodeIfPresent([UUID].self, forKey: .relatedStampIds) ?? []
        editorState = try container.decodeIfPresent(EditorStateSnapshot.self, forKey: .editorState)
    }
    
    // Custom encoder to ensure displayDuration is always saved
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(screenshotName, forKey: .screenshotName)
        try container.encode(videoTime, forKey: .videoTime)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(saveAsTag, forKey: .saveAsTag)
        try container.encode(displayDuration, forKey: .displayDuration)
        try container.encode(relatedStampIds, forKey: .relatedStampIds)
        try container.encodeIfPresent(editorState, forKey: .editorState)
    }
    
    // Standard initializer
    init(screenshotName: String, videoTime: Double, createdAt: Date, saveAsTag: Bool, displayDuration: Double, relatedStampIds: [UUID] = [], editorState: EditorStateSnapshot? = nil) {
        self.screenshotName = screenshotName
        self.videoTime = videoTime
        self.createdAt = createdAt
        self.saveAsTag = saveAsTag
        self.displayDuration = displayDuration
        self.relatedStampIds = relatedStampIds
        self.editorState = editorState
    }
}

// MARK: - Screenshot Constants

struct ScreenshotConstants {
    static let screenshotsTimelineID = UUID(uuidString: "00000000-0000-0000-0000-000000000228")!
    static let screenshotsGroupID = "screenshots_group_id_unique_228"
    static var screenshotsGroupName: String { ^String.Titles.drawingsTimelineName }
}

extension TimelineLine {
    var isDrawingsTimeline: Bool { id == ScreenshotConstants.screenshotsTimelineID }
}

