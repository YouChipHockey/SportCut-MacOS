//
//  DrawingImageMerger.swift
//  Youchip-Stat
//

import SwiftUI
import AppKit

enum DrawingImageMerger {
    
    static func merge(baseImage: NSImage, drawingState: EditorDrawingState) -> NSImage {
        let size = baseImage.size
        let finalImage = NSImage(size: size)
        
        finalImage.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: size))
        
        let rect = NSRect(origin: .zero, size: size)
        let viewSize = drawingState.viewSize
        
        for path in drawingState.completedPaths {
            drawPath(path, in: rect, viewSize: viewSize)
        }
        if !drawingState.currentPath.points.isEmpty {
            drawPath(drawingState.currentPath, in: rect, viewSize: viewSize)
        }
        for object in drawingState.telestrationObjects {
            drawTelestrationObject(object, in: rect, viewSize: viewSize)
        }
        for shape in drawingState.shapes {
            drawShape(shape, in: rect, viewSize: viewSize)
        }
        for textBox in drawingState.textBoxes {
            drawTextBox(textBox, in: rect, viewSize: viewSize)
        }
        
        finalImage.unlockFocus()
        return finalImage
    }
    
    // MARK: - Paths
    
    private static func drawPath(_ path: EditorDrawingPath, in rect: NSRect, viewSize: CGSize) {
        guard path.points.count > 1 else { return }
        let bezierPath = NSBezierPath()
        let scaleX = viewSize.width > 0 ? rect.width / viewSize.width : 1.0
        let scaleY = viewSize.height > 0 ? rect.height / viewSize.height : 1.0
        let scale = max(scaleX, scaleY)
        
        let scaledX = path.points[0].x * scaleX
        let scaledY = path.points[0].y * scaleY
        let first = CGPoint(x: scaledX, y: rect.height - scaledY)
        bezierPath.move(to: first)
        
        var scaledPoints: [CGPoint] = [first]
        for point in path.points.dropFirst() {
            let sx = point.x * scaleX
            let sy = point.y * scaleY
            let flipped = CGPoint(x: sx, y: rect.height - sy)
            bezierPath.line(to: flipped)
            scaledPoints.append(flipped)
        }
        
        NSColor(path.color).setStroke()
        bezierPath.lineWidth = path.lineWidth * scale
        bezierPath.lineCapStyle = .round
        bezierPath.lineJoinStyle = .round
        
        if let dashPattern = path.lineStyle.dashPattern {
            let baseLineWidth: CGFloat = 3
            let widthScale = max(1, path.lineWidth / baseLineWidth)
            let scaledDash = dashPattern.map { $0 * scale * widthScale }
            bezierPath.setLineDash(scaledDash, count: scaledDash.count, phase: 0)
        }
        bezierPath.stroke()
        
        if path.hasArrow && scaledPoints.count >= 2 {
            drawArrowHead(path: path, scaledPoints: scaledPoints, scale: scale, in: rect)
        }
    }
    
    private static func drawArrowHead(path: EditorDrawingPath, scaledPoints: [CGPoint], scale: CGFloat, in rect: NSRect) {
        guard scaledPoints.count >= 2 else { return }
        let lastPoint = scaledPoints.last!
        let pointsToUse = min(20, max(10, scaledPoints.count))
        let startIndex = max(0, scaledPoints.count - pointsToUse)
        let ref = scaledPoints[startIndex]
        
        let dx = lastPoint.x - ref.x
        let dy = lastPoint.y - ref.y
        let distance = sqrt(dx * dx + dy * dy)
        let angle: CGFloat
        if distance < 30 * scale {
            let avgPts = min(7, max(3, scaledPoints.count))
            var sumDx: CGFloat = 0, sumDy: CGFloat = 0
            for i in max(1, scaledPoints.count - avgPts)..<scaledPoints.count {
                sumDx += scaledPoints[i].x - scaledPoints[i-1].x
                sumDy += scaledPoints[i].y - scaledPoints[i-1].y
            }
            angle = atan2(sumDy, sumDx)
        } else {
            angle = atan2(dy, dx)
        }
        
        let arrowLength = path.lineWidth * scale * 3
        let arrowWidth = path.lineWidth * scale * 2
        let arrowPath = NSBezierPath()
        let tip = lastPoint
        let p1 = CGPoint(x: tip.x - arrowLength * cos(angle) + arrowWidth * cos(angle + .pi/2),
                         y: tip.y - arrowLength * sin(angle) + arrowWidth * sin(angle + .pi/2))
        let p2 = CGPoint(x: tip.x - arrowLength * cos(angle) + arrowWidth * cos(angle - .pi/2),
                         y: tip.y - arrowLength * sin(angle) + arrowWidth * sin(angle - .pi/2))
        arrowPath.move(to: tip)
        arrowPath.line(to: p1)
        arrowPath.line(to: p2)
        arrowPath.close()
        NSColor(path.color).setFill()
        arrowPath.fill()
        NSColor(path.color).setStroke()
        arrowPath.lineWidth = path.lineWidth * scale
        arrowPath.stroke()
    }
    
    // MARK: - Telestration
    
    private static func drawTelestrationObject(_ object: DrawableObject, in rect: NSRect, viewSize: CGSize) {
        let scaleX = rect.width / viewSize.width
        let scaleY = rect.height / viewSize.height
        let scale = max(scaleX, scaleY)
        
        var scaled = object
        scaled.positions = object.positions.map {
            CGPoint(x: $0.x * scaleX, y: rect.height - ($0.y * scaleY))
        }
        if let cp = object.controlPoint {
            scaled.controlPoint = CGPoint(x: cp.x * scaleX, y: rect.height - (cp.y * scaleY))
        }
        if object.type == .objectHighlight {
            scaled.radius = object.radius * scale
        }
        
        switch scaled.type {
        case .zoneBetweenObjects: drawZone(scaled, scale: scale)
        case .lineBetweenObjects: drawLine(scaled, scale: scale)
        case .lineWithArrow:     drawLineWithArrow(scaled, scale: scale)
        case .curvedArrow:       drawCurvedArrow(scaled, scale: scale, scaleX: scaleX, scaleY: scaleY)
        case .objectHighlight:   drawObjectHighlight(scaled)
        case .simpleZone:        drawSimpleZone(scaled, scale: scale)
        }
    }
    
    private static func drawZone(_ o: DrawableObject, scale: CGFloat) {
        guard o.positions.count >= 3 else { return }
        let p = NSBezierPath()
        p.move(to: NSPoint(x: o.positions[0].x, y: o.positions[0].y))
        for pos in o.positions.dropFirst() { p.line(to: NSPoint(x: pos.x, y: pos.y)) }
        p.close()
        NSColor(o.fillColor).withAlphaComponent(0.3).setFill(); p.fill()
        NSColor(o.edgeColor).withAlphaComponent(0.8).setStroke(); p.lineWidth = 2 * scale
        if o.lineStyle == .dashed { p.setLineDash([5*scale, 5*scale], count: 2, phase: 0) }
        p.stroke()
        drawVertices(o.positions, color: o.vertexColor, scale: scale)
    }
    
    private static func drawLine(_ o: DrawableObject, scale: CGFloat) {
        guard o.positions.count >= 2 else { return }
        let p = NSBezierPath()
        for i in 0..<(o.positions.count-1) {
            p.move(to: NSPoint(x: o.positions[i].x, y: o.positions[i].y))
            p.line(to: NSPoint(x: o.positions[i+1].x, y: o.positions[i+1].y))
        }
        let lw = o.strokeWidth * scale
        NSColor(o.edgeColor).withAlphaComponent(0.8).setStroke(); p.lineWidth = lw
        if o.lineStyle == .dashed {
            let ds = max(1, o.strokeWidth / 3.0)
            p.setLineDash([5*scale*ds, 5*scale*ds], count: 2, phase: 0)
        }
        p.stroke()
        drawVertices(o.positions, color: o.vertexColor, scale: scale)
    }
    
    private static func drawLineWithArrow(_ o: DrawableObject, scale: CGFloat) {
        guard o.positions.count >= 2 else { return }
        let lw = o.strokeWidth * scale
        let p = NSBezierPath()
        for i in 0..<(o.positions.count-1) {
            p.move(to: NSPoint(x: o.positions[i].x, y: o.positions[i].y))
            p.line(to: NSPoint(x: o.positions[i+1].x, y: o.positions[i+1].y))
        }
        NSColor(o.edgeColor).withAlphaComponent(0.8).setStroke(); p.lineWidth = lw
        if o.lineStyle == .dashed {
            let ds = max(1, o.strokeWidth / 3.0)
            p.setLineDash([5*scale*ds, 5*scale*ds], count: 2, phase: 0)
        }
        p.stroke()
        
        let last = o.positions.last!
        let prev = o.positions[o.positions.count - 2]
        let angle = atan2(last.y - prev.y, last.x - prev.x)
        let aLen: CGFloat = 15 * scale, aW: CGFloat = 10 * scale
        let ap = NSBezierPath()
        ap.move(to: NSPoint(x: last.x, y: last.y))
        ap.line(to: NSPoint(x: last.x - aLen*cos(angle) + aW*cos(angle + .pi/2),
                            y: last.y - aLen*sin(angle) + aW*sin(angle + .pi/2)))
        ap.line(to: NSPoint(x: last.x - aLen*cos(angle) + aW*cos(angle - .pi/2),
                            y: last.y - aLen*sin(angle) + aW*sin(angle - .pi/2)))
        ap.close()
        NSColor(o.edgeColor).setFill(); ap.fill()
        NSColor(o.edgeColor).setStroke(); ap.lineWidth = lw; ap.stroke()
        drawVertices(Array(o.positions.dropLast()), color: o.vertexColor, scale: scale)
    }
    
    private static func drawCurvedArrow(_ o: DrawableObject, scale: CGFloat, scaleX: CGFloat, scaleY: CGFloat) {
        guard o.positions.count >= 2 else { return }
        let start = o.positions[0], end = o.positions[1]
        let cp: CGPoint
        if let cpt = o.controlPoint {
            cp = cpt
        } else {
            let dxIm = end.x - start.x, dyIm = end.y - start.y
            let lIm = sqrt(dxIm*dxIm + dyIm*dyIm)
            let lView = lIm > 0 ? sqrt((dxIm*dxIm)/(scaleX*scaleX) + (dyIm*dyIm)/(scaleY*scaleY)) : 0
            let segScale = lView > 0 ? (lIm / lView) : 1
            let mx = (start.x + end.x)/2, my = (start.y + end.y)/2
            let dx = end.x - start.x, dy = end.y - start.y, l = sqrt(dx*dx + dy*dy)
            if l == 0 { cp = CGPoint(x: mx, y: my) } else {
                let px = -dy/l, py = dx/l
                cp = CGPoint(x: mx + px * (-o.curveHeight * segScale), y: my + py * (-o.curveHeight * segScale))
            }
        }
        let p = NSBezierPath()
        p.move(to: NSPoint(x: start.x, y: start.y))
        p.curve(to: NSPoint(x: end.x, y: end.y),
                controlPoint1: NSPoint(x: cp.x, y: cp.y),
                controlPoint2: NSPoint(x: cp.x, y: cp.y))
        let lw = o.strokeWidth * scale
        NSColor(o.edgeColor).withAlphaComponent(0.8).setStroke(); p.lineWidth = lw
        if o.lineStyle == .dashed { p.setLineDash([5*scale, 5*scale], count: 2, phase: 0) }
        p.stroke()
        
        let t: CGFloat = 0.95
        let cPt = CGPoint(x: pow(1-t,2)*start.x + 2*(1-t)*t*cp.x + pow(t,2)*end.x,
                          y: pow(1-t,2)*start.y + 2*(1-t)*t*cp.y + pow(t,2)*end.y)
        let angle = atan2(end.y - cPt.y, end.x - cPt.x)
        let aLen: CGFloat = 15*scale, aW: CGFloat = 10*scale
        let ap = NSBezierPath()
        ap.move(to: NSPoint(x: end.x, y: end.y))
        ap.line(to: NSPoint(x: end.x - aLen*cos(angle) + aW*cos(angle + .pi/2),
                            y: end.y - aLen*sin(angle) + aW*sin(angle + .pi/2)))
        ap.line(to: NSPoint(x: end.x - aLen*cos(angle) + aW*cos(angle - .pi/2),
                            y: end.y - aLen*sin(angle) + aW*sin(angle - .pi/2)))
        ap.close()
        NSColor(o.edgeColor).setFill(); ap.fill()
        NSColor(o.edgeColor).setStroke(); ap.lineWidth = lw; ap.stroke()
        
        let vs: CGFloat = 10 * scale
        let r = NSRect(x: start.x - vs/2, y: start.y - vs/2, width: vs, height: vs)
        NSColor(o.vertexColor).setFill(); NSBezierPath(ovalIn: r).fill()
        NSColor.white.setStroke(); let b = NSBezierPath(ovalIn: r); b.lineWidth = scale; b.stroke()
    }
    
    private static func drawObjectHighlight(_ o: DrawableObject) {
        guard let pos = o.positions.first else { return }
        var refT = AffineTransform()
        refT.translate(x: pos.x, y: pos.y)
        refT.scale(x: 1.0, y: -1.0)
        refT.translate(x: -pos.x, y: -pos.y)
        
        let colRect = NSRect(x: pos.x - o.radius/2, y: pos.y - o.radius*2, width: o.radius, height: o.radius*2)
        var colPath = NSBezierPath(rect: colRect); colPath.transform(using: refT)
        let op = CGFloat(o.glowOpacity)
        let grad = NSGradient(colors: [
            NSColor(o.glowColor).withAlphaComponent(0.9*op),
            NSColor(o.glowColor).withAlphaComponent(0.6*op),
            NSColor(o.glowColor).withAlphaComponent(0.3*op),
            NSColor.clear
        ])
        grad?.draw(in: colPath, angle: 90)
        for i in 1...3 {
            let br = colRect.insetBy(dx: -CGFloat(i), dy: 0)
            var bp = NSBezierPath(rect: br); bp.transform(using: refT)
            NSColor(o.glowColor).withAlphaComponent(0.1/CGFloat(i)*op).setFill(); bp.fill()
        }
        
        let ovalRect = NSRect(x: pos.x - o.radius/2, y: pos.y - (o.radius*0.6)/2, width: o.radius, height: o.radius*0.6)
        var ovalPath = NSBezierPath(ovalIn: ovalRect); ovalPath.transform(using: refT)
        
        let cx = ovalRect.midX, cy = ovalRect.midY, rx = ovalRect.width/2, ry = ovalRect.height/2
        var bottomHalf = NSBezierPath()
        var first = true
        for i in 0...20 {
            let a = CGFloat.pi * CGFloat(i) / 20.0
            let x = cx + rx * cos(a), y = cy + ry * sin(a)
            if first { bottomHalf.move(to: NSPoint(x: x, y: y)); first = false }
            else { bottomHalf.line(to: NSPoint(x: x, y: y)) }
        }
        bottomHalf.line(to: NSPoint(x: cx + rx, y: cy)); bottomHalf.close()
        bottomHalf.transform(using: refT)
        NSColor(o.glowColor).withAlphaComponent(0.8*op).setFill(); bottomHalf.fill()
        NSColor(o.glowColor).withAlphaComponent(0.8*op).setStroke(); ovalPath.lineWidth = 1; ovalPath.stroke()
    }
    
    private static func drawSimpleZone(_ o: DrawableObject, scale: CGFloat) {
        guard o.positions.count >= 3 else { return }
        let p = NSBezierPath()
        p.move(to: NSPoint(x: o.positions[0].x, y: o.positions[0].y))
        for pos in o.positions.dropFirst() { p.line(to: NSPoint(x: pos.x, y: pos.y)) }
        p.close()
        NSColor(o.fillColor).withAlphaComponent(0.3).setFill(); p.fill()
        NSColor(o.edgeColor).withAlphaComponent(0.8).setStroke(); p.lineWidth = 2*scale
        if o.lineStyle == .dashed { p.setLineDash([5*scale, 5*scale], count: 2, phase: 0) }
        p.stroke()
    }
    
    private static func drawVertices(_ positions: [CGPoint], color: Color, scale: CGFloat) {
        let vs: CGFloat = 10 * scale
        for pos in positions {
            let r = NSRect(x: pos.x - vs/2, y: pos.y - vs/2, width: vs, height: vs)
            NSColor(color).setFill(); NSBezierPath(ovalIn: r).fill()
            NSColor.white.setStroke(); let b = NSBezierPath(ovalIn: r); b.lineWidth = scale; b.stroke()
        }
    }
    
    // MARK: - Shapes
    
    static func drawShape(_ shape: EditorShape, in rect: NSRect, viewSize: CGSize) {
        let scaleX = rect.width / viewSize.width
        let scaleY = rect.height / viewSize.height
        let flippedY = rect.height - (shape.position.y * scaleY)
        let scaledX = shape.position.x * scaleX
        let scaledSize = CGSize(width: shape.size.width * scaleX, height: shape.size.height * scaleY)
        
        var path = createShapePath(type: shape.type, size: scaledSize)
        let rot = shape.rotation * .pi / 180
        let t = CGAffineTransform(translationX: scaledX, y: flippedY).rotated(by: rot)
        let af = AffineTransform(m11: t.a, m12: t.b, m21: t.c, m22: t.d, tX: t.tx, tY: t.ty)
        path.transform(using: af)
        
        var ref = AffineTransform()
        ref.translate(x: scaledX, y: flippedY); ref.scale(x: 1.0, y: -1.0); ref.translate(x: -scaledX, y: -flippedY)
        path.transform(using: ref)
        
        NSColor(shape.fillColor).withAlphaComponent(CGFloat(shape.fillOpacity)).setFill(); path.fill()
        NSColor(shape.strokeColor).setStroke(); path.lineWidth = shape.strokeWidth * scaleX
        if shape.lineStyle == .dashed { path.setLineDash([5*scaleX, 5*scaleX], count: 2, phase: 0) }
        path.stroke()
    }
    
    private static func createShapePath(type: ShapeType, size: CGSize) -> NSBezierPath {
        let hw = size.width/2, hh = size.height/2
        let p = NSBezierPath()
        switch type {
        case .triangle:
            p.move(to: NSPoint(x: 0, y: -hh)); p.line(to: NSPoint(x: -hw, y: hh)); p.line(to: NSPoint(x: hw, y: hh)); p.close()
        case .square, .rectangle:
            p.appendRect(NSRect(x: -hw, y: -hh, width: size.width, height: size.height))
        case .circle:
            p.appendOval(in: NSRect(x: -hw, y: -hh, width: size.width, height: size.height))
        case .star:
            let pts = 5; let or = min(hw, hh); let ir = or * 0.4
            for i in 0..<pts*2 {
                let a = Double(i) * .pi / Double(pts); let r = i % 2 == 0 ? or : ir
                let x = CGFloat(cos(a)) * r, y = CGFloat(sin(a)) * r
                if i == 0 { p.move(to: NSPoint(x: x, y: y)) } else { p.line(to: NSPoint(x: x, y: y)) }
            }; p.close()
        case .hexagon:
            let r = min(hw, hh)
            for i in 0..<6 {
                let a = Double(i) * .pi / 3.0; let x = CGFloat(cos(a))*r, y = CGFloat(sin(a))*r
                if i == 0 { p.move(to: NSPoint(x: x, y: y)) } else { p.line(to: NSPoint(x: x, y: y)) }
            }; p.close()
        }
        return p
    }
    
    // MARK: - TextBox
    
    static func drawTextBox(_ tb: EditorTextBox, in rect: NSRect, viewSize: CGSize) {
        let scaleX = rect.width / viewSize.width
        let scaleY = rect.height / viewSize.height
        let flippedY = rect.height - (tb.position.y * scaleY)
        let scaledX = tb.position.x * scaleX
        let scaledSize = CGSize(width: tb.size.width * scaleX, height: tb.size.height * scaleY)
        let tbRect = NSRect(x: -scaledSize.width/2, y: -scaledSize.height/2, width: scaledSize.width, height: scaledSize.height)
        
        var path = NSBezierPath(rect: tbRect)
        let rot = tb.rotation * .pi / 180
        let t = CGAffineTransform(translationX: scaledX, y: flippedY).rotated(by: rot)
        let af = AffineTransform(m11: t.a, m12: t.b, m21: t.c, m22: t.d, tX: t.tx, tY: t.ty)
        path.transform(using: af)
        
        var ref = AffineTransform()
        ref.translate(x: scaledX, y: flippedY); ref.scale(x: 1.0, y: -1.0); ref.translate(x: -scaledX, y: -flippedY)
        path.transform(using: ref)
        
        if tb.backgroundColor != .clear { NSColor(tb.backgroundColor).setFill(); path.fill() }
        NSColor(tb.borderColor).setStroke(); path.lineWidth = tb.borderWidth * max(scaleX, scaleY); path.stroke()
        
        guard !tb.text.isEmpty else { return }
        let textRect = tbRect.insetBy(dx: 5*max(scaleX,scaleY), dy: 5*max(scaleX,scaleY))
        let font = NSFont(name: tb.fontName, size: tb.fontSize * max(scaleX,scaleY)) ?? NSFont.systemFont(ofSize: tb.fontSize * max(scaleX,scaleY))
        let ps = NSMutableParagraphStyle(); ps.alignment = .center; ps.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(tb.textColor), .paragraphStyle: ps]
        let as_ = NSAttributedString(string: tb.text, attributes: attrs)
        
        NSGraphicsContext.current?.saveGraphicsState()
        let refNS = NSAffineTransform()
        refNS.translateX(by: scaledX, yBy: flippedY); refNS.scaleX(by: 1.0, yBy: 1.0)
        refNS.translateX(by: -scaledX, yBy: -flippedY); refNS.concat()
        let textT = NSAffineTransform()
        textT.translateX(by: scaledX, yBy: flippedY); textT.rotate(byRadians: rot); textT.concat()
        as_.draw(in: textRect)
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
