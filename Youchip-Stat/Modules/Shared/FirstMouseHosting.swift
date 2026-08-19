//
//  FirstMouseHosting.swift
//  Youchip-Stat
//
//  Клик по НЕактивному окну должен сразу доходить до контрола под курсором (как в Sportscode),
//  а не тратиться на активацию окна: разметка идёт в трёх окнах сразу, и лишний клик на каждое
//  переключение — это половина кликов пользователя.
//
//  Решение о «первом клике» принимает вью под курсором (`acceptsFirstMouse`), по умолчанию
//  NSView отвечает false и AppKit съедает такой клик. Чистый SwiftUI-контент живёт внутри
//  NSHostingView и своих решений не принимает — значит достаточно подменить сам хостинг.
//

import AppKit
import SwiftUI

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// `NSHostingController`, чей контент реагирует на первый клик в неактивном окне.
///
/// ВАЖНО: вью создаём мы, а `rootView` у `NSHostingController` не `open` и перехватить его
/// присваивание нельзя — поэтому дерево берётся ОДИН раз, при загрузке вью. Для окон, которые
/// потом переприсваивают `hostingController.rootView` (например
/// `FieldMapVisualizationWindowController`), нужен обычный `NSHostingController`.
final class FirstMouseHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = FirstMouseHostingView(rootView: rootView)
    }
}

// MARK: - Курсор над кликабельной зоной

/// Курсор-палец при наведении: подсказка, что зона кликабельна (важно теперь, когда клик
/// проходит сразу, без активации окна).
private struct PointingHandCursor: ViewModifier {
    /// Пары push/pop должны сходиться, иначе «палец» залипает на всё приложение.
    @State private var isPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { isInside in
                if isInside {
                    guard !isPushed else { return }
                    NSCursor.pointingHand.push()
                    isPushed = true
                } else if isPushed {
                    NSCursor.pop()
                    isPushed = false
                }
            }
            .onDisappear {
                // Вью может исчезнуть под курсором (скролл, смена коллекции) — снимаем курсор.
                if isPushed {
                    NSCursor.pop()
                    isPushed = false
                }
            }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

// MARK: - Вторичный клик (Ctrl+ЛКМ / ПКМ)

/// Ловит вторичный клик по SwiftUI-вью.
///
/// На macOS Ctrl+ЛКМ система доставляет как ПРАВОЕ нажатие (так работают контекстные меню),
/// поэтому обычный `.onTapGesture` его не видит — сколько ни проверяй `NSEvent.modifierFlags`.
/// Кладём поверх тонкий AppKit-слой, прозрачный для всего, кроме вторичного нажатия: `hitTest`
/// возвращает себя только на нужном событии, иначе слой съедал бы обычные тапы кнопки.
private struct SecondaryClickCatcher: NSViewRepresentable {

    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.action = action
    }

    final class CatcherView: NSView {
        var action: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, Self.isSecondary(event) else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) { action?() }

        /// Подстраховка: если AppKit всё же донёс Ctrl+ЛКМ левым событием — обрабатываем и его.
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                action?()
            } else {
                super.mouseDown(with: event)
            }
        }

        /// Своего контекстного меню у слоя нет — жест обрабатываем сами.
        override func menu(for event: NSEvent) -> NSMenu? { nil }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private static func isSecondary(_ event: NSEvent) -> Bool {
            switch event.type {
            case .rightMouseDown, .rightMouseUp:
                return true
            case .leftMouseDown, .leftMouseUp:
                return event.modifierFlags.contains(.control)
            default:
                return false
            }
        }
    }
}

extension View {
    /// Действие по Ctrl+ЛКМ или правому клику. Обычные нажатия проходят сквозь наложенный слой.
    /// `enabled: false` не вешает слой вовсе — чтобы не плодить NSView там, где жест не нужен.
    @ViewBuilder
    func onSecondaryClick(enabled: Bool = true, perform action: @escaping () -> Void) -> some View {
        if enabled {
            overlay(SecondaryClickCatcher(action: action))
        } else {
            self
        }
    }
}

// MARK: - Нажатие с первого клика

/// Нажатие, доходящее до контрола с ПЕРВОГО клика в неактивном окне.
///
/// `FirstMouseHostingView.acceptsFirstMouse` пропускает клик внутрь SwiftUI, но этого хватает
/// только кнопкам (`Button`): жесты (`onTapGesture`, `DragGesture`) первый клик, которым окно
/// делается активным, всё равно теряют. Поэтому нажатие ловим своим NSView — он сам отвечает
/// `acceptsFirstMouse` и получает mouseDown/mouseUp напрямую.
///
/// Слой прозрачен для вторичного клика (ПКМ / Ctrl+ЛКМ) — его обрабатывает `onSecondaryClick`
/// либо контекстное меню SwiftUI.
struct FirstMouseTapCatcher: NSViewRepresentable {

    /// Точка нажатия в координатах вью (оси как в SwiftUI: Y вниз).
    var onTap: (CGPoint) -> Void
    var onDoubleTap: (() -> Void)? = nil

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: CatcherView) {
        view.onTap = onTap
        view.onDoubleTap = onDoubleTap
    }

    final class CatcherView: NSView {
        var onTap: ((CGPoint) -> Void)?
        var onDoubleTap: (() -> Void)?

        private var isPressed = false

        /// Оси как в SwiftUI — точку нажатия отдаём без пересчёта.
        override var isFlipped: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Слой забирает ТОЛЬКО обычное левое нажатие. Наведение, прокрутка, ПКМ и Ctrl+ЛКМ
        /// проходят мимо — иначе он ломал бы `.onHover` (курсор-палец), зум колесом и
        /// контекстные меню под собой.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .leftMouseDown, .leftMouseUp:
                return event.modifierFlags.contains(.control) ? nil : super.hitTest(point)
            default:
                return nil
            }
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2, let onDoubleTap {
                isPressed = false
                onDoubleTap()
                return
            }
            isPressed = true
        }

        override func mouseUp(with event: NSEvent) {
            guard isPressed else { return }
            isPressed = false
            // Нажали и увели курсор за пределы кнопки — это не тап.
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return }
            onTap?(point)
        }
    }
}

