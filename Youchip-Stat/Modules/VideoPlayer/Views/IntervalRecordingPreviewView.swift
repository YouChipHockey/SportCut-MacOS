//
//  IntervalRecordingPreviewView.swift
//  Youchip-Stat
//
//  Растущий «призрачный» штамп интервального тега, пока идёт запись.
//

import Combine
import SwiftUI

/// Слой поверх дорожек таймлайна с интервальными тегами, которые сейчас пишутся.
///
/// Кладётся в тот же `ZStack`, что и плейхед, с тем же `.padding(.top, markerHeadBand)` —
/// поэтому внутри координаты считаются от верха линейки: `topInset` (высота линейки) плюс
/// `rowHeight` на строку. Кликов не перехватывает.
///
/// **Про перерисовку.** Внешняя вьюха подписана только на стор записей, поэтому пока
/// ничего не пишется — на часы плеера никто не подписан и 30-герцовых перерисовок нет.
/// Подписку на `PlaybackClock` держит вложенная `IntervalRecordingBars`, которая
/// создаётся только на время записи (см. предупреждение в `PlaybackClock`).
struct IntervalRecordingPreviewOverlay: View {

    let duration: Double
    let gridWidth: CGFloat
    /// Те же строки и в том же порядке, что отрисованы в таймлайне (`displayLines`).
    let lines: [TimelineLine]
    let selectedLineID: UUID?
    let rowHeight: CGFloat
    /// Высота линейки времени над дорожками.
    let topInset: CGFloat

    @ObservedObject private var store = IntervalRecordingPreviewStore.shared
    @ObservedObject private var tailManager = LiveStampTailManager.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            let rows = resolvedRows()
            if !rows.isEmpty, duration > 0, gridWidth > 0 {
                IntervalRecordingBars(
                    rows: rows,
                    duration: duration,
                    gridWidth: gridWidth,
                    rowHeight: rowHeight,
                    topInset: topInset
                )
            }

            let tails = resolvedTails()
            if !tails.isEmpty, duration > 0, gridWidth > 0 {
                LiveTailBars(
                    rows: tails,
                    duration: duration,
                    gridWidth: gridWidth,
                    rowHeight: rowHeight,
                    topInset: topInset
                )
            }
        }
        .frame(
            width: gridWidth,
            height: topInset + CGFloat(max(lines.count, 1)) * rowHeight,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
        // Именно короткий easeOut, а не пружина: штамп должен просто ПОЯВИТЬСЯ на своём месте
        // в момент старта записи. Всё «движение» даёт сам рост штампа вслед за плейхедом.
        .animation(.easeOut(duration: 0.15), value: store.allItems)
    }

    /// Раскладывает записи по строкам: индекс строки считаем здесь, а не в вьюхе, которая
    /// перерисовывается по часам плеера — там должно остаться только вычисление ширины.
    private func resolvedRows() -> [IntervalRecordingRow] {
        let active = store.allItems
        guard !active.isEmpty else { return [] }
        let isTagBased = (MarkupMode.current == .tagBased)
        // Сколько записей уже легло в эту строку — по ним сужаем следующие, как это делают
        // пересекающиеся штампы в `TimelineLineView`.
        var stackByLine: [Int: Int] = [:]
        var rows: [IntervalRecordingRow] = []
        for item in active {
            // Куда ляжет штамп: у счётчика дорожка задана явно (своя на каждый счётчик),
            // у тега — в `tagBased` дорожка тега, в `standard` выбранная.
            let resolvedIndex: Int?
            if let lineID = item.lineID {
                resolvedIndex = lines.firstIndex(where: { $0.id == lineID })
            } else if isTagBased {
                resolvedIndex = lines.firstIndex(where: { $0.tagIdForMode == item.tagId })
            } else if let selected = selectedLineID {
                resolvedIndex = lines.firstIndex(where: { $0.id == selected })
            } else {
                resolvedIndex = nil
            }
            guard let lineIndex = resolvedIndex else { continue }
            let stackIndex = stackByLine[lineIndex, default: 0]
            stackByLine[lineIndex] = stackIndex + 1
            rows.append(IntervalRecordingRow(item: item, lineIndex: lineIndex, stackIndex: stackIndex))
        }
        return rows
    }
}

struct IntervalRecordingRow: Equatable {
    let item: IntervalRecordingPreviewStore.Item
    let lineIndex: Int
    let stackIndex: Int
}

/// Хвост штампа, который в лайве ещё дописывается: от текущего конца штампа до записанного.
struct LiveTailRow: Equatable {
    let id: UUID
    let colorHex: String
    let lineIndex: Int
    /// Текущий конец штампа — левый край растущего хвоста.
    let stampFinish: Double
    let desiredFinish: Double
    /// Высота штампа с учётом наложений — чтобы хвост шёл с ним заподлицо.
    let height: CGFloat
}

