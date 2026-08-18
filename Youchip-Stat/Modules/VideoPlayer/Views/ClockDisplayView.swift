//
//  ClockDisplayView.swift
//  Youchip-Stat
//
//  Визуализация секундомера/таймера. Один вью на все места: кнопка холста в редакторе, живая
//  кнопка в библиотеке тегов, оверлей поверх видео. Вариант вида + стиль передаются снаружи.
//

import SwiftUI

/// Стиль отрисовки счётчика (берётся из TagFreeLayoutItem: цвета/шрифт).
struct ClockStyle {
    var foreground: Color = .white
    var accent: Color = .accentColor
    var cellBackground: Color = Color.black.opacity(0.55)
    var fontWeight: Font.Weight = .semibold

    static let `default` = ClockStyle()
}

struct ClockDisplayView: View {
    let seconds: Double
    let appearance: ClockAppearance
    var showCentiseconds: Bool = true
    var style: ClockStyle = .default
    /// Доля заполнения кольца 0…1 (для .ring). nil → вычисляем как долю минуты.
    var progress: Double? = nil
    /// Подпись под циферблатом. Пустая — не рисуется и места не занимает.
    var caption: String = ""

    var body: some View {
        if caption.isEmpty {
            dial
        } else {
            VStack(spacing: 2) {
                dial
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(style.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var dial: some View {
        let comps = ClockTimeComponents(seconds)
        return GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                switch appearance {
                case .segments: segments(comps, size: geo.size)
                case .analog:   analog(comps, side: side)
                case .ring:     ring(comps, side: side)
                case .text:     textView(comps, size: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Segments (HH.MM.SS.CC)

    @ViewBuilder
    private func segments(_ c: ClockTimeComponents, size: CGSize) -> some View {
        let digits = c.digits8
        let visible = showCentiseconds ? 8 : 6
        let sepCount = showCentiseconds ? 3 : 2
        let cellH = size.height
        // Ширину ячейки подбираем так, чтобы весь ряд (ячейки + разделители + отступы) уместился
        // в заданную ширину — иначе сегменты вылезали за рамку объекта.
        let spacingRatio: CGFloat = 0.12
        let sepRatio: CGFloat = 0.5
        let denom = CGFloat(visible) + sepRatio * CGFloat(sepCount) + spacingRatio * CGFloat(visible + sepCount - 1)
        let widthBasedCellW = denom > 0 ? size.width / denom : cellH * 0.62
        let cellW = max(3, min(cellH * 0.62, widthBasedCellW))
        let sepW = cellW * sepRatio
        let corner = cellW * 0.18
        let font = digitFont(min(cellW, cellH * 0.7))
        HStack(spacing: cellW * spacingRatio) {
            ForEach(0..<visible, id: \.self) { i in
                Text("\(digits[i])")
                    .font(font)
                    .foregroundColor(style.foreground)
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .frame(width: cellW, height: cellH)
                    .background(RoundedRectangle(cornerRadius: corner).fill(style.cellBackground))
                    .overlay(RoundedRectangle(cornerRadius: corner).stroke(style.accent.opacity(0.5), lineWidth: 1))
                if i == 1 || i == 3 {
                    Text(":").font(font).foregroundColor(style.foreground.opacity(0.8)).frame(width: sepW)
                } else if i == 5 && showCentiseconds {
                    Text(".").font(font).foregroundColor(style.foreground.opacity(0.8)).frame(width: sepW)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Analog

    @ViewBuilder
    private func analog(_ c: ClockTimeComponents, side: CGFloat) -> some View {
        let r: CGFloat = side / 2
        let hourAngle: Double = (Double(c.hours % 12) + Double(c.minutes) / 60.0) / 12.0 * 360.0
        let minuteAngle: Double = (Double(c.minutes) + Double(c.seconds) / 60.0) / 60.0 * 360.0
        let secondAngle: Double = (Double(c.seconds) + Double(c.centis) / 100.0) / 60.0 * 360.0
        let ringWidth: CGFloat = max(1.5, side * 0.03)
        let tickW: CGFloat = max(1, side * 0.012)
        let tickH: CGFloat = side * 0.07
        let tickOffset: CGFloat = -r + side * 0.05
        let hubSize: CGFloat = side * 0.06
        ZStack {
            Circle().stroke(style.accent, lineWidth: ringWidth)
            ForEach(0..<12, id: \.self) { t in
                Rectangle()
                    .fill(style.foreground.opacity(0.6))
                    .frame(width: tickW, height: tickH)
                    .offset(y: tickOffset)
                    .rotationEffect(.degrees(Double(t) * 30.0))
            }
            hand(length: r * 0.5, width: side * 0.035, color: style.foreground, angle: hourAngle)
            hand(length: r * 0.72, width: side * 0.025, color: style.foreground, angle: minuteAngle)
            hand(length: r * 0.82, width: side * 0.012, color: style.accent, angle: secondAngle)
            Circle().fill(style.accent).frame(width: hubSize, height: hubSize)
        }
        .frame(width: side, height: side)
    }

    private func hand(length: CGFloat, width: CGFloat, color: Color, angle: Double) -> some View {
        RoundedRectangle(cornerRadius: width / 2)
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
    }

    // MARK: - Ring

    @ViewBuilder
    private func ring(_ c: ClockTimeComponents, side: CGFloat) -> some View {
        let computed: Double = (Double(c.seconds) + Double(c.centis) / 100.0) / 60.0
        let frac: CGFloat = CGFloat(min(1.0, max(0.0, progress ?? computed)))
        let lineW: CGFloat = max(2, side * 0.08)
        let fontSize: CGFloat = side * 0.2
        let pad: CGFloat = side * 0.16
        let label: String = c.string(showCentis: false)
        ZStack {
            Circle().stroke(style.foreground.opacity(0.2), lineWidth: lineW)
            Circle()
                .trim(from: 0, to: frac)
                .stroke(style.accent, style: StrokeStyle(lineWidth: lineW, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(digitFont(fontSize))
                .foregroundColor(style.foreground)
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .padding(pad)
        }
        .frame(width: side, height: side)
    }

    // MARK: - Text

    @ViewBuilder
    private func textView(_ c: ClockTimeComponents, size: CGSize) -> some View {
        Text(c.string(showCentis: showCentiseconds))
            .font(digitFont(size.height * 0.7))
            .foregroundColor(style.foreground)
            .minimumScaleFactor(0.2)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Font

    private func digitFont(_ size: CGFloat) -> Font {
        .system(size: max(6, size), weight: style.fontWeight, design: .monospaced)
    }
}
