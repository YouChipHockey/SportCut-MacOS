//
//  VideoPlayerEditorComponents.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import AppKit

// MARK: - Editor Tools Panel

struct EditorToolsPanel: View {
    @ObservedObject var drawingState: EditorDrawingState
    let onSelectTool: (EditorTool) -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(^String.Titles.tools)
                    .font(.headline)
                    .padding(.top)
                
                VStack(spacing: 8) {
                    toolButton(tool: .cursor, icon: "cursorarrow.rays", label: ^String.Titles.editorCursor)
                    toolButton(tool: .pencil, icon: "pencil", label: ^String.Titles.pencil)
                    toolButton(tool: .arrow, icon: "arrow.right", label: ^String.Titles.arrow)
                    toolButton(tool: .eraser, icon: "eraser", label: ^String.Titles.eraser)
                    
                    // Telestration menu
                    Menu {
                        ForEach(ObjectType.allCases, id: \.self) { type in
                            Button(action: {
                                // Сбрасываем предыдущую телестрацию если была
                                if drawingState.isCreatingTelestrationObject || drawingState.pendingTelestrationObject != nil {
                                    drawingState.cancelTelestrationObjectCreation()
                                }
                                // Используем onSelectTool для правильного сброса выделения
                                onSelectTool(.telestration)
                                drawingState.startCreatingTelestrationObject(type: type)
                            }) {
                                Text(type.displayName)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "circle.grid.3x3")
                            Text(^String.Titles.editorTelestration)
                            Spacer()
                            if drawingState.currentTool == .telestration {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(drawingState.currentTool == .telestration ? Color.blue.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Shapes menu
                    Menu {
                        ForEach(ShapeType.allCases, id: \.self) { type in
                            Button(action: {
                                // Сбрасываем предыдущую фигуру если была
                                if drawingState.isCreatingShape || drawingState.pendingShape != nil {
                                    drawingState.cancelShapeCreation()
                                }
                                // Сбрасываем телестрацию если была
                                if drawingState.isCreatingTelestrationObject || drawingState.pendingTelestrationObject != nil {
                                    drawingState.cancelTelestrationObjectCreation()
                                }
                                // Сбрасываем текстовый бокс если был
                                if drawingState.isCreatingTextBox || drawingState.pendingTextBox != nil {
                                    drawingState.cancelTextBoxCreation()
                                }
                                // Используем onSelectTool для правильного сброса выделения
                                onSelectTool(.shapes)
                                drawingState.startCreatingShape(type: type)
                            }) {
                                HStack {
                                    Image(systemName: type.iconName)
                                    Text(type.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.on.circle")
                            Text(^String.Titles.editorShapes)
                            Spacer()
                            if drawingState.currentTool == .shapes {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(drawingState.currentTool == .shapes ? Color.blue.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // TextBox button
                    toolButton(tool: .textBox, icon: "text.bubble", label: ^String.Titles.editorTextBox)
                }
                
                Divider()
                    .padding(.vertical)
                
                Button(action: {
                    drawingState.undo()
                }) {
                    Text(^String.Titles.undo)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!drawingState.hasDrawing)
                
                Button(action: {
                    drawingState.clearDrawing()
                }) {
                    Text(^String.Titles.clearAll)
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
            // Сбрасываем телестрацию при переключении на другой инструмент
            if tool != .telestration && (drawingState.isCreatingTelestrationObject || drawingState.pendingTelestrationObject != nil) {
                drawingState.cancelTelestrationObjectCreation()
            }
            // Сбрасываем создание фигуры при переключении на другой инструмент
            if tool != .shapes && (drawingState.isCreatingShape || drawingState.pendingShape != nil) {
                drawingState.cancelShapeCreation()
            }
            // Сбрасываем создание текстового бокса при переключении на другой инструмент
            if tool != .textBox && (drawingState.isCreatingTextBox || drawingState.pendingTextBox != nil) {
                drawingState.cancelTextBoxCreation()
            }
            // Если выбираем текстовый бокс, начинаем создание
            if tool == .textBox {
                drawingState.startCreatingTextBox()
            }
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
                Text(^String.Titles.settings)
                    .font(.headline)
                    .padding(.top)
                
                if drawingState.isCreatingTelestrationObject {
                    telestrationCreationSettings
                } else if drawingState.pendingTelestrationObject != nil {
                    telestrationCustomizationSettings
                } else if drawingState.selectedTelestrationObjectId != nil {
                    selectedTelestrationSettings
                } else if drawingState.pendingShape != nil {
                    shapeCustomizationSettings
                } else if drawingState.selectedShapeId != nil {
                    selectedShapeSettings
                } else if drawingState.pendingTextBox != nil {
                    textBoxCustomizationSettings
                } else if drawingState.selectedTextBoxId != nil {
                    selectedTextBoxSettings
                } else if drawingState.currentTool == .cursor {
                    cursorSettings
                } else if drawingState.currentTool == .pencil {
                    pencilSettings
                } else if drawingState.currentTool == .arrow {
                    arrowSettings
                } else if drawingState.currentTool == .eraser {
                    eraserSettings
                }
            }
            .padding(.horizontal)
        }
        .frame(width: 180)
    }
    
    private var cursorSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(^String.Titles.editorCursorMode)
                .font(.subheadline)
            
            Text(^String.Titles.editorSelectMode)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var pencilSettings: some View {
        Group {
            // Color Picker
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.color)
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
                Text(^String.Titles.lineWidth)
                    .font(.subheadline)
                
                ForEach(EditorDrawingSettings.availableWidths, id: \.self) { width in
                    lineWidthButton(width: width)
                }
            }
            
            Divider()
            
            // Line Style
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.lineStyleDrawing)
                    .font(.subheadline)
                
                lineStyleButton(style: .solid, label: ^String.Titles.solid)
                lineStyleButton(style: .dashed, label: ^String.Titles.dashedLine)
            }
        }
    }
    
    private var arrowSettings: some View {
        // Стрелочка использует те же настройки, что и карандаш
        pencilSettings
    }
    
    private var eraserSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(^String.Titles.eraserWidth)
                .font(.subheadline)
            
            ForEach(EditorDrawingSettings.availableEraserWidths, id: \.self) { width in
                eraserWidthButton(width: width)
            }
        }
    }
    
    private var telestrationCreationSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let type = drawingState.currentTelestrationType {
                Text(String.Titles.editorCreatingFormat.format(type.displayName))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(String.Titles.editorVerticesCount.format(drawingState.telestrationVertices.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                if drawingState.canRemoveLastTelestrationPoint {
                    Button(action: { drawingState.removeLastTelestrationPoint() }) {
                        HStack {
                            Image(systemName: "arrow.uturn.backward")
                            Text(^String.Titles.editorBack)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 4)
                }
                
                Button(^String.Titles.done) {
                    drawingState.finishCreatingTelestrationObject()
                }
                .disabled(drawingState.telestrationVertices.isEmpty)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                
                Button(^String.Titles.cancel) {
                    drawingState.cancelTelestrationObjectCreation()
                    drawingState.currentTool = .pencil
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var telestrationCustomizationSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let object = drawingState.pendingTelestrationObject {
                Text("\(^String.Titles.configuration): \(object.type.displayName)")
                    .font(.headline)
                
                Divider()
                
                if drawingState.canRemoveLastTelestrationPoint {
                    Button(action: { drawingState.removeLastTelestrationPoint() }) {
                        HStack {
                            Image(systemName: "arrow.uturn.backward")
                            Text(^String.Titles.editorBack)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 4)
                }
                
                Group {
                    switch object.type {
                    case .zoneBetweenObjects:
                        EditorZoneBetweenObjectsCustomization(drawingState: drawingState)
                    case .lineBetweenObjects:
                        EditorLineBetweenObjectsCustomization(drawingState: drawingState)
                    case .lineWithArrow:
                        EditorLineBetweenObjectsCustomization(drawingState: drawingState)
                    case .curvedArrow:
                        EditorCurvedArrowCustomization(drawingState: drawingState)
                    case .objectHighlight:
                        EditorObjectHighlightCustomization(drawingState: drawingState)
                    case .simpleZone:
                        EditorSimpleZoneCustomization(drawingState: drawingState)
                    }
                }
                
                Divider()
                
                HStack(spacing: 8) {
                    Button(^String.Titles.cancel) {
                        drawingState.cancelTelestrationObjectCreation()
                        drawingState.currentTool = .pencil
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    
                    Button(^String.Titles.apply) {
                        drawingState.confirmTelestrationObjectCreation()
                        drawingState.currentTool = .cursor
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    private var selectedTelestrationSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let id = drawingState.selectedTelestrationObjectId,
               let object = drawingState.telestrationObjects.first(where: { $0.id == id }) {
                Text("\(^String.Titles.configuration): \(object.type.displayName)")
                    .font(.headline)
                
                Divider()
                
                if drawingState.canRemoveLastTelestrationPoint {
                    Button(action: { drawingState.removeLastTelestrationPoint() }) {
                        HStack {
                            Image(systemName: "arrow.uturn.backward")
                            Text(^String.Titles.editorBack)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 4)
                }
                
                Group {
                    switch object.type {
                    case .zoneBetweenObjects:
                        EditorZoneBetweenObjectsCustomization(drawingState: drawingState)
                    case .lineBetweenObjects:
                        EditorLineBetweenObjectsCustomization(drawingState: drawingState)
                    case .lineWithArrow:
                        EditorLineBetweenObjectsCustomization(drawingState: drawingState)
                    case .curvedArrow:
                        EditorCurvedArrowCustomization(drawingState: drawingState)
                    case .objectHighlight:
                        EditorObjectHighlightCustomization(drawingState: drawingState)
                    case .simpleZone:
                        EditorSimpleZoneCustomization(drawingState: drawingState)
                    }
                }
                .onAppear {
                    drawingState.syncTelestrationCustomizationFromSelectedObject()
                }
                
                Divider()
                
                Button(^String.Titles.delete, role: .destructive) {
                    drawingState.deleteSelectedTelestrationObject()
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                
                HStack(spacing: 8) {
                    Button(^String.Titles.cancel) {
                        drawingState.selectedTelestrationObjectId = nil
                        drawingState.isAddingPointToTelestration = false
                        drawingState.telestrationPointUndoStack = []
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    
                    Button(^String.Titles.apply) {
                        drawingState.selectedTelestrationObjectId = nil
                        drawingState.isAddingPointToTelestration = false
                        drawingState.telestrationPointUndoStack = []
                        drawingState.currentTool = .cursor
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    private var shapeCustomizationSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let shape = drawingState.pendingShape {
                Text(String.Titles.editorConfigurationShapeFormat.format(shape.type.displayName))
                    .font(.headline)
                
                Divider()
                
                // Fill Color
                HStack {
                    Text(^String.Titles.fillColor)
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { shape.fillColor },
                        set: { newColor in
                            if var updatedShape = drawingState.pendingShape {
                                updatedShape.fillColor = newColor
                                updatedShape.fillOpacity = 1
                                drawingState.pendingShape = updatedShape
                            }
                        }
                    ))
                    .frame(width: 40, height: 30)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Button(^String.Titles.transparentBackground) {
                        if var updatedShape = drawingState.pendingShape {
                            updatedShape.fillOpacity = 0
                            drawingState.pendingShape = updatedShape
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    Button(^String.Titles.opaqueBackground) {
                        if var updatedShape = drawingState.pendingShape {
                            updatedShape.fillOpacity = 1
                            drawingState.pendingShape = updatedShape
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                
                Divider()
                
                // Stroke Color
                HStack {
                    Text(^String.Titles.editorStrokeColor)
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { shape.strokeColor },
                        set: { newColor in
                            if var updatedShape = drawingState.pendingShape {
                                updatedShape.strokeColor = newColor
                                drawingState.pendingShape = updatedShape
                            }
                        }
                    ))
                    .frame(width: 40, height: 30)
                }
                
                Divider()
                
                // Stroke Width
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.editorStrokeWidth)
                        .font(.subheadline)
                    HStack {
                        Text("\(Int(shape.strokeWidth))pt")
                            .font(.caption)
                        Spacer()
                        Stepper("", value: Binding(
                            get: { shape.strokeWidth },
                            set: { newValue in
                                if var updatedShape = drawingState.pendingShape {
                                    updatedShape.strokeWidth = newValue
                                    drawingState.pendingShape = updatedShape
                                }
                            }
                        ), in: 1...20, step: 1)
                        .labelsHidden()
                    }
                }
                
                Divider()
                
                // Line Style
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.lineStyleDrawing)
                        .font(.subheadline)
                    HStack {
                        Button(action: {
                            if var updatedShape = drawingState.pendingShape {
                                updatedShape.lineStyle = .solid
                                drawingState.pendingShape = updatedShape
                            }
                        }) {
                            Text(^String.Titles.solid)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .background(shape.lineStyle == .solid ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(4)
                        
                        Button(action: {
                            if var updatedShape = drawingState.pendingShape {
                                updatedShape.lineStyle = .dashed
                                drawingState.pendingShape = updatedShape
                            }
                        }) {
                            Text(^String.Titles.dashedLine)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .background(shape.lineStyle == .dashed ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(4)
                    }
                }
                
                Divider()
                
                HStack(spacing: 8) {
                    Button(^String.Titles.cancel) {
                        drawingState.cancelShapeCreation()
                        drawingState.currentTool = .pencil
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    
                    Button(^String.Titles.apply) {
                        drawingState.confirmShapeCreation()
                        drawingState.currentTool = .cursor
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    private var selectedShapeSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let shapeId = drawingState.selectedShapeId,
               let shape = drawingState.shapes.first(where: { $0.id == shapeId }) {
                Text(String.Titles.editorEditShapeFormat.format(shape.type.displayName))
                    .font(.headline)
                
                Divider()
                
                // Fill Color
                HStack {
                    Text(^String.Titles.fillColor)
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { shape.fillColor },
                        set: { newColor in
                            drawingState.updateSelectedShape(fillColor: newColor, fillOpacity: 1)
                        }
                    ))
                    .frame(width: 40, height: 30)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Button(^String.Titles.transparentBackground) {
                        drawingState.updateSelectedShape(fillOpacity: 0)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    Button(^String.Titles.opaqueBackground) {
                        drawingState.updateSelectedShape(fillOpacity: 1)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                
                Divider()
                
                // Stroke Color
                HStack {
                    Text(^String.Titles.editorStrokeColor)
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { shape.strokeColor },
                        set: { newColor in
                            drawingState.updateSelectedShape(strokeColor: newColor)
                        }
                    ))
                    .frame(width: 40, height: 30)
                }
                
                Divider()
                
                // Stroke Width
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.editorStrokeWidth)
                        .font(.subheadline)
                    HStack {
                        Text("\(Int(shape.strokeWidth))pt")
                            .font(.caption)
                        Spacer()
                        Stepper("", value: Binding(
                            get: { shape.strokeWidth },
                            set: { newValue in
                                drawingState.updateSelectedShape(strokeWidth: newValue)
                            }
                        ), in: 1...20, step: 1)
                        .labelsHidden()
                    }
                }
                
                Divider()
                
                // Line Style
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.lineStyleDrawing)
                        .font(.subheadline)
                    HStack {
                        Button(action: {
                            drawingState.updateSelectedShape(lineStyle: .solid)
                        }) {
                            Text(^String.Titles.solid)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .background(shape.lineStyle == .solid ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(4)
                        
                        Button(action: {
                            drawingState.updateSelectedShape(lineStyle: .dashed)
                        }) {
                            Text(^String.Titles.dashedLine)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .background(shape.lineStyle == .dashed ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(4)
                    }
                }
                
                Divider()
                
                HStack(spacing: 8) {
                    Button(^String.Titles.cancel) {
                        drawingState.selectedShapeId = nil
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    
                    Button(^String.Titles.apply) {
                        // Изменения уже применены, просто убираем выделение
                        drawingState.selectedShapeId = nil
                        drawingState.currentTool = .cursor
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    private var textBoxCustomizationSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let textBox = drawingState.pendingTextBox {
                Text(^String.Titles.editorEditTextBox)
                    .font(.headline)
                
                Divider()
                
                // Text (многострочный)
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.editorTextLabel)
                        .font(.subheadline)
                    TextEditor(text: Binding(
                        get: { textBox.text },
                        set: { newText in
                            drawingState.updatePendingTextBox(apply: { $0.text = newText })
                        }
                    ))
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                }
                
                Divider()
                
                // Text Color
                HStack {
                    Text(^String.Titles.editorTextColor)
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { textBox.textColor },
                        set: { newColor in
                            if var updated = drawingState.pendingTextBox {
                                updated.textColor = newColor
                                drawingState.pendingTextBox = updated
                            }
                        }
                    ))
                    .frame(width: 40, height: 30)
                }
                
                Divider()
                
                // Font Size
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.editorFontSize)
                        .font(.subheadline)
                    HStack {
                        Text("\(Int(textBox.fontSize))pt")
                            .font(.caption)
                        Spacer()
                        Stepper("", value: Binding(
                            get: { textBox.fontSize },
                            set: { newValue in
                                drawingState.updatePendingTextBox(apply: { $0.fontSize = newValue })
                            }
                        ), in: 8...72, step: 1)
                        .labelsHidden()
                    }
                }
                
                Divider()
                
                // Font Name
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.editorFont)
                        .font(.subheadline)
                    Picker("", selection: Binding(
                        get: { textBox.fontName },
                        set: { newFont in
                            drawingState.updatePendingTextBox(apply: { $0.fontName = newFont })
                        }
                    )) {
                        Text("Helvetica").tag("Helvetica")
                        Text("Arial").tag("Arial")
                        Text("Times New Roman").tag("TimesNewRoman")
                        Text("Courier").tag("Courier")
                    }
                    .pickerStyle(.menu)
                }
                
                Divider()
                
                // Background Color
                HStack {
                    Text(^String.Titles.editorBackground)
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { textBox.backgroundColor },
                        set: { newColor in
                            if var updated = drawingState.pendingTextBox {
                                updated.backgroundColor = newColor
                                drawingState.pendingTextBox = updated
                            }
                        }
                    ))
                    .frame(width: 40, height: 30)
                }
                
                Divider()
                
                // Border Color
                HStack {
                    Text(^String.Titles.editorBorderColor)
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { textBox.borderColor },
                        set: { newColor in
                            if var updated = drawingState.pendingTextBox {
                                updated.borderColor = newColor
                                drawingState.pendingTextBox = updated
                            }
                        }
                    ))
                    .frame(width: 40, height: 30)
                }
                
                Divider()
                
                // Border Width
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.editorBorderWidth)
                        .font(.subheadline)
                    HStack {
                        Text("\(Int(textBox.borderWidth))pt")
                            .font(.caption)
                        Spacer()
                        Stepper("", value: Binding(
                            get: { textBox.borderWidth },
                            set: { newValue in
                                if var updated = drawingState.pendingTextBox {
                                    updated.borderWidth = newValue
                                    drawingState.pendingTextBox = updated
                                }
                            }
                        ), in: 0...10, step: 0.5)
                        .labelsHidden()
                    }
                }
                
                Divider()
                
                    Button(^String.Titles.apply) {
                        drawingState.confirmTextBoxCreation()
                        drawingState.currentTool = .cursor
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                
                Button(^String.Titles.cancel) {
                    drawingState.cancelTextBoxCreation()
                    drawingState.currentTool = .cursor
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var selectedTextBoxSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let textBoxId = drawingState.selectedTextBoxId,
               let textBox = drawingState.textBoxes.first(where: { $0.id == textBoxId }) {
                Text(^String.Titles.editorEditTextBox)
                    .font(.headline)
                
                Divider()
                
                // Text (многострочный)
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.editorTextLabel)
                        .font(.subheadline)
                    TextEditor(text: Binding(
                        get: { textBox.text },
                        set: { newText in
                            drawingState.updateSelectedTextBox(text: newText)
                        }
                    ))
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                }
                
                Divider()
                
                // Text Color
                HStack {
                    Text(^String.Titles.editorTextColor)
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { textBox.textColor },
                        set: { newColor in
                            drawingState.updateSelectedTextBox(textColor: newColor)
                        }
                    ))
                    .frame(width: 40, height: 30)
                }
                
                Divider()
                
                // Font Size
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.editorFontSize)
                        .font(.subheadline)
                    HStack {
                        Text("\(Int(textBox.fontSize))pt")
                            .font(.caption)
                        Spacer()
                        Stepper("", value: Binding(
                            get: { textBox.fontSize },
                            set: { newValue in
                                drawingState.updateSelectedTextBox(fontSize: newValue)
                            }
                        ), in: 8...72, step: 1)
                        .labelsHidden()
                    }
                }
                
                Divider()
                
                // Font Name
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.editorFont)
                        .font(.subheadline)
                    Picker("", selection: Binding(
                        get: { textBox.fontName },
                        set: { newFont in
                            drawingState.updateSelectedTextBox(fontName: newFont)
                        }
                    )) {
                        Text("Helvetica").tag("Helvetica")
                        Text("Arial").tag("Arial")
                        Text("Times New Roman").tag("TimesNewRoman")
                        Text("Courier").tag("Courier")
                    }
                    .pickerStyle(.menu)
                }
                
                Divider()
                
                // Background Color
                HStack {
                    Text(^String.Titles.editorBackground)
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { textBox.backgroundColor },
                        set: { newColor in
                            drawingState.updateSelectedTextBox(backgroundColor: newColor)
                        }
                    ))
                    .frame(width: 40, height: 30)
                }
                
                Divider()
                
                // Border Color
                HStack {
                    Text(^String.Titles.editorBorderColor)
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { textBox.borderColor },
                        set: { newColor in
                            drawingState.updateSelectedTextBox(borderColor: newColor)
                        }
                    ))
                    .frame(width: 40, height: 30)
                }
                
                Divider()
                
                // Border Width
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.editorBorderWidth)
                        .font(.subheadline)
                    HStack {
                        Text("\(Int(textBox.borderWidth))pt")
                            .font(.caption)
                        Spacer()
                        Stepper("", value: Binding(
                            get: { textBox.borderWidth },
                            set: { newValue in
                                drawingState.updateSelectedTextBox(borderWidth: newValue)
                            }
                        ), in: 0...10, step: 0.5)
                        .labelsHidden()
                    }
                }
                
                Divider()
                
                HStack(spacing: 8) {
                    Button(^String.Titles.cancel) {
                        drawingState.endTextBoxEditing()
                        drawingState.isEditingTextBox = false
                        drawingState.selectedTextBoxId = nil
                        drawingState.currentTool = .cursor
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    
                    Button(^String.Titles.apply) {
                        drawingState.selectedTextBoxId = nil
                        drawingState.currentTool = .cursor
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
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
    
}

// MARK: - Drawing Canvas View

struct DrawingCanvasView: View {
    @ObservedObject var drawingState: EditorDrawingState
    @State private var shapeInteractionMode: ShapeInteractionMode = .none
    @State private var initialRotation: CGFloat = 0 // Начальный угол для поворота
    @State private var initialSize: CGSize = .zero // Начальный размер для изменения размера
    @State private var initialPosition: CGPoint = .zero // Начальная позиция для перемещения
    
    @State private var textBoxInteractionMode: ShapeInteractionMode = .none
    @State private var initialTextBoxRotation: CGFloat = 0
    @State private var initialTextBoxSize: CGSize = .zero
    @State private var initialTextBoxPosition: CGPoint = .zero
    @State private var isMovingTelestrationObject = false
    @State private var curvedArrowMiddleDragStart: CGPoint? = nil
    @State private var lastTapTime: Date?
    @State private var lastTapLocation: CGPoint?
    
    enum ShapeInteractionMode {
        case none
        case moving
        case resizing(cornerIndex: Int) // Сохраняем индекс угла
        case rotating
    }
    
    /// Прямоугольник текстбокса (текст + обводка), без лишнего отступа — зона клика только по видимой области.
    private func textBoxRect(_ t: EditorTextBox) -> CGRect {
        let hw = t.size.width / 2, hh = t.size.height / 2
        return CGRect(x: t.position.x - hw, y: t.position.y - hh, width: t.size.width, height: t.size.height)
    }
    
    private func selectTextBoxAt(location: CGPoint, in drawingState: EditorDrawingState) {
        for textBox in drawingState.textBoxes.reversed() {
            if textBoxRect(textBox).contains(location) {
                drawingState.selectedTextBoxId = textBox.id
                drawingState.selectedShapeId = nil
                drawingState.selectedTelestrationObjectId = nil
                drawingState.isAddingPointToTelestration = false
                drawingState.telestrationPointUndoStack = []
                return
            }
        }
        drawingState.selectedTextBoxId = nil
    }
    
    /// Текстбокс под точкой: сначала pending, затем textBoxes. Зона — только видимая область (текст + обводка).
    private func textBoxAt(location: CGPoint, in drawingState: EditorDrawingState) -> (isPending: Bool, textBox: EditorTextBox)? {
        if let p = drawingState.pendingTextBox, textBoxRect(p).contains(location) { return (true, p) }
        for t in drawingState.textBoxes.reversed() {
            if textBoxRect(t).contains(location) { return (false, t) }
        }
        return nil
    }
    
    private func selectShapeAt(location: CGPoint, in drawingState: EditorDrawingState) {
        // Проверяем фигуры в обратном порядке (последние добавленные сверху)
        for shape in drawingState.shapes.reversed() {
            // Учитываем поворот при проверке попадания
            // Создаем трансформированный прямоугольник для проверки попадания
            let halfWidth = shape.size.width / 2
            let halfHeight = shape.size.height / 2
            
            // Создаем углы фигуры
            let corners = [
                CGPoint(x: -halfWidth, y: -halfHeight),
                CGPoint(x: halfWidth, y: -halfHeight),
                CGPoint(x: halfWidth, y: halfHeight),
                CGPoint(x: -halfWidth, y: halfHeight)
            ]
            
            // Применяем трансформацию (поворот и перемещение)
            let transform = CGAffineTransform(translationX: shape.position.x, y: shape.position.y)
                .rotated(by: shape.rotation * .pi / 180)
            
            let transformedCorners = corners.map { $0.applying(transform) }
            
            // Проверяем попадание через простой прямоугольник (для упрощения)
            let shapeRect = CGRect(
                x: shape.position.x - halfWidth - 5,
                y: shape.position.y - halfHeight - 5,
                width: shape.size.width + 10,
                height: shape.size.height + 10
            )
            
            if shapeRect.contains(location) {
                drawingState.selectedShapeId = shape.id
                drawingState.selectedTelestrationObjectId = nil
                drawingState.isAddingPointToTelestration = false
                drawingState.telestrationPointUndoStack = []
                return
            }
        }
        drawingState.selectedShapeId = nil
    }
    
    private func selectTelestrationObjectAt(location: CGPoint, in drawingState: EditorDrawingState) {
        for object in drawingState.telestrationObjects.reversed() {
            if telestrationObjectContains(point: location, object: object) {
                drawingState.selectedTelestrationObjectId = object.id
                drawingState.selectedShapeId = nil
                drawingState.selectedTextBoxId = nil
                drawingState.telestrationPointUndoStack = []
                drawingState.syncTelestrationCustomizationFromSelectedObject()
                return
            }
        }
        drawingState.selectedTelestrationObjectId = nil
        drawingState.isAddingPointToTelestration = false
        drawingState.telestrationPointUndoStack = []
    }
    
    private func telestrationObjectContains(point: CGPoint, object: DrawableObject) -> Bool {
        switch object.type {
        case .zoneBetweenObjects, .simpleZone:
            guard object.positions.count >= 3 else { return false }
            if pointInPolygon(point, object.positions) { return true }
            return distanceToPolygonOrPolyline(point, object.positions, closed: true) < 15
        case .lineBetweenObjects, .lineWithArrow:
            guard object.positions.count >= 2 else { return false }
            return distanceToPolygonOrPolyline(point, object.positions, closed: false) < 15
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
    
    /// Проверка: вершина (vertexIndex) или ребро/внутренность (nil). Для objectHighlight и simpleZone — только (nil, isOnObject).
    private func telestrationHitTest(point: CGPoint, object: DrawableObject) -> (vertexIndex: Int?, isOnObject: Bool) {
        let hitRadius: CGFloat = 12
        switch object.type {
        case .objectHighlight, .simpleZone:
            return (nil, telestrationObjectContains(point: point, object: object))
        case .zoneBetweenObjects, .lineBetweenObjects, .lineWithArrow, .curvedArrow:
            for i in 0..<object.positions.count {
                if hypot(point.x - object.positions[i].x, point.y - object.positions[i].y) < hitRadius {
                    return (i, true)
                }
            }
            return (nil, telestrationObjectContains(point: point, object: object))
        }
    }
    
    private func pointInPolygon(_ point: CGPoint, _ polygon: [CGPoint]) -> Bool {
        var inside = false
        let n = polygon.count
        var j = n - 1
        for i in 0..<n {
            let xi = polygon[i].x, yi = polygon[i].y
            let xj = polygon[j].x, yj = polygon[j].y
            if ((yi > point.y) != (yj > point.y)) && (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
    
    private func distanceToPolygonOrPolyline(_ point: CGPoint, _ pts: [CGPoint], closed: Bool) -> CGFloat {
        var d: CGFloat = .greatestFiniteMagnitude
        for i in 0..<(pts.count - 1) {
            d = min(d, distanceFromPointToSegment(point, pts[i], pts[i + 1]))
        }
        if closed, pts.count >= 3 {
            d = min(d, distanceFromPointToSegment(point, pts[pts.count - 1], pts[0]))
        }
        return d
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
    
    /// Минимальное расстояние от точки до квадратичной кривой Безье (start → control → end). Используется для hit-test закруглённой стрелки.
    private func distanceFromPointToQuadCurve(_ point: CGPoint, start: CGPoint, control: CGPoint, end: CGPoint) -> CGFloat {
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
    
    private func handleShapeInteraction(value: DragGesture.Value, shape: EditorShape, drawingState: EditorDrawingState, geometry: GeometryProxy, isPending: Bool) {
        let location = value.location
        let halfWidth = shape.size.width / 2
        let halfHeight = shape.size.height / 2
        
        // Трансформация для учета поворота фигуры
        // Поворот вокруг центра фигуры
        let rotationRadians = shape.rotation * .pi / 180
        let transform = CGAffineTransform(translationX: shape.position.x, y: shape.position.y)
            .rotated(by: rotationRadians)
            .translatedBy(x: -shape.position.x, y: -shape.position.y)
        
        // Определяем режим взаимодействия при первом движении
        if case .none = shapeInteractionMode {
            // Проверяем, кликнули ли на ручку поворота (сверху, с учетом трансформации)
            // Ручка поворота в локальных координатах (относительно центра фигуры)
            let rotationHandleLocal = CGPoint(x: 0, y: -halfHeight - 20)
            // Поворачиваем и перемещаем на позицию фигуры
            let rotatedHandle = rotationHandleLocal.applying(CGAffineTransform(rotationAngle: rotationRadians))
            let rotationHandleWorld = CGPoint(
                x: rotatedHandle.x + shape.position.x,
                y: rotatedHandle.y + shape.position.y
            )
            let rotationHandleRect = CGRect(
                x: rotationHandleWorld.x - 10,
                y: rotationHandleWorld.y - 10,
                width: 20,
                height: 20
            )
            
            if rotationHandleRect.contains(value.startLocation) {
                shapeInteractionMode = .rotating
                initialRotation = shape.rotation
            } else {
                // Проверяем угловые ручки для изменения размера (с учетом трансформации)
                // Углы в локальных координатах (относительно центра фигуры в (0,0))
                let corners = [
                    CGPoint(x: -halfWidth, y: -halfHeight),
                    CGPoint(x: halfWidth, y: -halfHeight),
                    CGPoint(x: halfWidth, y: halfHeight),
                    CGPoint(x: -halfWidth, y: halfHeight)
                ]
                
                var foundCorner = false
                for (index, corner) in corners.enumerated() {
                    // Трансформируем угол в мировые координаты
                    // Сначала поворачиваем вокруг центра, потом перемещаем на позицию фигуры
                    let rotatedCorner = corner.applying(CGAffineTransform(rotationAngle: rotationRadians))
                    let transformedCorner = CGPoint(
                        x: rotatedCorner.x + shape.position.x,
                        y: rotatedCorner.y + shape.position.y
                    )
                    let cornerRect = CGRect(x: transformedCorner.x - 10, y: transformedCorner.y - 10, width: 20, height: 20)
                    if cornerRect.contains(value.startLocation) {
                        shapeInteractionMode = .resizing(cornerIndex: index)
                        initialSize = shape.size
                        foundCorner = true
                        break
                    }
                }
                
                if !foundCorner {
                    // Проверяем попадание в фигуру для перемещения
                    // Используем простую проверку через bounding box (без учета поворота для упрощения)
                    let shapeRect = CGRect(
                        x: shape.position.x - halfWidth - 5,
                        y: shape.position.y - halfHeight - 5,
                        width: shape.size.width + 10,
                        height: shape.size.height + 10
                    )
                    if shapeRect.contains(value.startLocation) {
                        shapeInteractionMode = .moving
                        initialPosition = shape.position
                        if isPending {
                            drawingState.startMovingPendingShape()
                        } else {
                            drawingState.startMovingShape()
                        }
                    }
                }
            }
        }
        
        // Выполняем действие в зависимости от режима
        switch shapeInteractionMode {
        case .rotating:
            // Вычисляем угол от центра фигуры до текущей позиции мыши
            let dx = location.x - shape.position.x
            let dy = location.y - shape.position.y
            let angleRadians = atan2(dy, dx)
            // Конвертируем в градусы и добавляем 90, чтобы ручка была сверху
            let angle = angleRadians * 180 / .pi + 90
            if isPending {
                drawingState.rotatePendingShape(angle: angle)
            } else {
                drawingState.rotateSelectedShape(angle: angle)
            }
            
        case .resizing(let cornerIndex):
            // Преобразуем текущую позицию мыши в локальные координаты фигуры (без поворота)
            // Убираем перемещение и поворот
            let dx = location.x - shape.position.x
            let dy = location.y - shape.position.y
            // Поворачиваем обратно, чтобы получить локальные координаты
            let cosAngle = cos(-rotationRadians)
            let sinAngle = sin(-rotationRadians)
            let localX = dx * cosAngle - dy * sinAngle
            let localY = dx * sinAngle + dy * cosAngle
            
            // Вычисляем расстояние от центра до новой позиции мыши в локальных координатах
            let distanceX = abs(localX)
            let distanceY = abs(localY)
            
            // Новый размер - это удвоенное расстояние от центра
            let newWidth = distanceX * 2
            let newHeight = distanceY * 2
            let minSize: CGFloat = 20
            let newSize = CGSize(
                width: max(minSize, newWidth),
                height: max(minSize, newHeight)
            )
            if isPending {
                drawingState.resizePendingShape(newSize: newSize)
            } else {
                drawingState.resizeSelectedShape(newSize: newSize)
            }
            
        case .moving:
            if isPending {
                drawingState.movePendingShape(by: value.translation)
            } else {
                drawingState.moveSelectedShape(by: value.translation)
            }
            
        case .none:
            break
        }
    }
    
    private func handleTextBoxInteraction(value: DragGesture.Value, textBox: EditorTextBox, drawingState: EditorDrawingState, geometry: GeometryProxy, isPending: Bool) {
        let location = value.location
        let halfWidth = textBox.size.width / 2
        let halfHeight = textBox.size.height / 2
        
        let rotationRadians = textBox.rotation * .pi / 180
        
        // Определяем режим взаимодействия при первом движении (без ресайза — размер подстраивается под текст)
        if case .none = textBoxInteractionMode {
            // Ручка поворота: выше верхнего края, зона как у фигур, но крупнее для удобства
            let rotationHandleLocal = CGPoint(x: 0, y: -halfHeight - 30)
            let rotatedHandle = rotationHandleLocal.applying(CGAffineTransform(rotationAngle: rotationRadians))
            let rotationHandleWorld = CGPoint(
                x: rotatedHandle.x + textBox.position.x,
                y: rotatedHandle.y + textBox.position.y
            )
            let rotationHandleRect = CGRect(
                x: rotationHandleWorld.x - 30,
                y: rotationHandleWorld.y - 30,
                width: 60,
                height: 60
            )
            
            if rotationHandleRect.contains(value.startLocation) {
                textBoxInteractionMode = .rotating
                initialTextBoxRotation = textBox.rotation
            } else if textBoxRect(textBox).contains(value.startLocation) {
                textBoxInteractionMode = .moving
                initialTextBoxPosition = textBox.position
                if isPending {
                    drawingState.startMovingPendingTextBox()
                } else {
                    drawingState.startMovingTextBox()
                }
            }
        }
        
        switch textBoxInteractionMode {
        case .rotating:
            let dx = location.x - textBox.position.x
            let dy = location.y - textBox.position.y
            let angleRadians = atan2(dy, dx)
            let angle = angleRadians * 180 / .pi + 90
            if isPending {
                drawingState.rotatePendingTextBox(angle: angle)
            } else {
                drawingState.rotateSelectedTextBox(angle: angle)
            }
            
        case .moving:
            if isPending {
                drawingState.movePendingTextBox(by: value.translation)
            } else {
                drawingState.moveSelectedTextBox(by: value.translation)
            }
            
        case .resizing, .none:
            break
        }
    }
    
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background to catch clicks for deselecting text boxes
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if drawingState.currentTool == .cursor {
                            if drawingState.selectedTextBoxId != nil {
                                drawingState.selectedTextBoxId = nil
                            }
                            if drawingState.selectedShapeId != nil {
                                drawingState.selectedShapeId = nil
                            }
                            if drawingState.selectedTelestrationObjectId != nil {
                                drawingState.selectedTelestrationObjectId = nil
                                drawingState.telestrationPointUndoStack = []
                            }
                            drawingState.isAddingPointToTelestration = false
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
                    
                    // Визуализация вершин телестрации при создании
                    if drawingState.isCreatingTelestrationObject {
                        for vertex in drawingState.telestrationVertices {
                            let circle = Path(ellipseIn: CGRect(
                                x: vertex.x - 8,
                                y: vertex.y - 8,
                                width: 16,
                                height: 16
                            ))
                            context.fill(circle, with: .color(.red))
                            context.stroke(circle, with: .color(.white), lineWidth: 2)
                        }
                    }
                    
                    // Рендеринг объектов телестрации
                    for object in drawingState.telestrationObjects {
                        drawTelestrationObject(object, in: context, size: size, isSelected: drawingState.selectedTelestrationObjectId == object.id)
                    }
                    
                    // Рендеринг настраиваемого объекта телестрации (показывается во время настройки)
                    if let pendingObject = drawingState.pendingTelestrationObject {
                        drawTelestrationObject(pendingObject, in: context, size: size, isSelected: false)
                        if pendingObject.type == .curvedArrow, pendingObject.positions.count >= 2 {
                            let middle = middlePointForCurvedArrow(pendingObject)
                            drawCurvedArrowMiddleHandle(at: middle, in: context)
                        }
                    }
                    
                    // Рендеринг фигур
                    for shape in drawingState.shapes {
                        drawShape(shape, in: context, isSelected: drawingState.selectedShapeId == shape.id)
                    }
                    
                    // Рендеринг создаваемой фигуры
                    if let pendingShape = drawingState.pendingShape {
                        drawShape(pendingShape, in: context, isSelected: true)
                    }
                    
                }
                .gesture(
                    // Приоритетный жест для перемещения, изменения размера и поворота фигур
                    // Должен быть первым, чтобы перехватывать события для фигур
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Обрабатываем pendingShape (фигура после создания, до apply)
                            if let pendingShape = drawingState.pendingShape {
                                handleShapeInteraction(
                                    value: value,
                                    shape: pendingShape,
                                    drawingState: drawingState,
                                    geometry: geometry,
                                    isPending: true
                                )
                            }
                            // Обрабатываем выбранную фигуру (после apply, при выборе курсором)
                            else if drawingState.currentTool == .cursor,
                               let shapeId = drawingState.selectedShapeId,
                               let shape = drawingState.shapes.first(where: { $0.id == shapeId }) {
                                handleShapeInteraction(
                                    value: value,
                                    shape: shape,
                                    drawingState: drawingState,
                                    geometry: geometry,
                                    isPending: false
                                )
                            }
                            // Обрабатываем pendingTextBox (текстовый бокс после создания, до apply). Во время ввода текста — не трогаем.
                            else if !drawingState.isEditingTextBox, let pendingTextBox = drawingState.pendingTextBox {
                                handleTextBoxInteraction(
                                    value: value,
                                    textBox: pendingTextBox,
                                    drawingState: drawingState,
                                    geometry: geometry,
                                    isPending: true
                                )
                            }
                            // Обрабатываем выбранный текстовый бокс (после apply, при выборе курсором). Во время ввода текста — не трогаем.
                            else if !drawingState.isEditingTextBox, drawingState.currentTool == .cursor,
                               let textBoxId = drawingState.selectedTextBoxId,
                               let textBox = drawingState.textBoxes.first(where: { $0.id == textBoxId }) {
                                handleTextBoxInteraction(
                                    value: value,
                                    textBox: textBox,
                                    drawingState: drawingState,
                                    geometry: geometry,
                                    isPending: false
                                )
                            }
                            // Перетаскивание центральной ручки закруглённой стрелки (кружок по середине кривой) — и для выбранного, и для pending.
                            else if drawingState.isDraggingCurvedArrowMiddle, let startMiddle = curvedArrowMiddleDragStart {
                                let newMiddle = CGPoint(x: startMiddle.x + value.translation.width, y: startMiddle.y + value.translation.height)
                                drawingState.moveCurvedArrowMiddle(to: newMiddle)
                            }
                            // Перемещение объекта телестрации в настройке (после Done, до Apply) — без выделения. Вершина = тянуть вершину, ребро/внутренность = тянуть весь объект. В режиме «Добавить точку» не начинаем перетаскивание.
                            else if !drawingState.isAddingPointToTelestration, let pendingObj = drawingState.pendingTelestrationObject {
                                let start = CGPoint(x: value.location.x - value.translation.width, y: value.location.y - value.translation.height)
                                if isMovingTelestrationObject {
                                    drawingState.movePendingTelestrationObject(by: value.translation)
                                } else {
                                    // Сначала проверяем клик по центральной ручке закруглённой стрелки (pending)
                                    if pendingObj.type == .curvedArrow, pendingObj.positions.count >= 2 {
                                        let middle = middlePointForCurvedArrow(pendingObj)
                                        if hypot(start.x - middle.x, start.y - middle.y) < 14 {
                                            curvedArrowMiddleDragStart = middle
                                            drawingState.startDraggingCurvedArrowMiddle()
                                            drawingState.moveCurvedArrowMiddle(to: CGPoint(x: middle.x + value.translation.width, y: middle.y + value.translation.height))
                                        }
                                    }
                                    if !drawingState.isDraggingCurvedArrowMiddle {
                                        let hit = telestrationHitTest(point: start, object: pendingObj)
                                        if hit.isOnObject {
                                            isMovingTelestrationObject = true
                                            drawingState.startMovingPendingTelestrationObject(vertexIndex: hit.vertexIndex)
                                            drawingState.movePendingTelestrationObject(by: value.translation)
                                        }
                                    }
                                }
                            }
                            // Перемещение выбранного объекта телестрации (курсором). В режиме «Добавить точку» не начинаем перетаскивание.
                            else if !drawingState.isAddingPointToTelestration, drawingState.currentTool == .cursor,
                               let id = drawingState.selectedTelestrationObjectId,
                               let obj = drawingState.telestrationObjects.first(where: { $0.id == id }) {
                                let start = CGPoint(x: value.location.x - value.translation.width, y: value.location.y - value.translation.height)
                                if isMovingTelestrationObject {
                                    drawingState.moveSelectedTelestrationObject(by: value.translation)
                                } else {
                                    // Сначала проверяем клик по центральной ручке закруглённой стрелки
                                    if obj.type == .curvedArrow, obj.positions.count >= 2 {
                                        let middle = middlePointForCurvedArrow(obj)
                                        if hypot(start.x - middle.x, start.y - middle.y) < 14 {
                                            curvedArrowMiddleDragStart = middle
                                            drawingState.startDraggingCurvedArrowMiddle()
                                            drawingState.moveCurvedArrowMiddle(to: CGPoint(x: middle.x + value.translation.width, y: middle.y + value.translation.height))
                                        }
                                    }
                                    if !drawingState.isDraggingCurvedArrowMiddle {
                                        let hit = telestrationHitTest(point: start, object: obj)
                                        if hit.isOnObject {
                                            isMovingTelestrationObject = true
                                            drawingState.startMovingTelestrationObject(vertexIndex: hit.vertexIndex)
                                            drawingState.moveSelectedTelestrationObject(by: value.translation)
                                        }
                                    }
                                }
                            }
                            // Если не взаимодействуем с фигурой, обрабатываем другие инструменты
                            else if drawingState.currentTool == .pencil || drawingState.currentTool == .arrow || drawingState.currentTool == .eraser {
                                let location = value.location
                                if drawingState.currentPath.points.isEmpty {
                                    drawingState.startNewPath(at: location)
                                } else {
                                    drawingState.addPointToPath(location)
                                }
                            }
                        }
                        .onEnded { value in
                            // Завершаем взаимодействие с фигурой
                            if drawingState.pendingShape != nil || 
                               (drawingState.currentTool == .cursor && drawingState.selectedShapeId != nil) {
                                drawingState.endMovingShape()
                                shapeInteractionMode = .none
                                initialRotation = 0
                                initialSize = .zero
                                initialPosition = .zero
                            }
                            // Завершаем взаимодействие с текстовым боксом
                            if drawingState.pendingTextBox != nil || 
                               (drawingState.currentTool == .cursor && drawingState.selectedTextBoxId != nil) {
                                drawingState.endMovingTextBox()
                                textBoxInteractionMode = .none
                                initialTextBoxRotation = 0
                                initialTextBoxSize = .zero
                                initialTextBoxPosition = .zero
                            }
                            // Завершаем перемещение объекта телестрации
                            if isMovingTelestrationObject {
                                drawingState.endMovingTelestrationObject()
                                isMovingTelestrationObject = false
                            }
                            // Завершаем перетаскивание центральной ручки закруглённой стрелки
                            if drawingState.isDraggingCurvedArrowMiddle {
                                drawingState.endDraggingCurvedArrowMiddle()
                                curvedArrowMiddleDragStart = nil
                            }
                            // Клик (малое движение): режим «Добавить точку» телестрации — клик по холсту добавляет вершину
                            let location = value.location
                            let isClick = value.translation.width < 5 && value.translation.height < 5
                            if isClick, drawingState.isAddingPointToTelestration {
                                _ = drawingState.addPointToTelestrationObject(at: location)
                                return
                            }
                            if isClick {
                                if drawingState.isEditingTextBox {
                                    let edited = drawingState.pendingTextBox ?? drawingState.textBoxes.first(where: { $0.id == drawingState.selectedTextBoxId })
                                    if let box = edited, !textBoxRect(box).contains(location) {
                                        drawingState.endTextBoxEditing()
                                        drawingState.isEditingTextBox = false
                                        drawingState.currentTool = .cursor
                                        NotificationCenter.default.post(name: .textBoxEditingChanged, object: false)
                                        return
                                    }
                                }
                                if let last = lastTapTime, let lastLoc = lastTapLocation,
                                   Date().timeIntervalSince(last) < 0.4,
                                   hypot(location.x - lastLoc.x, location.y - lastLoc.y) < 25,
                                   textBoxAt(location: location, in: drawingState) != nil {
                                    drawingState.startTextBoxEditing()
                                    drawingState.isEditingTextBox = true
                                    NotificationCenter.default.post(name: .textBoxEditingChanged, object: true)
                                    lastTapTime = nil
                                    lastTapLocation = nil
                                    return
                                }
                                lastTapTime = Date()
                                lastTapLocation = location
                            }
                            // Обработка инструментов (клик или конец жеста)
                            if drawingState.currentTool == .pencil || drawingState.currentTool == .arrow || drawingState.currentTool == .eraser {
                                drawingState.finishPath()
                            } else if drawingState.currentTool == .telestration && drawingState.isCreatingTelestrationObject {
                                let location = value.location
                                drawingState.addTelestrationVertex(at: location)
                            } else if drawingState.currentTool == .shapes && drawingState.isCreatingShape {
                                let location = value.location
                                drawingState.createShape(at: location)
                            } else if drawingState.currentTool == .textBox && drawingState.isCreatingTextBox {
                                let location = value.location
                                drawingState.createTextBox(at: location)
                            } else if drawingState.currentTool == .cursor {
                                if value.translation.width < 5 && value.translation.height < 5 {
                                    let location = value.location
                                    selectTextBoxAt(location: location, in: drawingState)
                                    if drawingState.selectedTextBoxId == nil {
                                        selectShapeAt(location: location, in: drawingState)
                                    }
                                    if drawingState.selectedTextBoxId == nil && drawingState.selectedShapeId == nil {
                                        selectTelestrationObjectAt(location: location, in: drawingState)
                                    }
                                }
                            }
                        }
                )
                
                // Рендеринг текстовых боксов поверх Canvas (для правильной отрисовки текста)
                ForEach(drawingState.textBoxes) { textBox in
                    TextBoxView(
                        textBox: textBox,
                        isSelected: drawingState.selectedTextBoxId == textBox.id,
                        isEditing: drawingState.isEditingTextBox && drawingState.selectedTextBoxId == textBox.id,
                        onTextChange: { drawingState.updateSelectedTextBox(text: $0) },
                        onEndEditing: {
                            drawingState.endTextBoxEditing()
                            drawingState.isEditingTextBox = false
                            drawingState.currentTool = .cursor
                            NotificationCenter.default.post(name: .textBoxEditingChanged, object: false)
                        }
                    )
                }
                
                // Рендеринг создаваемого текстового бокса
                if let pendingTextBox = drawingState.pendingTextBox {
                    TextBoxView(
                        textBox: pendingTextBox,
                        isSelected: true,
                        isEditing: drawingState.isEditingTextBox && drawingState.pendingTextBox?.id == pendingTextBox.id,
                        onTextChange: { new in drawingState.updatePendingTextBox(apply: { $0.text = new }) },
                        onEndEditing: {
                            drawingState.endTextBoxEditing()
                            drawingState.isEditingTextBox = false
                            drawingState.currentTool = .cursor
                            NotificationCenter.default.post(name: .textBoxEditingChanged, object: false)
                        }
                    )
                }
                
                // ПКМ: контекстное меню только для инструмента «Курсор» (Удалить, Копировать, Вставить)
                if drawingState.currentTool == .cursor {
                    RightClickCanvasOverlay(drawingState: drawingState)
                        .allowsHitTesting(true)
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
        
        var strokeStyle = StrokeStyle(
            lineWidth: path.lineWidth,
            lineCap: .round,
            lineJoin: .round
        )
        
        // Масштабируем паттерн прерывистой линии по толщине: у толстых линий длиннее штрихи и пробелы
        if let dashPattern = path.lineStyle.dashPattern {
            let baseLineWidth: CGFloat = 3
            let widthScale = max(1, path.lineWidth / baseLineWidth)
            strokeStyle.dash = dashPattern.map { $0 * widthScale }
        }
        
        context.stroke(
            cgPath,
            with: .color(path.color),
            style: strokeStyle
        )
        
        // Рисуем стрелочку на конце пути, если нужно
        if path.hasArrow && path.points.count >= 2 {
            drawArrowHead(path: path, in: context)
        }
    }
    
    private func drawArrowHead(path: EditorDrawingPath, in context: GraphicsContext) {
        guard path.points.count >= 2 else { return }
        
        let lastPoint = path.points[path.points.count - 1]
        
        // Используем несколько последних точек для более стабильного направления
        // Берем больше точек для более плавного направления (15-20 точек или минимум 10)
        let pointsToUse = min(20, max(10, path.points.count))
        let startIndex = max(0, path.points.count - pointsToUse)
        let referencePoint = path.points[startIndex]
        
        // Вычисляем направление стрелки на основе более длинного сегмента
        let dx = lastPoint.x - referencePoint.x
        let dy = lastPoint.y - referencePoint.y
        
        // Если сегмент слишком короткий, используем среднее направление по нескольким последним точкам
        let distance = sqrt(dx * dx + dy * dy)
        let angle: CGFloat
        if distance < 30 {
            // Для коротких сегментов усредняем направление по последним 5-7 точкам
            let avgPoints = min(7, max(3, path.points.count))
            var sumDx: CGFloat = 0
            var sumDy: CGFloat = 0
            for i in max(1, path.points.count - avgPoints)..<path.points.count {
                let prevPoint = path.points[i - 1]
                let currPoint = path.points[i]
                sumDx += currPoint.x - prevPoint.x
                sumDy += currPoint.y - prevPoint.y
            }
            angle = atan2(sumDy, sumDx)
        } else {
            angle = atan2(dy, dx)
        }
        
        // Размер стрелки зависит от ширины линии
        let arrowLength = path.lineWidth * 3
        let arrowWidth = path.lineWidth * 2
        
        // Создаем путь стрелки
        var arrowPath = Path()
        let arrowTip = lastPoint
        
        // Вычисляем точки стрелки
        let arrowPoint1 = CGPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle + .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle + .pi / 2)
        )
        let arrowPoint2 = CGPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle - .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle - .pi / 2)
        )
        
        arrowPath.move(to: arrowTip)
        arrowPath.addLine(to: arrowPoint1)
        arrowPath.addLine(to: arrowPoint2)
        arrowPath.closeSubpath()
        
        // Рисуем стрелку
        context.fill(arrowPath, with: .color(path.color))
        context.stroke(arrowPath, with: .color(path.color), lineWidth: path.lineWidth)
    }
    
    private func drawTelestrationObject(_ object: DrawableObject, in context: GraphicsContext, size: CGSize, isSelected: Bool = false) {
        switch object.type {
        case .zoneBetweenObjects:
            drawZoneBetweenObjects(object, in: context)
        case .lineBetweenObjects:
            drawLineBetweenObjects(object, in: context)
        case .lineWithArrow:
            drawLineWithArrow(object, in: context)
        case .curvedArrow:
            drawCurvedArrow(object, in: context)
        case .objectHighlight:
            drawObjectHighlight(object, in: context)
        case .simpleZone:
            drawSimpleZone(object, in: context)
        }
        if isSelected {
            drawTelestrationSelectionIndicator(object, in: context)
        }
    }
    
    private func drawTelestrationSelectionIndicator(_ object: DrawableObject, in context: GraphicsContext) {
        var strokeStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        strokeStyle.dash = [6, 4]
        switch object.type {
        case .zoneBetweenObjects, .simpleZone:
            guard object.positions.count >= 3 else { return }
            var path = Path()
            path.move(to: object.positions[0])
            for p in object.positions.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
            context.stroke(path, with: .color(.blue), style: strokeStyle)
        case .lineBetweenObjects, .lineWithArrow:
            guard object.positions.count >= 2 else { return }
            var path = Path()
            path.move(to: object.positions[0])
            for p in object.positions.dropFirst() { path.addLine(to: p) }
            context.stroke(path, with: .color(.blue), style: strokeStyle)
        case .curvedArrow:
            guard object.positions.count >= 2 else { return }
            let start = object.positions[0]
            let end = object.positions[1]
            let control = effectiveControlPointForCurvedArrow(object)
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            context.stroke(path, with: .color(.blue), style: strokeStyle)
            // Кружок по середине кривой для перетаскивания
            let middle = CGPoint(
                x: 0.25*start.x + 0.5*control.x + 0.25*end.x,
                y: 0.25*start.y + 0.5*control.y + 0.25*end.y
            )
            drawCurvedArrowMiddleHandle(at: middle, in: context)
        case .objectHighlight:
            guard let p = object.positions.first else { return }
            let r = object.radius
            let rect = CGRect(x: p.x - r/2 - 4, y: p.y - r*2 - 4, width: r + 8, height: r*2 + r*0.6 + 8)
            context.stroke(Path(rect), with: .color(.blue), style: strokeStyle)
        }
    }
    
    private func drawZoneBetweenObjects(_ object: DrawableObject, in context: GraphicsContext) {
        guard object.positions.count >= 3 else { return }
        
        var path = Path()
        path.move(to: object.positions[0])
        for position in object.positions.dropFirst() {
            path.addLine(to: position)
        }
        path.closeSubpath()
        
        context.fill(path, with: .color(object.fillColor.opacity(0.3)))
        
        var strokeStyle = StrokeStyle(lineWidth: 2)
        if object.lineStyle == .dashed {
            strokeStyle.dash = [5, 5]
        }
        context.stroke(path, with: .color(object.edgeColor.opacity(0.8)), style: strokeStyle)
        
        // Вершины (уменьшены в 3 раза: с 30 до 10)
        for position in object.positions {
            let circle = Path(ellipseIn: CGRect(
                x: position.x - 5,
                y: position.y - 5,
                width: 10,
                height: 10
            ))
            context.fill(circle, with: .color(object.vertexColor))
            context.stroke(circle, with: .color(.white), lineWidth: 1)
        }
    }
    
    private func drawLineBetweenObjects(_ object: DrawableObject, in context: GraphicsContext) {
        guard object.positions.count >= 2 else { return }
        
        var path = Path()
        for i in 0..<(object.positions.count - 1) {
            path.move(to: object.positions[i])
            path.addLine(to: object.positions[i + 1])
        }
        
        let lineW = object.strokeWidth
        var strokeStyle = StrokeStyle(lineWidth: lineW)
        if object.lineStyle == .dashed {
            let baseLineWidth: CGFloat = 3.0
            let scale = max(1, lineW / baseLineWidth)
            strokeStyle.dash = [5 * scale, 5 * scale]
        }
        context.stroke(path, with: .color(object.edgeColor.opacity(0.8)), style: strokeStyle)
        
        // Вершины (уменьшены в 3 раза: с 30 до 10)
        for position in object.positions {
            let circle = Path(ellipseIn: CGRect(
                x: position.x - 5,
                y: position.y - 5,
                width: 10,
                height: 10
            ))
            context.fill(circle, with: .color(object.vertexColor))
            context.stroke(circle, with: .color(.white), lineWidth: 1)
        }
    }
    
    private func drawLineWithArrow(_ object: DrawableObject, in context: GraphicsContext) {
        guard object.positions.count >= 2 else { return }
        
        let lineW = object.strokeWidth
        // Рисуем линию до последней точки
        var path = Path()
        for i in 0..<(object.positions.count - 1) {
            path.move(to: object.positions[i])
            path.addLine(to: object.positions[i + 1])
        }
        
        var strokeStyle = StrokeStyle(lineWidth: lineW)
        if object.lineStyle == .dashed {
            let baseLineWidth: CGFloat = 3.0
            let scale = max(1, lineW / baseLineWidth)
            strokeStyle.dash = [5 * scale, 5 * scale]
        }
        context.stroke(path, with: .color(object.edgeColor.opacity(0.8)), style: strokeStyle)
        
        // Рисуем стрелку на последней точке (размер стрелки фиксированный)
        let lastPoint = object.positions[object.positions.count - 1]
        let secondLastPoint = object.positions[object.positions.count - 2]
        
        // Вычисляем направление стрелки
        let dx = lastPoint.x - secondLastPoint.x
        let dy = lastPoint.y - secondLastPoint.y
        let angle = atan2(dy, dx)
        
        // Размер стрелки (фиксированный, как у закругленной стрелки)
        let arrowLength: CGFloat = 15
        let arrowWidth: CGFloat = 10
        
        // Создаем путь стрелки
        var arrowPath = Path()
        let arrowTip = lastPoint
        let arrowPoint1 = CGPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle + .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle + .pi / 2)
        )
        let arrowPoint2 = CGPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle - .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle - .pi / 2)
        )
        
        arrowPath.move(to: arrowTip)
        arrowPath.addLine(to: arrowPoint1)
        arrowPath.addLine(to: arrowPoint2)
        arrowPath.closeSubpath()
        
        context.fill(arrowPath, with: .color(object.edgeColor))
        context.stroke(arrowPath, with: .color(object.edgeColor), lineWidth: lineW)
        
        // Вершины (кроме последней, так как там стрелка)
        for position in object.positions.dropLast() {
            let circle = Path(ellipseIn: CGRect(
                x: position.x - 5,
                y: position.y - 5,
                width: 10,
                height: 10
            ))
            context.fill(circle, with: .color(object.vertexColor))
            context.stroke(circle, with: .color(.white), lineWidth: 1)
        }
    }
    
    /// Рисует кружок-ручку по середине кривой закруглённой стрелки (для выбранного и для pending).
    private func drawCurvedArrowMiddleHandle(at middle: CGPoint, in context: GraphicsContext) {
        let circle = Path(ellipseIn: CGRect(x: middle.x - 8, y: middle.y - 8, width: 16, height: 16))
        context.fill(circle, with: .color(.blue.opacity(0.3)))
        context.stroke(circle, with: .color(.blue), lineWidth: 2)
    }
    
    /// Эффективная контрольная точка закруглённой стрелки: явная controlPoint или вычисленная из curveHeight.
    private func effectiveControlPointForCurvedArrow(_ object: DrawableObject) -> CGPoint {
        guard object.positions.count >= 2 else { return .zero }
        let start = object.positions[0]
        let end = object.positions[1]
        if let cp = object.controlPoint { return cp }
        return computeControlPointForCurvedArrow(start: start, end: end, curveHeight: object.curveHeight)
    }
    
    /// Точка на середине кривой (B(0.5)) для закруглённой стрелки — там рисуем ручку и обрабатываем перетаскивание.
    private func middlePointForCurvedArrow(_ object: DrawableObject) -> CGPoint {
        guard object.positions.count >= 2 else { return .zero }
        let start = object.positions[0]
        let end = object.positions[1]
        let control = effectiveControlPointForCurvedArrow(object)
        let t: CGFloat = 0.5
        return CGPoint(
            x: (1-t)*(1-t)*start.x + 2*(1-t)*t*control.x + t*t*end.x,
            y: (1-t)*(1-t)*start.y + 2*(1-t)*t*control.y + t*t*end.y
        )
    }
    
    // Вычисляем контрольную точку на основе curveHeight
    private func computeControlPointForCurvedArrow(start: CGPoint, end: CGPoint, curveHeight: CGFloat) -> CGPoint {
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        
        // Вычисляем перпендикулярный вектор к линии
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        
        if length == 0 {
            return CGPoint(x: midX, y: midY)
        }
        
        // Перпендикулярный вектор (повернутый на 90 градусов)
        let perpX = -dy / length
        let perpY = dx / length
        
        // Контрольная точка смещена перпендикулярно на curveHeight
        return CGPoint(
            x: midX + perpX * curveHeight,
            y: midY + perpY * curveHeight
        )
    }
    
    private func drawCurvedArrow(_ object: DrawableObject, in context: GraphicsContext) {
        guard object.positions.count >= 2 else { return }
        
        let startPoint = object.positions[0]
        let endPoint = object.positions[1]
        let controlPoint = effectiveControlPointForCurvedArrow(object)
        
        // Рисуем квадратичную кривую Bezier
        var path = Path()
        path.move(to: startPoint)
        path.addQuadCurve(to: endPoint, control: controlPoint)
        
        let lineW = object.strokeWidth
        var strokeStyle = StrokeStyle(lineWidth: lineW)
        if object.lineStyle == .dashed {
            strokeStyle.dash = [5, 5]
        }
        context.stroke(path, with: .color(object.edgeColor.opacity(0.8)), style: strokeStyle)
        
        // Вычисляем направление стрелки в конечной точке кривой
        let t: CGFloat = 0.95
        let curvePoint = CGPoint(
            x: pow(1-t, 2) * startPoint.x + 2 * (1-t) * t * controlPoint.x + pow(t, 2) * endPoint.x,
            y: pow(1-t, 2) * startPoint.y + 2 * (1-t) * t * controlPoint.y + pow(t, 2) * endPoint.y
        )
        
        // Вычисляем направление стрелки
        let dx = endPoint.x - curvePoint.x
        let dy = endPoint.y - curvePoint.y
        let angle = atan2(dy, dx)
        
        // Размер стрелки фиксированный (не зависит от толщины линии)
        let arrowLength: CGFloat = 15
        let arrowWidth: CGFloat = 10
        
        // Создаем путь стрелки
        var arrowPath = Path()
        let arrowTip = endPoint
        let arrowPoint1 = CGPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle + .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle + .pi / 2)
        )
        let arrowPoint2 = CGPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle - .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle - .pi / 2)
        )
        
        arrowPath.move(to: arrowTip)
        arrowPath.addLine(to: arrowPoint1)
        arrowPath.addLine(to: arrowPoint2)
        arrowPath.closeSubpath()
        
        context.fill(arrowPath, with: .color(object.edgeColor))
        context.stroke(arrowPath, with: .color(object.edgeColor), lineWidth: lineW)
        
        // Показываем только начальную точку (конечная точка скрыта, так как там стрелка)
        let circle = Path(ellipseIn: CGRect(
            x: startPoint.x - 5,
            y: startPoint.y - 5,
            width: 10,
            height: 10
        ))
        context.fill(circle, with: .color(object.vertexColor))
        context.stroke(circle, with: .color(.white), lineWidth: 1)
    }
    
