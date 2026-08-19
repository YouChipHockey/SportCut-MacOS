//
//  ClockOverlayCanvas.swift
//  Youchip-Stat
//
//  Отрисовка счётчиков поверх кадра: сами циферблаты, перетаскивание, изменение размера и
//  раскладка (стопка в правом верхнем углу, пока счётчик не трогали).
//
//  Вынесено из `ClockVideoOverlayView`, потому что показывать счётчики должны ТРИ разных места:
//   • разметка/лайв/пересмотр — `ClockVideoOverlayView` (живые счётчики + записи под плейхедом);
//   • режим просмотра и клипы плейлиста — `SportCutClockOverlayView` (записи под позицией клипа).
//  Канва ничего не знает про источник данных: ей дают готовый список того, что нарисовать.
//
//  Позиция и масштаб хранятся в `ClockOverlayLayoutStore` по `clockId` в долях кадра — одни и те
//  же для всех экранов (подвинул в разметке — так же встанет в просмотре).
//

import SwiftUI

/// Готовый к отрисовке счётчик: либо «живой» (пишется), либо запись, пересечённая плейхедом.
struct ClockOverlayItem: Identifiable, Equatable {
    let clockId: String
    let seconds: Double
    let appearance: ClockAppearance
    let showCentiseconds: Bool
    let caption: String
    let progress: Double?
    var id: String { clockId }
}

struct ClockOverlayCanvas: View {

    let items: [ClockOverlayItem]

    @ObservedObject private var layoutStore = ClockOverlayLayoutStore.shared

    /// Пока идёт жест, раскладка живёт ЛОКАЛЬНО: писать на каждом кадре в общий стор —
    /// это перерисовка всего оверлея через `@Published` на каждое движение мыши, отсюда рывки.
    /// В стор уходит один раз, по окончании жеста.
    private struct DragState {
        let id: String
        /// Раскладка на момент начала жеста — от неё считаем смещение (translation абсолютный).
        let start: ClockOverlayLayout
        var current: ClockOverlayLayout
    }

    @State private var drag: DragState? = nil
    @State private var hoveredId: String? = nil

