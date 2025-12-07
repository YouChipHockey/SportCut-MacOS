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
    let onTagDragging: (CGFloat?) -> Void
    
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @State private var isDraggingOver = false
    @Binding var scrollOffset: CGFloat
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
    
    // MARK: - drag properties
    @State private var dragOffset: CGSize = .zero
    @State private var draggingStampID: UUID?
    
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
            let totalDuration = max(1, videoManager.videoDuration)
            
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            isDraggingOver ? Color.blue.opacity(0.15) : Color.gray.opacity(0.05),
                            isDraggingOver ? Color.blue.opacity(0.08) : Color.gray.opacity(0.02)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: widthMax, height: lineHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(
                                isDraggingOver ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2),
                                lineWidth: 0.5
                            )
                    )
                    .onTapGesture {
                        timelineData.selectStamp(stampID: nil)
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
            .frame(width: widthMax, height: 60)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        scrollOffset = value.translation.width
                    }
            )
        }
    }

    
    @ViewBuilder
    private func stampView(stamp: TimelineStamp, index: Int, totalDuration: Double, widthMax: CGFloat) -> some View {
        let isResizing = resizingStampID == stamp.id
        let currentStartTime = isResizing && resizingEdge == .left ? dragStartTime : stamp.timeStartSeconds
        let currentEndTime = isResizing && resizingEdge == .right ? dragStartTime : stamp.timeFinishSeconds
        let currentDuration = currentEndTime - currentStartTime
        
        let isDragging = draggingStampID == stamp.id
        let dragOffsetX = isDragging ? dragOffset.width : 0
        
        let currentLineIndex = timelineData.lines.firstIndex(where: { $0.id == line.id }) ?? 0
        let maxYOffset = CGFloat(timelineData.lines.count - 1 - currentLineIndex) * lineHeight
        let minYOffset = -1 * CGFloat(currentLineIndex) * lineHeight
        let dragOffsetY = isDragging ? max(min(dragOffset.height, maxYOffset), minYOffset) : 0
        
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
        let overlapCount = getOverlapCount(stamp: stamp, stamps: line.stamps, stampIndex: index)
        let hasOverlaps = overlapCount > 0
        
        let borderColor = (hasOverlaps && !isSelected) ? Color.red :
        (isSelected && hasOverlaps) ? Color.red :
        (isSelected) ? Color.blue : Color.clear
        let heightReduction = CGFloat(overlapCount * 6)
        let stampHeight: CGFloat = 25 - heightReduction

        let positionX = max(min(widthMax, dragOffsetX + stampX + stampWidth / 2), 0)
        
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
        .frame(width: stampWidth, height: stampHeight)
        .position(x: clampedCenterX(isDragging: isDragging, stampX: stampX, stampWidth: stampWidth), y: dragOffsetY + 15)
        .onTapGesture {
            if resizingStampID == nil {
                withAnimation(.easeInOut(duration: 0.2)) {
                    videoManager.seek(to: stamp.timeStartSeconds)
                    timelineData.selectStamp(stampID: stamp.id)
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
                    dragOffset = value.translation
                    print(widthMax, dragOffsetX + stampX + stampWidth / 2)
                }
                .onEnded { value in
                    dragOffset = .zero
                    guard let draggingStampID else { return }
                    let offsetInSeconds = Double(dragOffsetX) / widthMax * totalDuration
                    var newStartSecond = stamp.timeStartSeconds + offsetInSeconds
                    newStartSecond = max(newStartSecond, 0)
                    var newEndSecond = stamp.timeFinishSeconds + offsetInSeconds
                    newEndSecond = min(newEndSecond, totalDuration)
                    
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
                        startSecond: newStartSecond,
                        endSecond: newEndSecond
                    )
                    transferStamp(stampInfo, to: destLineID)
                    
                    self.draggingStampID = nil
                    self.dragOffset = .zero
                }
        )
        .contextMenu {
            menuForTag(stamp: stamp)
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
                if resizingStampID != stamp.id {
                    resizingStampID = stamp.id
                    resizingEdge = .left
                    originalStartTime = stamp.timeStartSeconds
                    originalEndTime = stamp.timeFinishSeconds
                    dragStartTime = originalStartTime
                    
                    // Исходные геометрия
                    let baseDuration = originalEndTime - originalStartTime
                    let baseDurationRatio = baseDuration / totalDuration
                    visualWidth = max(baseDurationRatio * widthMax, 10)
                    
                    let baseStartRatio = originalStartTime / totalDuration
                    visualOffsetX = baseStartRatio * widthMax
                    maxVisualOffsetX = (visualOffsetX ?? 0) + (visualWidth ?? 0) - 10
                }
                
                let deltaX = value.translation.width
                let baseWidth = visualWidth ?? 0
                let baseOffsetX = visualOffsetX ?? 0
                
                // Сдвигаем левый край: offset увеличивается, ширина уменьшается
                let newOffsetX = baseOffsetX + deltaX
                let newWidth = max(baseWidth - deltaX, 10)
                
                if newOffsetX < 0 || newOffsetX > maxVisualOffsetX ?? 0 {
                    return
                }
                visualOffsetX = newOffsetX
                visualWidth = newWidth
                
                let time = (newOffsetX / widthMax) * totalDuration
                onTagDragging(newOffsetX)
                videoManager.seek(to: time)
            }
            .onEnded { _ in
                if let stampID = resizingStampID,
                   let finalOffsetX = visualOffsetX,
                   let finalWidth = visualWidth,
                   resizingEdge == .left {
                    
                    // Пересчитываем обратно во время
                    let finalStartRatio = finalOffsetX / widthMax
                    let finalStartTime = max(finalStartRatio * totalDuration, 0)
                    
                    let finalDurationRatio = finalWidth / widthMax
                    let finalDuration = finalDurationRatio * totalDuration
                    let finalEndTime = min(finalStartTime + finalDuration, totalDuration)
                    
                    // Проверка минимальной длительности
                    let adjustedStartTime = min(finalStartTime, finalEndTime - 0.5)
                    
                    timelineData.updateStampTime(
                        lineID: line.id,
                        stampID: stampID,
                        newStart: adjustedStartTime
                    )
                    onTagDragging(nil)
                }
                resizingStampID = nil
                resizingEdge = nil
                visualWidth = nil
                visualOffsetX = nil
            }
    }

    
    private func rightEdgeDragGesture(stamp: TimelineStamp, totalDuration: Double, widthMax: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizingStampID != stamp.id {
                    resizingStampID = stamp.id
                    resizingEdge = .right
                    originalStartTime = stamp.timeStartSeconds
                    originalEndTime = stamp.timeFinishSeconds
                    dragStartTime = originalStartTime
                    
                    let baseStartRatio = originalStartTime / totalDuration
                    visualOffsetX = baseStartRatio * widthMax
                    
                    // Запомнить исходную ширину в пикселях
                    let baseDuration = originalEndTime - originalStartTime
                    let baseDurationRatio = baseDuration / totalDuration
                    visualWidth = max(baseDurationRatio * widthMax, 10)
                }
                
                // Меняем ширину напрямую на deltaX
                let baseWidth = visualWidth ?? 0
                let newWidth = max(baseWidth + value.translation.width, 10) // минимум 10px
                if let visualOffsetX, visualOffsetX + newWidth > widthMax {
                    return
                }
                visualWidth = newWidth
                
                let time = originalStartTime + ((visualWidth ?? 0) / widthMax) * totalDuration
                onTagDragging(time / totalDuration * widthMax)
                videoManager.seek(to: time)
            }
            .onEnded { _ in
                if let stampID = resizingStampID,
                   let finalWidth = visualWidth,
                   resizingEdge == .right {
                    
                    // Пересчитываем ширину обратно во время
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
            ForEach(stamp.labels, id: \.self) { labelID in
                if let label = tagLibrary.findLabelById(labelID) {
                    if let group = tagLibrary.allLabelGroups.first(where: { $0.lables.contains(label.id) }) {
                        Text("\(label.name) (\(group.name))")
                    } else {
                        Text(label.name)
                    }
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
        Button(^String.Titles.timelineButtonDeleteTag) {
            TimelineDataManager.shared.removeStamp(lineID: line.id, stampID: stamp.id)
            if timelineData.selectedStampID == stamp.id {
                timelineData.selectStamp(stampID: nil)
            }
        }
        Button(^String.Titles.timelineButtonEditLabels) {
            onEditLabelsRequest(stamp.id)
        }
    }
    
    private func transferStamp(_ stampInfo: StampDragInfo, to destLineID: UUID) {
        guard let sourceLineIndex = timelineData.lines.firstIndex(where: { $0.id == stampInfo.lineID }),
              let destLineIndex = timelineData.lines.firstIndex(where: { $0.id == destLineID }),
              let stampIndex = timelineData.lines[sourceLineIndex].stamps.firstIndex(where: { $0.id == stampInfo.stampID }) else {
            return
        }
        
//        if stampInfo.lineID == destLineID {
//            return
//        }
        
        let stamp = timelineData.lines[sourceLineIndex].stamps[stampIndex]
        
        let newStamp = TimelineStamp(
            id: UUID(),
            idTag: stamp.idTag,
            primaryID: stamp.primaryID,
            timeStartSeconds: stampInfo.startSecond,
            timeFinishSeconds: stampInfo.endSecond,
            colorHex: stamp.colorHex,
            label: stamp.label,
            labels: stamp.labels,
            timeEvents: stamp.timeEvents,
            position: stamp.position
        )
        
        timelineData.lines[destLineIndex].stamps.append(newStamp)
        timelineData.lines[sourceLineIndex].stamps.remove(at: stampIndex)
        timelineData.updateTimelines()
    }
    
    private func clampedCenterX(isDragging: Bool, stampX: CGFloat, stampWidth: CGFloat) -> CGFloat {
        let dragX = isDragging ? dragOffset : .zero
        
        let baseCenterX = stampX + stampWidth / 2
        var centerX = baseCenterX + dragX.width

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
