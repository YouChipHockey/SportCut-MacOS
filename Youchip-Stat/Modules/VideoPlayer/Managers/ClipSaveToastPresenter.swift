//
//  ClipSaveToastPresenter.swift
//  Youchip-Stat
//
//  Самоисчезающее уведомление о сохранении клипа в правом нижнем углу ЭКРАНА
//  (screen-space, поверх любых окон приложения). Без кнопок и модалок — чтобы
//  не мешать аналитику в лайв-разметке.
//

import AppKit
import SwiftUI

final class ClipSaveToastPresenter {

    static let shared = ClipSaveToastPresenter()

    enum Style {
        case success
        case error
        case info
    }

    private var panel: NSPanel?
    private var hideTask: DispatchWorkItem?
    /// Модель прогресс-баннера — обновляется на месте, без пересоздания панели (плавный прогресс).
    private let progressModel = ProgressToastModel()
    /// Сейчас на экране прогресс-баннер (а не обычный тост).
    private var showingProgress = false

    private init() {}

    /// Показать тост. Можно вызывать с любого потока.
    func show(_ text: String, style: Style = .success) {
        if Thread.isMainThread {
            present(text, style: style)
        } else {
            DispatchQueue.main.async { [weak self] in self?.present(text, style: style) }
        }
    }

    /// Показать/обновить баннер прогресса экспорта (не исчезает сам; заменяется вызовом `show`).
    /// `progress` — 0…1. Можно вызывать с любого потока.
    func showProgress(_ text: String, progress: Double) {
        if Thread.isMainThread {
            presentProgress(text, progress: progress)
        } else {
            DispatchQueue.main.async { [weak self] in self?.presentProgress(text, progress: progress) }
        }
    }

    private func presentProgress(_ text: String, progress: Double) {
        hideTask?.cancel()
        progressModel.text = text
        progressModel.progress = min(max(progress, 0), 1)

        guard !showingProgress else { return } // панель уже есть — обновилась только модель
        showingProgress = true

        let hosting = NSHostingView(rootView: ClipSaveProgressToastView(model: progressModel))
        if #available(macOS 13.0, *) { hosting.sizingOptions = [] }
        let size = NSSize(width: 300, height: 54)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(size)

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        positionPanel(panel, size: size)
        panel.orderFrontRegardless()
    }

    private func present(_ text: String, style: Style) {
        hideTask?.cancel()
        showingProgress = false

        let hosting = NSHostingView(rootView: ClipSaveToastView(text: text, style: style))
        // ВАЖНО: не позволяем hosting-view управлять размером окна-панели. Иначе NSHostingView
        // на каждый layout гоняет updateWindowContentSizeExtrema → бесконечный цикл
        // «Update Constraints in Window» → NSGenericException и краш (падало на всплытии тоста
        // при старте записи интервального тега).
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        let fitting = hosting.fittingSize
        let size = NSSize(width: min(max(fitting.width, 160), 460), height: max(fitting.height, 36))

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(size)

        // hosting кладём в промежуточный контейнер, а не делаем его contentView напрямую —
        // на macOS 12 (где нет sizingOptions) это тоже разрывает связь hosting → размер окна.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        positionPanel(panel, size: size)
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    /// Скрыть прогресс-баннер без показа результата (например, при отмене экспорта).
    func dismissProgress() {
        let work: () -> Void = { [weak self] in
            guard let self, self.showingProgress else { return }
            self.showingProgress = false
            self.hideTask?.cancel()
            self.panel?.orderOut(nil)
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Прижимает панель к нижнему-правому углу активного экрана.
    private func positionPanel(_ panel: NSPanel, size: NSSize) {
        guard let screenFrame = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame else { return }
        let margin: CGFloat = 24
        let origin = NSPoint(
            x: screenFrame.maxX - size.width - margin,
            y: screenFrame.minY + margin
        )
        panel.setFrameOrigin(origin)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

/// Наблюдаемая модель прогресс-баннера — обновление её полей перерисовывает вью без
/// пересоздания панели (плавный прогресс-бар во время экспорта).
private final class ProgressToastModel: ObservableObject {
    @Published var text: String = ""
    @Published var progress: Double = 0
}

private struct ClipSaveProgressToastView: View {
    @ObservedObject var model: ProgressToastModel

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(.green)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.55), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ClipSaveToastView: View {
    let text: String
    let style: ClipSaveToastPresenter.Style

    private var accent: Color {
        switch style {
        case .success: return .green
        case .error: return .red
        case .info: return .white
        }
    }

    private var iconName: String {
        switch style {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accent)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accent.opacity(0.55), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}