    private func drawObjectHighlight(_ object: DrawableObject, in context: GraphicsContext) {
        guard let position = object.positions.first else { return }
        
        // Прямоугольник с градиентом (снизу вверх)
        let columnRect = CGRect(
            x: position.x - object.radius / 2,
            y: position.y - object.radius * 2,
            width: object.radius,
            height: object.radius * 2
        )
        
        // Создаем градиент снизу вверх (glowOpacity = прозрачность по умолчанию 50%)
        let o = object.glowOpacity
        let gradient = Gradient(colors: [
            object.glowColor.opacity(0.9 * o),
            object.glowColor.opacity(0.6 * o),
            object.glowColor.opacity(0.3 * o),
            Color.clear
        ])
        
        let columnPath = Path(columnRect)
        let bottomPoint = CGPoint(x: columnRect.midX, y: columnRect.maxY)
        let topPoint = CGPoint(x: columnRect.midX, y: columnRect.minY)
        context.fill(columnPath, with: .linearGradient(gradient, startPoint: bottomPoint, endPoint: topPoint))
        
        // Овал (центр в позиции клика)
        let ovalRect = CGRect(
            x: position.x - object.radius/2,
            y: position.y - (object.radius * 0.6)/2,
            width: object.radius,
            height: object.radius * 0.6
        )
        let ovalPath = Path(ellipseIn: ovalRect)
        
        // Создаем путь для нижней половины эллипса
        var bottomHalfPath = Path()
        let centerX = ovalRect.midX
        let centerY = ovalRect.midY
        let radiusX = ovalRect.width / 2
        let radiusY = ovalRect.height / 2
        
        // Создаем нижнюю половину эллипса через точки
        let steps = 20
        bottomHalfPath.move(to: CGPoint(x: centerX - radiusX, y: centerY))
        
        for i in 0...steps {
            let angle = CGFloat.pi * CGFloat(i) / CGFloat(steps) // от π до 0
            let x = centerX + radiusX * cos(angle)
            let y = centerY + radiusY * sin(angle)
            bottomHalfPath.addLine(to: CGPoint(x: x, y: y))
        }
        
        // Закрываем путь прямой линией
        bottomHalfPath.addLine(to: CGPoint(x: centerX + radiusX, y: centerY))
        bottomHalfPath.closeSubpath()
        
        // Заливаем только нижнюю половину овала
        context.fill(bottomHalfPath, with: .color(object.glowColor.opacity(0.8 * o)))
        
        // Рисуем обводку всего овала
        context.stroke(ovalPath, with: .color(object.glowColor.opacity(0.8 * o)), lineWidth: 1)
    }
    
