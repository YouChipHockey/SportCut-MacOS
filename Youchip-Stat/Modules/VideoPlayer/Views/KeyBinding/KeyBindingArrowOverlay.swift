//
//  KeyBindingArrowOverlay.swift
//  Youchip-Stat
//
//  Отрисовка стрелок связок клавиш на холсте редактора.
//

import SwiftUI

// MARK: - Arrow overlay (all bindings)

struct KeyBindingArrowOverlay: View {

    let layout: TagFreeLayout
    let scale: CGFloat
    let canvasPixelWidth: CGFloat
    let canvasPixelHeight: CGFloat
    let selectedGroupKey: KeyBindingGroupKey?
    let onSelectGroup: (KeyBindingGroupKey) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                for (key, group) in groupedBindings where key != selectedGroupKey {
                    drawArrow(ctx: &ctx, key: key, count: group.count,
                              scale: scale, isSelected: false, size: size)
                }
                if let sel = selectedGroupKey, let group = groupedBindings[sel] {
                    drawArrow(ctx: &ctx, key: sel, count: group.count,
                              scale: scale, isSelected: true, size: size)
                }
            }
            .allowsHitTesting(false)

            ForEach(Array(groupedBindings.keys), id: \.self) { key in
                if groupedBindings[key] != nil,
                   let srcCenter = center(for: key.sourceId, kind: key.sourceKind),
                   let dstCenter = center(for: key.targetId, kind: key.targetKind) {
                    let mid = CGPoint(
                        x: (srcCenter.x + dstCenter.x) / 2 * scale,
                        y: (srcCenter.y + dstCenter.y) / 2 * scale
                    )
                    ArrowBadgeButton(
                        count: groupedBindings[key]?.count ?? 0,
                        isSelected: key == selectedGroupKey
                    )
                    .position(x: mid.x, y: mid.y)
                    .onTapGesture { onSelectGroup(key) }
                }
            }
        }
        .frame(width: canvasPixelWidth, height: canvasPixelHeight, alignment: .topLeading)
    }

    // MARK: - Helpers

    private var groupedBindings: [KeyBindingGroupKey: [KeyBinding]] {
        Dictionary(grouping: layout.bindings, by: { $0.groupKey })
    }

    private func center(for elementId: String, kind: CanvasButtonKind) -> CGPoint? {
        layout.items.first(where: { $0.elementId == elementId && $0.kind == kind })?.center
    }

    private func drawArrow(ctx: inout GraphicsContext, key: KeyBindingGroupKey,
                           count: Int, scale: CGFloat, isSelected: Bool, size: CGSize) {
        guard let src = center(for: key.sourceId, kind: key.sourceKind),
              let dst = center(for: key.targetId, kind: key.targetKind) else { return }

        let s = CGPoint(x: src.x * scale, y: src.y * scale)
        let d = CGPoint(x: dst.x * scale, y: dst.y * scale)

        let color: Color = isSelected ? .accentColor : Color.primary.opacity(0.4)
        let lineWidth: CGFloat = isSelected ? 2 : 1.5

        let path = arrowPath(from: s, to: d)
        ctx.stroke(path, with: .color(color), lineWidth: lineWidth)

        let headPath = arrowheadPath(from: s, to: d)
        ctx.fill(headPath, with: .color(color))
    }

    private func arrowPath(from s: CGPoint, to d: CGPoint) -> Path {
        let midX = (s.x + d.x) / 2
        let midY = (s.y + d.y) / 2
        let dx = d.x - s.x
        let dy = d.y - s.y
        let len = max(sqrt(dx * dx + dy * dy), 1)
        let offsetScale: CGFloat = 0.15
        let cpX = midX - dy / len * len * offsetScale
        let cpY = midY + dx / len * len * offsetScale

        var path = Path()
        path.move(to: s)
        path.addQuadCurve(to: d, control: CGPoint(x: cpX, y: cpY))
        return path
    }

    private func arrowheadPath(from s: CGPoint, to d: CGPoint) -> Path {
        let angle = atan2(d.y - s.y, d.x - s.x)
        let size: CGFloat = 8
        let tip = d
        let left = CGPoint(
            x: tip.x - size * cos(angle - .pi / 6),
            y: tip.y - size * sin(angle - .pi / 6)
        )
        let right = CGPoint(
            x: tip.x - size * cos(angle + .pi / 6),
            y: tip.y - size * sin(angle + .pi / 6)
        )
        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }
}

// MARK: - Badge button on arrow midpoint

private struct ArrowBadgeButton: View {
    let count: Int
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .overlay(Circle().stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1))
                .frame(width: 22, height: 22)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isSelected ? .white : .primary)
        }
    }
}