extension View {
    /// Тап, срабатывающий с первого клика даже в неактивном окне (замена `.onTapGesture`).
    func onFirstMouseTap(doubleTap: (() -> Void)? = nil, perform action: @escaping () -> Void) -> some View {
        overlay(FirstMouseTapCatcher(onTap: { _ in action() }, onDoubleTap: doubleTap))
    }

    /// Тот же тап, но с точкой нажатия в координатах вью — когда важно КУДА нажали.
    func onFirstMouseTap(location action: @escaping (CGPoint) -> Void) -> some View {
        overlay(FirstMouseTapCatcher(onTap: action))
    }
}

// MARK: - Пинч-зум в неактивном окне

/// Пинч-зум, работающий, когда окно не в фокусе.
///
/// `MagnificationGesture` — такой же SwiftUI-жест, как остальные: в неключевом окне он событий
/// не получает, поэтому зум требовал сперва «взять окно в фокус». Панорама колесом этим не
/// страдала, потому что слушает `NSEvent` напрямую — здесь делаем ровно то же самое для `.magnify`.
///
/// Колбэки повторяют семантику `MagnificationGesture`: в них приходит масштаб ОТНОСИТЕЛЬНО
/// начала жеста (1.0 — без изменений), так что вызывающий код можно переносить один в один.
private struct FirstMouseMagnifyModifier: ViewModifier {

    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    @State private var monitor: Any?
    @State private var isHovering = false
    /// Накопленный масштаб текущего жеста: `NSEvent.magnification` — приращение, а не итог.
    @State private var accumulated: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .onAppear { install() }
            .onDisappear { remove() }
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { event in
            // Жест адресован тому, над чем курсор, — как и панорама колесом.
            guard isHovering else { return event }
            switch event.phase {
            case .began:
                accumulated = 1
            case .ended, .cancelled:
                let final = accumulated
                accumulated = 1
                onEnded(final)
                return nil
            default:
                break
            }
            accumulated *= (1 + event.magnification)
            onChanged(accumulated)
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    /// Пинч-зум, срабатывающий и в неактивном окне (замена `MagnificationGesture`).
    /// В колбэки приходит масштаб относительно начала жеста, как у SwiftUI-жеста.
    func onFirstMouseMagnify(
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping (CGFloat) -> Void = { _ in }
    ) -> some View {
        modifier(FirstMouseMagnifyModifier(onChanged: onChanged, onEnded: onEnded))
    }
}

// MARK: - Перетаскивание с первого клика

/// Перетаскивание, работающее в НЕактивном окне с первого нажатия.
///
/// `FirstMouseHostingView.acceptsFirstMouse` пропускает первый клик к SwiftUI-контенту, но
/// `DragGesture` этого не хватает: первое нажатие в неактивном окне уходит на активацию, и жест
/// начинается только со второго. Поэтому перетаскивание ловим своим NSView — он сам отвечает
/// `acceptsFirstMouse` и получает mouseDown/Dragged/Up напрямую.
///
/// Смещение считается от точки нажатия в координатах ОКНА, поэтому не зависит от того, что вью
/// во время жеста двигается (как `.position`-ированный элемент), и приводится к осям SwiftUI (Y вниз).
struct FirstMouseDragCatcher: NSViewRepresentable {

    var onBegin: () -> Void = {}
    /// Смещение от точки нажатия в точках, оси как в SwiftUI.
    var onDrag: (CGSize) -> Void
    var onEnd: () -> Void = {}
    var onDoubleClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: CatcherView) {
        view.onBegin = onBegin
        view.onDrag = onDrag
        view.onEnd = onEnd
        view.onDoubleClick = onDoubleClick
    }

    final class CatcherView: NSView {
        var onBegin: () -> Void = {}
        var onDrag: (CGSize) -> Void = { _ in }
        var onEnd: () -> Void = {}
        var onDoubleClick: (() -> Void)?

        private var pressOrigin: NSPoint?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Слой прозрачен для вторичного клика (ПКМ / Ctrl+ЛКМ) — он не про перетаскивание.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return super.hitTest(point) }
            switch event.type {
            case .rightMouseDown, .rightMouseUp:
                return nil
            case .leftMouseDown, .leftMouseUp:
                return event.modifierFlags.contains(.control) ? nil : super.hitTest(point)
            default:
                return super.hitTest(point)
            }
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2, let onDoubleClick {
                pressOrigin = nil
                onDoubleClick()
                return
            }
            pressOrigin = event.locationInWindow
            onBegin()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let origin = pressOrigin else { return }
            onDrag(CGSize(
                width: event.locationInWindow.x - origin.x,
                // В AppKit ось Y направлена вверх, в SwiftUI — вниз.
                height: origin.y - event.locationInWindow.y
            ))
        }

        override func mouseUp(with event: NSEvent) {
            guard pressOrigin != nil else { return }
            pressOrigin = nil
            onEnd()
        }
    }
}
