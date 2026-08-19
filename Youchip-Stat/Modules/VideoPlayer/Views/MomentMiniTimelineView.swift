//
//  MomentMiniTimelineView.swift
//  Youchip-Stat
//
//  Мини-таймлайн окна «Момент»: та же модель зума, что и разметка SportCut
//  (`timelineScale` 1…max, шаг сетки как `sportCutMarkupTimeGridInterval`),
//  сетка через TimeGridView; подписи — фиксированный шаг по пикселям (без наложения).
//

import SwiftUI
import AppKit

/// Как `SportCutTimelineView.sportCutTimelineMaxScale`.
private let momentMiniTimelineMaxScale: CGFloat = 40

struct MomentMiniTimelineView: View {

    @ObservedObject var session: MomentViewerSession
    let stamp: TimelineStamp?
    let lineID: UUID?
    let stampID: UUID?
    @Binding var timelineScale: CGFloat
    /// Счётчик из родителя при каждом показе окна «Момент» — повторно применяем 25% и центрирование.
    let layoutEpoch: Int

    @ObservedObject private var timelineData = TimelineDataManager.shared

    @StateObject private var scrollController = TimelineScrollController()
    @StateObject private var dragState = MomentMiniTimelineDragState()

    /// Живой масштаб пинч-жеста. Не `@GestureState`: зум ловится AppKit-монитором,
    /// чтобы работать и в неактивном окне (см. `onFirstMouseMagnify`).
    @State private var magnifyScale: CGFloat = 1.0
    /// Последний `layoutEpoch`, для которого уже выставили стартовый масштаб (при появлении `stamp`).
    @State private var lastAppliedInitialLayoutEpoch: Int?

    private enum DragMode {
        case idle
        case seekTrack
        case resizeLeft
        case resizeRight
    }

    @State private var dragMode: DragMode = .idle

    private let handleHitSlop: CGFloat = 14
    /// Доля видимой ширины таймлайна, которую изначально занимает тег (~25%).
    private let initialTagWidthFractionOfViewport: CGFloat = 0.25
    /// Отступ от края viewport, на котором край тега замораживается во время edge-scroll.
    private let resizeEdgeFreezeOffset: CGFloat = 14
    /// Ширина зоны у края, в которой активируется edge-scroll (больше freeze-offset).
    private let resizeEdgeScrollZone: CGFloat = 40
    /// Максимальный шаг скролла за одно drag-событие (pts).
    private let resizeEdgeScrollMaxStep: CGFloat = 14
    /// Ограничиваем частоту preview при resize (~15 fps).
    private let resizePreviewThrottle: TimeInterval = 0.067
    /// Throttle визуального обновления края во время resize (~60 fps).
    private let resizeVisualThrottle: TimeInterval = 0.016
    /// Throttle seek при scrub-drag (~30 fps).
    private let seekTrackThrottle: TimeInterval = 0.033
    @State private var lastResizePreviewAt = Date.distantPast
    @State private var lastResizeVisualAt = Date.distantPast
    @State private var lastSeekTrackAt = Date.distantPast
    /// Локальное время композиции под пальцем при scrub трека (мини-плейхэд без ожидания seek).
    @State private var seekTrackVisualComposition: Double?
    /// Замороженное время края тега пока курсор в edge-зоне.
    @State private var resizeLockedTime: Double? = nil
    /// Ширина полосы из `GeometryReader` — нужна для пересчёта viewport при зуме/перецентровке.
    @State private var lastLayoutFullWidth: CGFloat = 1
    @State private var lastTimelineScaleForScrollSync: CGFloat = 1.0
    /// Для медленных машин: после первой стабильной ширины делаем дополнительный re-center.
    @State private var didStabilizeInitialWidthCentering = false

    private var canResize: Bool {
        lineID != nil && stampID != nil && stamp != nil
    }

    private var baseTagStart: Double { stamp?.timeStartSeconds ?? session.displayStartTime }
    private var baseTagEnd: Double { stamp?.timeFinishSeconds ?? (baseTagStart + session.displayDuration) }
    private var tagStart: Double { dragState.previewStart ?? baseTagStart }
    private var tagEnd: Double { dragState.previewEnd ?? baseTagEnd }
    private var tagDuration: Double { max(tagEnd - tagStart, 0.000_001) }

