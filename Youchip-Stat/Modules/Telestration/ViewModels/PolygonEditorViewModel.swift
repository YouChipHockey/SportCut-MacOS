//
//  PolygonEditorViewModel.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

final class PolygonEditorViewModel: ObservableObject {
    @Published var image: NSImage
    @Published var objects: [DrawableObject] = []
    @Published var templateObjects: [TemplateObject] = []
    @Published var isCreatingObject: Bool = false
    @Published var currentObjectType: ObjectType?
    @Published var tempVertices: [CGPoint] = []
    @Published var showingTypeSelection: Bool = false
    @Published var showingCustomization: Bool = false
    @Published var currentCustomization = ObjectCustomization()
    @Published var pendingObject: DrawableObject?
    
    @Published var showingFormationSelection: Bool = false
    @Published var showingTemplateCustomization: Bool = false
    @Published var selectedObjectForTemplate: DrawableObject?
    @Published var currentTemplateCustomization = TemplateCustomization()
    @Published var pendingTemplate: TemplateObject?
    
    private var nextObjectNumber = 1

    init(image: NSImage) {
        self.image = image
    }

    var imageSize: CGSize { image.size }
    
    func startCreatingObject(type: ObjectType) {
        currentObjectType = type
        isCreatingObject = true
        tempVertices.removeAll()
        showingTypeSelection = false
    }
    
    func addVertex(at imageSpacePoint: CGPoint) {
        guard let objectType = currentObjectType else { return }
        guard imageSpacePoint.x >= 0, imageSpacePoint.y >= 0,
              imageSpacePoint.x <= imageSize.width, imageSpacePoint.y <= imageSize.height else { return }
        
        switch objectType {
        case .objectHighlight:
            tempVertices = [imageSpacePoint]
            finishCreatingObject()
        case .curvedArrow:
            if tempVertices.isEmpty {
                // Первая точка
                tempVertices.append(imageSpacePoint)
            } else if tempVertices.count == 1 {
                // Вторая точка - автоматически создаем объект (только 2 точки, контрольная точка вычисляется на основе curveHeight)
                tempVertices.append(imageSpacePoint)
                finishCreatingObject()
            }
        case .zoneBetweenObjects, .simpleZone, .lineBetweenObjects, .lineWithArrow:
            tempVertices.append(imageSpacePoint)
        }
    }
    
    func finishCreatingObject() {
        guard let objectType = currentObjectType,
              !tempVertices.isEmpty else { return }
        
        var newObject = DrawableObject(number: nextObjectNumber, type: objectType)
        newObject.positions = tempVertices
        
        switch objectType {
        case .objectHighlight:
            newObject.radius = 30
            newObject.glowColor = .white
            newObject.glowOpacity = currentCustomization.glowOpacity
        default:
            newObject.edgeColor = .red
            newObject.vertexColor = .red
            newObject.fillColor = .red
            newObject.lineStyle = .solid
        }
        
        pendingObject = newObject
        showingCustomization = true
        isCreatingObject = false
        tempVertices.removeAll()
        currentObjectType = nil
    }
    
    func confirmObjectCreation() {
        guard var object = pendingObject else { return }
        
        object.edgeColor = currentCustomization.edgeColor
        object.vertexColor = currentCustomization.vertexColor
        object.fillColor = currentCustomization.fillColor
        object.lineStyle = currentCustomization.lineStyle
        object.glowColor = currentCustomization.glowColor
        object.radius = currentCustomization.radius
        if object.type == .objectHighlight {
            object.glowOpacity = currentCustomization.glowOpacity
        }
        
        // Для закругленной стрелки сохраняем curveHeight
        if object.type == .curvedArrow {
            object.curveHeight = currentCustomization.curveHeight
        }
        
        objects.append(object)
        nextObjectNumber += 1
        
        pendingObject = nil
        showingCustomization = false
        currentCustomization = ObjectCustomization()
    }
    
    func cancelObjectCreation() {
        pendingObject = nil
        showingCustomization = false
        isCreatingObject = false
        tempVertices.removeAll()
        currentObjectType = nil
        currentCustomization = ObjectCustomization()
    }
    
    func toggleObjectVisibility(_ object: DrawableObject) {
        if let index = objects.firstIndex(where: { $0.id == object.id }) {
            objects[index].isVisible.toggle()
        }
    }
    
    func toggleObjectNumberVisibility(_ object: DrawableObject) {
        if let index = objects.firstIndex(where: { $0.id == object.id }) {
            objects[index].showNumber.toggle()
        }
    }
    
