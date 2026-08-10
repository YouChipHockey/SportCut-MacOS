//
//  ClubLogoWatermarkSettingsView.swift
//  Youchip-Stat
//
//  Настройка логотипа клуба: выбор картинки и её позиции/размера на кадре.
//  Серый холст 16:9 — можно плавно двигать лого и менять размер за угловую ручку.
//

import SwiftUI

struct ClubLogoWatermarkSettingsView: View {
    @ObservedObject private var manager = ClubLogoWatermarkManager.shared
    var onClose: (() -> Void)? = nil

    // Живое состояние жестов — для плавности не пишем в менеджер на каждый кадр.
    @State private var dragStartOrigin: CGPoint? = nil
    @State private var resizeStartWidth: CGFloat? = nil

    private let handleSize: CGFloat = 18
    // Стабильная система координат холста. Жесты меряем относительно неё, а не
    // относительно самой лого/ручки — иначе двигающийся под курсором элемент
    // пересчитывает translation и получается петля лэйаута (зависание при resize).
    private let canvasSpace = "clubLogoCanvas"

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(^String.Titles.clubLogoTitle)
                    .font(.headline)
                Spacer()
                Button {
                    manager.persist()
                    onClose?()
                } label: {
                    Text(^String.Titles.done)
                }
                .keyboardShortcut(.defaultAction)
            }

            Text(^String.Titles.clubLogoHint)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            editorCanvas

            HStack(spacing: 12) {
                Button {
                    manager.pickLogoFromDisk()
                } label: {
                    SwiftUI.Label(manager.hasLogo ? ^String.Titles.clubLogoReplace : ^String.Titles.clubLogoChoose,
                                  systemImage: "photo")
                }
                if manager.hasLogo {
                    Button(role: .destructive) {
                        manager.removeLogo()
                    } label: {
                        SwiftUI.Label(^String.Titles.deleteButtonTitle, systemImage: "trash")
                    }
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var editorCanvas: some View {
        GeometryReader { geo in
            // Холст фиксированной пропорции 16:9 по центру области.
            let canvas = fittedCanvasSize(in: geo.size)
            let originX = (geo.size.width - canvas.width) / 2
            let originY = (geo.size.height - canvas.height) / 2

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.darkGray).opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .frame(width: canvas.width, height: canvas.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                if manager.hasLogo, let image = manager.logoImage {
                    logoRect(in: canvas, canvasOrigin: CGPoint(x: originX, y: originY), image: image)
                } else {
                    Text(^String.Titles.clubLogoNotSet)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: canvas.width, height: canvas.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .coordinateSpace(name: canvasSpace)
        }
        .frame(height: 300)
    }

    @ViewBuilder
    private func logoRect(in canvas: CGSize, canvasOrigin: CGPoint, image: NSImage) -> some View {
        let w = manager.normWidth * canvas.width
        let h = w * manager.imageAspect
        let x = canvasOrigin.x + manager.normOrigin.x * canvas.width
        let y = canvasOrigin.y + manager.normOrigin.y * canvas.height

        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: w, height: h)
            .overlay(
                Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            )
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: handleSize, height: handleSize)
                    .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white))
                    .offset(x: handleSize / 2, y: handleSize / 2)
                    .gesture(resizeGesture(canvas: canvas))
            }
            .position(x: x + w / 2, y: y + h / 2)
            .gesture(dragGesture(canvas: canvas))
    }

    private func dragGesture(canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasSpace))
            .onChanged { value in
                if dragStartOrigin == nil { dragStartOrigin = manager.normOrigin }
                guard let startOrigin = dragStartOrigin, canvas.width > 0, canvas.height > 0 else { return }
                let dx = value.translation.width / canvas.width
                let dy = value.translation.height / canvas.height
                manager.normOrigin = CGPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)
                manager.clampLayout()
            }
            .onEnded { _ in
                dragStartOrigin = nil
                manager.persist()
            }
    }

    private func resizeGesture(canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasSpace))
            .onChanged { value in
                if resizeStartWidth == nil { resizeStartWidth = manager.normWidth }
                guard let startWidth = resizeStartWidth, canvas.width > 0 else { return }
                let dw = value.translation.width / canvas.width
                manager.normWidth = startWidth + dw
                manager.clampLayout()
            }
            .onEnded { _ in
                resizeStartWidth = nil
                manager.persist()
            }
    }

    /// Вписывает прямоугольник 16:9 в доступную область.
    private func fittedCanvasSize(in available: CGSize) -> CGSize {
        let aspect: CGFloat = 16.0 / 9.0
        var w = available.width
        var h = w / aspect
        if h > available.height {
            h = available.height
            w = h * aspect
        }
        return CGSize(width: max(1, w), height: max(1, h))
    }
}
