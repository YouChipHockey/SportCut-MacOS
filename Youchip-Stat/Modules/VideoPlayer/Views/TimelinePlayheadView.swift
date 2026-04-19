//
//  TimelinePlayheadView.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 19.04.2026.
//

import SwiftUI

// Isolated view that owns the playhead rendering and drag gesture.
// By keeping all reads of PlayheadEdgeScrollController's @Published properties
// inside this struct, FullControlView is excluded from the 60 Hz re-render loop
// that the edge-scroll timer drives during interactive playhead drag.
struct TimelinePlayheadView: View {

    @ObservedObject var dragController: PlayheadEdgeScrollController
    let scrollController: TimelineScrollController
    let timeOffsetToPixels: CGFloat
    let tagEdgePosition: CGFloat?
    let gridWidth: CGFloat
    let duration: Double
    let isResizingTag: Bool

    private let hitWidth: CGFloat = 16

    // The position at which the red line is drawn.
    // Stamp-edge drag takes priority, then interactive playhead drag (clamped
    // to the visible viewport), then the live playback position.
    private var displayX: CGFloat {
        if let tagPos = tagEdgePosition { return tagPos }
        guard dragController.isDragging else { return timeOffsetToPixels }
        let raw = dragController.dragX
        let lo  = scrollController.currentScrollX
        let hi  = lo + scrollController.visibleWidth - 2
        return max(lo, min(raw, hi))
    }

    var body: some View {
        Color.clear
            .frame(width: hitWidth)
            .overlay(Rectangle().fill(Color.red).frame(width: 2))
            .contentShape(Rectangle())
            .offset(x: displayX - (hitWidth / 2 - 1))
            .onHover { isHovering in
                NSCursor.setHiddenUntilMouseMoves(false)
                if isHovering { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("timelineSpace"))
                    .onChanged { value in
                        guard tagEdgePosition == nil, !isResizingTag else { return }
                        scrollController.stopAutoScrollFollow()
                        if dragController.isDragging {
                            dragController.updateDrag(
                                at: value.location.x,
                                gridWidth: gridWidth,
                                duration: duration,
                                scrollController: scrollController
                            )
                        } else {
                            dragController.beginDrag(
                                at: value.location.x,
                                gridWidth: gridWidth,
                                duration: duration,
                                scrollController: scrollController
                            )
                        }
                    }
                    .onEnded { _ in
                        let time = dragController.endDrag()
                        VideoPlayerManager.shared.seek(to: time)
                    }
            )
    }

}
