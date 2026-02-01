//
//  CircularPercentProgressView.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 18.01.2026.
//


import SwiftUI

struct CircularPercentProgressView: View {
    let progress: Double

    let lineWidth: CGFloat = 15
    let ringColor: Color = .blue
    let backgroundRingColor: Color = .gray.opacity(0.25)
    let textInset: CGFloat = 12

    private var clamped: Double { min(max(progress, 0), 1) }
    private var percentText: String { "\(Int((clamped * 100).rounded()))%" }

    var body: some View {
        ZStack {
            Circle()
                .stroke(backgroundRingColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.15), value: clamped)

            Text(percentText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}
