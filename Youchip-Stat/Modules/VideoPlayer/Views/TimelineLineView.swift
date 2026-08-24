//
//  TimelineLineView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

/// Одна дорожка таймлайна.
///
/// **Это значение, а не подписчик.** Раньше строка держала `@ObservedObject` на
/// `VideoPlayerManager`, `TimelineDataManager` и `TagLibraryManager` — то есть любое изменение
/// разметки перерисовывало ВСЕ строки, даже если поменялся один тег в одной из них.
/// Теперь всё, что влияет на картинку, приходит параметрами, а к синглтонам строка обращается
/// только императивно (seek, мутации по нажатию). Благодаря `Equatable` + `.equatable()` на
/// вызове SwiftUI пропускает перерисовку строк, у которых данные не изменились.
///
/// Если добавляешь сюда чтение изменяемого состояния — заводи параметр и включай его в `==`,
/// иначе строка начнёт показывать устаревшие данные. См. TASK-007, 3.1/3.2/5.4.
struct TimelineLineView: View, Equatable {

    /// Обычные ссылки, БЕЗ подписки — только для императивных вызовов.
    private let videoManager = VideoPlayerManager.shared
    private let timelineData = TimelineDataManager.shared

    let line: TimelineLine
    let scale: CGFloat
    let widthMax: CGFloat
    /// Длительность видео. Приходит сверху, чтобы строка не читала `AVPlayerItem.duration`.
    let totalDuration: Double
    /// Позиция строки и общее число строк — нужны для вертикального переноса штампа.
    let lineIndex: Int
    let linesCount: Int
    /// Выбранный штамп и пачка ⌘-выбора — только то, что относится к отрисовке этой строки.
    let selectedStampID: UUID?
    let bulkSelectedStampIDs: Set<UUID>

    let isSelected: Bool
    let onSelect: () -> Void
    let onEditLabelsRequest: (UUID) -> Void
    let onEditTimeEventsRequest: (UUID) -> Void
    let onTagDragging: (CGFloat?) -> Void
    /// Листы живут в родителе, а не здесь: `.sheet` на строке означал по два
    /// presentation-хоста на КАЖДУЮ строку (на 613 таймлайнах — больше тысячи).
    /// См. TASK-007, 3.5.
    let onEditComment: (TimelineStamp) -> Void
    let onPickSession: (TimelineStamp) -> Void
    /// Открыть лист «Добавить в плейлист…» для тега (или ⌘-пачки, если тег в неё входит).
    /// Лист живёт в родителе (перф: не по хосту на строку), поэтому это колбэк.
    var onAddToPlaylist: (TimelineLine, TimelineStamp) -> Void = { _, _ in }

    /// Состояние Shift для drag-and-drop тега в плейлист. `@ObservedObject` обновляет строку при
    /// переключении Shift, но в `==` не входит (сравниваются только `let`-данные), так что на
    /// обычные перерисовки не влияет. См. [[TimelineDnDModifierMonitor]].
    @ObservedObject private var dndModifier = TimelineDnDModifierMonitor.shared

    private let tagLibrary = TagLibraryManager.shared
    @State private var isDraggingOver = false
    private let lineHeight: CGFloat = 30
    
    // MARK: - Stamp edges drag properties
    @State private var resizingStampID: UUID? = nil
    @State private var resizingEdge: ResizeEdge? = nil
    @State private var dragStartTime: Double = 0
    @State private var originalStartTime: Double = 0
    @State private var originalEndTime: Double = 0
    
    @State private var visualWidth: CGFloat? = nil
    @State private var visualOffsetX: CGFloat? = nil
    @State private var maxVisualOffsetX: CGFloat? = nil

    @State private var initialVisualWidth: CGFloat = 0
    @State private var initialVisualOffsetX: CGFloat = 0
    @State private var dragAnchorX: CGFloat = 0
    
    @State private var lastSeekTime: Date = Date()
    private let seekThrottleInterval: TimeInterval = 0.033 // ~30fps