    /// Ось времени мини-таймлайна — только длина исходника (не раздуваем при preview ресайза, иначе разъезжается маппинг и сетка).
    private var timelineMappingDuration: Double {
        max(session.sourceAssetDuration, 0.000_001)
    }

    private var clampedTagStart: Double {
        min(max(tagStart, 0), timelineMappingDuration)
    }
    private var clampedTagEnd: Double {
        min(max(tagEnd, clampedTagStart + 0.000_001), timelineMappingDuration)
    }
    private var tagCenter: Double { (clampedTagStart + clampedTagEnd) * 0.5 }

    /// Как `SportCutTimelineView.sportCutMarkupTimeGridInterval`.
    private func sportCutMarkupTimeGridInterval(scale: CGFloat, totalDuration: Double) -> Double {
        let baseCount = 20 * max(scale, 1.0)
        let baseInterval = totalDuration / baseCount
        return max(0.5, baseInterval)
    }

    /// Ширина полосы: `viewport * scale` — тег в пикселях растёт пропорционально `timelineScale`.
    private func contentWidth(viewportWidth: CGFloat, effectiveScale: CGFloat) -> CGFloat {
        let w = max(viewportWidth, 1)
        return w * max(effectiveScale, 1.0)
    }

    private func worldX(time: Double, contentW: CGFloat) -> CGFloat {
        CGFloat(time / timelineMappingDuration) * contentW
    }

    private func timeAtWorldX(_ x: CGFloat, contentW: CGFloat) -> Double {
        min(max(0, Double(x / max(contentW, 1)) * timelineMappingDuration), timelineMappingDuration)
    }

    private var stampColor: Color {
        stamp?.color ?? Color.accentColor
    }