    func deleteObject(_ object: DrawableObject) {
        objects.removeAll { $0.id == object.id }
    }
    
    func clearAllObjects() {
        objects.removeAll()
        templateObjects.removeAll()
        nextObjectNumber = 1
        cancelObjectCreation()
    }
    
    func showFormationSelection(for object: DrawableObject) {
        selectedObjectForTemplate = object
        showingFormationSelection = true
    }
    
    func getAvailableFormations(for object: DrawableObject) -> [FootballFormation] {
        let vertexCount = object.positions.count
        return FootballFormation.formations.filter { formation in
            formation.playerCount == vertexCount
        }
    }
    
    func createTemplate(using formation: FootballFormation) {
        guard let selectedObject = selectedObjectForTemplate else { return }
        
        let originalPositions = selectedObject.positions
        guard !originalPositions.isEmpty && !formation.positions.isEmpty else { return }
        
        let otherPositions = Array(originalPositions.dropFirst())
        let minX = otherPositions.map { $0.x }.min() ?? originalPositions[0].x
        let maxX = otherPositions.map { $0.x }.max() ?? originalPositions[0].x
        let minY = otherPositions.map { $0.y }.min() ?? originalPositions[0].y
        let maxY = otherPositions.map { $0.y }.max() ?? originalPositions[0].y
        
        let width = max(maxX - minX, 50)
        let height = max(maxY - minY, 50)
        
        let firstUserVertex = originalPositions[0]
        
        let firstTemplateVertex = formation.positions[0]
        
        var templatePositions: [CGPoint] = []
        
        for (index, normalizedPos) in formation.positions.enumerated() {
            if index == 0 {
                templatePositions.append(firstUserVertex)
            } else {
                let relativeX = (normalizedPos.x - firstTemplateVertex.x) * width
                let relativeY = (normalizedPos.y - firstTemplateVertex.y) * height
                
                let actualPosition = CGPoint(
                    x: firstUserVertex.x + relativeX,
                    y: firstUserVertex.y + relativeY
                )
                templatePositions.append(actualPosition)
            }
        }
        
        let template = TemplateObject(
            formationName: formation.name,
            originalObject: selectedObject,
            templatePositions: templatePositions
        )
        
        pendingTemplate = template
        showingTemplateCustomization = true
        showingFormationSelection = false
    }
    
    func confirmTemplateCreation() {
        guard var template = pendingTemplate else { return }
        
        template.templateCustomization = currentTemplateCustomization
        
        templateObjects.append(template)
        
        pendingTemplate = nil
        selectedObjectForTemplate = nil
        showingTemplateCustomization = false
        currentTemplateCustomization = TemplateCustomization()
    }
    
    func cancelTemplateCreation() {
        pendingTemplate = nil
        selectedObjectForTemplate = nil
        showingFormationSelection = false
        showingTemplateCustomization = false
        currentTemplateCustomization = TemplateCustomization()
    }
    
    func toggleTemplateVisibility(_ template: TemplateObject) {
        if let index = templateObjects.firstIndex(where: { $0.id == template.id }) {
            templateObjects[index].isVisible.toggle()
        }
    }
    
    func deleteTemplate(_ template: TemplateObject) {
        templateObjects.removeAll { $0.id == template.id }
    }
    
    func getMisalignedVertices(for template: TemplateObject) -> [Int] {
        let originalPositions = template.originalObject.positions
        let templatePositions = template.templatePositions
        let threshold = template.templateCustomization.misalignmentThreshold
        
        var misalignedIndices: [Int] = []
        
        for i in 0..<min(originalPositions.count, templatePositions.count) {
            let distance = sqrt(
                pow(originalPositions[i].x - templatePositions[i].x, 2) +
                pow(originalPositions[i].y - templatePositions[i].y, 2)
            )
            
            if distance > threshold {
                misalignedIndices.append(i)
            }
        }
        
        return misalignedIndices
    }

    func imagePoint(fromViewPoint p: CGPoint, in viewSize: CGSize) -> CGPoint {
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (viewSize.width - displayedSize.width)/2,
                             y: (viewSize.height - displayedSize.height)/2)

