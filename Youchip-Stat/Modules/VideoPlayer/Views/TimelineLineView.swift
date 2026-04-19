//
//  TimelineLineView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct TimelineLineView: View {
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    
    let line: TimelineLine
    let scale: CGFloat
    let widthMax: CGFloat
    
    let isSelected: Bool
    let onSelect: () -> Void
    let onEditLabelsRequest: (UUID) -> Void
    let onEditTimeEventsRequest: (UUID) -> Void
    let onTagDragging: (CGFloat?) -> Void
    
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @State private var isDraggingOver = false
    private let lineHeight: CGFloat = 30
    
    // MARK: - Stamp edges drag properties
    @State private var resizingStampID: UUID? = nil
    @State private var resizingEdge: ResizeEdge? = nil
    @State private var dragStartTime: Double = 0
    @State private var originalStartTime: Double = 0
    @State private var originalEndTime: Double = 0
    
    @State private var visualWidth: CGFloat? = nil
    @State private var visualOffsetX: CGFloat? = nil
    @State private var maxVisualOffsetX: CGFloat? = nil
    
    @State private var lastSeekTime: Date = Date()
    private let seekThrottleInterval: TimeInterval = 0.033 // ~30fps
    
    // MARK: - drag properties
    @State private var dragOffsetY: CGFloat = 0
    @State private var draggingStampID: UUID?

    // MARK: - comment sheet
    @State private var commentEditingStamp: TimelineStamp? = nil
    
    enum ResizeEdge {
        case left
        case right
    }
    
    private func getOverlapCount(stamp: TimelineStamp, stamps: [TimelineStamp], stampIndex: Int) -> Int {
        var count = 0
        
        for i in 0..<stampIndex {
            let olderStamp = stamps[i]
            
            let stampStart = stamp.timeStartSeconds
            let stampEnd = stamp.timeFinishSeconds
            let olderStart = olderStamp.timeStartSeconds
            let olderEnd = olderStamp.timeFinishSeconds
            
            if stampStart < olderEnd && olderStart < stampEnd {
                count += 1
            }
        }
        
        return count
    }
    
    var body: some View {
        GeometryReader { geometry in
            let totalDuration = max(1, videoManager.timelineDuration)
            
            HStack(alignment: .top, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            isDraggingOver ? Color.blue.opacity(0.15) : Color.gray.opacity(0.05),
                            isDraggingOver ? Color.blue.opacity(0.08) : Color.gray.opacity(0.02)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(
                                isDraggingOver ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2),
                                lineWidth: 0.5
                            )
                    )
                    .timelineTapToSeek(
                        gridWidth: widthMax,
                        duration: totalDuration,
                        onShortPress: {
                            timelineData.selectStamp(stampID: nil)
                            timelineData.clearSportCutExportSelection()
                        }
                    ) { time in
                        videoManager.seek(to: time)
                    }
                    ForEach(Array(line.stamps.enumerated()), id: \.element.id) { index, stamp in
                        stampView(
                            stamp: stamp,
                            index: index,
                            totalDuration: totalDuration,
                            widthMax: widthMax
                        )
                    }
                }
            }
            .frame(width: widthMax, height: lineHeight)
        }
        .sheet(item: $commentEditingStamp) { stamp in
            StampCommentEditSheet(stamp: stamp) { newComment in
                if let lineIndex = timelineData.lines.firstIndex(where: { $0.id == line.id }),
                   let stampIndex = timelineData.lines[lineIndex].stamps.firstIndex(where: { $0.id == stamp.id }) {
                    timelineData.lines[lineIndex].stamps[stampIndex].comment = newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newComment
                    timelineData.updateTimelines()
                }
            }
        }
    }

    
    @ViewBuilder
    private func stampView(stamp: TimelineStamp, index: Int, totalDuration: Double, widthMax: CGFloat) -> some View {
        let isResizing = resizingStampID == stamp.id
        let currentStartTime = isResizing && resizingEdge == .left ? dragStartTime : stamp.timeStartSeconds
        let currentEndTime = isResizing && resizingEdge == .right ? dragStartTime : stamp.timeFinishSeconds
        let currentDuration = currentEndTime - currentStartTime
        
        let isDragging = draggingStampID == stamp.id
        
        let currentLineIndex = timelineData.lines.firstIndex(where: { $0.id == line.id }) ?? 0
        let maxYOffset = CGFloat(timelineData.lines.count - 1 - currentLineIndex) * lineHeight
        let minYOffset = -1 * CGFloat(currentLineIndex) * lineHeight
        let verticalOffset = isDragging ? max(min(dragOffsetY, maxYOffset), minYOffset) : 0
        
        let startRatio = currentStartTime / totalDuration
        let durationRatio = currentDuration / totalDuration
        
        let baseStampWidth = max(durationRatio * widthMax, 10)
        let baseStampX = startRatio * widthMax
        //let stampWidth = max(durationRatio * widthMax, 10) // Minimum width
        let stampWidth = ((isResizing && resizingEdge == .right) ?
            (visualWidth ?? baseStampWidth) : (isResizing && resizingEdge == .left) ?
            (visualWidth ?? baseStampWidth) : baseStampWidth) ?? 0
        

        let stampX = ((isResizing && resizingEdge == .left) ?
                      (visualOffsetX ?? baseStampX) : baseStampX) ?? 0
        
        let isSelected = timelineData.selectedStampID == stamp.id
        let inSportCutBulk = timelineData.stampsSelectedForSportCut.contains(stamp.id)
        let overlapCount = getOverlapCount(stamp: stamp, stamps: line.stamps, stampIndex: index)
        let hasOverlaps = overlapCount > 0
        
        let borderColor: Color = {
            if inSportCutBulk { return Color.green }
            if hasOverlaps && !isSelected { return Color.red }
            if isSelected && hasOverlaps { return Color.red }
            if isSelected { return Color.blue }
            return Color.clear
        }()
        let heightReduction = CGFloat(overlapCount * 6)
        let stampHeight: CGFloat = 25 - heightReduction
        
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            stamp.color,
                            stamp.color.opacity(0.8)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: stampHeight)
                .shadow(
                    color: stamp.color.opacity(0.3),
                    radius: isSelected ? 4 : 2,
                    x: 0,
                    y: isSelected ? 2 : 1
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: isSelected ? 2.5 : 1.5)
                )
            
            StampLabelsOverlayView(
                stamp: stamp,
                maxWidth: stampWidth
            )
            .frame(height: stampHeight)
            .padding(.horizontal, 4)
        }
        .overlay(
            edgeHandlesView(
                stamp: stamp,
                isSelected: isSelected,
                stampHeight: stampHeight,
                stampWidth: stampWidth,
                totalDuration: totalDuration,
                widthMax: widthMax
            )
        )
        .overlay(alignment: .topTrailing) {
            if stamp.comment != nil {
                Circle()
                    .fill(Color.red)
                    .overlay(Circle().stroke(Color.black, lineWidth: 0.8))
                    .frame(width: 7, height: 7)
                    .offset(x: 2, y: -2)
            }
        }
        .frame(width: stampWidth, height: stampHeight)
        .position(x: clampedCenterX(isDragging: isDragging, stampX: stampX, stampWidth: stampWidth), y: verticalOffset + 15)
        .onTapGesture(count: 2) {
            if resizingStampID == nil {
                let stampDuration = max(stamp.timeFinishSeconds - stamp.timeStartSeconds, 1.0)
                WindowsManager.shared.openMomentViewer(
                    stampStart: stamp.timeStartSeconds,
                    stampDuration: stampDuration,
                    tagName: stamp.label,
                    lineName: line.name,
                    lineID: line.id,
                    stampID: stamp.id
                )
            }
        }
        .onTapGesture(count: 1) {
            if resizingStampID == nil {
                let commandDown = NSEvent.modifierFlags.contains(.command)
                if commandDown {
                    timelineData.toggleSportCutExportSelection(stampID: stamp.id)
                    return
                }
                // Сброс пачки ⌘-выбора только по пустому месту или «Снять выделение», не при обычном клике по тегу.
                withAnimation(.easeInOut(duration: 0.2)) {
                    timelineData.selectStamp(stampID: stamp.id)
                }
                if videoManager.isReviewMode {
                    videoManager.seekReview(to: stamp.timeStartSeconds)
                } else {
                    videoManager.seek(to: stamp.timeStartSeconds)
                    videoManager.player?.play()
                }
            }
        }
        .gesture(
            (resizingStampID == nil ? DragGesture() : nil)
                .onChanged { value in
                    if draggingStampID == nil {
                        draggingStampID = stamp.id
                    }
                    dragOffsetY = value.translation.height
                }
                .onEnded { value in
                    dragOffsetY = 0
                    guard let draggingStampID else { return }

                    let lineHeight: CGFloat = lineHeight
                    let sourceLineIndex = timelineData.lines.firstIndex(where: { $0.id == line.id }) ?? 0
                    let y = value.location.y + CGFloat(sourceLineIndex) * lineHeight
                    
                    var destLineIndex = Int(y / lineHeight)
                    destLineIndex = max(0, destLineIndex)
                    destLineIndex = min(timelineData.lines.count - 1, destLineIndex)

                    let destLineID = timelineData.lines[destLineIndex].id
                    
                    let stampInfo = StampDragInfo(
                        lineID: line.id,
                        stampID: draggingStampID,
                    )
                    transferStamp(stampInfo, to: destLineID)
                    
                    self.draggingStampID = nil
                    dragOffsetY = 0
                }
        )
        .contextMenu {
            menuForTag(stamp: stamp)
        }
        .onDrag {
            guard let data = WindowsManager.shared.encodeMarkupPlaylistDragData(line: line, stamp: stamp) else {
                return NSItemProvider()
            }
            return NSItemProvider(item: data as NSData, typeIdentifier: UTType.data.identifier)
        }
        .coordinateSpace(name: "timelineSpace")
    }
    
    @ViewBuilder
    private func edgeHandlesView(
        stamp: TimelineStamp,
        isSelected: Bool,
        stampHeight: CGFloat,
        stampWidth: CGFloat,
        totalDuration: Double,
        widthMax: CGFloat
    ) -> some View {
        Group {
            if isSelected {
                HStack(spacing: 0) {
                    // Left edge handle
                    EdgeResizeHandle(
                        edge: .left,
                        stampHeight: stampHeight
                    )
                    .frame(width: 8)
                    .gesture(
                        leftEdgeDragGesture(
                            stamp: stamp,
                            totalDuration: totalDuration,
                            widthMax: widthMax
                        )
                    )
                    
                    Spacer()
                    
                    // Right edge handle
                    EdgeResizeHandle(
                        edge: .right,
                        stampHeight: stampHeight
                    )
                    .frame(width: 8)
                    .gesture(
                        rightEdgeDragGesture(
                            stamp: stamp,
                            totalDuration: totalDuration,
                            widthMax: widthMax
                        )
                    )
                }
                .frame(width: stampWidth)
            }
        }
    }
    
    private func leftEdgeDragGesture(stamp: TimelineStamp, totalDuration: Double, widthMax: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let minWidth: CGFloat = 30
                
                if resizingStampID != stamp.id {
                    resizingStampID = stamp.id
                    resizingEdge = .left
                    originalStartTime = stamp.timeStartSeconds
                    originalEndTime = stamp.timeFinishSeconds
                    dragStartTime = originalStartTime
                    
                    videoManager.isResizingTag = true
                    
                    let baseDuration = originalEndTime - originalStartTime
                    let baseDurationRatio = baseDuration / totalDuration
                    visualWidth = max(baseDurationRatio * widthMax, minWidth)
                    
                    let baseStartRatio = originalStartTime / totalDuration
                    visualOffsetX = baseStartRatio * widthMax
                    maxVisualOffsetX = (visualOffsetX ?? 0) + (visualWidth ?? 0) - minWidth
                }
                
                let deltaX = value.translation.width
                let baseWidth = visualWidth ?? 0
                let baseOffsetX = visualOffsetX ?? 0
                
                let newOffsetX = baseOffsetX + deltaX
                let newWidth = max(baseWidth - deltaX, minWidth)
                
                if newOffsetX < 0 || newOffsetX > maxVisualOffsetX ?? 0 {
                    return
                }
                visualOffsetX = newOffsetX
                visualWidth = newWidth
                
                let time = (newOffsetX / widthMax) * totalDuration
                onTagDragging(newOffsetX)
                
                let now = Date()
                if now.timeIntervalSince(lastSeekTime) >= seekThrottleInterval {
                    lastSeekTime = now
                    videoManager.seek(to: time)
                }
            }
            .onEnded { _ in
                if let stampID = resizingStampID,
                   let finalOffsetX = visualOffsetX,
                   let finalWidth = visualWidth,
                   resizingEdge == .left {
                    
                    let finalStartRatio = finalOffsetX / widthMax
                    let finalStartTime = max(finalStartRatio * totalDuration, 0)
                    
                    let finalDurationRatio = finalWidth / widthMax
                    let finalDuration = finalDurationRatio * totalDuration
                    let finalEndTime = min(finalStartTime + finalDuration, totalDuration)
                    
                    let adjustedStartTime = min(finalStartTime, finalEndTime - 0.5)
                    
                    timelineData.updateStampTime(
                        lineID: line.id,
                        stampID: stampID,
                        newStart: adjustedStartTime
                    )
                    onTagDragging(nil)
                }
                
                videoManager.isResizingTag = false
                
                resizingStampID = nil
                resizingEdge = nil
                visualWidth = nil
                visualOffsetX = nil
            }
    }

    
    private func rightEdgeDragGesture(stamp: TimelineStamp, totalDuration: Double, widthMax: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let minWidth: CGFloat = 30
                
                if resizingStampID != stamp.id {
                    resizingStampID = stamp.id
                    resizingEdge = .right
                    originalStartTime = stamp.timeStartSeconds
                    originalEndTime = stamp.timeFinishSeconds
                    dragStartTime = originalStartTime
                    
                    videoManager.isResizingTag = true
                    
                    let baseStartRatio = originalStartTime / totalDuration
                    visualOffsetX = baseStartRatio * widthMax
                    
                    let baseDuration = originalEndTime - originalStartTime
                    let baseDurationRatio = baseDuration / totalDuration
                    visualWidth = max(baseDurationRatio * widthMax, minWidth)
                }
                
                let baseWidth = visualWidth ?? 0
                let newWidth = max(baseWidth + value.translation.width, minWidth) 
                if let visualOffsetX, visualOffsetX + newWidth > widthMax {
                    return
                }
                visualWidth = newWidth
                
                let time = originalStartTime + ((visualWidth ?? 0) / widthMax) * totalDuration
                onTagDragging(time / totalDuration * widthMax)
                
                let now = Date()
                if now.timeIntervalSince(lastSeekTime) >= seekThrottleInterval {
                    lastSeekTime = now
                    videoManager.seek(to: time)
                }
            }
            .onEnded { _ in
                if let stampID = resizingStampID,
                   let finalWidth = visualWidth,
                   resizingEdge == .right {
                    
                    let finalDurationRatio = finalWidth / widthMax
                    let finalDuration = finalDurationRatio * totalDuration
                    let finalEndTime = min(originalStartTime + finalDuration, totalDuration)
                    
                    timelineData.updateStampTime(
                        lineID: line.id,
                        stampID: stampID,
                        newEnd: finalEndTime
                    )
                    onTagDragging(nil)
                }
                
                videoManager.isResizingTag = false
                
                resizingStampID = nil
                resizingEdge = nil
                visualWidth = nil
                visualOffsetX = nil
            }
    }
    
    @ViewBuilder
    private func menuForTag(stamp: TimelineStamp) -> some View {
        Text("\(^String.Titles.fieldMapTagTitleNoNumber) \(stamp.label)")
        
        if let position = stamp.position {
            Text(String(format: ^String.Titles.fieldMapTagPosition, position.x, position.y))
        }
        
        if !stamp.labels.isEmpty {
            ForEach(stamp.labels, id: \.id) { labelItem in
                let label = tagLibrary.findLabelById(labelItem.id)
                let displayName = label?.name ?? labelItem.name
                if let group = tagLibrary.allLabelGroups.first(where: { $0.lables.contains(labelItem.id) }) {
                    Text("\(displayName) (\(group.name))")
                } else if !displayName.isEmpty {
                    Text(displayName)
                }
            }
            Divider()
        }
        if !stamp.timeEvents.isEmpty {
            Text(^String.Titles.fieldMapLabelEvents)
            ForEach(stamp.timeEvents, id: \.self) { eventID in
                if let event = tagLibrary.allTimeEvents.first(where: { $0.id == eventID }) {
                    Text("• \(event.name)")
                }
            }
            Divider()
        }
        
        Button("Посмотреть момент") {
            let stampDuration = max(stamp.timeFinishSeconds - stamp.timeStartSeconds, 1.0)
            WindowsManager.shared.openMomentViewer(
                stampStart: stamp.timeStartSeconds,
                stampDuration: stampDuration,
                tagName: stamp.label,
                lineName: line.name,
                lineID: line.id,
                stampID: stamp.id
            )
        }

        Button("Новая сессия просмотра") {
            WindowsManager.shared.openSportCutFromTimelineStamps([(line, stamp)])
        }
        let existingSessions = SportCutSessionManager.shared.sessions
        if !existingSessions.isEmpty {
            Menu("В существующую сессию") {
                ForEach(existingSessions, id: \.id) { sess in
                    Button(sess.name) {
                        WindowsManager.shared.appendStampsToSportCutSession(pairs: [(line, stamp)], sessionID: sess.id)
                    }
                }
            }
        }

        Divider()

        Button(stamp.comment == nil ? "Добавить комментарий" : "Редактировать комментарий") {
            commentEditingStamp = stamp
        }
        if stamp.comment != nil {
            Button("Удалить комментарий") {
                if let lineIndex = timelineData.lines.firstIndex(where: { $0.id == line.id }),
                   let stampIndex = timelineData.lines[lineIndex].stamps.firstIndex(where: { $0.id == stamp.id }) {
                    timelineData.lines[lineIndex].stamps[stampIndex].comment = nil
                    timelineData.updateTimelines()
                }
            }
        }
        
        Button(^String.Titles.timelineButtonDeleteTag) {
            TimelineDataManager.shared.removeStamp(lineID: line.id, stampID: stamp.id)
            if timelineData.selectedStampID == stamp.id {
                timelineData.selectStamp(stampID: nil)
            }
        }
        
        // Проверяем, является ли это тегом рисунка (скриншота)
        // Тег должен:
        // 1. Быть связан со скриншотом (через relatedStampIds)
        // 2. Находиться на специальном таймлайне для рисунков
        // 3. Иметь имя, совпадающее с именем скриншота
        let isDrawingsTimeline = line.isDrawingsTimeline
        
        let isScreenshotTag = isDrawingsTimeline && ScreenshotsMetadataManager.shared.screenshots.contains { screenshot in
            screenshot.relatedStampIds.contains(stamp.id) &&
            screenshot.screenshotName == stamp.label
        }
        
        // Показываем кнопку редактирования лейблов только если это не тег рисунка
        if !isScreenshotTag {
            Button(^String.Titles.timelineButtonEditLabels) {
                onEditLabelsRequest(stamp.id)
            }
        }
        Button(^String.Titles.timelineButtonEditTimeEvents) {
            onEditTimeEventsRequest(stamp.id)
        }
    }
    
    private func transferStamp(_ stampInfo: StampDragInfo, to destLineID: UUID) {
        guard let sourceLineIndex = timelineData.lines.firstIndex(where: { $0.id == stampInfo.lineID }),
              let destLineIndex = timelineData.lines.firstIndex(where: { $0.id == destLineID }),
              let stampIndex = timelineData.lines[sourceLineIndex].stamps.firstIndex(where: { $0.id == stampInfo.stampID }) else {
            return
        }
        
        let stamp = timelineData.lines[sourceLineIndex].stamps[stampIndex]
        
        let newStamp = TimelineStamp(
            id: UUID(),
            tagRefs: stamp.tagRefs,
            primaryID: stamp.primaryID,
            timeStartSeconds: stamp.timeStartSeconds,
            timeFinishSeconds: stamp.timeFinishSeconds,
            colorHex: stamp.colorHex,
            label: stamp.label,
            labels: stamp.labels,
            timeEvents: stamp.timeEvents,
            position: stamp.position,
            comment: stamp.comment
        )
        
        timelineData.lines[destLineIndex].stamps.append(newStamp)
        timelineData.lines[sourceLineIndex].stamps.remove(at: stampIndex)
        timelineData.updateTimelines()
    }
    
    private func clampedCenterX(isDragging: Bool, stampX: CGFloat, stampWidth: CGFloat) -> CGFloat {
        let baseCenterX = stampX + stampWidth / 2
        var centerX = baseCenterX

        let minCenterX = stampWidth / 2
        let maxCenterX = widthMax - stampWidth / 2

        centerX = max(minCenterX, min(centerX, maxCenterX))
        return centerX
    }
}

// Edge resize handle view
struct EdgeResizeHandle: View {
    let edge: TimelineLineView.ResizeEdge
    let stampHeight: CGFloat
    
    private let handleWidth: CGFloat = 8
    private let handleHeight: CGFloat = 20
    
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.8))
            .frame(width: handleWidth, height: min(handleHeight, stampHeight))
            .overlay(
                Rectangle()
                    .stroke(Color.blue, lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            .contentShape(Rectangle())
    }
}
