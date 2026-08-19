//
//  ReviewPlayheadView.swift
//  Youchip-Stat
//
//  Второй плейхэд (бирюзовый) поверх таймлайнов — показывает позицию ПЕРЕСМОТРА в лайве, пока
//  основной (белый) плейхэд держит позицию живой записи.
//
//  Функционально это полноценный плейхед, а не индикатор: его можно хватать и тянуть (с
//  edge-scroll'ом у краёв вьюпорта), при перетаскивании идёт превью-seek видео пересмотра, а
//  «голова»-треугольник живёт в закреплённой шапке таймлайнов (`PinnedTimelineRulerView`) — ровно
//  как у основного плейхеда. Здесь — стебель и его зона захвата.
//
//  Живёт своими часами `ReviewPlaybackClock`, чтобы тик пересмотра не перестраивал остальной
//  таймлайн (тот же приём, что у основного плейхеда с `PlaybackClock`).
//

import AppKit
import SwiftUI

/// Бирюзовый — в тон стрелки связки stateSync и общей «пересмотровой» акцентировки.
/// Один источник цвета на стебель (здесь) и «голову» в закреплённой шапке.
let reviewPlayheadTint = Color(red: 0.00, green: 0.70, blue: 0.75)

struct ReviewPlayheadView: View {

    /// Тот же контроллер, что и у «головы» в шапке, — чтобы тянуть можно было за любую часть.
    /// Отдельный экземпляр от основного плейхеда: два плейхеда тянутся независимо.
    @ObservedObject var dragController: PlayheadEdgeScrollController
    @ObservedObject private var clock = ReviewPlaybackClock.shared
    let scrollController: TimelineScrollController
    let gridWidth: CGFloat
    let duration: Double

    private let hitWidth: CGFloat = 16
    /// Высота зоны захвата при зажатом Cmd — только верх стебля, ниже клики уходят к тегам
    /// (мультивыбор Cmd+ЛКМ). Логика повторяет основной плейхед.
    private let grabHitHeight: CGFloat = 22
    @State private var lastScrubPreviewAt = Date.distantPast
    private let scrubPreviewMinInterval: TimeInterval = 0.033
    @State private var wasPlayingBeforeDrag = false
    @State private var isCommandHeld = false
    @State private var flagsMonitor: Any?

    private var timeOffsetToPixels: CGFloat {
        guard duration > 0 else { return 0 }
        return (clock.time / duration) * gridWidth
    }

    /// Во время перетаскивания позиция берётся из контроллера (и прижимается к вьюпорту),
    /// иначе — из часов пересмотра.
    private var displayX: CGFloat {
        guard dragController.isDragging else { return timeOffsetToPixels }
        let raw = dragController.dragX
        let lo = scrollController.currentScrollX
        let hi = lo + scrollController.visibleWidth - 2
        return max(lo, min(raw, hi))
    }

    var body: some View {
        PlayheadStemWithGrabHead(stemWidth: 2, headBaseWidth: 12, compact: false, tint: reviewPlayheadTint)
            .frame(width: hitWidth)
            .allowsHitTesting(false)
            .overlay(alignment: .top) {
                Color.clear
                    .frame(width: hitWidth)
                    .frame(maxHeight: isCommandHeld ? grabHitHeight : .infinity, alignment: .top)
                    .contentShape(Rectangle())
                    .onHover { isHovering in
                        NSCursor.setHiddenUntilMouseMoves(false)
                        if isHovering { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
                    }
                    .gesture(dragGesture)
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("timelineSpace"))
            .onChanged { value in
                ReviewPlayheadDrag.onChanged(
                    contentX: value.location.x,
                    gridWidth: gridWidth,
                    duration: duration,
                    dragController: dragController,
                    scrollController: scrollController,
                    lastScrubPreviewAt: $lastScrubPreviewAt,
                    minInterval: scrubPreviewMinInterval,
                    wasPlaying: $wasPlayingBeforeDrag
                )
            }
            .onEnded { _ in
                ReviewPlayheadDrag.onEnded(
                    dragController: dragController,
                    lastScrubPreviewAt: $lastScrubPreviewAt,
                    wasPlaying: $wasPlayingBeforeDrag
                )
            }
    }
}

/// Общая механика перетаскивания бирюзового плейхеда: одна и та же для стебля (в скролле) и
/// «головы» (в закреплённой шапке) — как у основного плейхеда, только seek'и уходят в
/// review-плеер.
enum ReviewPlayheadDrag {

    static func onChanged(
        contentX: CGFloat,
        gridWidth: CGFloat,
        duration: Double,
        dragController: PlayheadEdgeScrollController,
        scrollController: TimelineScrollController,
        lastScrubPreviewAt: Binding<Date>,
        minInterval: TimeInterval,
        wasPlaying: Binding<Bool>
    ) {
        scrollController.stopAutoScrollFollow()
        if dragController.isDragging {
            dragController.updateDrag(
                at: contentX, gridWidth: gridWidth, duration: duration, scrollController: scrollController
            )
        } else {
            lastScrubPreviewAt.wrappedValue = .distantPast
            let vm = VideoPlayerManager.shared
            wasPlaying.wrappedValue = vm.reviewPlayer?.timeControlStatus == .playing
            if wasPlaying.wrappedValue { vm.reviewPlayer?.pause() }
            dragController.beginDrag(
                at: contentX, gridWidth: gridWidth, duration: duration, scrollController: scrollController
            )
        }
        let now = Date()
        guard duration > 0, gridWidth > 0,
              now.timeIntervalSince(lastScrubPreviewAt.wrappedValue) >= minInterval else { return }
        lastScrubPreviewAt.wrappedValue = now
        let lo = scrollController.currentScrollX
        let hi = lo + scrollController.visibleWidth - 2
        let x = max(lo, min(dragController.dragX, hi))
        let t = Double(x / gridWidth) * duration
        VideoPlayerManager.shared.seekReviewForTimelineScrubPreview(to: t)
    }

    static func onEnded(
        dragController: PlayheadEdgeScrollController,
        lastScrubPreviewAt: Binding<Date>,
        wasPlaying: Binding<Bool>
    ) {
        let time = dragController.endDrag()
        let resume = wasPlaying.wrappedValue
        wasPlaying.wrappedValue = false
        lastScrubPreviewAt.wrappedValue = .distantPast
        VideoPlayerManager.shared.seekReview(to: time, resumePlaybackAfterSeek: resume)
    }
}
