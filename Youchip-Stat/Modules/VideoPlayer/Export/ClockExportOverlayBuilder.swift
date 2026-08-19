//
//  ClockExportOverlayBuilder.swift
//  Youchip-Stat
//
//  Счётчики в экспортируемом видео. Оверлеи экспорта — это CALayer'ы поверх видеослоя, а текст
//  в них статичен на весь клип, поэтому «идущий» счётчик так не нарисовать. Решение: заранее
//  отрисовать циферблат по шагам времени в картинки и прокрутить их дискретной анимацией
//  `contents` — layer при этом остаётся один, а на экране счётчик тикает.
//
//  Показания берутся не из живого движка, а из записи разметки (`StampClockInfo`), поэтому в файле
//  счётчик показывает ровно то, что показывал в тот момент игры — даже если клипы идут не подряд.
//

import AVFoundation
import AppKit
import SwiftUI

/// Где и что рисовать: одна запись счётчика, наложенная на один сегмент композиции.
struct ClockExportPlacement {
    let info: StampClockInfo
    /// Границы записи счётчика в ИСХОДНОМ видео.
    let recordStart: Double
    let recordFinish: Double
    /// Видимый кусок в ВРЕМЕНИ КОМПОЗИЦИИ (пересечение записи и сегмента).
    let visibleStart: Double
    let visibleDuration: Double
    /// Границы видимого куска в ИСХОДНОМ видео — по ним сэмплируем `info.value(atVideoTime:)`
    /// покадрово, чтобы экспорт повторял ход счётчика с паузами (а не линейно start→end).
    let sampleStart: Double
    let sampleFinish: Double
    /// Показания на концах видимого куска (для справки/совместимости).
    let valueAtStart: Double
    let valueAtEnd: Double
    /// Позиция в стопке: 0 — верхний.
    let stackIndex: Int
}

/// Запись счётчика в проекте. Списка выбора в экспорте больше нет — тип остался, чтобы понять,
/// есть ли в проекте счётчики вообще (показывать ли тумблер).
struct ClockExportRecord: Identifiable {
    let id: UUID
    let title: String
}

enum ClockExportRecords {
    /// Все записи счётчиков текущего проекта. Выбирать их в экспорте нельзя (наносится всё, что
    /// видно на кадре) — список нужен только чтобы понять, есть ли счётчики вообще.
    static func available() -> [ClockExportRecord] {
        var result: [ClockExportRecord] = []
        for stamp in TimelineDataManager.shared.lines.clockStamps {
            guard let info = stamp.clockInfo else { continue }
            let name = info.caption.isEmpty ? info.name : "\(info.name) — \(info.caption)"
            let from = ClockTimeComponents(info.startValue).string(showCentis: false)
            let to = ClockTimeComponents(info.endValue).string(showCentis: false)
            result.append(ClockExportRecord(id: stamp.id, title: "\(name)  \(from) → \(to)"))
        }
        return result
    }
}

enum ClockExportOverlayBuilder {

    /// Primary Counter тега момента по его штампу: сначала сохранённый в штампе id (работает без
    /// коллекции, в т.ч. в просмотре), иначе резолвим тег из текущей коллекции (старые штампы).
    static func momentPrimaryClockIds(for stamp: TimelineStamp?) -> Set<String> {
        guard let stamp else { return [] }
        if let pc = stamp.primaryClockId ?? TagLibraryManager.shared.findTagById(stamp.idTag)?.primaryClockId,
           !pc.isEmpty {
            return [pc]
        }
        return []
    }

    /// Шаг перерисовки. С сотыми — чаще (иначе счётчик выглядит замершим), без них хватает секунды.
    private static func step(showCentiseconds: Bool) -> Double { showCentiseconds ? 0.1 : 1.0 }
    /// Предохранитель от гигантских клипов: больше кадров — переходим на секундный шаг.
    private static let maxFramesPerPlacement = 900

    // MARK: - Подбор записей под сегменты