extension IntervalRecordingPreviewOverlay {

    /// Привязывает хвосты к строкам и повторяет расчёт высоты штампа из `TimelineLineView`
    /// (каждое наложение с более ранним штампом сужает клип на 6 pt).
    fileprivate func resolvedTails() -> [LiveTailRow] {
        guard !tailManager.tails.isEmpty else { return [] }
        var rows: [LiveTailRow] = []
        for tail in tailManager.tails {
            guard let lineIndex = lines.firstIndex(where: { line in
                line.stamps.contains(where: { $0.id == tail.stampID })
            }) else { continue }
            let stamps = lines[lineIndex].stamps
            guard let stampIndex = stamps.firstIndex(where: { $0.id == tail.stampID }) else { continue }
            let stamp = stamps[stampIndex]
            var overlaps = 0
            for j in 0..<stampIndex {
                if stamp.timeStartSeconds < stamps[j].timeFinishSeconds,
                   stamps[j].timeStartSeconds < stamp.timeFinishSeconds {
                    overlaps += 1
                }
            }
            rows.append(
                LiveTailRow(
                    id: tail.stampID,
                    colorHex: tail.colorHex,
                    lineIndex: lineIndex,
                    stampFinish: stamp.timeFinishSeconds,
                    desiredFinish: tail.desiredFinish,
                    height: max(7, 25 - CGFloat(overlaps * 6))
                )
            )
        }
        return rows
    }
}

/// Дорисовка хвостов. Растут по `liveDuration` (10 Гц) — на паузе трансляции стоят.
private struct LiveTailBars: View {

    let rows: [LiveTailRow]
    let duration: Double
    let gridWidth: CGFloat
    let rowHeight: CGFloat
    let topInset: CGFloat

    /// Не `@ObservedObject` на весь `LiveStreamManager`: у него десяток `@Published`
    /// (устройства, конфигурация сессии), а нужна ровно длительность записи.
    @State private var recorded: Double = LiveStreamManager.shared.liveDuration

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rows, id: \.id) { row in
                tail(for: row)
            }
        }
        .onReceive(LiveStreamManager.shared.$liveDuration) { recorded = $0 }
    }

    @ViewBuilder
    private func tail(for row: LiveTailRow) -> some View {
        let end = min(row.desiredFinish, recorded)
        if end > row.stampFinish {
            let startX = min(max(row.stampFinish / duration, 0), 1) * gridWidth
            let endX = min(max(end / duration, 0), 1) * gridWidth
            // Заезжаем на скруглённый край штампа: иначе на стыке остаётся выемка от его
            // скругления. Эта часть хвоста непрозрачная — она лежит поверх самого штампа.
            let joint: CGFloat = 6
            let width = max(endX - startX, 1) + joint
            let centerY = topInset + CGFloat(row.lineIndex) * rowHeight + rowHeight / 2

            LiveTailBar(
                color: ColorHexCache.color(hex: row.colorHex),
                width: width,
                height: row.height,
                joint: joint
            )
            // Длительность записи тикает 10 раз в секунду — сглаживаем шаги, чтобы
            // хвост «дописывался» плавно, а не рывками.
            .animation(.linear(duration: 0.1), value: width)
            .transition(.opacity)
            .offset(x: startX - joint, y: centerY - row.height / 2)
        }
    }
}

/// Вид растущего хвоста: непрозрачный стык со штампом, дальше — полупрозрачное тело,
/// которое тает к «головке» записи. Полупрозрачность держится до самого конца: штамп
/// докрашивается один раз, когда хвост дописан (см. `LiveStampTailManager`).
private struct LiveTailBar: View {

    let color: Color
    let width: CGFloat
    let height: CGFloat
    /// Ширина стыка со штампом (в этих пикселях хвост лежит поверх него).
    let joint: CGFloat

    @State private var isPulsing = false

