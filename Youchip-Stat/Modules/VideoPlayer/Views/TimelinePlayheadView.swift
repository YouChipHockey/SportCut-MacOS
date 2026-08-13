//
//  TimelinePlayheadView.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 19.04.2026.
//

import AppKit
import SwiftUI

// Isolated view that owns the playhead rendering and drag gesture.
// By keeping all reads of PlayheadEdgeScrollController's @Published properties
// inside this struct, FullControlView is excluded from the 60 Hz re-render loop
// that the edge-scroll timer drives during interactive playhead drag.
//
// Время плейхед берёт сам, из `PlaybackClock` — раньше позиция приходила параметром
// `timeOffsetToPixels`, который FullControlView считал в своём body из `videoManager.currentTime`.
// Из-за этого вся изоляция была бесполезной: FullControlView всё равно перестраивался 30 Гц
// вместе со всеми дорожками. Не возвращай чтение времени в родителя.
struct TimelinePlayheadView: View {

    @ObservedObject var dragController: PlayheadEdgeScrollController
    @ObservedObject private var clock = PlaybackClock.shared
    let scrollController: TimelineScrollController
    let tagEdgePosition: CGFloat?
    let gridWidth: CGFloat
    let duration: Double
    let isResizingTag: Bool

    /// Позиция плейхеда по времени воспроизведения, в координатах контента таймлайна.
    private var timeOffsetToPixels: CGFloat {
        guard duration > 0 else { return 0 }
        return (clock.time / duration) * gridWidth
    }

    private let hitWidth: CGFloat = 16
    /// Высота зоны захвата, когда зажат Cmd — только верхняя «ручка»-треугольник. Ниже (по стеблю)
    /// клики проходят сквозь плейхед к тегам, чтобы стебель не мешал выбирать теги Cmd+ЛКМ.
    /// Без Cmd плейхед тянется по всей высоте (как раньше).
    private let grabHitHeight: CGFloat = 22
    @State private var lastScrubVideoPreviewAt = Date.distantPast
    private let scrubVideoPreviewMinInterval: TimeInterval = 0.033
    @State private var wasPlayingBeforePlayheadDrag = false
    /// Зажат ли сейчас Cmd (для мультивыбора тегов). Отслеживается монитором `.flagsChanged`.
    @State private var isCommandHeld = false
    @State private var flagsMonitor: Any?

    // The position at which the playhead (stem tip) is drawn.
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
        // Визуал плейхеда (треугольник + стебель) кликов НЕ перехватывает — иначе стебель по всей
        // высоте мешает выбирать теги. Перетаскивание/курсор — только на верхней зоне-«ручке».
        PlayheadStemWithGrabHead(stemWidth: 2, headBaseWidth: 12, compact: false)
            .frame(width: hitWidth)
            .allowsHitTesting(false)
            .overlay(alignment: .top) {
                // Зажат Cmd → зона захвата только у треугольника (стебель пропускает клики к тегам).
                // Cmd не зажат → плейхед тянется по всей высоте, как раньше.
                Color.clear
                    .frame(width: hitWidth)
                    .frame(maxHeight: isCommandHeld ? grabHitHeight : .infinity, alignment: .top)
                    .contentShape(Rectangle())
                    .onHover { isHovering in
                        NSCursor.setHiddenUntilMouseMoves(false)
                        if isHovering { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
                    }
                    .gesture(playheadDragGesture)
            }
            .offset(x: displayX - (hitWidth / 2 - 1))
            .onAppear { installCommandMonitor() }
            .onDisappear { removeCommandMonitor() }
    }

    private func installCommandMonitor() {
        guard flagsMonitor == nil else { return }
        isCommandHeld = NSEvent.modifierFlags.contains(.command)
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let held = event.modifierFlags.contains(.command)
            DispatchQueue.main.async { isCommandHeld = held }
            return event
        }
    }

    private func removeCommandMonitor() {
        if let m = flagsMonitor {
            NSEvent.removeMonitor(m)
            flagsMonitor = nil
        }
    }

    private var playheadDragGesture: some Gesture {
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
                            lastScrubVideoPreviewAt = .distantPast
                            let vm = VideoPlayerManager.shared
                            wasPlayingBeforePlayheadDrag = vm.player?.timeControlStatus == .playing
                            if wasPlayingBeforePlayheadDrag {
                                vm.player?.pause()
                            }
                            dragController.beginDrag(
                                at: value.location.x,
                                gridWidth: gridWidth,
                                duration: duration,
                                scrollController: scrollController
                            )
                        }
                        let now = Date()
                        guard duration > 0, gridWidth > 0,
                              now.timeIntervalSince(lastScrubVideoPreviewAt) >= scrubVideoPreviewMinInterval else { return }
                        lastScrubVideoPreviewAt = now
                        let lo = scrollController.currentScrollX
                        let hi = lo + scrollController.visibleWidth - 2
                        let x = max(lo, min(dragController.dragX, hi))
                        let t = Double(x / gridWidth) * duration
                        VideoPlayerManager.shared.seekForTimelineScrubPreview(to: t)
                    }
                    .onEnded { _ in
                        let time = dragController.endDrag()
                        let resume = wasPlayingBeforePlayheadDrag
                        wasPlayingBeforePlayheadDrag = false
                        lastScrubVideoPreviewAt = .distantPast
                        VideoPlayerManager.shared.seek(to: time, resumePlaybackAfterSeek: resume)
                    }
    }

}
