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
    @State private var isResizing = false
    @State private var resizingSide: ResizingSide = .none
    @State private var initialDragLocation: CGPoint = .zero
    @State private var initialStartTime: Double = 0
    @State private var initialEndTime: Double = 0
    @Binding var scrollOffset: CGFloat
    
    enum ResizingSide {
        case left, right, none
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
                    Rectangle()
                        .fill(isDraggingOver ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        .frame(width: widthMax, height: 30)
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
                        let startRatio = stamp.startSeconds / totalDuration
                        let durationRatio = stamp.duration / totalDuration
                        
                        let stampWidth = durationRatio * widthMax
                        let stampX = startRatio * widthMax
                        
                        let isSelected = timelineData.selectedStampID == stamp.id
                        let overlapCount = getOverlapCount(stamp: stamp, stamps: line.stamps, stampIndex: index)
                        let hasOverlaps = overlapCount > 0
                        
                        let borderColor = (hasOverlaps && !isSelected) ? Color.red :
                        (isSelected && hasOverlaps) ? Color.red :
                        (isSelected) ? Color.blue : Color.clear
                        let heightReduction = CGFloat(overlapCount * 6)
                        let stampHeight: CGFloat = 30 - heightReduction
                        let verticalOffset = (30 - stampHeight) / 2
                        
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(stamp.color)
                                .frame(height: stampHeight)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
                                )
                            StampLabelsOverlayView(
                                stamp: stamp,
                                maxWidth: stampWidth,
                                isResizing: isResizing
                            )
                            .frame(height: stampHeight)
                        }
                        .frame(width: stampWidth, height: stampHeight)
                        .position(x: stampX + stampWidth / 2, y: 15)
                        .onTapGesture {
                            videoManager.seek(to: stamp.startSeconds)
                            timelineData.selectStamp(stampID: stamp.id)
                        }
                        .onDrag {
                            let stampInfo = StampDragInfo(
                                lineID: line.id,
                                stampID: stamp.id
                            )
                            if let data = try? JSONEncoder().encode(stampInfo) {
                                return NSItemProvider(item: data as NSData, typeIdentifier: UTType.plainText.identifier)
                            }
                            return NSItemProvider()
                        }
                        .contextMenu {
                            menuForTag(stamp: stamp)
                        }
                    }
                }
            }
            .frame(width: widthMax, height: 30)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        scrollOffset = value.translation.width
                    }
            )
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