    private func drawSimpleZone(_ object: DrawableObject, in context: GraphicsContext) {
        guard object.positions.count >= 3 else { return }
        
        var path = Path()
        path.move(to: object.positions[0])
        for position in object.positions.dropFirst() {
            path.addLine(to: position)
        }
        path.closeSubpath()
        
        context.fill(path, with: .color(object.fillColor.opacity(0.3)))
        
        var strokeStyle = StrokeStyle(lineWidth: 2)
        if object.lineStyle == .dashed {
            strokeStyle.dash = [5, 5]
        }
        context.stroke(path, with: .color(object.edgeColor.opacity(0.8)), style: strokeStyle)
        
        // В простой зоне нет вершин после нажатия done
    }
    
    // MARK: - Shapes Drawing
    
    private func drawShape(_ shape: EditorShape, in context: GraphicsContext, isSelected: Bool) {
        // Создаем путь фигуры
        var shapePath = createShapePath(type: shape.type, size: shape.size)
        
        // Применяем трансформации к пути
        let transform = CGAffineTransform(translationX: shape.position.x, y: shape.position.y)
            .rotated(by: shape.rotation * .pi / 180)
        shapePath = shapePath.applying(transform)
        
        // Заливка
        context.fill(shapePath, with: .color(shape.fillColor.opacity(shape.fillOpacity)))
        
        // Обводка
        var strokeStyle = StrokeStyle(lineWidth: shape.strokeWidth)
        if shape.lineStyle == .dashed {
            strokeStyle.dash = [5, 5]
        }
        context.stroke(shapePath, with: .color(shape.strokeColor), style: strokeStyle)
        
        // Выделение
        if isSelected {
            let selectionRect = CGRect(
                x: shape.position.x - shape.size.width / 2 - 5,
                y: shape.position.y - shape.size.height / 2 - 5,
                width: shape.size.width + 10,
                height: shape.size.height + 10
            )
            var selectionPath = Path()
            selectionPath.addRect(selectionRect)
            // Применяем поворот к выделению
            let selectionTransform = CGAffineTransform(translationX: shape.position.x, y: shape.position.y)
                .rotated(by: shape.rotation * .pi / 180)
                .translatedBy(x: -shape.position.x, y: -shape.position.y)
            selectionPath = selectionPath.applying(selectionTransform)
            context.stroke(selectionPath, with: .color(.blue), lineWidth: 2)
            
            // Ручки для изменения размера и поворота
            drawShapeHandles(shape: shape, in: context)
        }
    }
    