    /// Строит размещения для одного сегмента: какие выбранные счётчики попадают в него и когда.
    ///
    /// - Parameters:
    ///   - sourceRange: кусок ИСХОДНОГО видео, вошедший в композицию;
    ///   - compositionStart: куда этот кусок встал на шкале композиции.
    ///   - momentPrimaryClockIds: Primary Counter тега ЭТОГО момента (сегмента/клипа). Наносится
    ///     даже без флага «Показывать на видео». Именно тега момента, а не всех тегов, попавших под
    ///     кусок исходника, — иначе в командных видах на кадр лезли бы счётчики соседних тегов.
    /// - Parameter enabled: тумблер «экспорт со счётчиками». Наносится всё, что пересекает кусок
    ///   исходника и подлежит показу: флаг `showOnVideo` ЛИБО Primary Counter момента.
    static func placements(
        enabled: Bool,
        lines: [TimelineLine],
        sourceRange: CMTimeRange,
        compositionStart: Double,
        momentPrimaryClockIds: Set<String> = []
    ) -> [ClockExportPlacement] {
        guard enabled else { return [] }
        // У каждого счётчика своя линия — собираем записи со всех.
        let clockStamps = lines.clockStamps
        guard !clockStamps.isEmpty else { return [] }

        let srcStart = CMTimeGetSeconds(sourceRange.start)
        let srcDuration = CMTimeGetSeconds(sourceRange.duration)
        let srcFinish = srcStart + srcDuration
        guard srcDuration > 0 else { return [] }

        let primarySet = momentPrimaryClockIds

        var result: [ClockExportPlacement] = []
        var stackIndex = 0

        for stamp in clockStamps {
            guard let info = stamp.clockInfo else { continue }
            guard info.showOnVideo || primarySet.contains(info.clockId) else { continue }
            let overlapStart = max(stamp.timeStartSeconds, srcStart)
            let overlapFinish = min(stamp.timeFinishSeconds, srcFinish)
            guard overlapFinish - overlapStart > 0.05 else { continue }

            let valueStart = info.value(
                atVideoTime: overlapStart,
                start: stamp.timeStartSeconds,
                finish: stamp.timeFinishSeconds
            )
            let valueEnd = info.value(
                atVideoTime: overlapFinish,
                start: stamp.timeStartSeconds,
                finish: stamp.timeFinishSeconds
            )

            result.append(
                ClockExportPlacement(
                    info: info,
                    recordStart: stamp.timeStartSeconds,
                    recordFinish: stamp.timeFinishSeconds,
                    // Сегмент лежит в композиции подряд, поэтому смещение внутри него сохраняется.
                    visibleStart: compositionStart + (overlapStart - srcStart),
                    visibleDuration: overlapFinish - overlapStart,
                    sampleStart: overlapStart,
                    sampleFinish: overlapFinish,
                    valueAtStart: valueStart,
                    valueAtEnd: valueEnd,
                    stackIndex: stackIndex
                )
            )
            stackIndex += 1
        }
        return result
    }

    // MARK: - Слои

    /// Добавляет счётчики в дерево слоёв экспорта. Вызывать на главном потоке (рисуем через AppKit).
    static func addLayers(
        placements: [ClockExportPlacement],
        to parentLayer: CALayer,
        renderSize: CGSize,
        totalDuration: Double
    ) {
        guard totalDuration > 0 else { return }

        // Масштаб под разрешение кадра: на 4K счётчик размером «как в приложении» был бы неразличим.
        let scale = max(1.0, renderSize.width / 1280.0)
        let padding: CGFloat = 12 * scale

        for placement in placements {
            // Куда и какого размера — так же, как счётчик стоит на экране: если его двигали или
            // меняли размер, экспорт повторяет это (раскладка хранится в долях кадра).
            let layout = ClockOverlayLayoutStore.shared.layout(for: placement.info.clockId)
            let userScale = (layout?.scale ?? ClockOverlayLayout.defaultScale) / ClockOverlayLayout.defaultScale
            let baseSize = ClockOverlayMetrics.size(for: placement.info)
            let size = CGSize(
                width: baseSize.width * scale * CGFloat(userScale),
                height: baseSize.height * scale * CGFloat(userScale)
            )

            let frames = renderFrames(for: placement, size: size)
            guard !frames.isEmpty else { continue }

            let layer = CALayer()
            layer.contentsGravity = .resizeAspect
            if let layout {
                // В CALayer ось Y снизу вверх, а раскладка хранится «от верха» — переворачиваем.
                layer.frame = CGRect(
                    x: CGFloat(layout.centerX) * renderSize.width - size.width / 2,
                    y: renderSize.height - CGFloat(layout.centerY) * renderSize.height - size.height / 2,
                    width: size.width,
                    height: size.height
                )
            } else {
            // Не трогали — стопка сверху вниз в правом верхнем углу, как и на экране.
            let offsetY = CGFloat(placement.stackIndex) * (size.height + 8 * scale)
            layer.frame = CGRect(
                x: renderSize.width - size.width - padding,
                y: renderSize.height - size.height - padding - offsetY,
                width: size.width,
                height: size.height
            )
            }
            layer.contents = frames.first
            layer.opacity = 0
            parentLayer.addSublayer(layer)

            addAnimations(to: layer, frames: frames, placement: placement, totalDuration: totalDuration)
        }
    }

