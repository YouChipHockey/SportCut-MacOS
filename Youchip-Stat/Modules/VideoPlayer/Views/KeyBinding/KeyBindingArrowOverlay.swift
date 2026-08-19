//
//  KeyBindingArrowOverlay.swift
//  Youchip-Stat
//
//  Отрисовка стрелок связок клавиш на холсте редактора.
//  KeyBindingArrowLinesOverlay — сами стрелки (Canvas, без хит-теста).
//  Слой размещается над или под кнопками в зависимости от глобального
//  переключателя (над кнопками / под кнопками / скрыть всё).
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
    /// Смещение начала координат холста (для «бесконечного» редактора). По умолчанию — без смещения.
    var origin: CGPoint = .zero
    let canvasPixelWidth: CGFloat
    let canvasPixelHeight: CGFloat
    let selectedGroupKey: KeyBindingGroupKey?
    /// Группы связок, подсвеченные (раскрытые в деталке кнопки справа).
    var highlightedGroupKeys: Set<KeyBindingGroupKey> = []
    /// Составной ключ кнопки, на которой сфокусирован пользователь ("kind:id").
    /// Когда задан — рисуются только связки, входящие в эту кнопку или исходящие из неё.
    var focusedSourceKey: String? = nil

    /// Тема окна — чтобы «белые» highlight-стрелки красить в чёрный в светлой теме.
    /// (Динамический NSColor внутри Canvas разрешается по фиксированному appearance и не адаптируется.)
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { ctx, size in
            let grouped = KeyBindingArrowGeometry.groupedBindings(layout)
            var highlighted = highlightedGroupKeys
            if let sel = selectedGroupKey { highlighted.insert(sel) }

            // Обычные связки — под подсвеченными.
            for (key, group) in grouped where !highlighted.contains(key) {
                guard passesFocusFilter(key) else { continue }
                drawArrow(ctx: &ctx, key: key, type: group.first?.type,
                          scale: scale, isSelected: false,
                          isExclusive: isExclusiveGroup(group), size: size)
            }
            // Подсвеченные связки — поверх остальных.
            for key in highlighted {
                guard let group = grouped[key], passesFocusFilter(key) else { continue }
                drawArrow(ctx: &ctx, key: key, type: group.first?.type,
                          scale: scale, isSelected: true,
                          isExclusive: isExclusiveGroup(group), size: size)
            }
        }
        .allowsHitTesting(false)
        .frame(width: canvasPixelWidth, height: canvasPixelHeight, alignment: .topLeading)
    }

    /// Связка проходит фильтр фокуса: фокуса нет, либо связка входит/исходит из сфокусированной кнопки.
    private func passesFocusFilter(_ key: KeyBindingGroupKey) -> Bool {
        focusedSourceKey == nil
            || key.sourceButtonKey == focusedSourceKey
            || key.targetButtonKey == focusedSourceKey
    }

    /// Группа состоит только из эксклюзивных связок — она двунаправленная и рисуется без наконечника.
    private func isExclusiveGroup(_ group: [KeyBinding]) -> Bool {
        !group.isEmpty && group.allSatisfy { $0.type == .exclusive }
    }

    /// «Белая» стрелка highlight-связки: в светлой теме белый не виден, поэтому красим в чёрный.
    private var highlightArrowColor: Color {
        colorScheme == .dark ? .white : .black
    }

    /// Цвет стрелки по типу связки.
    private func arrowColor(for type: KeyBindingType?) -> Color {
        switch type {
        case .activation:          return Color(red: 0.00, green: 0.45, blue: 0.16) // тёмно-зелёный
        case .deactivation:        return .red                                       // красный
        case .highlight:           return highlightArrowColor                         // белый в тёмной теме, чёрный в светлой
        case .exclusive:           return .orange                                    // оранжевый
        case .intervalInversion:   return .purple                                    // фиолетовый
        case .stateSync:           return Color(red: 0.00, green: 0.70, blue: 0.75)  // бирюзовый

        // Пурпурный — сброс счётчика. Тон намеренно «малиновее» фиолетовой инверсии интервала,
        // иначе две связки не различить на холсте.
        case .clockReset:          return Color(red: 0.68, green: 0.10, blue: 0.60)
        case .visibility:          return Color(red: 0.60, green: 0.85, blue: 0.30)  // салатовый
        case .invisibility:        return Color(red: 1.00, green: 0.45, blue: 0.70)  // розовый
        case .visibilityInversion: return .brown                                     // коричневый
        case .none:                return .primary
        }
    }

    private func drawArrow(ctx: inout GraphicsContext, key: KeyBindingGroupKey,
                           type: KeyBindingType?, scale: CGFloat, isSelected: Bool, isExclusive: Bool, size: CGSize) {
        guard let src = KeyBindingArrowGeometry.center(in: layout, for: key.sourceId, kind: key.sourceKind),
              let dst = KeyBindingArrowGeometry.center(in: layout, for: key.targetId, kind: key.targetKind) else { return }

        let s = CGPoint(x: (src.x - origin.x) * scale, y: (src.y - origin.y) * scale)
        let d = CGPoint(x: (dst.x - origin.x) * scale, y: (dst.y - origin.y) * scale)

        // Все связки полупрозрачные (60%), выделенные — полностью непрозрачные и вдвое толще.
        let baseLineWidth: CGFloat = 2
        let color: Color = arrowColor(for: type).opacity(isSelected ? 1.0 : 0.6)
        let lineWidth: CGFloat = isSelected ? baseLineWidth * 2 : baseLineWidth

        // Все связки — прямые линии.
        var line = Path()
        line.move(to: s)
        line.addLine(to: d)
        ctx.stroke(line, with: .color(color), lineWidth: lineWidth)

        // Эксклюзивная связка двунаправленная — без наконечника.
        if isExclusive { return }

        let headPath = arrowheadPath(from: s, to: d)
        ctx.fill(headPath, with: .color(color))
    }

    private func arrowheadPath(from s: CGPoint, to d: CGPoint) -> Path {
        let dx = d.x - s.x
        let dy = d.y - s.y
        let angle = atan2(dy, dx)
        // Базовый размер наконечника, масштабируется вместе с зумом холста.
        let size: CGFloat = 16 * scale
        // Наконечник — по середине расстояния между кнопками, остриём к цели.
        let tip = CGPoint(x: (s.x + d.x) / 2, y: (s.y + d.y) / 2)
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
