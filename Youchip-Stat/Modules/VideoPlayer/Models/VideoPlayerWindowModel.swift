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
    var savedWindowHeight: CGFloat? = nil
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
        } else if currentTool == .eraser {
            eraseAt(point)
        } else if currentTool == .textBox {
            addTextBox(at: point)
        }
    }
    
    func addPointToPath(_ point: CGPoint) {
        if currentTool == .pencil {
            currentPath.points.append(point)
        } else if currentTool == .eraser {
            eraseAt(point)
        }
    }
    
    func finishPath() {
        if currentTool == .pencil && !currentPath.points.isEmpty {
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
        
        textBoxes.removeAll { box in
            let boxRect = CGRect(origin: box.position, size: box.size)
            return boxRect.contains(point)
        }
    }
    
    func addTextBox(at point: CGPoint) {
        let defaultSize = CGSize(width: 150, height: 60)
        
        // Clamp position to canvas bounds
        let halfWidth = defaultSize.width / 2
        let halfHeight = defaultSize.height / 2
        let clampedX = max(halfWidth, min(point.x, viewSize.width - halfWidth))
        let clampedY = max(halfHeight, min(point.y, viewSize.height - halfHeight))
        
        let textBox = EditorTextBox(
            position: CGPoint(x: clampedX, y: clampedY),
            size: defaultSize,
            textColor: settings.textBoxTextColor,
            fontSize: settings.textBoxFontSize,
            fontName: settings.textBoxFontName,
            backgroundColor: settings.textBoxBackgroundColor,
            borderColor: settings.textBoxBorderColor,
            borderWidth: settings.textBoxBorderWidth
        )
        textBoxes.append(textBox)
        selectedTextBoxId = textBox.id
    }
    
    func updateTextBox(id: UUID, text: String) {
        if let index = textBoxes.firstIndex(where: { $0.id == id }) {
            textBoxes[index].text = text
        }
    }
    
    func moveTextBox(id: UUID, to position: CGPoint) {
        if let index = textBoxes.firstIndex(where: { $0.id == id }) {
            textBoxes[index].position = position
        }
    }
    
    func resizeTextBox(id: UUID, size: CGSize) {
        if let index = textBoxes.firstIndex(where: { $0.id == id }) {
            textBoxes[index].size = size
        }
    }
    
    func rotateTextBox(id: UUID, rotation: CGFloat) {
        if let index = textBoxes.firstIndex(where: { $0.id == id }) {
            textBoxes[index].rotation = rotation
        }
    }
    
    func deleteTextBox(id: UUID) {
        textBoxes.removeAll { $0.id == id }
        if selectedTextBoxId == id {
            selectedTextBoxId = nil
        }
    }
    
    func updateSelectedTextBoxSettings() {
        guard let selectedId = selectedTextBoxId,
              let index = textBoxes.firstIndex(where: { $0.id == selectedId }) else {
            return
        }
        
        textBoxes[index].textColor = settings.textBoxTextColor
        textBoxes[index].fontSize = settings.textBoxFontSize
        textBoxes[index].fontName = settings.textBoxFontName
        textBoxes[index].backgroundColor = settings.textBoxBackgroundColor
        textBoxes[index].borderColor = settings.textBoxBorderColor
        textBoxes[index].borderWidth = settings.textBoxBorderWidth
    }
    
    func clearDrawing() {
        completedPaths.removeAll()
        currentPath = EditorDrawingPath()
        textBoxes.removeAll()
        selectedTextBoxId = nil
        initialViewSize = .zero
        viewSize = .zero
    }
    
    func undo() {
        if !textBoxes.isEmpty {
            textBoxes.removeLast()
            selectedTextBoxId = nil
        } else if !completedPaths.isEmpty {
            completedPaths.removeLast()
        }
    }
    
    var hasDrawing: Bool {
        return !completedPaths.isEmpty || !currentPath.points.isEmpty || !textBoxes.isEmpty
    }
}

// MARK: - Editor Models

enum EditorTool {
    case cursor
    case pencil
    case eraser
    case textBox
}

struct EditorDrawingPath {
    var points: [CGPoint] = []
    var color: Color = .red
    var lineWidth: CGFloat = 3.0
    var lineStyle: EditorLineStyle = .solid
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
    var text: String = "текст"
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
}

struct EditorDrawingSettings {
    var currentColor: Color = .red
    var lineWidth: CGFloat = 3.0
    var lineStyle: EditorLineStyle = .solid
    var eraserWidth: CGFloat = 20.0
    
    // Text box settings
    var textBoxTextColor: Color = .white
    var textBoxFontSize: CGFloat = 20
    var textBoxFontName: String = "Helvetica"
    var textBoxBackgroundColor: Color = .clear
    var textBoxBorderColor: Color = .white
    var textBoxBorderWidth: CGFloat = 2.0
    
    static let availableColors: [Color] = [
        .red, .blue, .green, .yellow, .orange, .purple, .pink, .white, .black, .clear
    ]
    
    static let availableWidths: [CGFloat] = [1, 2, 3, 5, 8, 12]
    static let availableEraserWidths: [CGFloat] = [10, 20, 30, 50]
    static let availableFontSizes: [CGFloat] = [12, 14, 16, 18, 20, 24, 28, 32, 36, 48]
    static let availableFonts: [String] = [
        "Helvetica", "Helvetica-Bold", "Arial", "Arial-Bold",
        "Courier", "Courier-Bold", "Times New Roman", "Times New Roman-Bold"
    ]
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

