//
//  TelestrationModeView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 3/20/26.
//

import SwiftUI

struct TelestrationModeView: View {
    
    @ObservedObject var viewModel: TelestrationModeViewModel
    let onClose: () -> Void
    let onExport: () -> Void
    
    @State private var isExtractingFrames = false
    @State private var displaySize: CGSize = .zero
    
    var body: some View {
        VStack(spacing: 0) {
            telestrationToolbar
            
            Divider()
            
            HStack(spacing: 0) {
                toolPickerSidebar
                
                Divider()
                
                canvasArea
                
                Divider()
                
                settingsSidebar
            }
            
            Divider()
            
            timelineScrubber
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            isExtractingFrames = true
            viewModel.extractFirstFrame()
            viewModel.extractFrames {
                isExtractingFrames = false
            }
        }
    }
    
    // MARK: - Toolbar
    
    private var telestrationToolbar: some View {
        HStack(spacing: 12) {
            Text("Telestration Mode")
                .font(.system(size: 14, weight: .semibold))
            
            Spacer()
            
            if viewModel.isTracking {
                HStack(spacing: 8) {
                    ProgressView(value: Double(viewModel.trackingProgress))
                        .frame(width: 120)
                    Text("Tracking...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if isExtractingFrames {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Extracting frames...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button("Export") {
                onExport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.markers.isEmpty && viewModel.arrows.isEmpty)
            
            Button("Close") {
                viewModel.stop()
                onClose()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Tool Picker Sidebar
    
    private var toolPickerSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tools")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.top, 8)
            
            ForEach(TelestrationModeTool.allCases, id: \.self) { tool in
                toolButton(for: tool)
            }
            
            Divider()
            
            objectsList
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: 180)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func toolButton(for tool: TelestrationModeTool) -> some View {
        Button(action: {
            viewModel.currentTool = tool
            if tool != .animatedArrow {
                viewModel.cancelArrowPlacement()
            }
            if tool != .zone {
                viewModel.zoneSelectingMarkerIDs.removeAll()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: tool.iconName)
                    .font(.system(size: 14))
                    .frame(width: 20)
                
                Text(tool.displayName)
                    .font(.system(size: 12))
                
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(viewModel.currentTool == tool ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(viewModel.currentTool == tool ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Objects List
    
    private var objectsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.markers.isEmpty {
                Text("Markers")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                ForEach(viewModel.markers) { marker in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(marker.color)
                            .frame(width: 10, height: 10)
                        
                        Text("Player \(viewModel.markers.firstIndex(where: { $0.id == marker.id }).map { $0 + 1 } ?? 0)")
                            .font(.system(size: 11))
                        
                        Spacer()
                        
                        Button(action: { viewModel.removeMarker(marker.id) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.vertical, 2)
                }
            }
            
            if !viewModel.zones.isEmpty {
                Text("Zones")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                ForEach(viewModel.zones) { zone in
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(zone.fillColor.opacity(0.5))
                            .frame(width: 10, height: 10)
                        
                        Text("Zone (\(zone.markerIDs.count) players)")
                            .font(.system(size: 11))
                        
                        Spacer()
                        
                        Button(action: { viewModel.removeZone(zone.id) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.vertical, 2)
                }
            }
            
            if !viewModel.arrows.isEmpty {
                Text("Arrows")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                ForEach(viewModel.arrows) { arrow in
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(arrow.color)
                        
                        Text("Arrow")
                            .font(.system(size: 11))
                        
                        Spacer()
                        
                        Button(action: { viewModel.removeArrow(arrow.id) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
    
    // MARK: - Settings Sidebar
    
    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.top, 8)
            
            switch viewModel.currentTool {
            case .playerMarker:
                markerSettings
            case .zone:
                zoneSettings
            case .animatedArrow:
                arrowSettings
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Pause Duration (s)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                HStack {
                    Slider(value: $viewModel.pauseBeforePlay, in: 0...5, step: 0.5)
                    Text(String(format: "%.1f", viewModel.pauseBeforePlay))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 30)
                }
            }
            
            Spacer()
            
            Text("Frame \(viewModel.currentFrameIndex + 1) / \(viewModel.totalFrames)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 12)
        .frame(width: 180)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var markerSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Marker Color")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            ColorPicker("", selection: $viewModel.markerColor)
                .labelsHidden()
                .frame(width: 40, height: 24)
            
            Text("Click on a player to place a marker. Markers track automatically during playback.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var zoneSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zone Color")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            ColorPicker("", selection: $viewModel.zoneColor)
                .labelsHidden()
                .frame(width: 40, height: 24)
            
            if !viewModel.zoneSelectingMarkerIDs.isEmpty {
                Text("\(viewModel.zoneSelectingMarkerIDs.count) markers selected")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                
                Button("Create Zone") {
                    viewModel.confirmZone()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.zoneSelectingMarkerIDs.count < 2)
            }
            
            Text("Click existing markers to select them for a zone, then create.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var arrowSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Arrow Color")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            ColorPicker("", selection: $viewModel.arrowColor)
                .labelsHidden()
                .frame(width: 40, height: 24)
            
            Text("Animation Duration (s)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            HStack {
                Slider(value: $viewModel.arrowAnimationDuration, in: 0.5...5.0, step: 0.25)
                Text(String(format: "%.1f", viewModel.arrowAnimationDuration))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 30)
            }
            
            if viewModel.pendingArrow != nil {
                Text("Click the end point for the arrow")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                
                Button("Cancel") {
                    viewModel.cancelArrowPlacement()
                }
                .buttonStyle(.bordered)
            } else {
                Text("Click a start point, then an end point.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: - Canvas Area
    
    private var canvasArea: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                if let frameImage = viewModel.currentFrameImage {
                    let imgSize = viewModel.imageSize
                    let containerSize = geometry.size
                    let fitSize = calculateFitSize(imageSize: imgSize, containerSize: containerSize)
                    
                    ZStack {
                        Image(nsImage: frameImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: fitSize.width, height: fitSize.height)
                        
                        TelestrationOverlayCanvas(
                            viewModel: viewModel,
                            displaySize: fitSize,
                            imageSize: imgSize
                        )
                        .frame(width: fitSize.width, height: fitSize.height)
                    }
                    .frame(width: fitSize.width, height: fitSize.height)
                    .onAppear { displaySize = fitSize }
                    .onChange(of: fitSize) { displaySize = $0 }
                } else {
                    ProgressView("Loading frame...")
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private func calculateFitSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return containerSize }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        
        if imageAspect > containerAspect {
            let w = containerSize.width
            return CGSize(width: w, height: w / imageAspect)
        } else {
            let h = containerSize.height
            return CGSize(width: h * imageAspect, height: h)
        }
    }
    
    // MARK: - Timeline Scrubber
    
    private var timelineScrubber: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button(action: { viewModel.stepBackward() }) {
                    Image(systemName: "backward.frame.fill")
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { viewModel.togglePlayPause() }) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.markers.isEmpty && viewModel.arrows.isEmpty)
                
                Button(action: { viewModel.stepForward() }) {
                    Image(systemName: "forward.frame.fill")
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { viewModel.trackMarkers() }) {
                    Image(systemName: "scope")
                        .foregroundColor(viewModel.isTracking ? .accentColor : .primary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.markers.isEmpty || viewModel.isTracking || viewModel.isPlaying)
                .help("Track markers")
                
                Spacer()
                
                Text(formatTime(viewModel.currentClipTime))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Text("/")
                    .foregroundColor(.secondary)
                
                Text(formatTime(viewModel.clipDuration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // Scrubber slider
            Slider(
                value: Binding(
                    get: { Double(viewModel.currentFrameIndex) },
                    set: { viewModel.seekToFrame(Int($0)) }
                ),
                in: 0...max(1, Double(viewModel.totalFrames - 1)),
                step: 1
            )
            .disabled(viewModel.isPlaying)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%01d", mins, secs, ms)
    }
}

// MARK: - Telestration Overlay Canvas

struct TelestrationOverlayCanvas: View {
    
    @ObservedObject var viewModel: TelestrationModeViewModel
    let displaySize: CGSize
    let imageSize: CGSize
    
    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / imageSize.width
            let scaleY = size.height / imageSize.height
            
            func toView(_ pt: CGPoint) -> CGPoint {
                CGPoint(x: pt.x * scaleX, y: pt.y * scaleY)
            }
            
            let frameIndex = viewModel.currentFrameIndex
            
            // Draw zones
            for zone in viewModel.zones {
                let points = zone.points(from: viewModel.markers, at: frameIndex)
                guard points.count >= 3 else { continue }
                
                let hull = ConvexHull.compute(from: points)
                let viewHull = hull.map { toView($0) }
                
                var path = Path()
                path.move(to: viewHull[0])
                for p in viewHull.dropFirst() { path.addLine(to: p) }
                path.closeSubpath()
                
                context.fill(path, with: .color(zone.fillColor.opacity(zone.fillOpacity)))
                context.stroke(path, with: .color(zone.edgeColor), lineWidth: 2)
            }
            
            // Draw zone selection highlights
            for markerID in viewModel.zoneSelectingMarkerIDs {
                guard let marker = viewModel.markers.first(where: { $0.id == markerID }),
                      let pos = marker.position(at: frameIndex) else { continue }
                let vp = toView(pos)
                let highlightRect = CGRect(x: vp.x - 18, y: vp.y - 18, width: 36, height: 36)
                context.stroke(Path(ellipseIn: highlightRect), with: .color(.white), lineWidth: 2)
            }
            
            // Draw markers
            for marker in viewModel.markers {
                guard let pos = marker.position(at: frameIndex) else { continue }
                let vp = toView(pos)
                let r = marker.radius * scaleX
                
                let outerRect = CGRect(x: vp.x - r, y: vp.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: outerRect), with: .color(marker.color.opacity(0.3)))
                context.stroke(Path(ellipseIn: outerRect), with: .color(marker.color), lineWidth: 2.5)
                
                let innerRect = CGRect(x: vp.x - 4, y: vp.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: innerRect), with: .color(marker.color))
            }
            
            // Draw arrows
            for arrow in viewModel.arrows {
                let start = toView(arrow.startPoint)
                let end = toView(arrow.endPoint)
                
                let animProgress: Double
                if viewModel.isPlaying {
                    let elapsed = viewModel.currentClipTime
                    animProgress = min(1.0, elapsed / arrow.animationDuration)
                } else {
                    animProgress = 1.0
                }
                
                let currentEnd = CGPoint(
                    x: start.x + (end.x - start.x) * animProgress,
                    y: start.y + (end.y - start.y) * animProgress
                )
                
                var linePath = Path()
                linePath.move(to: start)
                linePath.addLine(to: currentEnd)
                context.stroke(linePath, with: .color(arrow.color), lineWidth: arrow.lineWidth)
                
                // Arrowhead
                if animProgress > 0.05 {
                    let dx = currentEnd.x - start.x
                    let dy = currentEnd.y - start.y
                    let angle = atan2(dy, dx)
                    let headLength: CGFloat = 14
                    let headWidth: CGFloat = 8
                    
                    let p1 = CGPoint(
                        x: currentEnd.x - headLength * cos(angle) + headWidth * cos(angle + .pi / 2),
                        y: currentEnd.y - headLength * sin(angle) + headWidth * sin(angle + .pi / 2)
                    )
                    let p2 = CGPoint(
                        x: currentEnd.x - headLength * cos(angle) - headWidth * cos(angle + .pi / 2),
                        y: currentEnd.y - headLength * sin(angle) - headWidth * sin(angle + .pi / 2)
                    )
                    
                    var headPath = Path()
                    headPath.move(to: currentEnd)
                    headPath.addLine(to: p1)
                    headPath.addLine(to: p2)
                    headPath.closeSubpath()
                    context.fill(headPath, with: .color(arrow.color))
                }
            }
            
            // Draw pending arrow start point
            if let pending = viewModel.pendingArrow {
                let start = toView(pending.startPoint)
                let startRect = CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: startRect), with: .color(viewModel.arrowColor))
                context.stroke(Path(ellipseIn: startRect), with: .color(.white), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dragDistance = hypot(
                        value.location.x - value.startLocation.x,
                        value.location.y - value.startLocation.y
                    )
                    if dragDistance > 4 && viewModel.draggedMarkerID == nil {
                        let startImagePt = toImageCoord(value.startLocation)
                        _ = viewModel.startDraggingMarker(at: startImagePt)
                    }
                    if viewModel.draggedMarkerID != nil {
                        let imagePoint = toImageCoord(value.location)
                        viewModel.dragMarker(to: imagePoint)
                    }
                }
                .onEnded { value in
                    if viewModel.draggedMarkerID != nil {
                        viewModel.endDraggingMarker()
                    } else {
                        let dragDistance = hypot(
                            value.location.x - value.startLocation.x,
                            value.location.y - value.startLocation.y
                        )
                        if dragDistance < 5 {
                            let imagePoint = toImageCoord(value.startLocation)
                            viewModel.handleCanvasClick(at: imagePoint)
                        }
                    }
                }
        )
    }
    
    private func toImageCoord(_ viewPoint: CGPoint) -> CGPoint {
        guard displaySize.width > 0, displaySize.height > 0 else { return viewPoint }
        let scaleX = imageSize.width / displaySize.width
        let scaleY = imageSize.height / displaySize.height
        return CGPoint(x: viewPoint.x * scaleX, y: viewPoint.y * scaleY)
    }
}

