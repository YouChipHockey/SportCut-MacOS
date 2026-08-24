//
//  TimelineTimestampsHeaderView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct TimelineTimestampsHeaderView: View {

    /// Без жёсткого лимита при большом зуме получаются тысячи `Text` → зависание UI при ресайзе окна.
    private static let maxTickViews = 240

    let duration: Double
    let interval: Double
    let width: CGFloat

    private var tickCount: Int {
        guard duration > 0, interval > 0 else { return 1 }
        let raw = Int(duration / interval) + 1
        return min(max(raw, 1), Self.maxTickViews)
    }

    /// Равномерный шаг по времени, если число меток урезано лимитом.
    private var effectiveTimeStep: Double {
        let n = tickCount
        guard n > 1 else { return duration }
        return duration / Double(n - 1)
    }

    /// Сколько равных мелких насечек приходится на один шаг подписи (включая крупную под подписью).
    /// Между двумя подписями получается `subdivisions - 1` мелких делений.
    private static let subdivisions = 5

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.gray.opacity(0.05),
                    Color.gray.opacity(0.02)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: width, height: 30)

            Rectangle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                .frame(width: width, height: 30)

            // Все насечки одним Canvas (дёшево, без сотен View): крупные — под подписями,
            // между ними — равные мелкие деления. Прижаты к низу полосы, как на обычной линейке.
            Canvas { context, size in
                guard duration > 0, width > 0 else { return }
                let minorStep = effectiveTimeStep / Double(Self.subdivisions)
                guard minorStep > 0 else { return }
                let baseY = size.height
                let majorHeight: CGFloat = 6
                let minorHeight: CGFloat = 3
                var idx = 0
                var t = 0.0
                while t <= duration + 1e-6 {
                    let x = (t / duration) * Double(width)
                    let isMajor = idx % Self.subdivisions == 0
                    let h = isMajor ? majorHeight : minorHeight
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: baseY))
                    path.addLine(to: CGPoint(x: x, y: baseY - h))
                    context.stroke(
                        path,
                        with: .color(Color.gray.opacity(isMajor ? 0.45 : 0.28)),
                        lineWidth: isMajor ? 1 : 0.5
                    )
                    idx += 1
                    t = Double(idx) * minorStep
                }
            }
            .frame(width: width, height: 30)

            // Подписи времени — у верха полосы, по позициям крупных насечек.
            ForEach(0..<tickCount, id: \.self) { i in
                let timePosition = Double(i) * effectiveTimeStep
                let xPosition = (timePosition / duration) * Double(width)

                Text(secondsToTimeString(timePosition))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.1))
                            .padding(.horizontal, -2)
                            .padding(.vertical, -1)
                    )
                    .position(x: CGFloat(xPosition), y: 9)
            }
        }
        .frame(width: width, height: 30)
    }

}