    private func createShapePath(type: ShapeType, size: CGSize) -> Path {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        var path = Path()
        
        switch type {
        case .triangle:
            path.move(to: CGPoint(x: 0, y: -halfHeight))
            path.addLine(to: CGPoint(x: -halfWidth, y: halfHeight))
            path.addLine(to: CGPoint(x: halfWidth, y: halfHeight))
            path.closeSubpath()
            
        case .square:
            let rect = CGRect(x: -halfWidth, y: -halfHeight, width: size.width, height: size.height)
            path.addRect(rect)
            
        case .rectangle:
            let rect = CGRect(x: -halfWidth, y: -halfHeight, width: size.width, height: size.height)
            path.addRect(rect)
            
        case .circle:
            let rect = CGRect(x: -halfWidth, y: -halfHeight, width: size.width, height: size.height)
            path.addEllipse(in: rect)
            
        case .star:
            let points = 5
            let outerRadius = min(halfWidth, halfHeight)
            let innerRadius = outerRadius * 0.4
            for i in 0..<points * 2 {
                let angle = Double(i) * .pi / Double(points)
                let radius = i % 2 == 0 ? outerRadius : innerRadius
                let x = CGFloat(cos(angle)) * radius
                let y = CGFloat(sin(angle)) * radius
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()
            
        case .hexagon:
            let radius = min(halfWidth, halfHeight)
            for i in 0..<6 {
                let angle = Double(i) * .pi / 3.0
                let x = CGFloat(cos(angle)) * radius
                let y = CGFloat(sin(angle)) * radius
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()
        }
        
        return path
    }
    
    private func drawShapeHandles(shape: EditorShape, in context: GraphicsContext) {
        let halfWidth = shape.size.width / 2
        let halfHeight = shape.size.height / 2
        
        // Трансформация для поворота ручек
        let transform = CGAffineTransform(translationX: shape.position.x, y: shape.position.y)
            .rotated(by: shape.rotation * .pi / 180)
        
        // Угловые ручки для изменения размера
        let corners = [
            CGPoint(x: -halfWidth, y: -halfHeight),
            CGPoint(x: halfWidth, y: -halfHeight),
            CGPoint(x: halfWidth, y: halfHeight),
            CGPoint(x: -halfWidth, y: halfHeight)
        ]
        
        for corner in corners {
            let transformedCorner = corner.applying(transform)
            let handleRect = CGRect(x: transformedCorner.x - 6, y: transformedCorner.y - 6, width: 12, height: 12)
            var handlePath = Path()
            handlePath.addEllipse(in: handleRect)
            context.fill(handlePath, with: .color(.blue))
            context.stroke(handlePath, with: .color(.white), lineWidth: 1)
        }
        
        // Ручка для поворота (сверху)
        let rotationHandle = CGPoint(x: 0, y: -halfHeight - 20)
        let transformedRotationHandle = rotationHandle.applying(transform)
        let rotationRect = CGRect(x: transformedRotationHandle.x - 6, y: transformedRotationHandle.y - 6, width: 12, height: 12)
        var rotationPath = Path()
        rotationPath.addEllipse(in: rotationRect)
        context.fill(rotationPath, with: .color(.green))
        context.stroke(rotationPath, with: .color(.white), lineWidth: 1)
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

// MARK: - TextBox View

struct TextBoxView: View {
    let textBox: EditorTextBox
    let isSelected: Bool
    var isEditing: Bool = false
    var onTextChange: ((String) -> Void)? = nil
    var onEndEditing: (() -> Void)? = nil
    
    @State private var editText: String = ""
    
    var body: some View {
        ZStack {
            // Прямоугольник с фоном и границей
            RoundedRectangle(cornerRadius: 4)
                .fill(textBox.backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(textBox.borderColor, lineWidth: textBox.borderWidth)
                )
                .frame(width: textBox.size.width, height: textBox.size.height)
                .rotationEffect(.degrees(textBox.rotation))
                .position(textBox.position)
            
            // Текст или многострочное поле ввода (при дабл-клике). Без drawingGroup — иначе TextEditor не получает ввод (картинка «заблокировано»).
            Group {
                if isEditing, let onTextChange = onTextChange, let onEndEditing = onEndEditing {
                    TextEditor(text: $editText)
                        .font(.custom(textBox.fontName, size: textBox.fontSize))
                        .foregroundColor(textBox.textColor)
                        .multilineTextAlignment(.center)
                        .onChange(of: editText) { new in onTextChange(new) }
                } else {
                    Text(textBox.text)
                        .font(.custom(textBox.fontName, size: textBox.fontSize))
                        .foregroundColor(textBox.textColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
            }
            .frame(width: max(1, textBox.size.width - 10), height: max(1, textBox.size.height - 10))
            .rotationEffect(.degrees(textBox.rotation))
            .position(textBox.position)
            
            // Только ручка поворота (ресайз убран — размер подстраивается под текст)
            if isSelected && !isEditing {
                let halfWidth = textBox.size.width / 2
                let halfHeight = textBox.size.height / 2
                let rotationRadians = textBox.rotation * .pi / 180
                let rotationHandleLocal = CGPoint(x: 0, y: -halfHeight - 30)
                let rotatedHandle = rotationHandleLocal.applying(CGAffineTransform(rotationAngle: rotationRadians))
                let worldHandle = CGPoint(
                    x: rotatedHandle.x + textBox.position.x,
                    y: rotatedHandle.y + textBox.position.y
                )
                Circle()
                    .fill(Color.green)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .frame(width: 20, height: 20)
                    .position(worldHandle)
            }
        }
        .allowsHitTesting(isEditing) // когда не редактируем — хиты идут в Canvas (поворот по зелёной ручке, перемещение/выделение по области текстбокса)
        .onChange(of: isEditing) { editing in
            if editing { editText = textBox.text }
        }
    }
}

// MARK: - Editor Telestration Components

struct EditorTelestrationTypeSelectionSheet: View {
    @ObservedObject var drawingState: EditorDrawingState
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            Text(^String.Titles.selectObjectType)
                .font(.headline)
            
            VStack(spacing: 12) {
                ForEach(ObjectType.allCases, id: \.self) { type in
                    Button(action: {
                        drawingState.startCreatingTelestrationObject(type: type)
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Text(type.displayName)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Button(^String.Titles.cancel) {
                drawingState.currentTool = .pencil
                presentationMode.wrappedValue.dismiss()
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 300)
    }
}


struct EditorZoneBetweenObjectsCustomization: View {
    @ObservedObject var drawingState: EditorDrawingState
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(^String.Titles.edgeColor)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { drawingState.telestrationCustomization.edgeColor },
                    set: { newColor in
                        drawingState.telestrationCustomization.edgeColor = newColor
                        drawingState.updatePendingTelestrationObjectFromCustomization()
                    }
                ))
                .frame(width: 40, height: 30)
            }
            
            HStack {
                Text(^String.Titles.vertexColor)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { drawingState.telestrationCustomization.vertexColor },
                    set: { newColor in
                        drawingState.telestrationCustomization.vertexColor = newColor
                        drawingState.updatePendingTelestrationObjectFromCustomization()
                    }
                ))
                .frame(width: 40, height: 30)
            }
            
            HStack {
                Text(^String.Titles.fillColor)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { drawingState.telestrationCustomization.fillColor },
                    set: { newColor in
                        drawingState.telestrationCustomization.fillColor = newColor
                        drawingState.updatePendingTelestrationObjectFromCustomization()
                    }
                ))
                .frame(width: 40, height: 30)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(^String.Titles.lineType)
                Picker("", selection: Binding(
                    get: { drawingState.telestrationCustomization.lineStyle },
                    set: { newStyle in
                        drawingState.telestrationCustomization.lineStyle = newStyle
                        drawingState.updatePendingTelestrationObjectFromCustomization()
                    }
                )) {
                    ForEach(LineStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 120)
            }
            
            Divider()
            
            Group {
                if drawingState.isAddingPointToTelestration {
                    Button {
                        drawingState.isAddingPointToTelestration.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text(^String.Titles.editorAddPoint)
                            Text(^String.Titles.editorModeInParentheses)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                } else {
                    Button {
                        drawingState.isAddingPointToTelestration.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text(^String.Titles.editorAddPoint)
                        }
                    }
                    .buttonStyle(BorderedButtonStyle())
                }
            }
            .help(^String.Titles.editorAddPointModeHelp)
        }
    }
}

struct EditorLineBetweenObjectsCustomization: View {
    @ObservedObject var drawingState: EditorDrawingState
    
