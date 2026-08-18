//
//  PinnedTimelineRulerView.swift
//  Youchip-Stat
//
//  Закреплённая сверху линейка времени с «головой»-треугольником плейхеда. Синхронно едет за
//  таймлайнами по горизонтали (через `TimelineScrollController.liveScrollX`). Вынесена в отдельный
//  View, чтобы частые ре-рендеры (скролл + плейхед) не тянули за собой перерисовку FullControlView.
//

import SwiftUI
import AppKit

struct PinnedTimelineRulerView: View {

    @ObservedObject var controller: TimelineScrollController
    /// Без `@ObservedObject`: менеджер нужен только для вызова `seek`, а подписка на него
    /// затягивала шапку в перерисовку на каждое изменение любого его свойства. Время берём из
    /// `PlaybackClock` — см. [[PlaybackClock]].
    let videoManager: VideoPlayerManager
    @ObservedObject private var clock = PlaybackClock.shared
    /// Контроллер перетаскивания плейхеда — тот же, что и у стебля в скролле, чтобы «голову» в
    /// закреплённой шапке можно было хватать и тянуть (раньше шапка перекрывала стебель и хват пропадал).
    @ObservedObject var dragController: PlayheadEdgeScrollController
    let duration: Double
    let gridWidth: CGFloat
    let interval: Double
    let viewportWidth: CGFloat
    /// Верхняя полоса (под «головы» меток рисунков) — линейка идёт под ней.
    let band: CGFloat
    /// Высота таймлайнов (для позиционирования меток рисунков; стебли обрезаются по шапке).
    let markersTotalHeight: CGFloat
    /// Проброс наружу: лист «привязанные теги» открывает окно, а не сама вьюха меток —
    /// иначе хостов листа было бы столько, сколько экземпляров `ScreenshotMarkersView`.
    var onEditScreenshotTags: (ScreenshotMetadata) -> Void = { _ in }

    private let hitWidth: CGFloat = 16
    @State private var lastScrubVideoPreviewAt = Date.distantPast
    private let scrubVideoPreviewMinInterval: TimeInterval = 0.033
    @State private var wasPlayingBeforePlayheadDrag = false

    /// Экранная (во вьюпорте шапки) X плейхеда с учётом горизонтального скролла.
    private var playheadViewportX: CGFloat {
        let offsetX = -controller.liveScrollX
        let base = duration > 0 ? (clock.time / duration) * gridWidth : 0
        // Во время перетаскивания показываем позицию из dragController (в координатах контента).
        let contentX = dragController.isDragging ? dragController.dragX : base
        return contentX + offsetX
    }

    var body: some View {
        let offsetX = -controller.liveScrollX
        let playheadX = duration > 0 ? (clock.time / duration) * gridWidth : 0

        ZStack(alignment: .topLeading) {
            TimelineTimestampsHeaderView(duration: duration, interval: interval, width: gridWidth)
                .frame(width: gridWidth, height: 30, alignment: .leading)
                .timelineTapToSeek(gridWidth: gridWidth, duration: duration) { time in
                    videoManager.seek(to: time)
                }
                .offset(x: offsetX, y: band)

            // «Голова» плейхеда (треугольник) — только индикатор; хват — прозрачная зона ниже.
            PlayheadStemWithGrabHead(stemWidth: 2, headBaseWidth: 12, compact: false)
                .frame(width: hitWidth, height: band + 30)
                .offset(x: (dragController.isDragging ? dragController.dragX + offsetX : playheadX + offsetX) - 7, y: 0)
                .allowsHitTesting(false)

            // Прозрачная зона захвата плейхеда в шапке. Тянет тот же dragController, что и стебель
            // в скролле, — поэтому голову теперь можно хватать прямо в закреплённой линейке.
            Color.clear
                .frame(width: hitWidth, height: band + 30)
                .contentShape(Rectangle())
                .offset(x: playheadViewportX - hitWidth / 2, y: 0)
                .onHover { hovering in
                    NSCursor.setHiddenUntilMouseMoves(false)
                    if hovering { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
                }
                .gesture(playheadDragGesture)
                .zIndex(1)

            // «Головы» меток рисунков (кликабельны — возврат к рисунку) закреплены в шапке-баре.
            // Стебли рисуются отдельно в скролле (на всю высоту дорожек) — см. timelineZStackContent.
            ScreenshotMarkersView(
                duration: duration,
                gridWidth: gridWidth,
                totalHeight: markersTotalHeight,
                headLift: 0,
                part: .headsOnly,
                onEditRelatedTags: onEditScreenshotTags
            )
            .frame(width: gridWidth, height: band + 30, alignment: .topLeading)
            .offset(x: offsetX)
            .zIndex(3)
        }
        .frame(width: viewportWidth, height: band + 30, alignment: .topLeading)
        .coordinateSpace(name: "pinnedRuler")
        .clipped()
    }

    /// Перетаскивание плейхеда в закреплённой шапке. Координаты — во вьюпорте шапки; переводим их
    /// в координаты контента таймлайна (+ горизонтальный скролл) и кормим тем же dragController.
    private var playheadDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("pinnedRuler"))
            .onChanged { value in
                let contentX = value.location.x + controller.currentScrollX
                controller.stopAutoScrollFollow()
                if dragController.isDragging {
                    dragController.updateDrag(
                        at: contentX, gridWidth: gridWidth, duration: duration, scrollController: controller
                    )
                } else {
                    lastScrubVideoPreviewAt = .distantPast
                    let vm = VideoPlayerManager.shared
                    wasPlayingBeforePlayheadDrag = vm.player?.timeControlStatus == .playing
                    if wasPlayingBeforePlayheadDrag { vm.player?.pause() }
                    dragController.beginDrag(
                        at: contentX, gridWidth: gridWidth, duration: duration, scrollController: controller
                    )
                }
                let now = Date()
                guard duration > 0, gridWidth > 0,
                      now.timeIntervalSince(lastScrubVideoPreviewAt) >= scrubVideoPreviewMinInterval else { return }
                lastScrubVideoPreviewAt = now
                let lo = controller.currentScrollX
                let hi = lo + controller.visibleWidth - 2
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
