//
//  VideoPlayerEditorComponents.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit

// MARK: - Editor Tools Panel

struct EditorToolsPanel: View {
    @ObservedObject var drawingState: EditorDrawingState
    let onSelectTool: (EditorTool) -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Tools")
                    .font(.headline)
                    .padding(.top)
                
                VStack(spacing: 8) {
                    toolButton(tool: .cursor, icon: "cursorarrow.rays", label: "Cursor")
                    toolButton(tool: .pencil, icon: "pencil", label: "Pencil")
                    toolButton(tool: .eraser, icon: "eraser", label: "Eraser")
                    toolButton(tool: .textBox, icon: "textbox", label: "Text Box")
                }
                
                Divider()
                    .padding(.vertical)
                
                Button(action: {
                    drawingState.undo()
                }) {
                    Text("Undo")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!drawingState.hasDrawing)
                
                Button(action: {
                    drawingState.clearDrawing()
                }) {
                    Text("Clear All")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!drawingState.hasDrawing)
            }
            .padding(.horizontal)
        }
        .frame(width: 180)
    }
    
    private func toolButton(tool: EditorTool, icon: String, label: String) -> some View {
        Button(action: {
            onSelectTool(tool)
        }) {
            HStack {
                Image(systemName: icon)
                Text(label)
                Spacer()
                if drawingState.currentTool == tool {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(drawingState.currentTool == tool ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Editor Settings Panel

struct EditorSettingsPanel: View {
    @ObservedObject var drawingState: EditorDrawingState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Settings")
                    .font(.headline)
                    .padding(.top)
                
                if drawingState.currentTool == .cursor {
                    cursorSettings
                } else if drawingState.currentTool == .pencil {
                    pencilSettings
                } else if drawingState.currentTool == .eraser {
                    eraserSettings
                } else if drawingState.currentTool == .textBox {
                    textBoxSettings
                }
            }
            .padding(.horizontal)
        }
        .frame(width: 180)
    }
    
    private var cursorSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cursor Mode")
                .font(.subheadline)
            
            Text("Click to select text boxes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var pencilSettings: some View {
        Group {
            // Color Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.subheadline)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 8) {
                    ForEach(EditorDrawingSettings.availableColors, id: \.self) { color in
                        colorButton(color: color)
                    }
                }
            }
            
            Divider()
            
            // Line Width
            VStack(alignment: .leading, spacing: 8) {
                Text("Line Width")
                    .font(.subheadline)
                
                ForEach(EditorDrawingSettings.availableWidths, id: \.self) { width in
                    lineWidthButton(width: width)
                }
            }
            
            Divider()
            
            // Line Style
            VStack(alignment: .leading, spacing: 8) {
                Text("Line Style")
                    .font(.subheadline)
                
                lineStyleButton(style: .solid, label: "Solid")
                lineStyleButton(style: .dashed, label: "Dashed")
            }
        }
    }
    
    private var eraserSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eraser Size")
                .font(.subheadline)
            
            ForEach(EditorDrawingSettings.availableEraserWidths, id: \.self) { width in
                eraserWidthButton(width: width)
            }
        }
    }
    
    private var textBoxSettings: some View {
        Group {
            // Text Color
            VStack(alignment: .leading, spacing: 8) {
                Text("Text Color")
                    .font(.subheadline)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 8) {
                    ForEach(EditorDrawingSettings.availableColors, id: \.self) { color in
                        textColorButton(color: color)
                    }
                }
            }
            
            Divider()
            
            // Font Size
            VStack(alignment: .leading, spacing: 8) {
                Text("Font Size")
                    .font(.subheadline)
                
                ForEach(EditorDrawingSettings.availableFontSizes, id: \.self) { size in
                    fontSizeButton(size: size)
                }
            }
            
            Divider()
            
            // Font
            VStack(alignment: .leading, spacing: 8) {
                Text("Font")
                    .font(.subheadline)
                
                ForEach(EditorDrawingSettings.availableFonts, id: \.self) { fontName in
                    fontButton(fontName: fontName)
                }
            }
            
            Divider()
            
            // Background Color
            VStack(alignment: .leading, spacing: 8) {
                Text("Background Color")
                    .font(.subheadline)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 8) {
                    ForEach(EditorDrawingSettings.availableColors, id: \.self) { color in
                        backgroundColorButton(color: color)
                    }
                }
            }
            
            Divider()
            
            // Border Color
            VStack(alignment: .leading, spacing: 8) {
                Text("Border Color")
                    .font(.subheadline)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 8) {
                    ForEach(EditorDrawingSettings.availableColors, id: \.self) { color in
                        borderColorButton(color: color)
                    }
                }
            }
            
            Divider()
            
            // Border Width
            VStack(alignment: .leading, spacing: 8) {
                Text("Border Width")
                    .font(.subheadline)
                
                ForEach(EditorDrawingSettings.availableWidths, id: \.self) { width in
                    borderWidthButton(width: width)
                }
            }
        }
    }
    
    private func colorButton(color: Color) -> some View {
        Button(action: {
            drawingState.settings.currentColor = color
        }) {
            ZStack {
                if color == .clear {
                    // Checkerboard pattern for transparent
                    Circle()
                        .fill(Color.white)
                        .overlay(
                            Image(systemName: "slash.circle")
                                .foregroundColor(.red)
                        )
                } else {
                    Circle()
                        .fill(color)
                }
            }
            .frame(width: 30, height: 30)
            .overlay(
                Circle()
                    .stroke(drawingState.settings.currentColor == color ? Color.primary : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func lineWidthButton(width: CGFloat) -> some View {
        Button(action: {
            drawingState.settings.lineWidth = width
        }) {
            HStack {
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 60, height: width)
                    .cornerRadius(width / 2)
                
                Spacer()
                
                Text("\(Int(width))pt")
                    .font(.caption)
                
                if drawingState.settings.lineWidth == width {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(drawingState.settings.lineWidth == width ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func lineStyleButton(style: EditorLineStyle, label: String) -> some View {
        Button(action: {
            drawingState.settings.lineStyle = style
        }) {
            HStack {
                Text(label)
                Spacer()
                if drawingState.settings.lineStyle == style {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(drawingState.settings.lineStyle == style ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func eraserWidthButton(width: CGFloat) -> some View {
        Button(action: {
            drawingState.settings.eraserWidth = width
        }) {
            HStack {
                Circle()
                    .fill(Color.gray)
                    .frame(width: width / 2, height: width / 2)
                
                Spacer()
                
                Text("\(Int(width))pt")
                    .font(.caption)
                
                if drawingState.settings.eraserWidth == width {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(drawingState.settings.eraserWidth == width ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Text Box Settings Buttons
    
    private func textColorButton(color: Color) -> some View {
        Button(action: {
            drawingState.settings.textBoxTextColor = color
            drawingState.updateSelectedTextBoxSettings()
        }) {
            ZStack {
                if color == .clear {
                    Circle()
                        .fill(Color.white)
                        .overlay(
                            Image(systemName: "slash.circle")
                                .foregroundColor(.red)
                        )
                } else {
                    Circle()
                        .fill(color)
                }
            }
            .frame(width: 30, height: 30)
            .overlay(
                Circle()
                    .stroke(drawingState.settings.textBoxTextColor == color ? Color.primary : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func fontSizeButton(size: CGFloat) -> some View {
        Button(action: {
            drawingState.settings.textBoxFontSize = size
            drawingState.updateSelectedTextBoxSettings()
        }) {
            HStack {
                Text("Aa")
                    .font(.system(size: size / 2))
                
                Spacer()
                
                Text("\(Int(size))pt")
                    .font(.caption)
                
                if drawingState.settings.textBoxFontSize == size {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(drawingState.settings.textBoxFontSize == size ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func fontButton(fontName: String) -> some View {
        Button(action: {
            drawingState.settings.textBoxFontName = fontName
            drawingState.updateSelectedTextBoxSettings()
        }) {
            HStack {
                Text(fontName.replacingOccurrences(of: "-", with: " "))
                    .font(.custom(fontName, size: 12))
                    .lineLimit(1)
                
                Spacer()
                
                if drawingState.settings.textBoxFontName == fontName {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(drawingState.settings.textBoxFontName == fontName ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func backgroundColorButton(color: Color) -> some View {
        Button(action: {
            drawingState.settings.textBoxBackgroundColor = color
            drawingState.updateSelectedTextBoxSettings()
        }) {
            ZStack {
                if color == .clear {
                    Circle()
                        .fill(Color.white)
                        .overlay(
                            Image(systemName: "slash.circle")
                                .foregroundColor(.red)
                        )
                } else {
                    Circle()
                        .fill(color)
                }
            }
            .frame(width: 30, height: 30)
            .overlay(
                Circle()
                    .stroke(drawingState.settings.textBoxBackgroundColor == color ? Color.primary : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func borderColorButton(color: Color) -> some View {
        Button(action: {
            drawingState.settings.textBoxBorderColor = color
            drawingState.updateSelectedTextBoxSettings()
        }) {
            ZStack {
                if color == .clear {
                    Circle()
                        .fill(Color.white)
                        .overlay(
                            Image(systemName: "slash.circle")
                                .foregroundColor(.red)
                        )
                } else {
                    Circle()
                        .fill(color)
                }
            }
            .frame(width: 30, height: 30)
            .overlay(
                Circle()
                    .stroke(drawingState.settings.textBoxBorderColor == color ? Color.primary : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func borderWidthButton(width: CGFloat) -> some View {
        Button(action: {
            drawingState.settings.textBoxBorderWidth = width
            drawingState.updateSelectedTextBoxSettings()
        }) {
            HStack {
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 60, height: width)
                    .cornerRadius(width / 2)
                
                Spacer()
                
                Text("\(Int(width))pt")
                    .font(.caption)
                
                if drawingState.settings.textBoxBorderWidth == width {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(drawingState.settings.textBoxBorderWidth == width ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Drawing Canvas View

struct DrawingCanvasView: View {
    @ObservedObject var drawingState: EditorDrawingState
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background to catch clicks for deselecting text boxes
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Deselect when clicking outside text boxes (only for cursor and textBox tools)
                        if (drawingState.currentTool == .cursor || drawingState.currentTool == .textBox) &&
                           drawingState.selectedTextBoxId != nil {
                            drawingState.selectedTextBoxId = nil
                        }
                    }
                
                // Canvas для рисования путей
                Canvas { context, size in
                    // Обновляем размер в drawing state
                    DispatchQueue.main.async {
                        if drawingState.viewSize != size {
                            drawingState.viewSize = size
                        }
                    }
                    
                    for path in drawingState.completedPaths {
                        drawPath(path, in: context)
                    }
                    
                    if !drawingState.currentPath.points.isEmpty {
                        drawPath(drawingState.currentPath, in: context)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let location = value.location
                            
                            if drawingState.currentTool == .pencil || drawingState.currentTool == .eraser {
                                if drawingState.currentPath.points.isEmpty {
                                    drawingState.startNewPath(at: location)
                                } else {
                                    drawingState.addPointToPath(location)
                                }
                            }
                        }
                        .onEnded { _ in
                            if drawingState.currentTool == .pencil || drawingState.currentTool == .eraser {
                                drawingState.finishPath()
                            }
                        }
                )
                .simultaneousGesture(
                    TapGesture()
                        .onEnded { _ in
                            if drawingState.currentTool == .textBox {
                                let centerPoint = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                drawingState.startNewPath(at: centerPoint)
                            }
                        }
                )
                
                // Текстовые боксы
                ForEach(drawingState.textBoxes.indices, id: \.self) { index in
                    InteractiveTextBox(
                        textBox: $drawingState.textBoxes[index],
                        drawingState: drawingState,
                        isSelected: drawingState.selectedTextBoxId == drawingState.textBoxes[index].id,
                        onSelect: {
                            drawingState.selectedTextBoxId = drawingState.textBoxes[index].id
                        },
                        onDeselect: {
                            if drawingState.selectedTextBoxId == drawingState.textBoxes[index].id {
                                drawingState.selectedTextBoxId = nil
                            }
                        }
                    )
                }
            }
        }
    }
    
    private func drawPath(_ path: EditorDrawingPath, in context: GraphicsContext) {
        guard path.points.count > 1 else { return }
        
        var cgPath = Path()
        cgPath.move(to: path.points[0])
        
        for point in path.points.dropFirst() {
            cgPath.addLine(to: point)
        }
        
        context.stroke(
            cgPath,
            with: .color(path.color),
            lineWidth: path.lineWidth
        )
    }
}

// MARK: - Interactive Text Box

struct InteractiveTextBox: View {
    @Binding var textBox: EditorTextBox
    @ObservedObject var drawingState: EditorDrawingState
    let isSelected: Bool
    let onSelect: () -> Void
    let onDeselect: () -> Void
    
    @State private var isEditing = false
    @State private var lastTapTime: Date = Date()
    @GestureState private var dragState = DragState.inactive
    
    enum DragState {
        case inactive
        case dragging(startPosition: CGPoint)
    }
    
    var body: some View {
        ZStack {
            // Text box container
            RoundedRectangle(cornerRadius: 4)
                .fill(textBox.backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(textBox.borderColor, lineWidth: textBox.borderWidth)
                )
            
            // Text
            if isEditing {
                TextField("", text: $textBox.text, onCommit: {
                    isEditing = false
                    drawingState.isEditingTextBox = false
                    NotificationCenter.default.post(name: .textBoxEditingChanged, object: false)
                })
                .font(.custom(textBox.fontName, size: textBox.fontSize))
                .foregroundColor(textBox.textColor)
                .multilineTextAlignment(.center)
                .padding(8)
            } else {
                Text(textBox.text)
                    .font(.custom(textBox.fontName, size: textBox.fontSize))
                    .foregroundColor(textBox.textColor)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
            
            // Selection handles
            if isSelected && !isEditing {
                selectionHandles
            }
        }
        .frame(width: textBox.size.width, height: textBox.size.height)
        .rotationEffect(.degrees(Double(textBox.rotation)))
        .position(x: textBox.position.x, y: textBox.position.y)
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    let now = Date()
                    let timeSinceLastTap = now.timeIntervalSince(lastTapTime)
                    
                    if timeSinceLastTap < 0.3 {
                        // Double tap - enter edit mode
                        if isSelected && !isEditing {
                            isEditing = true
                            drawingState.isEditingTextBox = true
                            NotificationCenter.default.post(name: .textBoxEditingChanged, object: true)
                        }
                    } else {
                        // Single tap - select
                        if !isEditing {
                            onSelect()
                        }
                    }
                    
                    lastTapTime = now
                }
        )
        .gesture(
            DragGesture()
                .updating($dragState) { value, state, _ in
                    if isSelected && !isEditing {
                        if case .inactive = state {
                            state = .dragging(startPosition: textBox.position)
                        }
                    }
                }
                .onChanged { value in
                    if isSelected && !isEditing {
                        if case .dragging(let startPosition) = dragState {
                            let newX = startPosition.x + value.translation.width
                            let newY = startPosition.y + value.translation.height
                            
                            // Clamp to canvas bounds
                            let halfWidth = textBox.size.width / 2
                            let halfHeight = textBox.size.height / 2
                            let clampedX = max(halfWidth, min(newX, drawingState.viewSize.width - halfWidth))
                            let clampedY = max(halfHeight, min(newY, drawingState.viewSize.height - halfHeight))
                            
                            textBox.position = CGPoint(x: clampedX, y: clampedY)
                        }
                    }
                }
        )
        .onChange(of: isSelected) { selected in
            if !selected {
                if isEditing {
                    NotificationCenter.default.post(name: .textBoxEditingChanged, object: false)
                }
                isEditing = false
                drawingState.isEditingTextBox = false
            }
        }
    }
    
    private var selectionHandles: some View {
        ZStack {
            // Border
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.blue, lineWidth: 2)
                .frame(width: textBox.size.width, height: textBox.size.height)
            
            // Top-left corner
            resizeHandle(xMultiplier: -1, yMultiplier: -1)
                .offset(x: -textBox.size.width/2, y: -textBox.size.height/2)
            
            // Top-right corner
            resizeHandle(xMultiplier: 1, yMultiplier: -1)
                .offset(x: textBox.size.width/2, y: -textBox.size.height/2)
            
            // Bottom-left corner
            resizeHandle(xMultiplier: -1, yMultiplier: 1)
                .offset(x: -textBox.size.width/2, y: textBox.size.height/2)
            
            // Bottom-right corner
            resizeHandle(xMultiplier: 1, yMultiplier: 1)
                .offset(x: textBox.size.width/2, y: textBox.size.height/2)
            
            // Rotation handle
            rotationHandle()
                .offset(x: 0, y: -textBox.size.height/2 - 20)
        }
    }
    
    private func resizeHandle(xMultiplier: CGFloat, yMultiplier: CGFloat) -> some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 12, height: 12)
            .highPriorityGesture(
                DragGesture()
                    .onChanged { value in
                        let newWidth = max(50, textBox.size.width + value.translation.width * 2 * xMultiplier)
                        let newHeight = max(30, textBox.size.height + value.translation.height * 2 * yMultiplier)
                        
                        // Clamp to canvas bounds
                        let maxWidth = min(newWidth, (drawingState.viewSize.width - abs(textBox.position.x)) * 2)
                        let maxHeight = min(newHeight, (drawingState.viewSize.height - abs(textBox.position.y)) * 2)
                        
                        textBox.size = CGSize(width: maxWidth, height: maxHeight)
                    }
            )
    }
    
    private func rotationHandle() -> some View {
        Circle()
            .fill(Color.green)
            .frame(width: 12, height: 12)
            .highPriorityGesture(
                DragGesture()
                    .onChanged { value in
                        // Calculate angle relative to text box center
                        let dx = value.location.x
                        let dy = value.location.y
                        let angle = atan2(dy, dx) * 180 / .pi
                        textBox.rotation = angle - 90 // Subtract 90 to make top handle align properly
                    }
            )
    }
}

// MARK: - Editor Video Player View

struct EditorVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> NSView {
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        
        let view = NSView()
        view.wantsLayer = true
        view.layer = playerLayer
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let playerLayer = nsView.layer as? AVPlayerLayer {
            playerLayer.player = player
            playerLayer.frame = nsView.bounds
        }
    }
}

