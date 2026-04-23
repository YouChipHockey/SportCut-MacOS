//
//  PlayheadGrabChrome.swift
//  Youchip-Stat
//
//  Shared white playhead stem + top grab head for draggable affordance.
//

import SwiftUI

/// Apex at the bottom (tip meets the stem); flat base on top — reads as a classic scrub handle.
struct PlayheadGrabTriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Vertical white playhead with a visible triangular head at the top.
struct PlayheadStemWithGrabHead: View {
    var stemWidth: CGFloat = 2
    /// Minimum width of the triangle base (also caps stem visual alignment).
    var headBaseWidth: CGFloat = 12
    var compact: Bool = false

    var body: some View {
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            let headH: CGFloat = {
                if compact {
                    return min(7, max(5, h * 0.48))
                }
                return min(11, max(7, h * 0.14))
            }()
            let stemH = max(h - headH, compact ? 2 : 4)
            let baseW = compact ? min(headBaseWidth, max(8, h * 0.85)) : headBaseWidth

            VStack(spacing: 0) {
                PlayheadGrabTriangleShape()
                    .fill(Color.white)
                    .frame(width: baseW, height: headH)
                    .overlay(
                        PlayheadGrabTriangleShape()
                            .stroke(Color.black.opacity(0.32), lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.45), radius: compact ? 1 : 1.5, y: 1)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: stemWidth, height: stemH)
                    .shadow(color: .black.opacity(0.55), radius: compact ? 0.8 : 1.5, x: 0, y: 0)
            }
            .frame(width: geo.size.width, height: h, alignment: .top)
        }
    }
}