        let x = (p.x - origin.x) / scale
        let yFromTop = (p.y - origin.y) / scale
        let y = imageSize.height - yFromTop
        return CGPoint(x: x, y: y)
    }

    func viewPoint(fromImagePoint p: CGPoint, in viewSize: CGSize) -> CGPoint {
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (viewSize.width - displayedSize.width)/2,
                             y: (viewSize.height - displayedSize.height)/2)

        let x = origin.x + p.x * scale
        let yFromTop = (imageSize.height - p.y) * scale
        let y = origin.y + yFromTop
        return CGPoint(x: x, y: y)
    }

    func exportImage() -> NSImage? {
        let visibleObjects = objects.filter { $0.isVisible }
        let visibleTemplates = templateObjects.filter { $0.isVisible }
        guard !visibleObjects.isEmpty || !visibleTemplates.isEmpty else { return nil }

        let size = image.size
        let outputImage = NSImage(size: size)

        outputImage.lockFocus()

        let imageRect = NSRect(origin: .zero, size: size)
        image.draw(in: imageRect)

        for object in visibleObjects {
            drawObject(object)
        }
        
        for template in visibleTemplates {
            drawTemplate(template)
        }

        outputImage.unlockFocus()
        return outputImage
    }
    
    private func drawObject(_ object: DrawableObject) {
        switch object.type {
        case .zoneBetweenObjects:
            drawZoneBetweenObjects(object)
        case .lineBetweenObjects:
            drawLineBetweenObjects(object)
        case .lineWithArrow:
            drawLineWithArrow(object)
        case .curvedArrow:
            drawCurvedArrow(object)
        case .objectHighlight:
            drawObjectHighlight(object)
        case .simpleZone:
            drawSimpleZone(object)
        }
        
        if object.showNumber {
            drawObjectNumber(object)
        }
    }
    
    private func drawZoneBetweenObjects(_ object: DrawableObject) {
        guard object.positions.count >= 3 else { return }
        
        let path = NSBezierPath()
        path.move(to: NSPoint(x: object.positions[0].x, y: object.positions[0].y))
        for position in object.positions.dropFirst() {
            path.line(to: NSPoint(x: position.x, y: position.y))
        }
        path.close()

        NSColor(object.fillColor).withAlphaComponent(0.3).setFill()
        path.fill()

        NSColor(object.edgeColor).withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2
        
        if object.lineStyle == .dashed {
            path.setLineDash([5, 5], count: 2, phase: 0)
        }
        path.stroke()
        
        for position in object.positions {
            let rect = NSRect(x: position.x - 15, y: position.y - 15, width: 30, height: 30)
            NSColor(object.vertexColor).setFill()
            NSBezierPath(ovalIn: rect).fill()

            NSColor.white.setStroke()
            let b = NSBezierPath(ovalIn: rect)
            b.lineWidth = 2
            b.stroke()
        }
    }
    
    private func drawLineBetweenObjects(_ object: DrawableObject) {
        guard object.positions.count >= 2 else { return }
        
        let path = NSBezierPath()
        
        for i in 0..<(object.positions.count - 1) {
            let current = object.positions[i]
            let next = object.positions[i + 1]
            
            path.move(to: NSPoint(x: current.x, y: current.y))
            path.line(to: NSPoint(x: next.x, y: next.y))
        }
        
        NSColor(object.edgeColor).withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2
        
        if object.lineStyle == .dashed {
            path.setLineDash([5, 5], count: 2, phase: 0)
        }
        path.stroke()
        
        for position in object.positions {
            let rect = NSRect(x: position.x - 15, y: position.y - 15, width: 30, height: 30)
            NSColor(object.vertexColor).setFill()
            NSBezierPath(ovalIn: rect).fill()

            NSColor.white.setStroke()
            let b = NSBezierPath(ovalIn: rect)
            b.lineWidth = 2
            b.stroke()
        }
    }
    
    private func drawLineWithArrow(_ object: DrawableObject) {
        guard object.positions.count >= 2 else { return }
        
        let path = NSBezierPath()
        
        // Рисуем линию через все точки
        for i in 0..<(object.positions.count - 1) {
            let current = object.positions[i]
            let next = object.positions[i + 1]
            
            path.move(to: NSPoint(x: current.x, y: current.y))
            path.line(to: NSPoint(x: next.x, y: next.y))
        }
        
        NSColor(object.edgeColor).withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2
        
        if object.lineStyle == .dashed {
            path.setLineDash([5, 5], count: 2, phase: 0)
        }
        path.stroke()
        
        // Рисуем стрелку на последней точке
        let lastPoint = object.positions[object.positions.count - 1]
        let secondLastPoint = object.positions[object.positions.count - 2]
        
        // Вычисляем направление стрелки
        let dx = lastPoint.x - secondLastPoint.x
        let dy = lastPoint.y - secondLastPoint.y
        let angle = atan2(dy, dx)
        
        // Размер стрелки
        let arrowLength: CGFloat = 15
        let arrowWidth: CGFloat = 10
        
        // Создаем путь стрелки
        let arrowPath = NSBezierPath()
        let arrowTip = NSPoint(x: lastPoint.x, y: lastPoint.y)
        let arrowPoint1 = NSPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle + .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle + .pi / 2)
        )
        let arrowPoint2 = NSPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle - .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle - .pi / 2)
        )
        
        arrowPath.move(to: arrowTip)
        arrowPath.line(to: arrowPoint1)
        arrowPath.line(to: arrowPoint2)
        arrowPath.close()
        
        NSColor(object.edgeColor).setFill()
        arrowPath.fill()
        NSColor(object.edgeColor).setStroke()
        arrowPath.lineWidth = 2
        arrowPath.stroke()
        
        // Вершины (кроме последней, так как там стрелка)
        for position in object.positions.dropLast() {
            let rect = NSRect(x: position.x - 15, y: position.y - 15, width: 30, height: 30)
            NSColor(object.vertexColor).setFill()
            NSBezierPath(ovalIn: rect).fill()

            NSColor.white.setStroke()
            let b = NSBezierPath(ovalIn: rect)
            b.lineWidth = 2
            b.stroke()
        }
    }
    
    // Вычисляем контрольную точку на основе curveHeight
    private func computeControlPoint(start: CGPoint, end: CGPoint, curveHeight: CGFloat) -> CGPoint {
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
    
    private func drawCurvedArrow(_ object: DrawableObject) {
        guard object.positions.count >= 2 else { return }
        
        let startPoint = object.positions[0]
        let endPoint = object.positions[1]
        
        // Вычисляем контрольную точку на основе curveHeight
        let controlPoint = computeControlPoint(
            start: startPoint,
            end: endPoint,
            curveHeight: object.curveHeight
        )
        
        // Рисуем квадратичную кривую Bezier
        let path = NSBezierPath()
        path.move(to: NSPoint(x: startPoint.x, y: startPoint.y))
        path.curve(to: NSPoint(x: endPoint.x, y: endPoint.y),
                   controlPoint1: NSPoint(x: controlPoint.x, y: controlPoint.y),
                   controlPoint2: NSPoint(x: controlPoint.x, y: controlPoint.y))
        
        NSColor(object.edgeColor).withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2
        
        if object.lineStyle == .dashed {
            path.setLineDash([5, 5], count: 2, phase: 0)
        }
        path.stroke()
        
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
        
        // Размер стрелки
        let arrowLength: CGFloat = 15
        let arrowWidth: CGFloat = 10
        
        // Создаем путь стрелки
        let arrowPath = NSBezierPath()
        let arrowTip = NSPoint(x: endPoint.x, y: endPoint.y)
        let arrowPoint1 = NSPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle + .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle + .pi / 2)
        )
        let arrowPoint2 = NSPoint(
            x: arrowTip.x - arrowLength * cos(angle) + arrowWidth * cos(angle - .pi / 2),
            y: arrowTip.y - arrowLength * sin(angle) + arrowWidth * sin(angle - .pi / 2)
        )
        
        arrowPath.move(to: arrowTip)
        arrowPath.line(to: arrowPoint1)
        arrowPath.line(to: arrowPoint2)
        arrowPath.close()
        
        NSColor(object.edgeColor).setFill()
        arrowPath.fill()
        NSColor(object.edgeColor).setStroke()
        arrowPath.lineWidth = 2
        arrowPath.stroke()
        
        // Показываем только начальную точку (конечная точка скрыта, так как там стрелка)
        let vertexSize: CGFloat = 10
        let rect = NSRect(x: startPoint.x - vertexSize/2, y: startPoint.y - vertexSize/2, width: vertexSize, height: vertexSize)
        NSColor(object.vertexColor).setFill()
        NSBezierPath(ovalIn: rect).fill()
        
        NSColor.white.setStroke()
        let b = NSBezierPath(ovalIn: rect)
        b.lineWidth = 2
        b.stroke()
    }
    
    private func drawObjectHighlight(_ object: DrawableObject) {
        guard let position = object.positions.first else { return }
        
        let columnRect = NSRect(
            x: position.x - object.radius / 2,
            y: position.y,
            width: object.radius,
            height: object.radius * 2
        )
        
        let columnPath = NSBezierPath(rect: columnRect)
        
        let o = CGFloat(object.glowOpacity)
        let columnGradient = NSGradient(colors: [
            NSColor(object.glowColor).withAlphaComponent(0.9 * o),
            NSColor(object.glowColor).withAlphaComponent(0.6 * o),
            NSColor(object.glowColor).withAlphaComponent(0.3 * o),
            NSColor.clear
        ])
        
        columnGradient?.draw(in: columnPath, angle: 90)
        
        for i in 1...3 {
            let blurRect = columnRect.insetBy(dx: -CGFloat(i), dy: 0)
            let blurPath = NSBezierPath(rect: blurRect)
            NSColor(object.glowColor).withAlphaComponent(0.1 / CGFloat(i) * o).setFill()
            blurPath.fill()
        }
        
        let ovalRect = NSRect(
            x: position.x - object.radius/2,
            y: position.y - (object.radius * 0.6)/2,
            width: object.radius,
            height: object.radius * 0.6
        )
        
        let ovalPath = NSBezierPath(ovalIn: ovalRect)
        
        let ovalGradient = NSGradient(colors: [
            NSColor(object.edgeColor).withAlphaComponent(0.8 * o),
            NSColor(object.edgeColor).withAlphaComponent(0.6 * o),
            NSColor(object.edgeColor).withAlphaComponent(0.4 * o)
        ])
        
        ovalGradient?.draw(in: ovalPath, relativeCenterPosition: NSPoint(x: 0, y: 0))
        
        NSColor(object.edgeColor).withAlphaComponent(o).setStroke()
        ovalPath.lineWidth = 2
        ovalPath.stroke()
    }
    
    private func drawSimpleZone(_ object: DrawableObject) {
        guard object.positions.count >= 3 else { return }
        
        let path = NSBezierPath()
        path.move(to: NSPoint(x: object.positions[0].x, y: object.positions[0].y))
        for position in object.positions.dropFirst() {
            path.line(to: NSPoint(x: position.x, y: position.y))
        }
        path.close()

        NSColor(object.fillColor).withAlphaComponent(0.3).setFill()
        path.fill()

        NSColor(object.edgeColor).withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2
        
        if object.lineStyle == .dashed {
            path.setLineDash([5, 5], count: 2, phase: 0)
        }
        path.stroke()
    }
    
    private func drawObjectNumber(_ object: DrawableObject) {
        guard let firstPosition = object.positions.first else { return }
        
        let numberString = "\(object.number)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -2
        ]
        
        let attributedString = NSAttributedString(string: numberString, attributes: attributes)
        let size = attributedString.size()
        
        let drawPoint = NSPoint(x: firstPosition.x - size.width/2,
                               y: firstPosition.y + 20)
        
        attributedString.draw(at: drawPoint)
    }
    
    private func drawTemplate(_ template: TemplateObject) {
        let customization = template.templateCustomization
        
        if template.templatePositions.count >= 3 {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: template.templatePositions[0].x, y: template.templatePositions[0].y))
            for position in template.templatePositions.dropFirst() {
                path.line(to: NSPoint(x: position.x, y: position.y))
            }
            path.close()

            NSColor(customization.fillColor).withAlphaComponent(0.2).setFill()
            path.fill()

            NSColor(customization.edgeColor).withAlphaComponent(0.8).setStroke()
            path.lineWidth = 2
            
            if customization.lineStyle == .dashed {
                path.setLineDash([5, 5], count: 2, phase: 0)
            }
            path.stroke()
        }
        
        for position in template.templatePositions {
            let rect = NSRect(x: position.x - 15, y: position.y - 15, width: 30, height: 30)
            NSColor(customization.vertexColor).setFill()
            NSBezierPath(ovalIn: rect).fill()

            NSColor.white.setStroke()
            let b = NSBezierPath(ovalIn: rect)
            b.lineWidth = 2
            b.stroke()
        }
        
        if customization.showMisalignedVertices {
            let misalignedIndices = getMisalignedVertices(for: template)
            let originalPositions = template.originalObject.positions
            
            for index in misalignedIndices {
                if index < originalPositions.count {
                    let position = originalPositions[index]
                    let rect = NSRect(x: position.x - 20, y: position.y - 20, width: 40, height: 40)
                    
                    NSColor(customization.misalignedVertexColor).withAlphaComponent(0.3).setFill()
                    NSBezierPath(ovalIn: rect).fill()
                    
                    NSColor(customization.misalignedVertexColor).setStroke()
                    let warningPath = NSBezierPath(ovalIn: rect)
                    warningPath.lineWidth = 3
                    warningPath.setLineDash([3, 3], count: 2, phase: 0)
                    warningPath.stroke()
                }
            }
        }
    }
}