    private static func addAnimations(
        to layer: CALayer,
        frames: [CGImage],
        placement: ClockExportPlacement,
        totalDuration: Double
    ) {
        let start = placement.visibleStart
        let finish = min(totalDuration, start + placement.visibleDuration)
        let startFraction = min(max(start / totalDuration, 0), 1)
        let endFraction = min(max(finish / totalDuration, 0), 1 - 1e-7)
        guard endFraction > startFraction else { return }

        // Видимость: до и после своего куска счётчика в кадре нет.
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 0, 0]
        opacity.keyTimes = [0, NSNumber(value: startFraction), NSNumber(value: endFraction), 1]
        opacity.duration = totalDuration
        opacity.beginTime = AVCoreAnimationBeginTimeAtZero
        opacity.isRemovedOnCompletion = false
        opacity.fillMode = .both
        opacity.calculationMode = .discrete
        layer.add(opacity, forKey: "clockOpacity")

        // Сам ход времени: дискретная прокрутка заранее отрисованных кадров.
        let contents = CAKeyframeAnimation(keyPath: "contents")
        contents.values = frames
        contents.keyTimes = frames.indices.map { index in
            let progress = frames.count > 1 ? Double(index) / Double(frames.count - 1) : 0
            let time = startFraction + (endFraction - startFraction) * progress
            return NSNumber(value: min(max(time, 0), 1))
        }
        contents.duration = totalDuration
        contents.beginTime = AVCoreAnimationBeginTimeAtZero
        contents.isRemovedOnCompletion = false
        contents.fillMode = .both
        contents.calculationMode = .discrete
        layer.add(contents, forKey: "clockContents")
    }

    // MARK: - Отрисовка кадров

    /// Кадры циферблата по шагам времени. Рисуем тем же вью, что и в приложении, — чтобы экспорт
    /// выглядел как пересмотр момента.
    private static func renderFrames(for placement: ClockExportPlacement, size: CGSize) -> [CGImage] {
        var stepSeconds = step(showCentiseconds: placement.info.showCentiseconds)
        var count = Int((placement.visibleDuration / stepSeconds).rounded(.up)) + 1
        if count > maxFramesPerPlacement {
            stepSeconds = 1.0
            count = min(Int((placement.visibleDuration / stepSeconds).rounded(.up)) + 1, maxFramesPerPlacement)
        }
        guard count > 0 else { return [] }

        let renderer = ClockFrameRenderer(size: size)
        var images: [CGImage] = []
        images.reserveCapacity(count)

        for index in 0..<count {
            let progress = count > 1 ? Double(index) / Double(count - 1) : 0
            // Сэмплируем реальный ход счётчика (с паузами) по времени исходного видео.
            let vt = placement.sampleStart + (placement.sampleFinish - placement.sampleStart) * progress
            let value = placement.info.value(atVideoTime: vt, start: placement.recordStart, finish: placement.recordFinish)
            if let image = renderer.image(seconds: value, info: placement.info) {
                images.append(image)
            }
        }
        return images
    }
}

// MARK: - Снимок циферблата

/// Рисует `ClockDisplayView` в картинку. Держим один hosting-view на серию кадров: пересоздавать
/// его на каждый кадр — самая дорогая часть отрисовки.
private final class ClockFrameRenderer {

    private let size: CGSize
    private let hostingView: NSHostingView<ClockDisplayView>
    /// Вью снимается вне экрана, но живёт в окне: у SwiftUI-контента без окна `cacheDisplay`
    /// умеет отдавать пустой кадр. Окно невидимое и existing только на время серии снимков.
    private let window: NSWindow

    init(size: CGSize) {
        self.size = size
        let placeholder = ClockDisplayView(seconds: 0, appearance: .segments)
        hostingView = NSHostingView(rootView: placeholder)
        hostingView.frame = CGRect(origin: .zero, size: size)

        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = hostingView
    }

    deinit {
        window.contentView = nil
        window.close()
    }

    func image(seconds: Double, info: StampClockInfo) -> CGImage? {
        hostingView.rootView = ClockDisplayView(
            seconds: seconds,
            appearance: info.appearance,
            showCentiseconds: info.showCentiseconds,
            style: ClockStyle(
                foreground: .white,
                accent: .accentColor,
                cellBackground: Color.black.opacity(0.6),
                fontWeight: .semibold
            ),
            progress: nil,
            caption: info.caption
        )
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return nil }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        return rep.cgImage
    }
}