    var body: some View {
        GeometryReader { outerGeo in
            let W = max(outerGeo.size.width, 1)
            let trackHeight: CGFloat = 36
            let labelRowHeight: CGFloat = 30
            let height = max(outerGeo.size.height, trackHeight + labelRowHeight)
            let wFull = max(W, 1)
            let effectiveScale = timelineScale * magnifyScale
            let provisionalContentW = contentWidth(viewportWidth: wFull, effectiveScale: effectiveScale)
            let needsScroll = provisionalContentW > wFull + 0.5
            let chevronSlot: CGFloat = 28
            let reserveChevronSlots = needsScroll
            let scrollViewport: CGFloat = reserveChevronSlots
                ? max(wFull - 2 * chevronSlot - 8, 48)
                : wFull
            let contentW = contentWidth(viewportWidth: scrollViewport, effectiveScale: effectiveScale)
            let scrollable = contentW > scrollViewport + 0.5
            let gridInterval = sportCutMarkupTimeGridInterval(scale: effectiveScale, totalDuration: timelineMappingDuration)

            ScrollViewReader { proxy in
                HStack(spacing: 4) {
                    Group {
                        if reserveChevronSlots {
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo("miniTagLead", anchor: .leading)
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.borderless)
                            .help(^String.Titles.momentScrollLeftHelp)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: reserveChevronSlots ? chevronSlot : 0)

                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .leading) {
                            stripContent(
                                viewportWidth: scrollViewport,
                                contentWidth: contentW,
                                trackHeight: trackHeight,
                                labelRowHeight: labelRowHeight,
                                totalHeight: height,
                                gridInterval: gridInterval,
                                scrollProxy: proxy,
                                scrollable: scrollable,
                                dragMode: dragMode
                            )
                            .frame(width: contentW, height: height)

                            TimelineScrollControllerAttacher(controller: scrollController)
                                .frame(width: 1, height: 1)
                                .allowsHitTesting(false)
                        }
                        .coordinateSpace(name: "miniWorld")
                    }
                    .frame(height: height)

                    Group {
                        if reserveChevronSlots {
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo("miniTagTrail", anchor: .trailing)
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.borderless)
                            .help(^String.Titles.momentScrollRightHelp)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: reserveChevronSlots ? chevronSlot : 0)
                }
                .onFirstMouseMagnify(
                    onChanged: { magnifyScale = max(1.0, $0) },
                    onEnded: { value in
                        magnifyScale = 1.0
                        finishMagnificationZoom(value: value)
                    }
                )
                .onAppear {
                    lastLayoutFullWidth = max(W, 1)
                    lastTimelineScaleForScrollSync = timelineScale
                    didStabilizeInitialWidthCentering = false
                    applyInitialTimelineScaleIfNeeded()
                    scheduleScrollToTagCenter(proxy: proxy, fullWidth: W)
                }
                .onChange(of: stampID) { _ in
                    lastAppliedInitialLayoutEpoch = nil
                    applyInitialTimelineScaleIfNeeded()
                    scheduleScrollToTagCenter(proxy: proxy, fullWidth: nil)
                }
                .onChange(of: stamp?.id) { _ in
                    lastAppliedInitialLayoutEpoch = nil
                    applyInitialTimelineScaleIfNeeded()
                    scheduleScrollToTagCenter(proxy: proxy, fullWidth: nil)
                }
                .onChange(of: layoutEpoch) { _ in
                    lastAppliedInitialLayoutEpoch = nil
                    applyInitialTimelineScaleIfNeeded()
                    scheduleScrollToTagCenter(proxy: proxy, fullWidth: nil)
                }
                .onChange(of: outerGeo.size.width) { newWidth in
                    lastLayoutFullWidth = max(newWidth, 1)
                    guard !didStabilizeInitialWidthCentering, newWidth > 120 else { return }
                    didStabilizeInitialWidthCentering = true
                    scheduleScrollToTagCenter(proxy: proxy, fullWidth: newWidth)
                }
                .onChange(of: timelineScale) { newValue in
                    handleTimelineScaleChanged(newValue)
                }
            }
        }
    }

    private func scrollViewportFromFullWidth(_ W: CGFloat) -> CGFloat {
        let wFull = max(W, 1)
        let effectiveScale = timelineScale
        let provisionalContentW = contentWidth(viewportWidth: wFull, effectiveScale: effectiveScale)
        let needsScroll = provisionalContentW > wFull + 0.5
        let chevronSlot: CGFloat = 28
        let reserveChevronSlots = needsScroll
        return reserveChevronSlots
            ? max(wFull - 2 * chevronSlot - 8, 48)
            : wFull
    }

    private func handleTimelineScaleChanged(_ newValue: CGFloat) {
        let old = lastTimelineScaleForScrollSync
        lastTimelineScaleForScrollSync = newValue
        guard abs(old - newValue) > 0.001 else { return }
        centerViewportByTagAfterScaleChange(newScale: newValue)
    }

    private func applyInitialTimelineScaleIfNeeded() {
        guard stampID != nil, stamp != nil else { return }
        if lastAppliedInitialLayoutEpoch == layoutEpoch { return }
        lastAppliedInitialLayoutEpoch = layoutEpoch
        let td = max(tagDuration, 0.000_001)
        let target = CGFloat(timelineMappingDuration * Double(initialTagWidthFractionOfViewport) / td)
        timelineScale = min(momentMiniTimelineMaxScale, max(1.0, target))
        let applied = timelineScale
        DispatchQueue.main.async {
            centerViewportByTagAfterScaleChange(newScale: applied)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            centerViewportByTagAfterScaleChange(newScale: applied)
        }
    }

    /// Центрирование тега; `fullWidth` используется только для первого мгновенного прохода.
    /// Отложенные повторы всегда берут актуальную `lastLayoutFullWidth`, чтобы не прыгать
    /// к позиции, рассчитанной по устаревшей ширине контейнера.
    private func scheduleScrollToTagCenter(proxy: ScrollViewProxy, fullWidth: CGFloat?) {
        func attempt(widthOverride: CGFloat? = nil) {
            let wBase = max(widthOverride ?? lastLayoutFullWidth, 1)
            let vw = scrollViewportFromFullWidth(wBase)
            let cw = contentWidth(viewportWidth: vw, effectiveScale: timelineScale)
            scrollMiniTimelineToTagCenter(proxy: proxy, scrollViewport: vw, contentW: cw)
        }
        attempt(widthOverride: fullWidth)
        DispatchQueue.main.async {
            attempt()
            DispatchQueue.main.async { attempt() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { attempt() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { attempt() }
    }

    private func scrollMiniTimelineToTagCenter(
        proxy: ScrollViewProxy,
        scrollViewport: CGFloat,
        contentW: CGFloat
    ) {
        let fallbackVW = max(scrollViewport, 1)
        let fallbackCW = max(contentW, 1)
        guard fallbackCW > fallbackVW + 0.5 else { return }
        if let sv = scrollController.scrollView,
           let doc = sv.documentView,
           scrollController.visibleWidth > 1 {
            // Критично для старых Intel: центрируем по ФАКТИЧЕСКОМУ document width,
            // а не по предварительному расчёту SwiftUI layout.
            let actualVW = max(scrollController.visibleWidth, 1)
            let actualCW = max(doc.frame.width, actualVW)
            let cx = worldX(time: tagCenter, contentW: actualCW)
            let maxScroll = max(0, actualCW - actualVW)
            let target = min(maxScroll, max(0, cx - actualVW * 0.5))
            scrollController.scrollTo(x: target)
        } else {
            let cx = worldX(time: tagCenter, contentW: fallbackCW)
            guard cx.isFinite else { return }
            var t = Transaction()
            t.animation = nil
            withTransaction(t) {
                proxy.scrollTo("miniTagCenter", anchor: .center)
            }
        }
    }

    private func finishMagnificationZoom(value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        let oldScale = timelineScale
        let newScale = min(momentMiniTimelineMaxScale, max(1.0, oldScale * value))
        guard abs(newScale - oldScale) > 0.001 else { return }
        timelineScale = newScale
        // Сохранение скролла — в `onChange(of: timelineScale)`.
    }

    /// При зуме мини-таймлайна держим тег в центре видимой области.
    private func centerViewportByTagAfterScaleChange(newScale: CGFloat) {
        func attempt() {
            let rawViewport = scrollController.visibleWidth > 1
                ? scrollController.visibleWidth
                : scrollViewportFromFullWidth(lastLayoutFullWidth)
            let vw = max(rawViewport, 1)
            let cw = contentWidth(viewportWidth: vw, effectiveScale: newScale)
            guard cw > vw + 0.5 else { return }
            let cx = worldX(time: tagCenter, contentW: cw)
            let maxScroll = max(0, cw - vw)
            let target = min(maxScroll, max(0, cx - vw * 0.5))
            scrollController.scrollTo(x: target)
        }
        attempt()
        DispatchQueue.main.async { attempt() }
    }

    @ViewBuilder
    private func stripContent(
        viewportWidth W: CGFloat,
        contentWidth contentW: CGFloat,
        trackHeight: CGFloat,
        labelRowHeight: CGFloat,
        totalHeight height: CGFloat,
        gridInterval: Double,
        scrollProxy: ScrollViewProxy,
        scrollable: Bool,
        dragMode: DragMode
    ) -> some View {
        let absolutePlayheadTime: Double = {
            switch dragMode {
            case .resizeLeft: return clampedTagStart
            case .resizeRight: return clampedTagEnd
            case .idle: return clampedTagStart + session.compositionPlaybackSeconds
            case .seekTrack:
                return clampedTagStart + (seekTrackVisualComposition ?? session.compositionPlaybackSeconds)
            }
        }()
        let cx = worldX(time: tagCenter, contentW: contentW)

        let tagLeft = worldX(time: clampedTagStart, contentW: contentW)
        let tagRight = worldX(time: clampedTagEnd, contentW: contentW)

        VStack(spacing: 0) {
            MomentMiniEvenSpacedTimeLabels(
                assetDuration: timelineMappingDuration,
                contentWidth: contentW,
                rowHeight: labelRowHeight
            )

            ZStack(alignment: .leading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .position(x: cx, y: trackHeight * 0.5)
                    .id("miniTagCenter")

                markupTrackBackground
                    .frame(height: trackHeight)
                    .allowsHitTesting(false)

                TimeGridView(
                    duration: timelineMappingDuration,
                    interval: gridInterval,
                    width: contentW,
                    height: trackHeight
                )
                .drawingGroup()
                .allowsHitTesting(false)

                if tagRight > tagLeft + 0.5 {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: [stampColor, stampColor.opacity(0.82)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: max(tagRight - tagLeft, 4), height: trackHeight - 8)
                        .position(x: (tagLeft + tagRight) * 0.5, y: trackHeight * 0.5)
                        .shadow(color: stampColor.opacity(0.35), radius: 2, x: 0, y: 1)

                    Color.clear.frame(width: 1, height: 1).position(x: tagLeft, y: trackHeight * 0.5).id("miniTagLead")
                    Color.clear.frame(width: 1, height: 1).position(x: tagRight, y: trackHeight * 0.5).id("miniTagTrail")

                    if canResize {
                        EdgeResizeHandle(edge: .left, stampHeight: trackHeight - 8)
                            .frame(width: handleHitSlop, height: trackHeight)
                            .contentShape(Rectangle())
                            .position(x: tagLeft, y: trackHeight * 0.5)
                        EdgeResizeHandle(edge: .right, stampHeight: trackHeight - 8)
                            .frame(width: handleHitSlop, height: trackHeight)
                            .contentShape(Rectangle())
                            .position(x: tagRight, y: trackHeight * 0.5)
                    } else {
                        handleCapsule(trackHeight: trackHeight)
                            .position(x: tagLeft, y: trackHeight * 0.5)
                        handleCapsule(trackHeight: trackHeight)
                            .position(x: tagRight, y: trackHeight * 0.5)
                    }
                }

                let playX = worldX(time: absolutePlayheadTime, contentW: contentW)
                if playX.isFinite, playX >= -12, playX <= contentW + 12 {
                    miniPlayhead(trackHeight: trackHeight)
                        .position(x: min(max(playX, 8), contentW - 8), y: trackHeight * 0.5 - 2)
                }
            }
            .frame(height: trackHeight)
            .simultaneousGesture(
                resizeOrSeekGesture(
                    viewportWidth: W,
                    contentWidth: contentW,
                    tagLeftWorld: tagLeft,
                    tagRightWorld: tagRight,
                    scrollProxy: scrollProxy,
                    scrollable: scrollable
                )
            )
            .transaction { t in
                t.animation = nil
            }
        }
        .frame(width: contentW, height: height)
    }

    private var markupTrackBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.gray.opacity(0.07),
                Color.gray.opacity(0.025)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.22), lineWidth: 0.5)
        )
    }

    private func resizeOrSeekGesture(
        viewportWidth W: CGFloat,
        contentWidth contentW: CGFloat,
        tagLeftWorld: CGFloat,
        tagRightWorld: CGFloat,
        scrollProxy: ScrollViewProxy,
        scrollable: Bool
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("miniWorld"))
            .onChanged { value in
                let vx = value.location.x
                let vis = scrollController.documentVisibleRect
                let docLeft: CGFloat
                let docRight: CGFloat
                if vis.width > 1 {
                    docLeft = vis.origin.x
                    docRight = vis.origin.x + vis.width
                } else {
                    docLeft = 0
                    docRight = W
                }
                if dragMode == .idle {
                    if canResize, abs(vx - tagLeftWorld) <= handleHitSlop * 0.55 {
                        dragMode = .resizeLeft
                        dragState.previewStart = baseTagStart
                        dragState.previewEnd = baseTagEnd
                        resizeLockedTime = nil
                        scrollController.stopAutoScrollFollow()
                        session.pausePlayback()
                    } else if canResize, abs(vx - tagRightWorld) <= handleHitSlop * 0.55 {
                        dragMode = .resizeRight
                        dragState.previewStart = baseTagStart
                        dragState.previewEnd = baseTagEnd
                        resizeLockedTime = nil
                        scrollController.stopAutoScrollFollow()
                        session.pausePlayback()
                    } else {
                        dragMode = .seekTrack
                    }
                }

                switch dragMode {
                case .idle:
                    break
                case .seekTrack:
                    let absolute = timeAtWorldX(vx, contentW: contentW)
                    let composition = absolute - clampedTagStart
                    seekTrackVisualComposition = session.clampedCompositionLocal(composition)
                    let now = Date()
                    guard now.timeIntervalSince(lastSeekTrackAt) >= seekTrackThrottle else { break }
                    lastSeekTrackAt = now
                    session.seekToCompositionTime(seekTrackVisualComposition ?? composition)
                case .resizeLeft:
                    guard lineID != nil, stampID != nil else { break }
                    let resolvedTime = resolveResizeCursorTime(
                        cursorX: vx,
                        docLeft: docLeft, docRight: docRight,
                        contentW: contentW, scrollable: scrollable
                    )
                    let clamped = max(0, min(resolvedTime, min(tagEnd - 0.5, timelineMappingDuration - 0.5)))
                    let now = Date()
                    if now.timeIntervalSince(lastResizeVisualAt) >= resizeVisualThrottle {
                        lastResizeVisualAt = now
                        dragState.previewStart = clamped
                    }
                    previewResizeIfNeeded(edgeAnchorAbsolute: clamped)
                case .resizeRight:
                    guard lineID != nil, stampID != nil else { break }
                    let resolvedTime = resolveResizeCursorTime(
                        cursorX: vx,
                        docLeft: docLeft, docRight: docRight,
                        contentW: contentW, scrollable: scrollable
                    )
                    let clamped = min(timelineMappingDuration, max(resolvedTime, clampedTagStart + 0.5))
                    let now = Date()
                    if now.timeIntervalSince(lastResizeVisualAt) >= resizeVisualThrottle {
                        lastResizeVisualAt = now
                        dragState.previewEnd = clamped
                    }
                    previewResizeIfNeeded(edgeAnchorAbsolute: clamped)
                }
            }
            .onEnded { _ in
                let mode = dragMode
                let endedResize = mode == .resizeLeft || mode == .resizeRight
                seekTrackVisualComposition = nil
                lastResizePreviewAt = .distantPast
                lastSeekTrackAt = .distantPast
                lastResizeVisualAt = .distantPast
                defer {
                    resizeLockedTime = nil
                    dragState.reset()
                    scrollController.stopAutoScrollFollow()
                    dragMode = .idle
                }
                if endedResize {
                    if let lid = lineID, let sid = stampID {
                        let cap = timelineMappingDuration
                        let rawStart = dragState.previewStart ?? baseTagStart
                        let rawEnd = dragState.previewEnd ?? baseTagEnd
                        let finalStart = min(max(0, rawStart), max(0, cap - 0.5))
                        let finalEnd = min(max(finalStart + 0.5, rawEnd), cap)
                        let edgeAnchorAbsolute: Double? = {
                            switch mode {
                            case .resizeLeft: return finalStart
                            case .resizeRight: return finalEnd
                            case .idle, .seekTrack: return nil
                            }
                        }()
                        timelineData.updateStampTime(
                            lineID: lid,
                            stampID: sid,
                            newStart: finalStart,
                            newEnd: finalEnd,
                            persistChanges: true,
                            runScreenshotUnlinkCheck: true
                        )
                        recomposeSessionAfterStampEdit(anchor: edgeAnchorAbsolute)
                    }
                }
            }
    }

    /// Единая логика для обоих edge-направлений при resize.
    /// Если курсор попал в зону у ЛЕВОГО или ПРАВОГО края viewport:
    ///   — скроллим таймлайн со скоростью пропорциональной дистанции от края
    ///   — замораживаем время тега у freeze-offset и возвращаем его
    /// Если курсор внутри — возвращаем реальное время под курсором, сбрасываем lock.
    private func resolveResizeCursorTime(
        cursorX: CGFloat,
        docLeft: CGFloat,
        docRight: CGFloat,
        contentW: CGFloat,
        scrollable: Bool
    ) -> Double {
        let vw = max(docRight - docLeft, 1)
        let maxScroll = max(0, contentW - vw)
        if !scrollable || maxScroll < 2 {
            resizeLockedTime = nil
            return timeAtWorldX(min(max(cursorX, 0), contentW), contentW: contentW)
        }
        let atLeft = scrollController.currentScrollX <= 0.5
        let atRight = scrollController.currentScrollX >= maxScroll - 0.5

        // Левый edge: курсор левее зоны и ещё есть куда скроллить влево
        if cursorX < docLeft + resizeEdgeScrollZone, !atLeft {
            if scrollable {
                let overshoot = max(0, (docLeft + resizeEdgeScrollZone) - cursorX)
                let step = min(overshoot / resizeEdgeScrollZone, 1) * resizeEdgeScrollMaxStep
                scrollController.scrollTo(x: max(0, scrollController.currentScrollX - step))
            }
            // Пересчитываем каждый раз от текущего docLeft, чтобы тег
            // продолжал тянуться по мере того как таймлайн скроллится.
            let t = min(timeAtWorldX(max(0, docLeft + resizeEdgeFreezeOffset), contentW: contentW), timelineMappingDuration)
            resizeLockedTime = t
            return t
        }

        // Правый edge: курсор правее зоны и ещё есть куда скроллить вправо
        if cursorX > docRight - resizeEdgeScrollZone, !atRight {
            if scrollable {
                let overshoot = max(0, cursorX - (docRight - resizeEdgeScrollZone))
                let step = min(overshoot / resizeEdgeScrollZone, 1) * resizeEdgeScrollMaxStep
                scrollController.scrollTo(x: min(maxScroll, scrollController.currentScrollX + step))
            }
            // Пересчитываем каждый раз от текущего docRight — тег ползёт дальше по мере скролла.
            let t = min(timeAtWorldX(min(contentW, docRight - resizeEdgeFreezeOffset), contentW: contentW), timelineMappingDuration)
            resizeLockedTime = t
            return t
        }

        // Курсор в свободной зоне — тег свободно следует за курсором
        resizeLockedTime = nil
        return timeAtWorldX(min(max(cursorX, 0), contentW), contentW: contentW)
    }

    private func recomposeSessionAfterStampEdit(anchor: Double?) {
        guard let lid = lineID, let sid = stampID,
              let line = timelineData.lines.first(where: { $0.id == lid }),
              let st = line.stamps.first(where: { $0.id == sid }) else { return }
        let dur = max(0.5, st.timeFinishSeconds - st.timeStartSeconds)
        session.recompose(
            startTime: st.timeStartSeconds,
            duration: dur,
            anchorAbsoluteTime: anchor,
            resumePlaybackAfterSeek: true
        )
    }

    /// Покадровый preview во время resize: не чаще `resizePreviewThrottle`,
    /// seek по исходному ассету без постоянного `replaceCurrentItem`.
    private func previewResizeIfNeeded(edgeAnchorAbsolute: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastResizePreviewAt) >= resizePreviewThrottle else { return }
        lastResizePreviewAt = now
        session.seekPreviewDuringResize(absoluteVideoTime: edgeAnchorAbsolute)
    }

    private func handleCapsule(trackHeight: CGFloat) -> some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 5, height: min(trackHeight - 10, 22))
            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
    }

    private func miniPlayhead(trackHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
                .frame(width: 11, height: 11)
            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: max(trackHeight - 18, 12))
        }
        .frame(width: 18, height: trackHeight)
    }
}

