//
//  SportCutSlideRenderer.swift
//  Youchip-Stat
//
//  Renders a title slide (SportCutSlide) into an NSImage. Used for the editor
//  preview, playback and exported film. Single source of truth for how a slide looks.
//

import AppKit
import SwiftUI

enum SportCutSlideRenderer {

    /// Рендерит слайд в изображение заданного размера (по умолчанию 1920×1080).
    /// Размеры/кегли заданы в расчёте на высоту 1080 и масштабируются под фактический размер.
    static func renderImage(for slide: SportCutSlide, size: CGSize = CGSize(width: 1920, height: 1080)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = CGRect(origin: .zero, size: size)
        NSColor(Color(hex: slide.backgroundColorHex)).setFill()
        rect.fill()

        let scale = size.height / 1080.0

        if slide.elements.isEmpty {
            drawLegacy(slide: slide, size: size, scale: scale)
        } else {
            for element in slide.elements {
                draw(element: element, size: size, scale: scale)
            }
        }

        return image
    }

    // MARK: - Element drawing

    private static func draw(element: SportCutSlideElement, size: CGSize, scale: CGFloat) {
        let cx = element.centerX * size.width
        // Нормализованный y: 0 = верх. NSImage — origin снизу.
        let cy = (1 - element.centerY) * size.height

        switch element.kind {
        case .image:
            guard let data = element.imageData, let img = NSImage(data: data) else { return }
            let boxW = max(1, element.width * size.width)
            let boxH = max(1, element.height * size.height)
            let aspect = img.size.width > 0 ? img.size.height / img.size.width : 1
            var w = boxW
            var h = boxW * aspect
            if h > boxH {
                h = boxH
                w = h / max(aspect, 0.0001)
            }
            let drawRect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
            img.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        case .text:
            let trimmed = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let fontSize = max(6, element.fontSize * scale)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment(from: element.alignment)
            paragraph.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font(name: element.fontName, size: fontSize, bold: element.bold),
                .foregroundColor: NSColor(Color(hex: element.colorHex)),
                .paragraphStyle: paragraph
            ]
            let maxTextWidth = size.width * 0.94
            let bounding = (element.text as NSString).boundingRect(
                with: CGSize(width: maxTextWidth, height: size.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            let boxWidth = min(maxTextWidth, max(bounding.width + 4, 40))
            let textRect = CGRect(
                x: cx - boxWidth / 2,
                y: cy - bounding.height / 2,
                width: boxWidth,
                height: bounding.height
            )
            (element.text as NSString).draw(
                with: textRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
        }
    }

    // MARK: - Legacy (slides authored before the layered editor)

    private static func drawLegacy(slide: SportCutSlide, size: CGSize, scale: CGFloat) {
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
            let logoRect = CGRect(x: (size.width - logoW) / 2, y: size.height * 0.55, width: logoW, height: logoH)
            logo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            textCenterY = size.height * 0.30
        }

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
    }

    // MARK: - Helpers

    private static func alignment(from raw: Int) -> NSTextAlignment {
        switch raw {
        case 0: return .left
        case 2: return .right
        default: return .center
        }
    }

    static func font(name: String?, size: CGFloat, bold: Bool) -> NSFont {
        if let name, !name.isEmpty, let base = NSFont(name: name, size: size) {
            if bold {
                let bolded = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
                return bolded
            }
            return base
        }
        return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    }
}