    var body: some View {
        LiveTailShape(radius: 6)
            .fill(bodyGradient)
            .frame(width: width, height: height)
            // Контур помогает хвосту читаться на сетке, но у стыка сходит на нет —
            // иначе поперёк штампа шла бы заметная вертикальная черта.
            .overlay(
                LiveTailShape(radius: 6)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [color.opacity(0), color.opacity(0.5)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .trailing) { recordingHead }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }

    /// Слева — цвет штампа в полную силу (стык), дальше резкий переход в полупрозрачность
    /// и мягкое затухание к головке.
    private var bodyGradient: LinearGradient {
        let jointStop = min(max(joint / max(width, 1), 0.01), 0.85)
        return LinearGradient(
            gradient: Gradient(stops: [
                .init(color: color.opacity(0.95), location: 0),
                .init(color: color.opacity(0.95), location: jointStop),
                .init(color: color.opacity(0.4), location: min(jointStop + 0.04, 1)),
                .init(color: color.opacity(0.18), location: 1)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// «Головка» записи у растущего края — светящаяся полоска с пульсацией.
    private var recordingHead: some View {
        Capsule()
            .fill(color)
            .overlay(
                Capsule()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 1.2)
            )
            .frame(width: 3, height: max(height - 4, 4))
            .shadow(color: color.opacity(0.9), radius: isPulsing ? 5 : 2)
            .opacity(isPulsing ? 1 : 0.6)
            .padding(.trailing, 1.5)
    }
}

/// Прямоугольник со скруглением только справа: слева хвост стыкуется со штампом встык.
private struct LiveTailShape: Shape {

    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = max(min(radius, min(rect.height / 2, rect.width)), 0)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Собственно растущие штампы. Единственный подписчик часов плеера в этом слое.
///
/// Часы выбираются ПО ЗАПИСИ, а не по текущему режиму: запись, начатая по плейхеду пересмотра,
/// растёт за бирюзовым до самого конца, даже если посреди неё переключили «Разметку лайва /
/// пересмотра» — ровно так же считаются и границы готового штампа
/// (`VideoPlayerManager.markupTime(usesReview:)`).
private struct IntervalRecordingBars: View {

    let rows: [IntervalRecordingRow]
    let duration: Double
    let gridWidth: CGFloat
    let rowHeight: CGFloat
    let topInset: CGFloat

    // Обе шкалы: у каждой записи свой якорь (лайв или пересмотр), зафиксированный на старте.
    @ObservedObject private var clock = PlaybackClock.shared
    @ObservedObject private var reviewClock = ReviewPlaybackClock.shared

    /// Время, за которым растёт эта конкретная запись.
    private func headTime(for row: IntervalRecordingRow) -> Double {
        row.item.usesReviewTime ? reviewClock.time : clock.time
    }

    /// Цвет «пишущего» края — того плейхеда, за которым растёт штамп: белый (лайв/обычное видео)
    /// или бирюзовый (пересмотр).
    private func edgeColor(for row: IntervalRecordingRow) -> Color {
        row.item.usesReviewTime ? reviewPlayheadTint : .white
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rows, id: \.item.id) { row in
                bar(for: row)
            }
        }
    }

    @ViewBuilder
    private func bar(for row: IntervalRecordingRow) -> some View {
        let startX = min(max(row.item.visualStart / duration, 0), 1) * gridWidth
        let headX = min(max(headTime(for: row) / duration, 0), 1) * gridWidth
        let width = max(headX - startX, 4)
        // Та же логика, что у пересекающихся штампов: каждая следующая запись в строке ниже ростом.
        let height = max(9, 25 - CGFloat(row.stackIndex * 6))
        let centerY = topInset + CGFloat(row.lineIndex) * rowHeight + rowHeight / 2

        IntervalRecordingBar(
            name: row.item.name,
            color: ColorHexCache.color(hex: row.item.colorHex),
            width: width,
            height: height,
            edgeColor: edgeColor(for: row)
        )
        // Транзишен — ВНУТРИ `.offset`, на самом штампе. Снаружи `.offset` его ставить нельзя:
        // `.offset` двигает только отрисовку, layout-фрейм остаётся в левом верхнем углу слоя,
        // и `.scale` считает якорь от угла таймлайна — штамп «вылетал» оттуда.
        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
        .offset(x: startX, y: centerY - height / 2)
    }
}

/// Один растущий штамп: заливка тега вполсилы, пунктирная рамка и мигающая точка записи.
/// Визуально отличается от готового штампа, чтобы «пишется» не путали с «записано».
private struct IntervalRecordingBar: View {

    let name: String
    let color: Color
    let width: CGFloat
    let height: CGFloat
    /// Цвет полоски у «пишущего» края — совпадает с цветом плейхеда, за которым идёт запись.
    var edgeColor: Color = .white

    @State private var isPulsing = false

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [color.opacity(0.55), color.opacity(0.3)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    color.opacity(isPulsing ? 0.95 : 0.45),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                )

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .opacity(isPulsing ? 1 : 0.25)

                if width > 70, height >= 16 {
                    Text(name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                }
            }
            .padding(.leading, 6)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // «Пишущий» край — светлая полоска у плейхеда, чтобы читался рост штампа.
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(edgeColor.opacity(0.9))
                .frame(width: 2, height: height)
                .shadow(color: color.opacity(0.9), radius: 3)
        }
        .shadow(color: color.opacity(0.35), radius: 3, x: 0, y: 1)
        .onAppear {
            // Анимация ставится один раз на жизнь штампа: вьюха перестраивается по часам
            // плеера, но `@State` и запущенная на нём анимация переживают перестроения.
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
