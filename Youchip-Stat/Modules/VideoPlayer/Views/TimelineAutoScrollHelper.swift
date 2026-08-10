//
//  TimelineAutoScrollHelper.swift
//  Youchip-Stat
//

import SwiftUI
import AppKit

// Holds a weak reference to the timeline's NSScrollView and provides
// programmatic scroll control without animation.
final class TimelineScrollController: ObservableObject {

    // True after the user has manually scrolled the timeline.
    // Cleared on pause→resume or zoom so auto-scroll resumes.
    var userDidManuallyScroll = false

    /// Текущее горизонтальное смещение (обновляется непрерывно при скролле) — чтобы закреплённая
    /// сверху линейка (safe-area/overlay) синхронно ехала за таймлайнами по горизонтали.
    @Published var liveScrollX: CGFloat = 0

    private var scrollObserverToken: Any?
    private var boundsObserverToken: Any?
    private var autoScrollTimer: Timer?
    private var autoScrollTargetX: CGFloat?
    private var lastAutoScrollTick: CFTimeInterval = 0

    weak var scrollView: NSScrollView? {
        didSet {
            guard scrollView !== oldValue else { return }
            if let token = scrollObserverToken {
                NotificationCenter.default.removeObserver(token)
                scrollObserverToken = nil
            }
            if let token = boundsObserverToken {
                NotificationCenter.default.removeObserver(token)
                boundsObserverToken = nil
            }
            if let sv = scrollView {
                // NSScrollView.willStartLiveScrollNotification fires only for
                // user-initiated scrolls (trackpad / scroll wheel), not for
                // programmatic documentView.scroll(_:) calls — so no extra
                // isProgrammaticScrollInFlight guard is needed here. That guard
                // caused a race condition: when auto-scroll called scrollTo()
                // frequently the flag was still true when the user's live-scroll
                // notification arrived, silently dropping the intent to suppress
                // auto-scroll.
                scrollObserverToken = NotificationCenter.default.addObserver(
                    forName: NSScrollView.willStartLiveScrollNotification,
                    object: sv,
                    queue: .main
                ) { [weak self] _ in
                    self?.userDidManuallyScroll = true
                }
                // Непрерывное отслеживание горизонтального смещения для закреплённой линейки.
                sv.contentView.postsBoundsChangedNotifications = true
                boundsObserverToken = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: sv.contentView,
                    queue: .main
                ) { [weak self, weak sv] _ in
                    guard let sv = sv else { return }
                    let x = sv.documentVisibleRect.origin.x
                    if self?.liveScrollX != x { self?.liveScrollX = x }
                }
                liveScrollX = sv.documentVisibleRect.origin.x
            }
        }
    }

    var currentScrollX: CGFloat {
        scrollView?.documentVisibleRect.origin.x ?? 0
    }

    var visibleWidth: CGFloat {
        scrollView?.documentVisibleRect.width ?? 0
    }

    var documentVisibleRect: CGRect {
        scrollView?.documentVisibleRect ?? .zero
    }

    // Jumps the scroll view to `x` with no animation.
    func scrollTo(x: CGFloat) {
        guard let scrollView = scrollView,
              let documentView = scrollView.documentView else { return }
        let clampedX = max(0, min(x, documentView.frame.width - visibleWidth))
        var origin = scrollView.documentVisibleRect.origin
        if abs(origin.x - clampedX) < 0.5 { return }
        origin.x = clampedX
        documentView.scroll(origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // Smoothly follows the requested x target using a lightweight 60 Hz timer.
    // This avoids visible "step" jumps when playhead-driven auto-scroll updates
    // arrive less frequently than display refresh.
    func setAutoScrollTarget(x: CGFloat) {
        guard let scrollView = scrollView,
              let documentView = scrollView.documentView else { return }
        let maxX = max(0, documentView.frame.width - visibleWidth)
        let clampedTarget = max(0, min(x, maxX))
        autoScrollTargetX = clampedTarget
        startAutoScrollTimerIfNeeded()
    }

    func stopAutoScrollFollow() {
        autoScrollTargetX = nil
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        lastAutoScrollTick = 0
    }

    private func startAutoScrollTimerIfNeeded() {
        guard autoScrollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickAutoScroll()
        }
        RunLoop.main.add(timer, forMode: .common)
        autoScrollTimer = timer
    }

    private func tickAutoScroll() {
        guard let targetX = autoScrollTargetX else {
            stopAutoScrollFollow()
            return
        }

        let now = CACurrentMediaTime()
        let dt: CGFloat
        if lastAutoScrollTick == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = max(1.0 / 240.0, min(1.0 / 20.0, CGFloat(now - lastAutoScrollTick)))
        }
        lastAutoScrollTick = now

        let currentX = currentScrollX
        let distance = targetX - currentX
        if abs(distance) < 0.5 {
            scrollTo(x: targetX)
            stopAutoScrollFollow()
            return
        }

        // Speed cap keeps motion stable on very long timelines.
        let maxSpeedPtsPerSec: CGFloat = 1800
        let maxStep = maxSpeedPtsPerSec * dt
        let step = max(-maxStep, min(distance, maxStep))
        scrollTo(x: currentX + step)
    }

    deinit {
        autoScrollTimer?.invalidate()
        if let token = scrollObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

// MARK: - PlayheadEdgeScrollController

/// Manages interactive playhead drag with velocity-based edge-scrolling.
/// Runs entirely on the main thread (Timer + NSScrollView) and publishes
/// only the two values the view actually reads — so SwiftUI re-renders are
/// as cheap as a single offset change per frame.
final class PlayheadEdgeScrollController: ObservableObject {

    @Published private(set) var isDragging: Bool = false
    @Published private(set) var dragX: CGFloat = 0

    // Cached layout values updated on every drag event
    private var gridWidth: CGFloat = 0
    private var duration: Double = 0

    /// Mouse X relative to the *visible* viewport (not scroll content).
    /// Stays constant while the user holds the mouse at the edge, which is
    /// exactly what we need for the timer to advance the playhead correctly.
    private var dragViewportX: CGFloat = 0

    /// Pts to scroll per 60 Hz tick, signed (+right / −left). Updated every
    /// mouse-move so the timer just reads this value without being restarted.
    private var edgeScrollPtsPerTick: CGFloat = 0
    private var edgeScrollTimer: Timer?

    private weak var scrollController: TimelineScrollController?

    private let edgeThreshold: CGFloat = 80
    private let maxSpeedPtsPerSec: CGFloat = 700

    // MARK: - Public API

    func beginDrag(at contentX: CGFloat,
                   gridWidth: CGFloat,
                   duration: Double,
                   scrollController: TimelineScrollController) {
        self.gridWidth = gridWidth
        self.duration = duration
        self.scrollController = scrollController
        isDragging = true
        applyPosition(contentX: contentX)
    }

    func updateDrag(at contentX: CGFloat,
                    gridWidth: CGFloat,
                    duration: Double,
                    scrollController: TimelineScrollController) {
        self.gridWidth = gridWidth
        self.duration = duration
        self.scrollController = scrollController
        applyPosition(contentX: contentX)
        refreshEdgeScroll()
    }

    /// Stops edge-scroll timer and returns the time to seek to.
    func endDrag() -> Double {
        stopEdgeScroll()
        isDragging = false
        return duration > 0 ? (dragX / gridWidth) * duration : 0
    }

    // MARK: - Private helpers

    private func applyPosition(contentX: CGFloat) {
        dragX = max(0, min(contentX, gridWidth))
        // dragViewportX uses the *raw* (possibly out-of-bounds) contentX so that
        // dragging past an edge triggers full-speed scrolling in that direction.
        dragViewportX = contentX - (scrollController?.currentScrollX ?? 0)
    }

    private func refreshEdgeScroll() {
        guard let sc = scrollController, sc.visibleWidth > 0 else {
            stopEdgeScroll()
            return
        }
        let vw = sc.visibleWidth
        // Right threshold mirrors the 85 % auto-scroll threshold used during
        // playback: edge-scroll starts when the drag reaches 85 % of the viewport.
        let rightThreshold = vw * 0.15

        if dragViewportX < edgeThreshold {
            let t = max(0, min((edgeThreshold - dragViewportX) / edgeThreshold, 1))
            edgeScrollPtsPerTick = -t * maxSpeedPtsPerSec / 60
            startEdgeScrollTimerIfNeeded()
        } else if dragViewportX > vw - rightThreshold {
            let t = max(0, min((dragViewportX - (vw - rightThreshold)) / rightThreshold, 1))
            edgeScrollPtsPerTick = t * maxSpeedPtsPerSec / 60
            startEdgeScrollTimerIfNeeded()
        } else {
            stopEdgeScroll()
        }
    }

    private func startEdgeScrollTimerIfNeeded() {
        guard edgeScrollTimer == nil else { return }
        // Timer.scheduledTimer uses .default run-loop mode, which is paused by
        // macOS during mouse-drag event tracking. Use .common so the timer fires
        // in BOTH .default and .eventTracking modes.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, let sc = self.scrollController else { return }
            sc.scrollTo(x: sc.currentScrollX + self.edgeScrollPtsPerTick)
            self.dragX = max(0, min(sc.currentScrollX + self.dragViewportX, self.gridWidth))
        }
        RunLoop.main.add(timer, forMode: .common)
        edgeScrollTimer = timer
    }

    private func stopEdgeScroll() {
        edgeScrollTimer?.invalidate()
        edgeScrollTimer = nil
        edgeScrollPtsPerTick = 0
    }

    deinit { edgeScrollTimer?.invalidate() }
}

// MARK: -

// An invisible zero-size NSViewRepresentable placed inside a SwiftUI ScrollView.
// On every update it walks up the NSView hierarchy to find the enclosing
// NSScrollView and registers it with the TimelineScrollController.
struct TimelineScrollControllerAttacher: NSViewRepresentable {

    let controller: TimelineScrollController

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Walk up the hierarchy asynchronously so the full view tree is ready.
        DispatchQueue.main.async { [weak controller] in
            guard let controller = controller else { return }
            var current: NSView? = nsView
            var depth = 0
            while let view = current, depth < 30 {
                if let scrollView = view as? NSScrollView {
                    controller.scrollView = scrollView
                    return
                }
                current = view.superview
                depth += 1
            }
        }
    }
}
