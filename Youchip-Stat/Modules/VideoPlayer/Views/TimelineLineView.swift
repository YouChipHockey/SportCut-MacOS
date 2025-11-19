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
    
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @State private var isDraggingOver = false
    @Binding var scrollOffset: CGFloat
    
    // State for edge resizing
    @State private var resizingStampID: UUID? = nil
    @State private var resizingEdge: ResizeEdge? = nil
    @State private var dragStartTime: Double = 0
    @State private var originalStartTime: Double = 0
    @State private var originalEndTime: Double = 0
    
    enum ResizeEdge {
        case left
        case right
    }
    
    private func getOverlapCount(stamp: TimelineStamp, stamps: [TimelineStamp], stampIndex: Int) -> Int {
        var count = 0
        
        for i in 0..<stampIndex {
            let olderStamp = stamps[i]
            
            let stampStart = stamp.startSeconds
            let stampEnd = stamp.finishSeconds
            let olderStart = olderStamp.startSeconds
            let olderEnd = olderStamp.finishSeconds
            
            if stampStart < olderEnd && olderStart < stampEnd {
                count += 1
            }
        }
        
        return count
    }
    
    var body: some View {
        GeometryReader { geometry in
            
            
            let baseWidth = geometry.size.width
            let totalDuration = max(1, videoManager.videoDuration)
            let computedWidth = baseWidth * max(scale, 1.0)
            
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
                    .frame(width: widthMax, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(
                                isDraggingOver ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2),
                                lineWidth: 0.5
                            )
                    )
                    .onDrop(
                        of: [.init(UTType.plainText.identifier)],
                        isTargeted: $isDraggingOver
                    ) { providers, _ in
                        if let provider = providers.first {
                            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { (data, error) in
                                if let stampData = data as? Data,
                                   let stampInfo = try? JSONDecoder().decode(StampDragInfo.self, from: stampData) {
                                    DispatchQueue.main.async {
                                        transferStamp(stampInfo, to: line.id)
                                    }
                                }
                            }
                            return true
                        }
                        return false
                    }
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
        let currentStartTime = isResizing && resizingEdge == .left ? dragStartTime : stamp.startSeconds
        let currentEndTime = isResizing && resizingEdge == .right ? dragStartTime : stamp.finishSeconds
        let currentDuration = currentEndTime - currentStartTime
        
        let startRatio = currentStartTime / totalDuration
        let durationRatio = currentDuration / totalDuration
        
        let stampWidth = max(durationRatio * widthMax, 10) // Minimum width
        let stampX = startRatio * widthMax
        
        let isSelected = timelineData.selectedStampID == stamp.id
        let overlapCount = getOverlapCount(stamp: stamp, stamps: line.stamps, stampIndex: index)
        let hasOverlaps = overlapCount > 0
        
        let borderColor = (hasOverlaps && !isSelected) ? Color.red :
        (isSelected && hasOverlaps) ? Color.red :
        (isSelected) ? Color.blue : Color.clear
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
        .frame(width: stampWidth, height: stampHeight)
        .position(x: stampX + stampWidth / 2, y: 15)
        .onTapGesture {
            if resizingStampID == nil {
                withAnimation(.easeInOut(duration: 0.2)) {
                    videoManager.seek(to: stamp.startSeconds)
                    timelineData.selectStamp(stampID: stamp.id)
                    videoManager.player?.play()
                }
            }
        }
        .onDrag {
            if resizingStampID == nil {
                let stampInfo = StampDragInfo(
                    lineID: line.id,
                    stampID: stamp.id
                )
                if let data = try? JSONEncoder().encode(stampInfo) {
                    return NSItemProvider(item: data as NSData, typeIdentifier: UTType.plainText.identifier)
                }
            }
            return NSItemProvider()
        }
        .contextMenu {
            menuForTag(stamp: stamp)
        }
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
                    originalStartTime = stamp.startSeconds
                    originalEndTime = stamp.finishSeconds
                }
                
                let deltaX = value.translation.width
                let deltaTime = (deltaX / widthMax) * totalDuration
                let newStartTime = max(0, min(originalStartTime + deltaTime, originalEndTime - 0.5))
                dragStartTime = newStartTime
            }
            .onEnded { _ in
                if let stampID = resizingStampID, resizingEdge == .left {
                    let finalStartTime = dragStartTime
                    timelineData.updateStampTime(
                        lineID: line.id,
                        stampID: stampID,
                        newStart: finalStartTime
                    )
                }
                resizingStampID = nil
                resizingEdge = nil
            }
    }
    
    private func rightEdgeDragGesture(stamp: TimelineStamp, totalDuration: Double, widthMax: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizingStampID != stamp.id {
                    resizingStampID = stamp.id
                    resizingEdge = .right
                    originalStartTime = stamp.startSeconds
                    originalEndTime = stamp.finishSeconds
                }
                
                let deltaX = value.translation.width
                let deltaTime = (deltaX / widthMax) * totalDuration
                let newEndTime = max(originalStartTime + 0.5, min(originalEndTime + deltaTime, totalDuration))
                dragStartTime = newEndTime
            }
            .onEnded { _ in
                if let stampID = resizingStampID, resizingEdge == .right {
                    let finalEndTime = dragStartTime
                    timelineData.updateStampTime(
                        lineID: line.id,
                        stampID: stampID,
                        newEnd: finalEndTime
                    )
                }
                resizingStampID = nil
                resizingEdge = nil
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
        
        if stampInfo.lineID == destLineID {
            return
        }
        
        let stamp = timelineData.lines[sourceLineIndex].stamps[stampIndex]
        
        let newStamp = TimelineStamp(
            id: UUID(),
            idTag: stamp.idTag,
            primaryID: stamp.primaryID,
            timeStart: stamp.timeStart,
            timeFinish: stamp.timeFinish,
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
