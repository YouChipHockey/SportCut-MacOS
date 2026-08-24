//
//  SheetHostWindowAccessor.swift
//  Youchip-Stat
//

import SwiftUI
import AppKit

/// Достаёт высоту окна, к которому прицеплен лист (`window.sheetParent`).
///
/// Лист — часть окна, а не отдельное окно: если его содержимое выше окна, AppKit «поднимает»
/// окно и лист вылезает за его края. Поэтому размеры листов считаем от окна-хозяина, а не от
/// экрана. Ставится фоном (`.background(...)`) на корень листа.
struct SheetHostWindowAccessor: NSViewRepresentable {

    let onResolve: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        report(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        report(from: nsView)
    }

    /// Окно появляется у вью не сразу — читаем его следующим тиком.
    private func report(from view: NSView) {
        DispatchQueue.main.async {
            guard let host = view.window?.sheetParent, host.frame.height > 0 else { return }
            onResolve(host.frame.height)
        }
    }
}

/// Держит лист в границах окна-хозяина: ширина фиксированная, высота — «родная», но не больше
/// окна. Внутри листа содержимое должно уметь скроллиться, иначе при низком окне часть уедет.
struct SheetFitsHostWindow: ViewModifier {

    let width: CGFloat
    let naturalHeight: CGFloat

    /// До показа листа ключевое окно — это ещё хозяин, поэтому первый кадр уже верный.
    @State private var hostWindowHeight: CGFloat? = NSApp.keyWindow?.frame.height

    private var resolvedHeight: CGFloat {
        guard let host = hostWindowHeight, host > 0 else { return naturalHeight }
        return min(naturalHeight, max(200, host - 40))
    }

    func body(content: Content) -> some View {
        content
            .frame(width: width, height: resolvedHeight)
            .background(SheetHostWindowAccessor { height in
                if hostWindowHeight != height { hostWindowHeight = height }
            })
    }
}

extension View {
    /// `.frame(width:height:)` для листа, но высота ужимается под окно, из которого он открыт.
    func sheetFitsHostWindow(width: CGFloat, height: CGFloat) -> some View {
        modifier(SheetFitsHostWindow(width: width, naturalHeight: height))
    }
}
