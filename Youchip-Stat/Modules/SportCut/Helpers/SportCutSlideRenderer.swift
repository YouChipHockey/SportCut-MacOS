//
//  SportCutSlideRenderer.swift
//  Youchip-Stat
//
//  Renders a title slide (SportCutSlide) into an NSImage. Used for the editor
//  preview and (stage 2) for baking the slide into playback / exported film.
//

import AppKit
import SwiftUI

enum SportCutSlideRenderer {

    /// Рендерит слайд в изображение заданного размера (по умолчанию 1920×1080).
    /// `textSize` слайда задан в расчёте на высоту 1080 и масштабируется под фактический размер.
    static func renderImage(for slide: SportCutSlide, size: CGSize = CGSize(width: 1920, height: 1080)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = CGRect(origin: .zero, size: size)

        // Фон
        NSColor(Color(hex: slide.backgroundColorHex)).setFill()
        rect.fill()

        let scale = size.height / 1080.0

        // Логотип (PNG), если есть — по центру верхней части.
        var textCenterY = size.height / 2
        if let data = slide.imageData, let logo = NSImage(data: data) {
            let maxLogoH = size.height * 0.42
            let maxLogoW = size.width * 0.6
            let aspect = logo.size.width > 0 ? logo.size.height / logo.size.width : 1
            var logoW = maxLogoW
            var logoH = logoW * aspect
            if logoH > maxLogoH {
                logoH = maxLogoH
                logoW = logoH / max(aspect, 0.0001)
            }
            let logoRect = CGRect(
                x: (size.width - logoW) / 2,
                y: size.height * 0.55,
                width: logoW,
                height: logoH
            )
            logo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            // Текст ниже логотипа.
            textCenterY = size.height * 0.30
        }

        // Заголовок — по центру.
        let trimmed = slide.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let fontSize = max(8, slide.textSize * scale)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: NSColor(Color(hex: slide.textColorHex)),
                .paragraphStyle: paragraph
            ]
            let maxTextWidth = size.width * 0.86
            let bounding = (trimmed as NSString).boundingRect(
                with: CGSize(width: maxTextWidth, height: size.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            let textRect = CGRect(
                x: (size.width - maxTextWidth) / 2,
                y: textCenterY - bounding.height / 2,
                width: maxTextWidth,
                height: bounding.height
            )
            (trimmed as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        }

        return image
    }
}
