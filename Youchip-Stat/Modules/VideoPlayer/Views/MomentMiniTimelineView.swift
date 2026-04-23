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

    @GestureState private var magnifyScale: CGFloat = 1.0
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
    private let resizeViewportEdgePadding: CGFloat = 14
    private let resizeViewportClampInterval: TimeInterval = 0.012
    @State private var lastViewportClampAt = Date.distantPast
    @State private var lastResizeStripContentW: CGFloat = 1
    /// Ширина полосы из `GeometryReader` — для `preserveScroll` при смене масштаба извне (слайдер в родителе).
    @State private var lastLayoutFullWidth: CGFloat = 1
    @State private var lastTimelineScaleForScrollSync: CGFloat = 1.0
    /// Стартовый `applyInitialTimelineScaleIfNeeded` не должен дёргать скролл (его делает `scheduleScrollToTagCenter`).
    @State private var skipTimelineScaleScrollPreserve = false

    private var canResize: Bool {
        lineID != nil && stampID != nil && stamp != nil
    }

    private var tagStart: Double { stamp?.timeStartSeconds ?? session.displayStartTime }
    private var tagEnd: Double { stamp?.timeFinishSeconds ?? (tagStart + session.displayDuration) }
    private var tagDuration: Double { max(tagEnd - tagStart, 0.000_001) }

    private var assetDuration: Double {
        max(session.sourceAssetDuration, tagEnd + 0.01)
    }
    private var tagCenter: Double { tagStart + tagDuration * 0.5 }

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
        CGFloat(time / max(assetDuration, 0.000_001)) * contentW
    }

    private func timeAtWorldX(_ x: CGFloat, contentW: CGFloat) -> Double {
        Double(x / max(contentW, 1)) * assetDuration
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
            let gridInterval = sportCutMarkupTimeGridInterval(scale: effectiveScale, totalDuration: assetDuration)

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
                            .help("Прокрутить влево")
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
                            .help("Прокрутить вправо")
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: reserveChevronSlots ? chevronSlot : 0)
                }
                .gesture(
                    MagnificationGesture()
                        .updating($magnifyScale) { state, gestureState, _ in
                            gestureState = max(1.0, state)
                        }
                        .onEnded { value in
                            finishMagnificationZoom(value: value)
                        }
                )
                .onAppear {
                    lastLayoutFullWidth = max(W, 1)
                    lastTimelineScaleForScrollSync = timelineScale
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
        if skipTimelineScaleScrollPreserve {
            skipTimelineScaleScrollPreserve = false
            lastTimelineScaleForScrollSync = newValue
            return
        }
        let old = lastTimelineScaleForScrollSync
        lastTimelineScaleForScrollSync = newValue
        guard abs(old - newValue) > 0.001 else { return }
        let vw = scrollViewportFromFullWidth(lastLayoutFullWidth)
        preserveScrollAfterScaleChange(oldScale: old, newScale: newValue, scrollViewport: vw)
    }

    private func applyInitialTimelineScaleIfNeeded() {
        guard stampID != nil, stamp != nil else { return }
        if lastAppliedInitialLayoutEpoch == layoutEpoch { return }
        lastAppliedInitialLayoutEpoch = layoutEpoch
        let td = max(tagDuration, 0.000_001)
        let target = CGFloat(assetDuration * Double(initialTagWidthFractionOfViewport) / td)
        skipTimelineScaleScrollPreserve = true
        timelineScale = min(momentMiniTimelineMaxScale, max(1.0, target))
    }

    /// Центрирование тега; `fullWidth` — ширина `GeometryReader` полосы (пересчитываем `scrollViewport` от актуального `timelineScale`).
    private func scheduleScrollToTagCenter(proxy: ScrollViewProxy, fullWidth: CGFloat?) {
        func attempt() {
            let wBase = max(fullWidth ?? lastLayoutFullWidth, 1)
            let vw = scrollViewportFromFullWidth(wBase)
            let cw = contentWidth(viewportWidth: vw, effectiveScale: timelineScale)
            scrollMiniTimelineToTagCenter(proxy: proxy, scrollViewport: vw, contentW: cw)
        }
        attempt()
        DispatchQueue.main.async {
            attempt()
            DispatchQueue.main.async { attempt() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { attempt() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { attempt() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { attempt() }
    }

    private func scrollMiniTimelineToTagCenter(
        proxy: ScrollViewProxy,
        scrollViewport: CGFloat,
        contentW: CGFloat
    ) {
        let vw = max(scrollViewport, 1)
        let cw = max(contentW, 1)
        guard cw > vw + 0.5 else { return }
        let cx = worldX(time: tagCenter, contentW: cw)
        if scrollController.scrollView != nil {
            let maxScroll = max(0, cw - vw)
            let target = min(maxScroll, max(0, cx - vw * 0.5))
            scrollController.scrollTo(x: target)
        } else {
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

    private func preserveScrollAfterScaleChange(oldScale: CGFloat, newScale: CGFloat, scrollViewport: CGFloat) {
        let vw = max(scrollViewport, 1)
        let oldCW = vw * oldScale
        let newCW = vw * newScale
        let oldCx = worldX(time: tagCenter, contentW: oldCW)
        let newCx = worldX(time: tagCenter, contentW: newCW)
        let delta = newCx - oldCx
        let oldScroll = scrollController.currentScrollX
        let sc = scrollController
        DispatchQueue.main.async {
            if sc.scrollView != nil {
                sc.scrollTo(x: oldScroll + delta)
            }
        }
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
            case .resizeLeft: return tagStart
            case .resizeRight: return tagEnd
            case .idle, .seekTrack: return tagStart + session.compositionPlaybackSeconds
            }
        }()
        let cx = worldX(time: tagCenter, contentW: contentW)

        VStack(spacing: 0) {
            MomentMiniEvenSpacedTimeLabels(
                assetDuration: assetDuration,
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
                    duration: assetDuration,
                    interval: gridInterval,
                    width: contentW,
                    height: trackHeight
                )
                .allowsHitTesting(false)

                let tagLeft = worldX(time: tagStart, contentW: contentW)
                let tagRight = worldX(time: tagEnd, contentW: contentW)

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
                    tagLeftWorld: worldX(time: tagStart, contentW: contentW),
                    tagRightWorld: worldX(time: tagEnd, contentW: contentW),
                    scrollProxy: scrollProxy,
                    scrollable: scrollable
                )
            )
        }
        .frame(width: contentW, height: height)
        .onAppear { lastResizeStripContentW = contentW }
        .onChange(of: contentW) { lastResizeStripContentW = $0 }
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
                        scrollController.stopAutoScrollFollow()
                        session.pausePlayback()
                    } else if canResize, abs(vx - tagRightWorld) <= handleHitSlop * 0.55 {
                        dragMode = .resizeRight
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
                    let composition = absolute - tagStart
                    session.seekToCompositionTime(composition)
                case .resizeLeft:
                    guard let lid = lineID, let sid = stampID else { break }
                    let newStart = timeAtWorldX(vx, contentW: contentW)
                    let end = tagEnd
                    let clamped = max(0, min(newStart, end - 0.5))
                    timelineData.updateStampTime(lineID: lid, stampID: sid, newStart: clamped)
                    if scrollable, let b = freshStampBounds() {
                        let tl = worldX(time: b.0, contentW: contentW)
                        clampDraggedTagEdgeInViewport(
                            edgeWorld: tl,
                            docLeft: docLeft,
                            docRight: docRight,
                            contentW: contentW
                        )
                    }
                case .resizeRight:
                    guard let lid = lineID, let sid = stampID else { break }
                    let newEnd = timeAtWorldX(vx, contentW: contentW)
                    let start = tagStart
                    let clamped = min(assetDuration, max(newEnd, start + 0.5))
                    timelineData.updateStampTime(lineID: lid, stampID: sid, newEnd: clamped)
                    if scrollable, let b = freshStampBounds() {
                        let tr = worldX(time: b.1, contentW: contentW)
                        clampDraggedTagEdgeInViewport(
                            edgeWorld: tr,
                            docLeft: docLeft,
                            docRight: docRight,
                            contentW: contentW
                        )
                    }
                }
            }
            .onEnded { _ in
                let mode = dragMode
                let endedResize = mode == .resizeLeft || mode == .resizeRight
                /// После `recompose` плейхед у края, за который тянули (начало / конец клипа), без сохранения старой позиции воспроизведения.
                let edgeAnchorAbsolute: Double? = {
                    guard endedResize, let b = freshStampBounds() else { return nil }
                    switch mode {
                    case .resizeLeft: return b.0
                    case .resizeRight: return b.1
                    case .idle, .seekTrack: return nil
                    }
                }()
                if endedResize {
                    recomposeSessionAfterStampEdit(anchor: edgeAnchorAbsolute)
                    finalizeResizeSmoothScroll()
                }
                dragMode = .idle
            }
    }

    private func freshStampBounds() -> (Double, Double)? {
        guard let lid = lineID, let sid = stampID,
              let line = timelineData.lines.first(where: { $0.id == lid }),
              let st = line.stamps.first(where: { $0.id == sid }) else { return nil }
        return (st.timeStartSeconds, st.timeFinishSeconds)
    }

    /// Перетаскиваемый край тега не выходит за видимую полосу (NSScrollView).
    private func clampDraggedTagEdgeInViewport(
        edgeWorld: CGFloat,
        docLeft: CGFloat,
        docRight: CGFloat,
        contentW: CGFloat
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastViewportClampAt) >= resizeViewportClampInterval else { return }
        guard scrollController.scrollView != nil, edgeWorld.isFinite else { return }
        let vw = docRight - docLeft
        guard vw > 1 else { return }
        let maxScroll = max(0, contentW - vw)
        let p = resizeViewportEdgePadding
        var target: CGFloat?
        if edgeWorld < docLeft + p {
            target = max(0, edgeWorld - p)
        } else if edgeWorld > docRight - p {
            target = min(maxScroll, edgeWorld - vw + p)
        }
        guard let t = target, abs(t - docLeft) > 0.25 else { return }
        lastViewportClampAt = now
        scrollController.scrollTo(x: t)
    }

    /// После отпускания — плавно подтянуть скролл к «ровному» положению относительно тега.
    private func finalizeResizeSmoothScroll() {
        guard scrollController.scrollView != nil else { return }
        let cw = max(lastResizeStripContentW, 1)
        guard let b = freshStampBounds() else { return }
        let tl = worldX(time: b.0, contentW: cw)
        let tr = worldX(time: b.1, contentW: cw)
        let vis = scrollController.documentVisibleRect
        guard vis.width > 1 else { return }

        let docL = vis.origin.x
        let docR = vis.origin.x + vis.width
        let vw = vis.width
        let m: CGFloat = 12
        let maxScroll = max(0, cw - vw)

        var target = docL
        if tl < docL + m {
            target = max(0, tl - m)
        } else if tr > docR - m {
            target = min(maxScroll, tr - vw + m)
        } else if tl - docL > m * 3 {
            target = min(maxScroll, max(0, tl - m))
        } else if docR - tr > m * 3 {
            target = min(maxScroll, max(0, tr - vw + m))
        } else {
            return
        }

        guard abs(target - docL) > 1.5 else { return }
        scrollController.setAutoScrollTarget(x: target)
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
        let maxLabels = 240
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