    var body: some View {
        let shown = items
        if shown.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { pair in
                        let item = pair.element
                        let layout = effectiveLayout(for: item, index: pair.offset, in: geo.size)

                        clockItem(item: item, layout: layout, container: geo.size)
                            .position(
                                x: CGFloat(layout.centerX) * geo.size.width,
                                y: CGFloat(layout.centerY) * geo.size.height
                            )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    // MARK: - Item

    /// Сам циферблат. Вынесен отдельно: вместе с цепочкой модификаторов ниже выражение
    /// становится слишком тяжёлым для тайпчекера.
    private func display(for item: ClockOverlayItem) -> ClockDisplayView {
        let style = ClockStyle(
            foreground: Color.white,
            accent: Color.accentColor,
            cellBackground: Color.black.opacity(0.6),
            fontWeight: .semibold
        )
        return ClockDisplayView(
            seconds: item.seconds,
            appearance: item.appearance,
            showCentiseconds: item.showCentiseconds,
            style: style,
            progress: item.progress,
            caption: item.caption
        )
    }

    private func clockItem(item: ClockOverlayItem, layout: ClockOverlayLayout, container: CGSize) -> some View {
        let size = overlaySize(item, scale: layout.scale)
        let isHovered = hoveredId == item.clockId || drag?.id == item.clockId

        return display(for: item)
            .frame(width: size.width, height: size.height)
        // Перетаскивание — AppKit-слоем: в неактивном окне первый клик иначе уходит на активацию
        // (SwiftUI-жест начинался бы только со второго). Слой ниже ручки размера — она поверх.
        .overlay(
            FirstMouseDragCatcher(
                onBegin: { beginDrag(clockId: item.clockId, current: layout) },
                onDrag: { delta in applyMove(delta: delta, container: container) },
                onEnd: { commitDrag() },
                // Двойной клик — вернуть счётчик на место по умолчанию (иначе утащенный за край
                // не вернуть иначе как правкой настроек).
                onDoubleClick: { layoutStore.resetLayout(for: item.clockId) }
            )
        )
        // Рамка и ручка — только под курсором: в покое поверх видео лежит чистый циферблат.
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(isHovered ? 0.7 : 0), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .allowsHitTesting(false)
        )
        .overlay(
            resizeHandle(clockId: item.clockId, layout: layout, size: size)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered),
            alignment: .bottomTrailing
        )
        // Хит-тест только по самому счётчику: остальной кадр остаётся кликабельным.
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                hoveredId = item.clockId
            } else if hoveredId == item.clockId {
                hoveredId = nil
            }
        }
        .help(^String.Titles.clockOverlayDragHelp)
    }

    /// Уголок для изменения размера: тянем — меняется масштаб счётчика.
    private func resizeHandle(clockId: String, layout: ClockOverlayLayout, size: CGSize) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(3)
            .background(Circle().fill(Color.black.opacity(0.65)))
            .offset(x: 5, y: 5)
            .overlay(
                FirstMouseDragCatcher(
                    onBegin: { beginDrag(clockId: clockId, current: layout) },
                    onDrag: { delta in applyResize(delta: delta, itemSize: size) },
                    onEnd: { commitDrag() }
                )
            )
    }

    // MARK: - Gestures

    /// Перенос: смещение курсора один-в-один в смещение центра. Считаем от раскладки НА МОМЕНТ
    /// НАЖАТИЯ, а не накопительно — тогда позиция не зависит от числа обработанных кадров жеста.
    private func applyMove(delta: CGSize, container: CGSize) {
        guard container.width > 0, container.height > 0, let start = drag?.start else { return }
        applyDuringGesture(
            ClockOverlayLayout(
                centerX: start.centerX + Double(delta.width / container.width),
                centerY: start.centerY + Double(delta.height / container.height),
                scale: start.scale
            )
        )
    }

    /// Размер: масштаб = во сколько раз изменилось расстояние от центра счётчика до курсора
    /// (тот же приём, что у ручки масштаба в редакторе изображений). Точка хвата — угол объекта,
    /// то есть половина его размера от центра.
    private func applyResize(delta: CGSize, itemSize: CGSize) {
        guard let start = drag?.start else { return }
        let grabX = itemSize.width / 2
        let grabY = itemSize.height / 2
        let startDistance = max(hypot(grabX, grabY), 1)
        let distance = hypot(grabX + delta.width, grabY + delta.height)
        applyDuringGesture(
            ClockOverlayLayout(
                centerX: start.centerX,
                centerY: start.centerY,
                scale: start.scale * Double(distance / startDistance)
            )
        )
    }

    /// Новое положение на текущем кадре жеста — строго без анимации: любая неявная анимация
    /// сверху превратила бы перетаскивание в «догоняющее» движение с задержкой.
    private func applyDuringGesture(_ layout: ClockOverlayLayout) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { drag?.current = layout }
    }

    /// Начало жеста: запоминаем раскладку, от которой считаем смещение.
    private func beginDrag(clockId: String, current: ClockOverlayLayout) {
        drag = DragState(id: clockId, start: current, current: current)
    }

    /// Конец жеста — единственная запись в общий стор (и на диск). Простой клик без сдвига ничего
    /// не сохраняет: иначе он «прибивал» бы счётчику текущую позицию по умолчанию как явную.
    private func commitDrag() {
        if let drag, drag.current != drag.start {
            layoutStore.setLayout(drag.current, for: drag.id)
        }
        drag = nil
    }

    // MARK: - Layout

    /// Раскладка для отрисовки: идущий жест (локальное состояние) → сохранённая → по умолчанию
    /// (стопка в правом верхнем углу).
    private func effectiveLayout(for item: ClockOverlayItem, index: Int, in container: CGSize) -> ClockOverlayLayout {
        if let drag, drag.id == item.clockId { return drag.current }
        if let stored = layoutStore.layout(for: item.clockId) { return stored }
        guard container.width > 1, container.height > 1 else {
            return ClockOverlayLayout(centerX: 0.5, centerY: 0.5, scale: ClockOverlayLayout.defaultScale)
        }
        let size = overlaySize(item, scale: ClockOverlayLayout.defaultScale)
        let padding: CGFloat = 12
        let stackOffset = CGFloat(index) * (size.height + 8)
        return ClockOverlayLayout(
            centerX: Double((container.width - padding - size.width / 2) / container.width),
            centerY: Double((padding + size.height / 2 + stackOffset) / container.height),
            scale: ClockOverlayLayout.defaultScale
        )
    }

    private func overlaySize(_ item: ClockOverlayItem, scale: Double) -> CGSize {
        let base: CGSize
        switch item.appearance {
        case .segments: base = CGSize(width: item.showCentiseconds ? 220 : 170, height: 44)
        case .analog, .ring: base = CGSize(width: 96, height: 96)
        case .text: base = CGSize(width: item.showCentiseconds ? 150 : 120, height: 44)
        }
        return CGSize(width: base.width * CGFloat(scale), height: base.height * CGFloat(scale))
    }
}
