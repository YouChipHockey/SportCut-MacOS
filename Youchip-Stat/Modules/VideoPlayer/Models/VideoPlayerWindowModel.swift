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

// MARK: - Editor Drawing State

class EditorDrawingState: ObservableObject {
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
    var lastTelestrationDragStartPositions: [CGPoint]? = nil
    /// Индекс вершины при перетаскивании одной вершины; nil = перемещение всего объекта.
    var lastTelestrationDragVertexIndex: Int? = nil
    
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
            
            textBoxes = textBoxes.map { box in
                var newBox = box
                newBox.position = CGPoint(x: box.position.x * scaleX, y: box.position.y * scaleY)
                newBox.size = CGSize(width: box.size.width * scaleX, height: box.size.height * scaleY)
                return newBox
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
        
        // Стираем объекты телестрации
        telestrationObjects.removeAll { object in
            object.positions.contains { position in
                let distance = hypot(position.x - point.x, position.y - point.y)
                return distance < eraserRadius
            }
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
    
    
    func clearDrawing() {
        completedPaths.removeAll()
        currentPath = EditorDrawingPath()
        textBoxes.removeAll()
        selectedTextBoxId = nil
        telestrationObjects.removeAll()
        selectedTelestrationObjectId = nil
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
        } else if !shapes.isEmpty {
            // Удаляем последнюю добавленную фигуру
            shapes.removeLast()
        } else if !telestrationObjects.isEmpty {
            // Удаляем последний добавленный объект телестрации
            telestrationObjects.removeLast()
        } else if !completedPaths.isEmpty {
            // Удаляем последний путь
            completedPaths.removeLast()
        }
    }
    
    var hasDrawing: Bool {
        return !completedPaths.isEmpty || !currentPath.points.isEmpty || !telestrationObjects.isEmpty || !shapes.isEmpty
    }
    
    // MARK: - Telestration Methods
    
    func startCreatingTelestrationObject(type: ObjectType) {
        currentTelestrationType = type
        isCreatingTelestrationObject = true
        telestrationVertices.removeAll()
        showingTelestrationTypeSelection = false
        selectedTelestrationObjectId = nil
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
        
        pendingTelestrationObject = newObject
        isCreatingTelestrationObject = false
        telestrationVertices.removeAll()
        currentTelestrationType = nil
        selectedTelestrationObjectId = nil
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
            if object.type == .curvedArrow { object.curveHeight = telestrationCustomization.curveHeight }
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
        if object.type == .curvedArrow { object.curveHeight = telestrationCustomization.curveHeight }
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
    }
    
    func deleteSelectedTelestrationObject() {
        guard let id = selectedTelestrationObjectId else { return }
        telestrationObjects.removeAll { $0.id == id }
        selectedTelestrationObjectId = nil
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
        
        // Для закругленной стрелки сохраняем curveHeight
        if object.type == .curvedArrow {
            object.curveHeight = telestrationCustomization.curveHeight
        }
        
        telestrationObjects.append(object)
        
        pendingTelestrationObject = nil
        telestrationCustomization = ObjectCustomization()
        
        return object
    }
    
    func cancelTelestrationObjectCreation() {
        pendingTelestrationObject = nil
        isCreatingTelestrationObject = false
        telestrationVertices.removeAll()
        currentTelestrationType = nil
        telestrationCustomization = ObjectCustomization()
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
        newTextBox.text = "Текст"
        updateTextBoxSizeToFit(&newTextBox)
        newTextBox.position = clampTextBoxPosition(newTextBox.position, size: newTextBox.size)
        pendingTextBox = newTextBox
        isCreatingTextBox = false
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
    
    func updateSelectedShape(fillColor: Color? = nil, strokeColor: Color? = nil, strokeWidth: CGFloat? = nil, lineStyle: EditorLineStyle? = nil) {
        guard let shapeId = selectedShapeId,
              let index = shapes.firstIndex(where: { $0.id == shapeId }) else { return }
        
        if let fillColor = fillColor {
            shapes[index].fillColor = fillColor
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
        case .triangle: return "Triangle"
        case .square: return "Square"
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .star: return "Star"
        case .hexagon: return "Hexagon"
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
    let id = UUID()
    var type: ShapeType
    var position: CGPoint
    var size: CGSize
    var rotation: CGFloat = 0.0
    
    var fillColor: Color = .blue
    var strokeColor: Color = .white
    var strokeWidth: CGFloat = 2.0
    var lineStyle: EditorLineStyle = .solid
    
    init(type: ShapeType, position: CGPoint, size: CGSize = CGSize(width: 100, height: 100)) {
        self.type = type
        self.position = position
        self.size = size
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
    var text: String = "Текст"
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

// MARK: - Screenshot Metadata

struct ScreenshotMetadata: Codable {
    let screenshotName: String
    let videoTime: Double
    let createdAt: Date
    let saveAsTag: Bool
    let displayDuration: Double // How long to show screenshot during export (default 3.0 for backward compatibility)
    let relatedStampIds: [UUID] // IDs of timeline stamps this screenshot is associated with
    
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
    }
    
    // Custom decoder for backward compatibility with old screenshots without displayDuration
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        screenshotName = try container.decode(String.self, forKey: .screenshotName)
        videoTime = try container.decode(Double.self, forKey: .videoTime)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        saveAsTag = try container.decode(Bool.self, forKey: .saveAsTag)
        displayDuration = try container.decodeIfPresent(Double.self, forKey: .displayDuration) ?? 3.0
        relatedStampIds = try container.decodeIfPresent([UUID].self, forKey: .relatedStampIds) ?? []
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
    }
    
    // Standard initializer
    init(screenshotName: String, videoTime: Double, createdAt: Date, saveAsTag: Bool, displayDuration: Double, relatedStampIds: [UUID] = []) {
        self.screenshotName = screenshotName
        self.videoTime = videoTime
        self.createdAt = createdAt
        self.saveAsTag = saveAsTag
        self.displayDuration = displayDuration
        self.relatedStampIds = relatedStampIds
    }
}

// MARK: - Screenshot Constants

struct ScreenshotConstants {
    static let screenshotsTimelineID = UUID(uuidString: "00000000-0000-0000-0000-000000000228")!
    static let screenshotsGroupID = "screenshots_group_id_unique_228"
    static let screenshotsGroupName = "Рисунки"
}