/// Локальное состояние интерактивного resize мини-таймлайна.
/// Изолирует частые drag-апдейты от общей модели `TimelineDataManager`.
@MainActor
final class MomentMiniTimelineDragState: ObservableObject {
    @Published var previewStart: Double?
    @Published var previewEnd: Double?

    func reset() {
        previewStart = nil
        previewEnd = nil
    }
}

// MARK: - Подписи времени с фиксированным шагом по пикселям

/// Центры подписей через равный интервал по X; при зуме меняются только значения времени, не расстояние между метками.
private struct MomentMiniEvenSpacedTimeLabels: View {
    let assetDuration: Double
    let contentWidth: CGFloat
    let rowHeight: CGFloat
    /// Минимальное расстояние между центрами соседних подписей (pt).
    var labelSpacingPx: CGFloat = 56

    var body: some View {
        let ad = max(assetDuration, 0.000_001)
        let cw = max(contentWidth, 1)
        let spacing = max(44, labelSpacingPx)
        let maxLabels = 60
        let rawCount = Int(floor((cw - 8) / spacing)) + 1
        let n = max(1, min(maxLabels, rawCount))
        let xs: [CGFloat] = (0..<n).map { 6 + CGFloat($0) * spacing }.filter { $0 <= cw - 4 }

        ZStack(alignment: .leading) {
            ForEach(Array(xs.enumerated()), id: \.offset) { _, x in
                let t = Double(x / cw) * ad
                Text(secondsToTimeString(t))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: true, vertical: false)
                    .position(x: x, y: rowHeight * 0.5)
            }
        }
        .frame(width: cw, height: rowHeight, alignment: .leading)
        .clipped()
        .allowsHitTesting(false)
    }
}
