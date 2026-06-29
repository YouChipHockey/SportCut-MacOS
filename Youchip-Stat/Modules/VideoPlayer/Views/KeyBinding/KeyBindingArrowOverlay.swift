//
//  KeyBindingArrowOverlay.swift
//  Youchip-Stat
//
//  Отрисовка стрелок связок клавиш на холсте редактора.
//  Разделено на два слоя:
//   - KeyBindingArrowLinesOverlay — сами стрелки (Canvas, без хит-теста);
//   - KeyBindingArrowBadgesOverlay — кликабельные кружки-счётчики на середине стрелок.
//  Оба слоя размещаются над или под кнопками в зависимости от глобального
//  переключателя (над кнопками / под кнопками / скрыть всё): в режиме «под кнопками»
//  бейджи уходят под кнопки вместе со стрелками.
//

import SwiftUI

// MARK: - Shared geometry

private enum KeyBindingArrowGeometry {

    static func groupedBindings(_ layout: TagFreeLayout) -> [KeyBindingGroupKey: [KeyBinding]] {
        Dictionary(grouping: layout.bindings, by: { $0.groupKey })
    }

    static func center(in layout: TagFreeLayout, for elementId: String, kind: CanvasButtonKind) -> CGPoint? {
        layout.items.first(where: { $0.elementId == elementId && $0.kind == kind })?.center
    }
}

// MARK: - Arrow lines (non-interactive)

struct KeyBindingArrowLinesOverlay: View {

    let layout: TagFreeLayout
    let scale: CGFloat
    let canvasPixelWidth: CGFloat
    let canvasPixelHeight: CGFloat
    let selectedGroupKey: KeyBindingGroupKey?

    var body: some View {
        Canvas { ctx, size in
            let grouped = KeyBindingArrowGeometry.groupedBindings(layout)
            for (key, group) in grouped where key != selectedGroupKey {
                drawArrow(ctx: &ctx, key: key, count: group.count,
                          scale: scale, isSelected: false,
                          isExclusive: isExclusiveGroup(group), size: size)
            }
            if let sel = selectedGroupKey, let group = grouped[sel] {
                drawArrow(ctx: &ctx, key: sel, count: group.count,
                          scale: scale, isSelected: true,
                          isExclusive: isExclusiveGroup(group), size: size)
            }
        }
        .allowsHitTesting(false)
        .frame(width: canvasPixelWidth, height: canvasPixelHeight, alignment: .topLeading)
    }

    /// Группа состоит только из эксклюзивных связок — она двунаправленная и рисуется без наконечника.
    private func isExclusiveGroup(_ group: [KeyBinding]) -> Bool {
        !group.isEmpty && group.allSatisfy { $0.type == .exclusive }
    }

    private func drawArrow(ctx: inout GraphicsContext, key: KeyBindingGroupKey,
                           count: Int, scale: CGFloat, isSelected: Bool, isExclusive: Bool, size: CGSize) {
        guard let src = KeyBindingArrowGeometry.center(in: layout, for: key.sourceId, kind: key.sourceKind),
              let dst = KeyBindingArrowGeometry.center(in: layout, for: key.targetId, kind: key.targetKind) else { return }

        let s = CGPoint(x: src.x * scale, y: src.y * scale)
        let d = CGPoint(x: dst.x * scale, y: dst.y * scale)

        let color: Color = isSelected ? .accentColor : Color.primary.opacity(0.4)
        let lineWidth: CGFloat = isSelected ? 2 : 1.5

        // Эксклюзивная связка двунаправленная — прямая линия без наконечника.
        if isExclusive {
            var line = Path()
            line.move(to: s)
            line.addLine(to: d)
            ctx.stroke(line, with: .color(color), lineWidth: lineWidth)
            return
        }

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

// MARK: - Arrow badges (interactive)

struct KeyBindingArrowBadgesOverlay: View {

    let layout: TagFreeLayout
    let scale: CGFloat
    let canvasPixelWidth: CGFloat
    let canvasPixelHeight: CGFloat
    let selectedGroupKey: KeyBindingGroupKey?
    let onSelectGroup: (KeyBindingGroupKey) -> Void

    var body: some View {
        let grouped = KeyBindingArrowGeometry.groupedBindings(layout)
        ZStack(alignment: .topLeading) {
            ForEach(Array(grouped.keys), id: \.self) { key in
                if let group = grouped[key],
                   let srcCenter = KeyBindingArrowGeometry.center(in: layout, for: key.sourceId, kind: key.sourceKind),
                   let dstCenter = KeyBindingArrowGeometry.center(in: layout, for: key.targetId, kind: key.targetKind) {
                    let mid = CGPoint(
                        x: (srcCenter.x + dstCenter.x) / 2 * scale,
                        y: (srcCenter.y + dstCenter.y) / 2 * scale
                    )
                    ArrowBadgeButton(
                        count: group.count,
                        isSelected: key == selectedGroupKey
                    )
                    .position(x: mid.x, y: mid.y)
                    .onTapGesture { onSelectGroup(key) }
                }
            }
        }
        .frame(width: canvasPixelWidth, height: canvasPixelHeight, alignment: .topLeading)
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
