//
//  MomentClocksPanel.swift
//  Youchip-Stat
//
//  Счётчики в пересмотре момента: список тех, что пересекаются с моментом, и их отрисовка
//  поверх видео. Показания берём из записи на скрытом таймлайне (`StampClockInfo`), поэтому
//  счётчик «идёт» ровно так, как шёл во время разметки, — включая момент запуска посреди клипа.
//

import SwiftUI

/// Запись счётчика, попавшая в окно момента.
struct MomentClockEntry: Identifiable {
    let stamp: TimelineStamp
    let info: StampClockInfo

    var id: UUID { stamp.id }
    var title: String { info.caption.isEmpty ? info.name : "\(info.name) — \(info.caption)" }

    /// Показание в этот момент видео; nil — счётчик в это время ещё/уже не шёл.
    func value(atVideoTime time: Double) -> Double? {
        guard time >= stamp.timeStartSeconds, time <= stamp.timeFinishSeconds else { return nil }
        return info.value(
            atVideoTime: time,
            start: stamp.timeStartSeconds,
            finish: stamp.timeFinishSeconds
        )
    }
}

// MARK: - Поиск пересечений

enum MomentClocksFinder {
    /// Записи счётчиков, пересекающиеся с окном [start, start + duration].
    /// Пересчитывается на каждое изменение границ момента, поэтому ресайз клипа сам обновляет список.
    static func entries(from lines: [TimelineLine], start: Double, duration: Double) -> [MomentClockEntry] {
        let finish = start + duration
        guard let line = lines.first(where: { $0.isClocksTimeline }) else { return [] }

        var result: [MomentClockEntry] = []
        for stamp in line.stamps {
            guard stamp.timeStartSeconds < finish, stamp.timeFinishSeconds > start else { continue }
            guard let info = stamp.clockInfo else { continue }
            result.append(MomentClockEntry(stamp: stamp, info: info))
        }
        result.sort { $0.stamp.timeStartSeconds < $1.stamp.timeStartSeconds }
        return result
    }
}

// MARK: - Панель выбора

/// Список счётчиков момента с галочками. Пустой список панель не показывает вовсе.
struct MomentClocksPanel: View {
    let entries: [MomentClockEntry]
    @Binding var enabledStampIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(^String.Titles.clockCountersTitle)
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(entries) { entry in
                Toggle(isOn: binding(for: entry)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title)
                            .font(.caption)
                            .lineLimit(1)
                        Text(rangeText(entry))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 190, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func binding(for entry: MomentClockEntry) -> Binding<Bool> {
        Binding(
            get: { enabledStampIDs.contains(entry.id) },
            set: { on in
                if on { enabledStampIDs.insert(entry.id) } else { enabledStampIDs.remove(entry.id) }
            }
        )
    }

    /// Границы отрезка счётчика в исходном видео — чтобы было видно, когда он шёл.
    private func rangeText(_ entry: MomentClockEntry) -> String {
        let comps = ClockTimeComponents(entry.info.startValue).string(showCentis: false)
        let compsEnd = ClockTimeComponents(entry.info.endValue).string(showCentis: false)
        return "\(comps) → \(compsEnd)"
    }
}

// MARK: - Отрисовка поверх видео

/// Включённые счётчики стопкой в правом верхнем углу кадра.
struct MomentClocksOverlay: View {
    let entries: [MomentClockEntry]
    let enabledStampIDs: Set<UUID>
    /// Время в ИСХОДНОМ видео (начало момента + позиция воспроизведения).
    let videoTime: Double

    var body: some View {
        let shown = entries.filter { enabledStampIDs.contains($0.id) }
        if shown.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(shown) { entry in
                    if let value = entry.value(atVideoTime: videoTime) {
                        ClockDisplayView(
                            seconds: value,
                            appearance: entry.info.appearance,
                            showCentiseconds: entry.info.showCentiseconds,
                            style: ClockStyle(
                                foreground: .white,
                                accent: .accentColor,
                                cellBackground: Color.black.opacity(0.6),
                                fontWeight: .semibold
                            ),
                            progress: nil,
                            caption: entry.info.caption
                        )
                        .frame(
                            width: ClockOverlayMetrics.size(for: entry.info).width,
                            height: ClockOverlayMetrics.size(for: entry.info).height
                        )
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Размеры

/// Размер счётчика поверх видео. Общий для пересмотра и экспорта, чтобы клип и его экспорт
/// выглядели одинаково.
enum ClockOverlayMetrics {
    static func size(for info: StampClockInfo) -> CGSize {
        size(appearance: info.appearance, showCentiseconds: info.showCentiseconds, hasCaption: !info.caption.isEmpty)
    }

    static func size(appearance: ClockAppearance, showCentiseconds: Bool, hasCaption: Bool) -> CGSize {
        let base: CGSize
        switch appearance {
        case .segments: base = CGSize(width: showCentiseconds ? 220 : 170, height: 44)
        case .analog, .ring: base = CGSize(width: 96, height: 96)
        case .text: base = CGSize(width: showCentiseconds ? 150 : 120, height: 44)
        }
        return hasCaption ? CGSize(width: base.width, height: base.height + 16) : base
    }
}
