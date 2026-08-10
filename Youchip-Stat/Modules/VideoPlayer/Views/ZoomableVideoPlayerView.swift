//
//  ZoomableVideoPlayerView.swift
//  Youchip-Stat
//
//  Переиспользуемый плеер с зумом (как в разметке). На масштабе 1.0 показывает «родной» плеер
//  (нативные контролы), при зуме — голый слой (`CustomVideoPlayer`) с трансформом + пан.
//  Кнопки зума и жесты (пинч/драг) — оверлеем. Используется в окне пересмотра лайва, окне тега
//  (двойной клик) и в плеере режима просмотра.
//

import SwiftUI
import AVKit

struct ZoomableVideoPlayerView<Native: View>: View {

    let player: AVPlayer
    /// «Родной» плеер, показываемый на масштабе 1.0 (нативные контролы сохраняются).
    @ViewBuilder let nativePlayer: () -> Native

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastDrag: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1.0

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0
    private let step: CGFloat = 0.25

    var body: some View {
        GeometryReader { geo in
            let effective = clamp(scale * pinch)
            ZStack {
                Color.black

                if effective <= 1.0001 {
                    nativePlayer()
                } else {
                    CustomVideoPlayer(
                        player: player,
                        scale: effective,
                        offset: clampedOffset(offset, scale: effective, size: geo.size)
                    )
                    .gesture(dragGesture(size: geo.size))
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(magnifyGesture)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                zoomControls
                    .padding(10)
            }
        }
    }

    // MARK: - Controls

    private var zoomControls: some View {
        HStack(spacing: 6) {
            zoomButton(system: "minus.magnifyingglass") { setScale(scale - step) }
                .disabled(scale <= minScale + 0.001)

            Text("\(Int((scale * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .frame(minWidth: 38)

            zoomButton(system: "plus.magnifyingglass") { setScale(scale + step) }
                .disabled(scale >= maxScale - 0.001)

            if scale > 1.0 {
                zoomButton(system: "arrow.counterclockwise") { setScale(1.0) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
    }

    private func zoomButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .updating($pinch) { value, state, _ in state = value }
            .onEnded { value in
                setScale(scale * value)
            }
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let candidate = CGSize(
                    width: lastDrag.width + value.translation.width,
                    height: lastDrag.height + value.translation.height
                )
                offset = clampedOffset(candidate, scale: scale, size: size)
            }
            .onEnded { _ in lastDrag = offset }
    }

    // MARK: - Helpers

    private func setScale(_ value: CGFloat) {
        scale = clamp(value)
        if scale <= 1.0 {
            offset = .zero
            lastDrag = .zero
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(maxScale, max(minScale, value))
    }

    private func clampedOffset(_ o: CGSize, scale: CGFloat, size: CGSize) -> CGSize {
        guard scale > 1.0, size.width > 0, size.height > 0 else { return .zero }
        let maxX = (size.width * (scale - 1)) / 2
        let maxY = (size.height * (scale - 1)) / 2
        return CGSize(
            width: min(max(o.width, -maxX), maxX),
            height: min(max(o.height, -maxY), maxY)
        )
    }
}