    /// Куда «подкидывать» плейхед, пока тег двигают или тянут за край.
    ///
    /// - обычная разметка — основной плеер, как и было;
    /// - лайв + пересмотр — ТОЛЬКО плеер пересмотра: на лайв-видео всегда идёт лайв, поэтому
    ///   белый плейхед прыгал впустую и на кадре ничего не менялось;
    /// - лайв без пересмотра — никуда: двигать белый плейхед лайва бессмысленно.
    ///
    /// `isPreview` — непрерывное перетаскивание (seek с допуском, чтобы кадр поспевал за
    /// курсором); `false` — финальная точка после отпускания.
    private func seekWhileEditingStamp(to time: Double, isPreview: Bool = true) {
        if videoManager.isReviewMode {
            if isPreview {
                videoManager.seekReviewForTimelineScrubPreview(to: time)
            } else {
                videoManager.seekReview(to: time)
            }
            return
        }
        guard !videoManager.isLiveMode else { return }
        videoManager.seek(to: time)
    }
    
    // MARK: - drag properties
    @State private var dragOffsetY: CGFloat = 0
    /// Горизонтальный сдвиг при перетаскивании — штамп двигается и во времени, а не только
    /// между дорожками.
    @State private var dragOffsetX: CGFloat = 0
    @State private var draggingStampID: UUID?

    enum ResizeEdge {
        case left
        case right
    }
    
    /// Сравнение для `EquatableView`: перечислено ВСЁ, что влияет на картинку строки.
    /// Замыкания-колбэки намеренно не сравниваются — они пересоздаются на каждый рендер
    /// родителя, но на результат отрисовки не влияют. Иначе `==` всегда давал бы `false`
    /// и вся затея с пропуском перерисовки не работала бы.
    static func == (lhs: TimelineLineView, rhs: TimelineLineView) -> Bool {
        lhs.line == rhs.line
            && lhs.scale == rhs.scale
            && lhs.widthMax == rhs.widthMax
            && lhs.totalDuration == rhs.totalDuration
            && lhs.lineIndex == rhs.lineIndex
            && lhs.linesCount == rhs.linesCount
            && lhs.selectedStampID == rhs.selectedStampID
            && lhs.bulkSelectedStampIDs == rhs.bulkSelectedStampIDs
            && lhs.isSelected == rhs.isSelected
    }

    /// Сколько ранее добавленных штампов перекрывается с каждым — по одному разу на строку,
    /// а не заново на каждый штамп (раньше это давало O(S²) на каждый рендер строки).
    /// Семантика та же: для штампа с индексом `i` считаем пересечения только с `j < i`,
    /// то есть порядок в массиве (порядок добавления) важен — от него зависит высота штампа.
    private func overlapCounts() -> [UUID: Int] {
        let stamps = line.stamps
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(stamps.count)
        for i in stamps.indices {
            let start = stamps[i].timeStartSeconds
            let end = stamps[i].timeFinishSeconds
            var count = 0
            for j in 0..<i where start < stamps[j].timeFinishSeconds && stamps[j].timeStartSeconds < end {
                count += 1
            }
            counts[stamps[i].id] = count
        }
        return counts
    }

