//
//  ClubLogoWatermarkManager.swift
//  Youchip-Stat
//
//  Логотип клуба как вотермарк на клипах. Пользователь один раз задаёт картинку,
//  её положение и размер в настройках, а при экспорте включает/выключает показ.
//  Позиция и ширина хранятся нормализованными (0…1) относительно кадра видео,
//  высота выводится из пропорций картинки — поэтому лого не искажается.
//

import AppKit
import Combine
import Foundation

final class ClubLogoWatermarkManager: ObservableObject {

    static let shared = ClubLogoWatermarkManager()

    private enum Keys {
        static let normX = "clubLogoNormX"
        static let normY = "clubLogoNormY"
        static let normWidth = "clubLogoNormWidth"
    }

    /// Текущее изображение логотипа (nil — не задан).
    @Published private(set) var logoImage: NSImage?
    /// Левый-верхний угол лого в долях кадра (0…1).
    @Published var normOrigin: CGPoint
    /// Ширина лого в долях ширины кадра (0…1). Высота считается из пропорций картинки.
    @Published var normWidth: CGFloat

    var hasLogo: Bool { logoImage != nil }

    /// Пропорции опорного кадра (редактор рисует холст 16:9). Нужны, чтобы
    /// перевести нормализованную ширину в нормализованную высоту.
    static let frameAspect: CGFloat = 16.0 / 9.0

    /// Соотношение высоты к ширине картинки (для вывода высоты из ширины).
    var imageAspect: CGFloat {
        guard let img = logoImage, img.size.width > 0 else { return 1 }
        return img.size.height / img.size.width
    }

    /// Высота лого в долях высоты кадра (для клампинга и позиционирования).
    /// = normWidth(доля ширины) × imageAspect × пропорции кадра.
    var normHeight: CGFloat {
        normWidth * imageAspect * Self.frameAspect
    }

    private var logoFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = dir.appendingPathComponent("YouChip-Stat", isDirectory: true)
            .appendingPathComponent("ClubLogo", isDirectory: true)
        return folder.appendingPathComponent("logo.png")
    }

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: Keys.normWidth) != nil {
            normOrigin = CGPoint(x: d.double(forKey: Keys.normX), y: d.double(forKey: Keys.normY))
            normWidth = CGFloat(d.double(forKey: Keys.normWidth))
        } else {
            // По умолчанию — правый верхний угол, ~18% ширины кадра.
            normOrigin = CGPoint(x: 0.78, y: 0.04)
            normWidth = 0.18
        }
        loadImageFromDisk()
    }

    // MARK: - Изображение

    func setLogo(_ image: NSImage) {
        logoImage = image
        saveImageToDisk(image)
    }

    func removeLogo() {
        logoImage = nil
        if let url = logoFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Диалог выбора файла картинки.
    func pickLogoFromDisk() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        panel.prompt = ^String.Titles.clubLogoChoose
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        setLogo(image)
    }

    private func loadImageFromDisk() {
        guard let url = logoFileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        logoImage = NSImage(contentsOf: url)
    }

    private func saveImageToDisk(_ image: NSImage) {
        guard let url = logoFileURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    // MARK: - Позиция/размер

    /// Ограничивает позицию/размер так, чтобы лого не вылезало за кадр.
    func clampLayout() {
        // Ширину ограничиваем так, чтобы и по высоте лого влезало в кадр.
        let maxWidthByHeight = imageAspect > 0 ? 1.0 / (imageAspect * Self.frameAspect) : 1.0
        let w = min(max(normWidth, 0.03), min(1.0, maxWidthByHeight))
        normWidth = w
        let h = normHeight
        var x = normOrigin.x
        var y = normOrigin.y
        x = min(max(x, 0), max(0, 1 - w))
        y = min(max(y, 0), max(0, 1 - h))
        normOrigin = CGPoint(x: x, y: y)
    }

    func persist() {
        clampLayout()
        let d = UserDefaults.standard
        d.set(Double(normOrigin.x), forKey: Keys.normX)
        d.set(Double(normOrigin.y), forKey: Keys.normY)
        d.set(Double(normWidth), forKey: Keys.normWidth)
    }

    // MARK: - Экспорт

    /// Слой Core Animation с логотипом для наложения на видео при экспорте.
    /// Система координат Core Animation — снизу-вверх, поэтому Y инвертируется.
    func makeLogoLayer(renderSize: CGSize) -> CALayer? {
        guard let image = logoImage,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let w = min(max(normWidth, 0.03), 1.0) * renderSize.width
        let h = w * imageAspect
        // Клампим в пределах кадра, чтобы лого не вылезало за границы при любом
        // соотношении сторон видео.
        let x = min(max(normOrigin.x * renderSize.width, 0), max(0, renderSize.width - w))
        let yTop = min(max(normOrigin.y * renderSize.height, 0), max(0, renderSize.height - h))
        let caY = renderSize.height - yTop - h

        let layer = CALayer()
        layer.frame = CGRect(x: x, y: caY, width: w, height: h)
        layer.contents = cg
        layer.contentsGravity = .resizeAspect
        layer.isOpaque = false
        return layer
    }
}