    var body: some View {
        VStack(spacing: 12) {
            EditorZoneBetweenObjectsCustomization(drawingState: drawingState)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.lineWidth)
                    .font(.subheadline)
                HStack {
                    Stepper("", value: Binding(
                        get: { drawingState.telestrationCustomization.strokeWidth },
                        set: { newWidth in
                            let clamped = min(20, max(1, newWidth))
                            drawingState.telestrationCustomization.strokeWidth = clamped
                            drawingState.updatePendingTelestrationObjectFromCustomization()
                        }
                    ), in: 1...20, step: 1)
                    .labelsHidden()
                    Text("\(Int(drawingState.telestrationCustomization.strokeWidth))")
                        .frame(width: 36)
                        .font(.caption)
                }
            }
        }
    }
}

struct EditorCurvedArrowCustomization: View {
    @ObservedObject var drawingState: EditorDrawingState
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(^String.Titles.lineColor)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { drawingState.telestrationCustomization.edgeColor },
                    set: { newColor in
                        drawingState.telestrationCustomization.edgeColor = newColor
                        drawingState.updatePendingTelestrationObjectFromCustomization()
                    }
                ))
                .frame(width: 40, height: 30)
            }
            
            HStack {
                Text(^String.Titles.vertexColor)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { drawingState.telestrationCustomization.vertexColor },
                    set: { newColor in
                        drawingState.telestrationCustomization.vertexColor = newColor
                        drawingState.updatePendingTelestrationObjectFromCustomization()
                    }
                ))
                .frame(width: 40, height: 30)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(^String.Titles.lineType)
                Picker("", selection: Binding(
                    get: { drawingState.telestrationCustomization.lineStyle },
                    set: { newStyle in
                        drawingState.telestrationCustomization.lineStyle = newStyle
                        drawingState.updatePendingTelestrationObjectFromCustomization()
                    }
                )) {
                    ForEach(LineStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 120)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.lineWidth)
                    .font(.subheadline)
                
                HStack {
                    Stepper("", value: Binding(
                        get: { drawingState.telestrationCustomization.strokeWidth },
                        set: { newWidth in
                            drawingState.telestrationCustomization.strokeWidth = newWidth
                            drawingState.updatePendingTelestrationObjectFromCustomization()
                        }
                    ), in: 1...20, step: 1)
                    .labelsHidden()
                    Text("\(Int(drawingState.telestrationCustomization.strokeWidth))")
                        .frame(width: 36)
                        .font(.caption)
                }
            }
        }
    }
}