    var body: some View {
        // Без `GeometryReader`: его `geometry` здесь не использовался ни разу — размеры строки
        // известны заранее (`widthMax` × `lineHeight`), а лишний GeometryReader — это лишний
        // проход лейаута на КАЖДУЮ строку. См. TASK-007, 3.7.
        Group {
            let overlaps = overlapCounts()

            HStack(alignment: .top, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            isDraggingOver ? Color.blue.opacity(0.15) : Color.gray.opacity(0.05),
                            isDraggingOver ? Color.blue.opacity(0.08) : Color.gray.opacity(0.02)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(
                                isDraggingOver ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2),
                                lineWidth: 0.5
                            )
                    )
                    .timelineTapToSeek(
                        gridWidth: widthMax,
                        duration: totalDuration,
                        onShortPress: {
                            timelineData.selectStamp(stampID: nil)
                            timelineData.clearSportCutExportSelection()
                        }
                    ) { time in
                        // В пересмотре клик по телу дорожки ведёт бирюзовый плейхед пересмотра —
                        // так же, как клик по линейке (см. PinnedTimelineRulerView). Основной
                        // (белый) плейхед в лайве прибит к живому краю, и `seek` для него ничего
                        // не делает, поэтому раньше клик по дорожке в лайв-пересмотре не двигал
                        // ничего.
                        if videoManager.isReviewMode {
                            videoManager.seekReview(to: time)
                        } else {
                            videoManager.seek(to: time)
                        }
                    }
                    // Идентичность по `stamp.id`, как и была; `Array(enumerated())` больше не
                    // нужен — перекрытия приходят словарём, посчитанным один раз на строку.
                    ForEach(line.stamps) { stamp in
                        stampView(
                            stamp: stamp,
                            overlapCount: overlaps[stamp.id] ?? 0,
                            totalDuration: totalDuration,
                            widthMax: widthMax
                        )
                    }
                }
                .coordinateSpace(name: "lineZStack")
            }
            .frame(width: widthMax, height: lineHeight)
        }
    }

    
    @ViewBuilder
    private func stampView(stamp: TimelineStamp, overlapCount: Int, totalDuration: Double, widthMax: CGFloat) -> some View {
        let isResizing = resizingStampID == stamp.id
        let currentStartTime = isResizing && resizingEdge == .left ? dragStartTime : stamp.timeStartSeconds
        let currentEndTime = isResizing && resizingEdge == .right ? dragStartTime : stamp.timeFinishSeconds

        let isDragging = draggingStampID == stamp.id

        // Индекс строки и их общее число приходят параметрами: раньше здесь на КАЖДЫЙ штамп
        // шёл `lines.firstIndex(where:)`, то есть линейный поиск по всем строкам.
        let maxYOffset = CGFloat(linesCount - 1 - lineIndex) * lineHeight
        let minYOffset = -1 * CGFloat(lineIndex) * lineHeight
        let verticalOffset = isDragging ? max(min(dragOffsetY, maxYOffset), minYOffset) : 0
        
        // Геометрия клипа считается из времени штампа, поэтому битые данные (конец далеко за
        // пределами видео — импорт из чужого XML, недозаписанный хвост в лайве — или NaN/inf)
        // давали прямоугольник шириной в несколько экранов. `.frame` в SwiftUI НЕ обрезает
        // содержимое и не ограничивает попадания, так что такой штамп ложится поверх соседей
        // (рисуется последним) и забирает себе ВСЕ клики: клик по любому тегу подматывал и
        // открывал последний тег разметки. Инфо-строка при наведении при этом права — её считает
        // `TimelineMouseTracker` по координате курсора, мимо hit-testing'а SwiftUI.
        // Поэтому клип всегда держим внутри таймлайна.
        let safeStart = currentStartTime.isFinite ? min(max(currentStartTime, 0), totalDuration) : 0
        let safeEnd = currentEndTime.isFinite ? min(max(currentEndTime, safeStart), totalDuration) : safeStart

        let startRatio = safeStart / totalDuration
        let durationRatio = (safeEnd - safeStart) / totalDuration

        let baseStampWidth = min(max(durationRatio * widthMax, 10), max(widthMax, 10))
        let baseStampX = min(max(startRatio * widthMax, 0), max(widthMax - 10, 0))

        let rawStampWidth: CGFloat = isResizing ? (visualWidth ?? baseStampWidth) : baseStampWidth
        let stampWidth = min(max(rawStampWidth, 10), max(widthMax, 10))

        let rawStampX: CGFloat = (isResizing && resizingEdge == .left) ? (visualOffsetX ?? baseStampX) : baseStampX
        let stampX = min(max(rawStampX, 0), max(widthMax - 10, 0))
        // Во время переноса штамп едет за курсором по обеим осям, не вылезая за таймлайн.
        let draggedStampX = isDragging
            ? min(max(stampX + dragOffsetX, 0), max(widthMax - stampWidth, 0))
            : stampX
        
        let isSelected = selectedStampID == stamp.id
        let inSportCutBulk = bulkSelectedStampIDs.contains(stamp.id)
        let hasOverlaps = overlapCount > 0
        
        let borderColor: Color = {
            if inSportCutBulk { return Color.green }
            if hasOverlaps && !isSelected { return Color.red }
            if isSelected && hasOverlaps { return Color.red }
            if isSelected { return Color.blue }
            return Color.clear
        }()
        let heightReduction = CGFloat(overlapCount * 6)
        // Клип сужается на каждое наложение, но не в минус: при 5+ наложениях 25 − 6·N уходило
        // отрицательным, и SwiftUI сыпал "Invalid frame dimension (negative or non-finite)".
        let stampHeight: CGFloat = max(7, 25 - heightReduction)
        
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            stamp.color,
                            stamp.color.opacity(0.8)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: stampHeight)
                .shadow(
                    color: stamp.color.opacity(0.3),
                    radius: isSelected ? 4 : 2,
                    x: 0,
                    y: isSelected ? 2 : 1
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: isSelected ? 2.5 : 1.5)
                )
            
            StampLabelsOverlayView(
                stamp: stamp,
                maxWidth: stampWidth
            )
            .frame(height: stampHeight)
            .padding(.horizontal, 4)
        }
        .overlay(
            edgeHandlesView(
                stamp: stamp,
                isSelected: isSelected,
                stampHeight: stampHeight,
                stampWidth: stampWidth,
                totalDuration: totalDuration,
                widthMax: widthMax
            )
        )
        .overlay(alignment: .topTrailing) {
            if stamp.comment != nil {
                Circle()
                    .fill(Color.red)
                    .overlay(Circle().stroke(Color.black, lineWidth: 0.8))
                    .frame(width: 7, height: 7)
                    .offset(x: 2, y: -2)
            }
        }
        .frame(width: stampWidth, height: stampHeight)
        // Кликабельна ровно площадь самого клипа: подписи/бейджи внутри могут вылезать за рамку,
        // а перехватывать чужие клики они не должны.
        .contentShape(Rectangle())
        .position(x: clampedCenterX(isDragging: isDragging, stampX: draggedStampX, stampWidth: stampWidth), y: verticalOffset + 15)
        .pointingHandCursor()
        // Подсказка по наведению работает и когда окно таймлайнов неактивно — не нужно
        // сперва кликать по окну, чтобы узнать, что за тег под курсором.
        .help(stampTooltip(stamp))
        .onTapGesture(count: 2) {
            if resizingStampID == nil {
                let stampDuration = max(stamp.timeFinishSeconds - stamp.timeStartSeconds, 1.0)
                WindowsManager.shared.openMomentViewer(
                    stampStart: stamp.timeStartSeconds,
                    stampDuration: stampDuration,
                    tagName: stamp.label,
                    lineName: line.name,
                    lineID: line.id,
                    stampID: stamp.id
                )
            }
        }
        .onTapGesture(count: 1) {
            if resizingStampID == nil {
                // Играли клипы плейлиста в окне видео — клик по обычному тегу возвращает разметку.
                MarkupPlaylistPanelStore.shared.returnToMarkupOnMarkupInteraction()
                let commandDown = NSEvent.modifierFlags.contains(.command)
                if commandDown {
                    timelineData.toggleSportCutExportSelection(stampID: stamp.id)
                    return
                }
                // Сброс пачки ⌘-выбора только по пустому месту или «Снять выделение», не при обычном клике по тегу.
                withAnimation(.easeInOut(duration: 0.2)) {
                    timelineData.selectStamp(stampID: stamp.id)
                }
                if videoManager.isReviewMode {
                    videoManager.seekReview(to: stamp.timeStartSeconds)
                } else {
                    videoManager.seek(to: stamp.timeStartSeconds)
                    videoManager.player?.play()
                }
            }
        }
        // Перетаскивание тега: ПЛЕЙЛИСТ по обычному ЛКМ (системный `.onDrag` ниже), а перенос по
        // ТАЙМЛАЙНАМ — при зажатом Shift. Поэтому жест переноса включаем ТОЛЬКО когда зажат Shift;
        // без него он отключён (nil), и срабатывает `.onDrag` — тег(и) уходят в панель плейлистов.
        .gesture(
            ((resizingStampID == nil && isTimelineMoveDrag()) ? DragGesture() : nil)
                .onChanged { value in
                    if draggingStampID == nil {
                        draggingStampID = stamp.id
                    }
                    dragOffsetY = value.translation.height
                    dragOffsetX = value.translation.width

                    // Чисто вертикальный перенос (смена дорожки) видео не трогает — направляющая
                    // и подмотка нужны только когда штамп реально едет во времени.
                    guard abs(value.translation.width) > 2 else { return }

                    // Направляющая у левого края штампа — как при изменении границ.
                    let baseX = (stamp.timeStartSeconds / totalDuration) * widthMax
                    let previewX = min(max(baseX + value.translation.width, 0), widthMax)
                    onTagDragging(previewX)

                    // Подматываем видео к новому началу штампа — видно, куда он приедет.
                    let now = Date()
                    if now.timeIntervalSince(lastSeekTime) >= seekThrottleInterval {
                        lastSeekTime = now
                        seekWhileEditingStamp(to: (previewX / widthMax) * totalDuration)
                    }
                }
                .onEnded { value in
                    let offsetX = dragOffsetX
                    dragOffsetY = 0
                    dragOffsetX = 0
                    onTagDragging(nil)
                    guard let draggingStampID else { return }
                    self.draggingStampID = nil

                    let lineHeight: CGFloat = lineHeight
                    let sourceLineIndex = timelineData.lines.firstIndex(where: { $0.id == line.id }) ?? 0
                    let y = value.location.y + CGFloat(sourceLineIndex) * lineHeight
                    
                    var destLineIndex = Int(y / lineHeight)
                    destLineIndex = max(0, destLineIndex)
                    destLineIndex = min(timelineData.lines.count - 1, destLineIndex)

                    let destLineID = timelineData.lines[destLineIndex].id

                    // Новое время: сдвигаем весь штамп, длительность не трогаем; за пределы
                    // видео не выпускаем.
                    let duration = max(stamp.timeFinishSeconds - stamp.timeStartSeconds, 0)
                    let deltaTime = widthMax > 0 ? Double(offsetX / widthMax) * totalDuration : 0
                    let maxStart = max(totalDuration - duration, 0)
                    let newStart = min(max(stamp.timeStartSeconds + deltaTime, 0), maxStart)
                    let newFinish = min(newStart + duration, totalDuration)
                    let movedInTime = abs(newStart - stamp.timeStartSeconds) > 0.01

                    if destLineID != line.id {
                        let stampInfo = StampDragInfo(
                            lineID: line.id,
                            stampID: draggingStampID,
                        )
                        transferStamp(
                            stampInfo,
                            to: destLineID,
                            newStart: movedInTime ? newStart : nil,
                            newFinish: movedInTime ? newFinish : nil
                        )
                    } else if movedInTime {
                        timelineData.updateStampTimeRange(
                            lineID: line.id,
                            stampID: draggingStampID,
                            newStartTime: newStart,
                            newEndTime: newFinish
                        )
                    }

                    if movedInTime {
                        seekWhileEditingStamp(to: newStart, isPreview: false)
                    }
                }
        )
        .contextMenu {
            menuForTag(stamp: stamp)
        }
        .onDrag {
            guard let data = WindowsManager.shared.encodeMarkupPlaylistDragData(line: line, stamp: stamp) else {
                return NSItemProvider()
            }
            return NSItemProvider(item: data as NSData, typeIdentifier: UTType.data.identifier)
        }
        .coordinateSpace(name: "timelineSpace")
    }
    
    @ViewBuilder
    private func edgeHandlesView(
        stamp: TimelineStamp,
        isSelected: Bool,
        stampHeight: CGFloat,
        stampWidth: CGFloat,
        totalDuration: Double,
        widthMax: CGFloat
    ) -> some View {
        Group {
            if isSelected {
                HStack(spacing: 0) {
                    // Left edge handle
                    EdgeResizeHandle(
                        edge: .left,
                        stampHeight: stampHeight
                    )
                    .frame(width: 8)
                    .gesture(
                        leftEdgeDragGesture(
                            stamp: stamp,
                            totalDuration: totalDuration,
                            widthMax: widthMax
                        )
                    )
                    
                    Spacer()
                    
                    // Right edge handle
                    EdgeResizeHandle(
                        edge: .right,
                        stampHeight: stampHeight
                    )
                    .frame(width: 8)
                    .gesture(
                        rightEdgeDragGesture(
                            stamp: stamp,
                            totalDuration: totalDuration,
                            widthMax: widthMax
                        )
                    )
                }
                .frame(width: stampWidth)
            }
        }
    }
    
    private func leftEdgeDragGesture(stamp: TimelineStamp, totalDuration: Double, widthMax: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("lineZStack"))
            .onChanged { value in
                let minWidth: CGFloat = 30

                if resizingStampID != stamp.id {
                    resizingStampID = stamp.id
                    resizingEdge = .left
                    originalStartTime = stamp.timeStartSeconds
                    originalEndTime = stamp.timeFinishSeconds
                    dragStartTime = originalStartTime

                    videoManager.isResizingTag = true

                    let baseDuration = originalEndTime - originalStartTime
                    let baseDurationRatio = baseDuration / totalDuration
                    let w = max(baseDurationRatio * widthMax, minWidth)

                    let baseStartRatio = originalStartTime / totalDuration
                    let ox = baseStartRatio * widthMax

                    initialVisualWidth = w
                    initialVisualOffsetX = ox
                    visualWidth = w
                    visualOffsetX = ox

                    // Remember cursor offset from edge so drag feels anchored
                    dragAnchorX = value.location.x - ox
                }

                let rightEdgeX = initialVisualOffsetX + initialVisualWidth
                let targetLeftX = value.location.x - dragAnchorX

                let clampedLeftX = max(0, min(targetLeftX, rightEdgeX - minWidth))
                let newWidth = rightEdgeX - clampedLeftX

                visualOffsetX = clampedLeftX
                visualWidth = newWidth

                let time = (clampedLeftX / widthMax) * totalDuration
                onTagDragging(clampedLeftX)

                let now = Date()
                if now.timeIntervalSince(lastSeekTime) >= seekThrottleInterval {
                    lastSeekTime = now
                    seekWhileEditingStamp(to: time)
                }
            }
            .onEnded { _ in
                if let stampID = resizingStampID,
                   let finalOffsetX = visualOffsetX,
                   let finalWidth = visualWidth,
                   resizingEdge == .left {

                    let finalStartRatio = finalOffsetX / widthMax
                    let finalStartTime = max(finalStartRatio * totalDuration, 0)

                    let finalDurationRatio = finalWidth / widthMax
                    let finalDuration = finalDurationRatio * totalDuration
                    let finalEndTime = min(finalStartTime + finalDuration, totalDuration)

                    let adjustedStartTime = min(finalStartTime, finalEndTime - 0.5)

                    timelineData.updateStampTime(
                        lineID: line.id,
                        stampID: stampID,
                        newStart: adjustedStartTime
                    )
                    onTagDragging(nil)
                }

                videoManager.isResizingTag = false

                resizingStampID = nil
                resizingEdge = nil
                visualWidth = nil
                visualOffsetX = nil
            }
    }

    
    private func rightEdgeDragGesture(stamp: TimelineStamp, totalDuration: Double, widthMax: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("lineZStack"))
            .onChanged { value in
                let minWidth: CGFloat = 30

                if resizingStampID != stamp.id {
                    resizingStampID = stamp.id
                    resizingEdge = .right
                    originalStartTime = stamp.timeStartSeconds
                    originalEndTime = stamp.timeFinishSeconds
                    dragStartTime = originalStartTime

                    videoManager.isResizingTag = true

                    let baseStartRatio = originalStartTime / totalDuration
                    let ox = baseStartRatio * widthMax

                    let baseDuration = originalEndTime - originalStartTime
                    let baseDurationRatio = baseDuration / totalDuration
                    let w = max(baseDurationRatio * widthMax, minWidth)

                    initialVisualWidth = w
                    initialVisualOffsetX = ox
                    visualOffsetX = ox
                    visualWidth = w

                    // Remember cursor offset from right edge
                    dragAnchorX = value.location.x - (ox + w)
                }

                let targetRightX = value.location.x - dragAnchorX
                let clampedRightX = max(initialVisualOffsetX + minWidth, min(targetRightX, widthMax))
                let newWidth = clampedRightX - initialVisualOffsetX

                visualWidth = newWidth

                let time = (clampedRightX / widthMax) * totalDuration
                onTagDragging(clampedRightX)

                let now = Date()
                if now.timeIntervalSince(lastSeekTime) >= seekThrottleInterval {
                    lastSeekTime = now
                    seekWhileEditingStamp(to: time)
                }
            }
            .onEnded { _ in
                if let stampID = resizingStampID,
                   let finalWidth = visualWidth,
                   resizingEdge == .right {

                    let finalDurationRatio = finalWidth / widthMax
                    let finalDuration = finalDurationRatio * totalDuration
                    let finalEndTime = min(originalStartTime + finalDuration, totalDuration)

                    timelineData.updateStampTime(
                        lineID: line.id,
                        stampID: stampID,
                        newEnd: finalEndTime
                    )
                    onTagDragging(nil)
                }

                videoManager.isResizingTag = false

                resizingStampID = nil
                resizingEdge = nil
                visualWidth = nil
                visualOffsetX = nil
            }
    }
    
    @ViewBuilder
    private func menuForTag(stamp: TimelineStamp) -> some View {
        Text("\(^String.Titles.fieldMapTagTitleNoNumber) \(stamp.label)")
        
        if let position = stamp.position {
            Text(String(format: ^String.Titles.fieldMapTagPosition, position.x, position.y))
        }
        
        if !stamp.labels.isEmpty {
            ForEach(stamp.labels, id: \.id) { labelItem in
                let label = tagLibrary.findLabelById(labelItem.id)
                let displayName = label?.name ?? labelItem.name
                if let group = tagLibrary.allLabelGroups.first(where: { $0.lables.contains(labelItem.id) }) {
                    Text("\(displayName) (\(group.name))")
                } else if !displayName.isEmpty {
                    Text(displayName)
                }
            }
            Divider()
        }
        if !stamp.timeEvents.isEmpty {
            Text(^String.Titles.fieldMapLabelEvents)
            ForEach(stamp.timeEvents, id: \.self) { eventID in
                if let event = tagLibrary.findTimeEventById(eventID) {
                    Text("• \(event.name)")
                }
            }
            Divider()
        }
        
        Button(^String.Titles.viewingViewMoment) {
            let stampDuration = max(stamp.timeFinishSeconds - stamp.timeStartSeconds, 1.0)
            WindowsManager.shared.openMomentViewer(
                stampStart: stamp.timeStartSeconds,
                stampDuration: stampDuration,
                tagName: stamp.label,
                lineName: line.name,
                lineID: line.id,
                stampID: stamp.id
            )
        }

        // Панель плейлистов открыта и плейлист выбран — быстрый путь «в текущий плейлист».
        if MarkupPlaylistPanelStore.shared.canAddToCurrentPlaylist {
            Button(^String.Titles.markupPlaylistsAddToCurrent) {
                MarkupPlaylistPanelStore.shared.addStampsToCurrentPlaylist(line: line, stamp: stamp)
            }
        }
        // Выбрана сессия просмотра в правой панели — лист с выбором любого её плейлиста (или создать новый).
        if MarkupPlaylistPanelStore.shared.hasSelectedSession {
            Button(^String.Titles.markupPlaylistsAddToPlaylist) {
                onAddToPlaylist(line, stamp)
            }
        }

        Button(^String.Titles.viewingNewSession) {
            WindowsManager.shared.openSportCutFromTimelineStamps([(line, stamp)], forceNewSession: true)
        }
        if !SportCutSessionManager.shared.sessions.isEmpty {
            Button(^String.Titles.viewingToExistingSession) {
                onPickSession(stamp)
            }
        }

        Divider()

        Button(stamp.comment == nil ? ^String.Titles.viewingAddComment : ^String.Titles.viewingEditComment) {
            onEditComment(stamp)
        }
        if stamp.comment != nil {
            Button(^String.Titles.viewingDeleteComment) {
                if let lineIndex = timelineData.lines.firstIndex(where: { $0.id == line.id }),
                   let stampIndex = timelineData.lines[lineIndex].stamps.firstIndex(where: { $0.id == stamp.id }) {
                    timelineData.lines[lineIndex].stamps[stampIndex].comment = nil
                    timelineData.updateTimelines()
                }
            }
        }
        
        Button(^String.Titles.timelineButtonDeleteTag) {
            TimelineDataManager.shared.removeStamp(lineID: line.id, stampID: stamp.id)
            if timelineData.selectedStampID == stamp.id {
                timelineData.selectStamp(stampID: nil)
            }
        }
        
        // Проверяем, является ли это тегом рисунка (скриншота)
        // Тег должен:
        // 1. Быть связан со скриншотом (через relatedStampIds)
        // 2. Находиться на специальном таймлайне для рисунков
        // 3. Иметь имя, совпадающее с именем скриншота
        let isDrawingsTimeline = line.isDrawingsTimeline
        
        // Через индекс, а не перебором всех скриншотов: это меню строится для каждого штампа.
        let isScreenshotTag = isDrawingsTimeline
            && ScreenshotsMetadataManager.shared.hasScreenshot(named: stamp.label, relatedTo: stamp.id)
        
        // Показываем кнопку редактирования лейблов только если это не тег рисунка
        if !isScreenshotTag {
            Button(^String.Titles.timelineButtonEditLabels) {
                onEditLabelsRequest(stamp.id)
            }
        }
        Button(^String.Titles.timelineButtonEditTimeEvents) {
            onEditTimeEventsRequest(stamp.id)
        }
    }
    
    /// Двигаем ли тег по ТАЙМЛАЙНАМ (а не тащим в плейлист): только при зажатом Shift. Без Shift
    /// обычный ЛКМ уходит в `.onDrag` — перенос в панель плейлистов (одиночный или вся ⌘-пачка).
    private func isTimelineMoveDrag() -> Bool {
        dndModifier.isShiftDown
    }

    /// Переносит штамп на другую дорожку. `newStart`/`newFinish` — если его заодно подвинули
    /// по времени (перенос идёт копией с новым id, поэтому время задаём прямо здесь).
    private func transferStamp(
        _ stampInfo: StampDragInfo,
        to destLineID: UUID,
        newStart: Double? = nil,
        newFinish: Double? = nil
    ) {
        guard let sourceLineIndex = timelineData.lines.firstIndex(where: { $0.id == stampInfo.lineID }),
              let destLineIndex = timelineData.lines.firstIndex(where: { $0.id == destLineID }),
              let stampIndex = timelineData.lines[sourceLineIndex].stamps.firstIndex(where: { $0.id == stampInfo.stampID }) else {
            return
        }
        
        var stamp = timelineData.lines[sourceLineIndex].stamps[stampIndex]
        if let newStart, let newFinish {
            // Показания счётчика внутри штампа тоже должны поехать вместе с ним.
            var moved = stamp
            moved.timeStartSeconds = newStart
            moved.timeFinishSeconds = newFinish
            if var info = moved.clockInfo {
                info.rescale(
                    oldStart: stamp.timeStartSeconds,
                    oldFinish: stamp.timeFinishSeconds,
                    newStart: newStart,
                    newFinish: newFinish
                )
                moved.clockInfo = info
            }
            stamp = moved
        }
        
        let newStamp = TimelineStamp(
            // id сохраняем: на него ссылаются скриншоты, выделение и пачка выбора — при новом
            // id перенос штампа на другую дорожку рвал бы эти связи.
            id: stamp.id,
            tagRefs: stamp.tagRefs,
            primaryID: stamp.primaryID,
            timeStartSeconds: stamp.timeStartSeconds,
            timeFinishSeconds: stamp.timeFinishSeconds,
            colorHex: stamp.colorHex,
            label: stamp.label,
            labels: stamp.labels,
            timeEvents: stamp.timeEvents,
            isActiveForMapView: stamp.isActiveForMapView,
            comment: stamp.comment,
            mapPositions: stamp.mapPositions,
            clockInfo: stamp.clockInfo,
            primaryClockId: stamp.primaryClockId
        )

        timelineData.lines[destLineIndex].stamps.append(newStamp)
        timelineData.lines[sourceLineIndex].stamps.remove(at: stampIndex)
        timelineData.updateTimelines()
    }
    
    /// Текст всплывающей подсказки штампа: тег, интервал и лейблы/события, если они есть.
    private func stampTooltip(_ stamp: TimelineStamp) -> String {
        var parts = ["\(stamp.label)  \(secondsToTimeString(stamp.timeStartSeconds))–\(secondsToTimeString(stamp.timeFinishSeconds))"]

        let labelNames = stamp.labels.map(\.name).filter { !$0.isEmpty }
        if !labelNames.isEmpty {
            parts.append(labelNames.joined(separator: ", "))
        }

        let eventNames = stamp.timeEvents.compactMap { id in
            tagLibrary.allTimeEvents.first(where: { $0.id == id })?.name
        }
        if !eventNames.isEmpty {
            parts.append(eventNames.joined(separator: ", "))
        }

        if let comment = stamp.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            parts.append(comment)
        }
        return parts.joined(separator: "\n")
    }

    private func clampedCenterX(isDragging: Bool, stampX: CGFloat, stampWidth: CGFloat) -> CGFloat {
        let baseCenterX = stampX + stampWidth / 2
        var centerX = baseCenterX

        let minCenterX = stampWidth / 2
        let maxCenterX = widthMax - stampWidth / 2

        centerX = max(minCenterX, min(centerX, maxCenterX))
        return centerX
    }
}

// Edge resize handle view
struct EdgeResizeHandle: View {
    let edge: TimelineLineView.ResizeEdge
    let stampHeight: CGFloat
    
    private let handleWidth: CGFloat = 8
    private let handleHeight: CGFloat = 20
    
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.8))
            .frame(width: handleWidth, height: min(handleHeight, stampHeight))
            .overlay(
                Rectangle()
                    .stroke(Color.blue, lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            .contentShape(Rectangle())
    }
}

/// Лист выбора существующей сессии просмотра (SportCut). Заменяет вложенное
/// `Menu`, которое не раскрывалось во время воспроизведения из-за частых
/// перерисовок таймлайна.
struct SportCutSessionPickerSheet: View {
    let title: String
    let sessions: [SportCutSession]
    let onSelect: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(sessions, id: \.id) { session in
                        Button(action: { onSelect(session.id) }) {
                            Text(session.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .frame(maxHeight: 240)

            HStack {
                Button(^String.Titles.cancelButtonTitle) { onCancel() }
                    .buttonStyle(PlainButtonStyle())
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 320, height: 360)
    }
}