struct EditorSimpleZoneCustomization: View {
    @ObservedObject var drawingState: EditorDrawingState
    
    var body: some View {
        EditorZoneBetweenObjectsCustomization(drawingState: drawingState)
    }
}

struct EditorObjectHighlightCustomization: View {
    @ObservedObject var drawingState: EditorDrawingState
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(^String.Titles.glowColor)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { drawingState.telestrationCustomization.glowColor },
                    set: { newColor in
                        drawingState.telestrationCustomization.glowColor = newColor
                        drawingState.updatePendingTelestrationObjectFromCustomization()
                    }
                ))
                .frame(width: 40, height: 30)
            }
            
            HStack {
                Text(^String.Titles.radius)
                Spacer()
                Stepper("", value: Binding(
                    get: { drawingState.telestrationCustomization.radius },
                    set: { newRadius in
                        drawingState.telestrationCustomization.radius = newRadius
                        drawingState.updatePendingTelestrationObjectFromCustomization()
                    }
                ), in: 10...100, step: 5)
                .labelsHidden()
                Text("\(Int(drawingState.telestrationCustomization.radius))")
                    .frame(width: 40)
            }
        }
    }
}

// MARK: - Right-Click Context Menu Overlay (Cursor tool only)

struct RightClickCanvasOverlay: NSViewRepresentable {
    @ObservedObject var drawingState: EditorDrawingState
    
    func makeNSView(context: Context) -> NSView {
        let view = RightClickHostView()
        view.storedDrawingState = drawingState
        view.onRightClick = { [weak drawingState] location in
            guard let state = drawingState else { return }
            let hit = state.hitTestForCursorContextMenu(at: location)
            RightClickCanvasOverlay.showContextMenu(hit: hit, at: location, drawingState: state, hostView: view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let host = nsView as? RightClickHostView else { return }
        host.storedDrawingState = drawingState
        host.onRightClick = { [weak drawingState] location in
            guard let state = drawingState else { return }
            let hit = state.hitTestForCursorContextMenu(at: location)
            RightClickCanvasOverlay.showContextMenu(hit: hit, at: location, drawingState: state, hostView: host)
        }
    }
    
    private static func showContextMenu(hit: CursorMenuHit, at location: CGPoint, drawingState: EditorDrawingState, hostView: RightClickHostView) {
        let menu = NSMenu()
        
        switch hit {
        case .telestration(let obj):
            let del = NSMenuItem(title: ^String.Titles.delete, action: #selector(RightClickHostView.menuDelete), keyEquivalent: "")
            del.representedObject = CursorMenuAction.deleteTelestration(obj.id)
            del.target = hostView
            let copy = NSMenuItem(title: ^String.Titles.copy, action: #selector(RightClickHostView.menuCopy), keyEquivalent: "")
            copy.representedObject = CursorMenuAction.copyTelestration(obj)
            copy.target = hostView
            menu.addItem(del)
            menu.addItem(copy)
        case .shape(let s):
            let del = NSMenuItem(title: ^String.Titles.delete, action: #selector(RightClickHostView.menuDelete), keyEquivalent: "")
            del.representedObject = CursorMenuAction.deleteShape(s.id)
            del.target = hostView
            let copy = NSMenuItem(title: ^String.Titles.copy, action: #selector(RightClickHostView.menuCopy), keyEquivalent: "")
            copy.representedObject = CursorMenuAction.copyShape(s)
            copy.target = hostView
            menu.addItem(del)
            menu.addItem(copy)
        case .textBox(let t):
            let del = NSMenuItem(title: ^String.Titles.delete, action: #selector(RightClickHostView.menuDelete), keyEquivalent: "")
            del.representedObject = CursorMenuAction.deleteTextBox(t.id)
            del.target = hostView
            let copy = NSMenuItem(title: ^String.Titles.copy, action: #selector(RightClickHostView.menuCopy), keyEquivalent: "")
            copy.representedObject = CursorMenuAction.copyTextBox(t)
            copy.target = hostView
            menu.addItem(del)
            menu.addItem(copy)
        case .empty:
            if drawingState.copyBuffer.isEmpty { return }
            for (index, item) in drawingState.copyBuffer.enumerated() {
                let title = "\(^String.Titles.paste): \(item.shortLabel)"
                let menuItem = NSMenuItem(title: title, action: #selector(RightClickHostView.menuPaste), keyEquivalent: "")
                menuItem.representedObject = CursorMenuAction.paste(index: index, point: location)
                menuItem.target = hostView
                menu.addItem(menuItem)
            }
        }
        
        guard !menu.items.isEmpty else { return }
        
        // Точка уже в координатах hostView (isFlipped), popUp ожидает именно их для параметра in:
        menu.popUp(positioning: nil, at: location, in: hostView)
    }
}

/// Действия контекстного меню (передаются через representedObject).
private enum CursorMenuAction {
    case deleteTelestration(UUID)
    case deleteShape(UUID)
    case deleteTextBox(UUID)
    case copyTelestration(DrawableObject)
    case copyShape(EditorShape)
    case copyTextBox(EditorTextBox)
    case paste(index: Int, point: CGPoint)
}

private class RightClickHostView: NSView {
    weak var storedDrawingState: EditorDrawingState?
    var onRightClick: ((CGPoint) -> Void)?
    private var rightClickMonitor: Any?
    
    /// Координаты как у SwiftUI: (0,0) сверху слева, Y вниз — совпадает с холстом и hit-test.
    override var isFlipped: Bool { true }
    
    /// Не перехватываем hit-test — все события (ЛКМ и др.) проходят к SwiftUI-холсту под нами.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                guard let self = self else { return event }
                let loc = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(loc) else { return event }
                self.onRightClick?(loc)
                return nil
            }
        } else {
            if let m = rightClickMonitor {
                NSEvent.removeMonitor(m)
                rightClickMonitor = nil
            }
        }
    }
    
    @objc func menuDelete(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? CursorMenuAction,
              let state = storedDrawingState else { return }
        switch action {
        case .deleteTelestration(let id): state.deleteTelestrationObject(id: id)
        case .deleteShape(let id): state.deleteShape(id: id)
        case .deleteTextBox(let id): state.deleteTextBox(id: id)
        default: break
        }
    }
    
    @objc func menuCopy(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? CursorMenuAction,
              let state = storedDrawingState else { return }
        switch action {
        case .copyTelestration(let obj): state.addToCopyBuffer(.telestration(obj))
        case .copyShape(let s): state.addToCopyBuffer(.shape(s))
        case .copyTextBox(let t): state.addToCopyBuffer(.textBox(t))
        default: break
        }
    }
    
    @objc func menuPaste(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? CursorMenuAction,
              case .paste(let index, let point) = action,
              let state = storedDrawingState else { return }
        state.pasteFromBuffer(at: point, bufferIndex: index)
    }
}