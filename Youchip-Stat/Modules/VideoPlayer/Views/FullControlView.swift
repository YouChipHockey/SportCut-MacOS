//
//  FullControlView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers
import WebKit

struct FullControlView: View {
    
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var liveStreamManager = LiveStreamManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    @ObservedObject var focusManager = FocusStateManager.shared
    @ObservedObject var hotkeyManager = HotKeyManager.shared
    /// ВНИМАНИЕ: именно `@State`, а НЕ `@StateObject`. `@StateObject` подписывает весь
    /// `FullControlView` на `objectWillChange` хелпера — и каждый тик `progress` во время
    /// экспорта пересчитывает body со ВСЕМИ дорожками. На больших проектах это приводило к
    /// зависанию главного потока и убийству приложения watchdog'ом.
    /// `@State` даёт стабильный экземпляр без подписки; `progress` читает только маленький
    /// `ExportProgressOverlay`. Не меняй обратно (см. TASK-007, фаза 5.1).
    @State private var exportHelper = ExportHelper()
    @ObservedObject var sportCutSessionManager = SportCutSessionManager.shared
    @ObservedObject var clipAutoSaveManager = ClipAutoSaveManager.shared

    /// Effective video duration - uses live stream duration when in live mode, otherwise AVPlayer duration.
    private var effectiveVideoDuration: Double {
        return max(1.0, videoManager.timelineDuration)
    }

    /// Верхняя полоса над линейкой таймлайна, куда выносятся «головы» меток
    /// рисунков (синие карандаши). Линейка, дорожки и плейхед сдвигаются вниз на
    /// эту величину, поэтому голова метки оказывается выше плейхеда и её видно/можно нажать.
    private let markerHeadBand: CGFloat = 22
    
    @State private var markupMode: MarkupMode = MarkupMode.current
    @State private var showMarkupModeToggle = false
    
    @State private var sliderValue: Double = 0.0
    @State private var showAddLineSheet = false
    @State private var isExporting: Bool = false
    @State private var stampItemsEditSheetType: StampEditSheetType? = nil
    @State private var showFieldMapVisualizationPicker = false
    @State private var editingStampLineID: UUID?
    @State private var editingStampID: UUID?
    /// Id перетаскиваемого таймлайна — для живого reorder при наведении (а не только при точном дропе).
    @State private var draggingLineID: UUID?
    @State private var timelineScale: CGFloat = 1.0
    // Effective scale at the time of the last zoom, so a new zoom can be
    // anchored on the playhead (see handleZoomChanged).
    @State private var previousEffectiveScale: CGFloat = 1.0
    @GestureState private var magnifyScale: CGFloat = 1.0
    @State private var keyEventMonitor: Any?
    @State private var tagEdgePosition: CGFloat? = nil
    /// Ширина правой колонки таймлайнов, измеряется фоновым `GeometryReader` (а не оборачивающим),
    /// чтобы контент сохранял свою реальную высоту — иначе вертикальный скролл не долистывает до
    /// конца при уменьшении окна (обёртка-GeometryReader в ScrollView отдаёт высоту вьюпорта).
    @State private var timelineRightColumnWidth: CGFloat = 0
    /// Стартовая высота окна (запоминается один раз) и текущая — для костыля: при уменьшении окна
    /// добавляем внизу списка пустоту, равную тому, насколько окно уменьшилось, чтобы всегда
    /// долистывалось до конца.
    @State private var standardWindowHeight: CGFloat = 0
    @State private var currentWindowHeight: CGFloat = 0
    @StateObject private var timelineScrollController = TimelineScrollController()
    @StateObject private var playheadDragController = PlayheadEdgeScrollController()
    
    @State private var isEditorModeActive = false
    @State private var isScreenshotDisplayActive = false
    @State private var notificationObservers: [NSObjectProtocol] = []
    
    private func handleActionWithEditorCheck(_ action: @escaping () -> Void) {
        if isScreenshotDisplayActive {
            action()
        } else if isEditorModeActive {
            NotificationCenter.default.post(name: .editorModeChanged, object: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                action()
            }
        } else {
            action()
        }
    }
    
    private func getCurrentFile() -> FilesFile? {
        guard let videoId = timelineData.currentVideoId else {
            return nil
        }
        return VideoFilesManager.shared.files.first(where: { $0.videoData.id == videoId })
    }
    
    /// Реально ли сейчас редактируется текстовое поле (по firstResponder окна, а не по
    /// разделяемому флагу). Флаг `isAnyTextFieldFocused` может «залипнуть» в false из-за гонок
    /// при переключении между полями — тогда Backspace съедался как «удалить тег». Проверка
    /// firstResponder всегда отражает актуальное состояние AppKit.
    static func isEditingTextInFocusedField() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextField { return true }
        if let textView = responder as? NSTextView { return textView.isFieldEditor }
        return false
    }

    private func setupKeyboardShortcuts() {
        // Идемпотентность: если монитор уже поставлен (повторный onAppear), сначала снимаем
        // старый — иначе мониторы копятся и клавиатура «затупливает» после долгой работы.
        if let existing = keyEventMonitor {
            NSEvent.removeMonitor(existing)
            keyEventMonitor = nil
        }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if focusManager.isAnyTextFieldFocused || FullControlView.isEditingTextInFocusedField() {
                return event
            }

            switch event.keyCode {
            case 48:
                // Tab — прыжок к следующему тегу на таймлайне; ⇧Tab — к предыдущему.
                // (⌘Tab macOS перехватывает под переключатель приложений, поэтому «назад» на Shift.)
                let backward = event.modifierFlags.contains(.shift)
                jumpBetweenStamps(forward: !backward)
                return nil
            case 53:
                // Esc cancels the "merge timelines" selection; otherwise pass through
                // so it still reaches sheets' cancel actions.
                if timelineData.isMergeSelectionActive {
                    timelineData.cancelMergeSelection()
                    return nil
                }
                return event
            case 51, 117:
                // Delete / Backspace (51) and Forward Delete (117) remove the
                // currently selected stamp in any markup mode. Text-field focus is
                // already handled by the early return above, so this can't eat a
                // deletion the user meant for a text field.
                if let stampID = timelineData.selectedStampID {
                    for line in timelineData.lines {
                        if line.stamps.contains(where: { $0.id == stampID }) {
                            timelineData.removeStamp(lineID: line.id, stampID: stampID)
                            break
                        }
                    }
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    /// Прыжок между тегами (штампами) на таймлайне. Вперёд/назад в рамках активного таймлайна;
    /// после последнего штампа — первый штамп следующего таймлайна (и симметрично назад).
    /// Активный таймлайн определяется выбранным штампом → иначе выбранным таймлайном → иначе первым.
    private func jumpBetweenStamps(forward: Bool) {
        let lines = timelineData.lines
        guard !lines.isEmpty else { return }

        func sorted(_ line: TimelineLine) -> [TimelineStamp] {
            line.stamps.sorted { $0.timeStartSeconds < $1.timeStartSeconds }
        }

        // Активный таймлайн + текущий штамп.
        var activeLineIndex = 0
        var currentStampID = timelineData.selectedStampID
        if let sid = currentStampID,
           let li = lines.firstIndex(where: { $0.stamps.contains(where: { $0.id == sid }) }) {
            activeLineIndex = li
        } else if let selLine = timelineData.selectedLineID,
                  let li = lines.firstIndex(where: { $0.id == selLine }) {
            activeLineIndex = li
            currentStampID = nil
        } else {
            currentStampID = nil
        }

        let currentTime = videoManager.currentTime
        let activeStamps = sorted(lines[activeLineIndex])
        let currentIndex = currentStampID.flatMap { sid in activeStamps.firstIndex(where: { $0.id == sid }) }

        func play(_ line: TimelineLine, _ stamp: TimelineStamp) {
            timelineData.selectLine(line.id)
            timelineData.selectStamp(stampID: stamp.id)
            videoManager.seek(to: stamp.timeStartSeconds, resumePlaybackAfterSeek: true)
        }

        if forward {
            let nextIndex: Int
            if let ci = currentIndex {
                nextIndex = ci + 1
            } else {
                nextIndex = activeStamps.firstIndex(where: { $0.timeStartSeconds > currentTime + 0.05 }) ?? activeStamps.count
            }
            if nextIndex < activeStamps.count {
                play(lines[activeLineIndex], activeStamps[nextIndex])
                return
            }
            // Конец таймлайна → первый штамп следующего непустого таймлайна (с переносом в начало).
            for offset in 1...lines.count {
                let li = (activeLineIndex + offset) % lines.count
                if let first = sorted(lines[li]).first {
                    play(lines[li], first)
                    return
                }
            }
        } else {
            let prevIndex: Int
            if let ci = currentIndex {
                prevIndex = ci - 1
            } else {
                prevIndex = activeStamps.lastIndex(where: { $0.timeStartSeconds < currentTime - 0.05 }) ?? -1
            }
            if prevIndex >= 0 {
                play(lines[activeLineIndex], activeStamps[prevIndex])
                return
            }
            // Начало таймлайна → последний штамп предыдущего непустого таймлайна.
            for offset in 1...lines.count {
                let li = (activeLineIndex - offset + lines.count) % lines.count
                if let last = sorted(lines[li]).last {
                    play(lines[li], last)
                    return
                }
            }
        }
    }

    @State private var selectedExportType: CutsExportType?
    @State private var showExportModeSheet: Bool = false
    @State private var showTagSelectionSheet: Bool = false
    @State private var parentWindowHeight: CGFloat = 600
    @State private var showEditNameSheet = false
    @State private var showEventSelectionSheet: Bool = false
    @State private var showAiReportSheet: Bool = false
    @State private var showSimpleReportSheet: Bool = false
    @State private var exportWithDrawings: Bool = false
    @State private var exportWatermarkOptions: ExportWatermarkOptions = .default
    
    @State private var showLabelSelectionSheet: Bool = false
    @State private var showMultiLabelSelectionSheet: Bool = false
    @State private var showMultiTagSelectionSheet: Bool = false
    @State private var selectedLabelForMultiSelection: Label?
    @State private var selectedTagForMultiSelection: Tag?
    
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showCSVExport = false
    @State private var hoveredStampInfo: AttributedString? = nil
    @State private var showZoomPopover = false
    /// Поиск по клипам в разметке: прячет на таймлайне все штампы, кроме найденных/выбранных.
    @StateObject private var clipFilter = TimelineFilter()
    @State private var showClipSearchSheet = false

    @State private var isLoading = false
    @State private var availableTags: [Tag] = []
    @State private var availableLabels: [Label] = []
    
    private enum TimelineLineSortMode {
        case original
        case nameAsc
        case nameDesc
        case tagCountDesc
        case tagCountAsc
        case lastTagChronological
        case lastTagChronologicalReverse
    }
    
    @State private var timelineLineSortMode: TimelineLineSortMode = .original
    @State private var originalLineOrderIDs: [UUID]? = nil
    
    @State private var multiTagSelectionItem: MultiSelectionItem?
    @State private var multiLabelSelectionItem: MultiSelectionItem?
    
    struct MultiSelectionItem: Identifiable {
        let id = UUID()
        let tag: Tag?
        let label: Label?
        
        init(tag: Tag? = nil, label: Label? = nil) {
            self.tag = tag
            self.label = label
        }
    }
    
    @ViewBuilder
    private func scrollBlock() -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                if !timelineData.stampsSelectedForSportCut.isEmpty {
                    sportCutBulkSelectionBar
                }
                if #available(macOS 13.0, *) {
                    ScrollView(.vertical) {
                        ScrollViewReader { scrollProxy in
                            timelineContent(proxy: scrollProxy)
                        }
                    }
                    // Система координат для измерителя вертикального смещения (см.
                    // `timelineScrollOffsetTracker` и `visibleLineRange`).
                    .coordinateSpace(name: "vTimelineScroll")
                    .scrollIndicators(.hidden)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .top) { pinnedTimelineHeaderOverlay }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                            .shadow(
                                color: Color.black.opacity(0.1),
                                radius: 8,
                                x: 0,
                                y: 2
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .gesture(
                        MagnificationGesture()
                            .updating($magnifyScale) { currentState, gestureState, _ in
                                gestureState = max(1.0, currentState)
                            }
                            .onEnded { value in
                                let newScale = timelineScale * value
                                let duration = effectiveVideoDuration
                                // Ограничиваем зум так, чтобы деления не стали мельче ~0.5с.
                                let maxScale = max(1.0, duration / 10.0)
                                timelineScale = min(max(1.0, newScale), maxScale)
                            }
                    )
                    .disabled(isEditorModeActive || isScreenshotDisplayActive)
                    .opacity(isEditorModeActive || isScreenshotDisplayActive ? 0.5 : 1.0)
                } else {
                    ScrollView(.vertical) {
                        ScrollViewReader { scrollProxy in
                            timelineContent(proxy: scrollProxy)
                        }
                    }
                    // Та же система координат, что и в ветке macOS 13+ — окно видимости строк
                    // должно работать в обеих.
                    .coordinateSpace(name: "vTimelineScroll")
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .top) { pinnedTimelineHeaderOverlay }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                            .shadow(
                                color: Color.black.opacity(0.1),
                                radius: 8,
                                x: 0,
                                y: 2
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .gesture(
                        MagnificationGesture()
                            .updating($magnifyScale) { currentState, gestureState, _ in
                                gestureState = max(1.0, currentState)
                            }
                            .onEnded { value in
                                let newScale = timelineScale * value
                                let duration = effectiveVideoDuration
                                // Ограничиваем зум так, чтобы деления не стали мельче ~0.5с.
                                let maxScale = max(1.0, duration / 10.0)
                                timelineScale = min(max(1.0, newScale), maxScale)
                            }
                    )
                    .disabled(isEditorModeActive || isScreenshotDisplayActive)
                    .opacity(isEditorModeActive || isScreenshotDisplayActive ? 0.5 : 1.0)
                }
            }
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// Шаг подписей на шкале времени, подстроенный под текущую ширину таймлайна.
    /// Держим минимум ~72pt между подписями и округляем шаг до «круглого»
    /// значения (5с, 10с, 30с, 1мин…), чтобы деления не слипались и читались.
    private func calculateTimeGridInterval(gridWidth: CGFloat, totalDuration: Double) -> Double {
        guard totalDuration > 0, gridWidth > 0 else { return max(0.5, totalDuration) }

        let minLabelSpacing: CGFloat = 72
        let maxLabels = max(1.0, Double(gridWidth / minLabelSpacing))
        let rawInterval = totalDuration / maxLabels

        return niceTimeInterval(atLeast: rawInterval)
    }

    /// Ближайшее сверху «круглое» значение времени для шага делений.
    private func niceTimeInterval(atLeast raw: Double) -> Double {
        let steps: [Double] = [0.5, 1, 2, 5, 10, 15, 20, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200]
        for step in steps where step >= raw {
            return step
        }
        // За пределами таблицы округляем вверх до целых часов.
        return max(3600, (raw / 3600).rounded(.up) * 3600)
    }

    private var sportCutBulkSelectionBar: some View {
        HStack(spacing: 10) {
            Text(String.Titles.viewingSelectedTags.format(timelineData.stampsSelectedForSportCut.count))
                .font(.system(size: 11, weight: .semibold))
            Text(String.Titles.viewingTotalDuration.format(formatTotalSelectedTagsDuration()))
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
            Button(^String.Titles.viewingNewSession) {
                WindowsManager.shared.openSportCutFromSelectedStamps()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            let existingSessions = sportCutSessionManager.sessions
            if !existingSessions.isEmpty {
                Menu {
                    ForEach(existingSessions, id: \.id) { sess in
                        Button(sess.name) {
                            WindowsManager.shared.appendMarkupSelectionToSportCutSession(sessionID: sess.id)
                        }
                    }
                } label: {
                    Text(^String.Titles.viewingToExistingSession)
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Button(^String.Titles.viewingDeselectAll) {
                timelineData.clearSportCutExportSelection()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
        }
        .onDrag {
            guard let data = WindowsManager.shared.encodeMarkupPlaylistDragDataForSelectionOnly() else {
                return NSItemProvider()
            }
            return NSItemProvider(item: data as NSData, typeIdentifier: UTType.data.identifier)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(8)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func timelineScrollView(width: CGFloat, effectiveScale: CGFloat, duration: Double, popupInfo: String?, popupLocation: CGPoint?) -> some View {
        let gridWidth = width * max(effectiveScale, 1.0)
        // Шаг подписей считаем от реальной пиксельной ширины, а не только от зума,
        // иначе при сужении окна метки слипаются в кучу.
        let interval = calculateTimeGridInterval(gridWidth: gridWidth, totalDuration: duration)

        return ScrollView(.horizontal) {
            HStack(spacing: 0) {
                timelineZStackContent(
                    duration: duration,
                    interval: interval,
                    gridWidth: gridWidth,
                    effectiveScale: effectiveScale
                )
                // Invisible attacher — finds the enclosing NSScrollView so we
                // can drive programmatic jumps from handleTimelineAutoScroll.
                .background(
                    TimelineScrollControllerAttacher(controller: timelineScrollController)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                )
            }
        }
        .hideScrollIndicators()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Именно `onReceive`, а не `onChange(of:)`. `onChange` сравнивает значения при пересчёте
        // body — а body этой вьюхи больше не пересчитывается на каждый тик плеера, поэтому
        // автоскролл с `onChange` просто перестал бы срабатывать. `onReceive` вызывает замыкание
        // по событию публикатора и сам body не инвалидирует: внутри двигается только NSScrollView.
        .onReceive(PlaybackClock.shared.$time) { newTime in
            handleTimelineAutoScroll(currentTime: newTime, duration: duration)
        }
        .onChange(of: videoManager.isPlaying) { isPlaying in
            if isPlaying {
                handlePlaybackResumed(duration: duration)
            }
        }
        .onChange(of: timelineScale) { _ in
            handleZoomChanged(duration: duration)
        }
    }
    
    // The playhead position (as a fraction of visible width) at which the
    // timeline starts scrolling to keep the playhead in place.
    private let autoScrollThreshold: CGFloat = 0.85

    // Continuous auto-scroll: once the playhead reaches autoScrollThreshold of
    // the visible area the timeline scrolls forward so the playhead stays fixed
    // at that threshold position. This applies both during normal playback and
    // when the user manually seeks the playhead past the threshold.
    //
    // If the user manually scrolled away, auto-scroll is suppressed until they
    // either resume playback or scroll back so the playhead re-enters the
    // visible zone before the threshold.
    private func handleTimelineAutoScroll(currentTime: Double, duration: Double) {
        guard !playheadDragController.isDragging else { return }
        let visibleWidth = timelineScrollController.visibleWidth
        guard visibleWidth > 0, duration > 0 else { return }

        let effectiveScale = max(timelineScale * magnifyScale, 1.0)
        let gridWidth = visibleWidth * effectiveScale
        let playheadX = (currentTime / duration) * gridWidth
        let currentScrollX = timelineScrollController.currentScrollX

        // If user scrolled away but has now scrolled back so the playhead is
        // visible and before the threshold, clear the flag and resume auto-scroll.
        if timelineScrollController.userDidManuallyScroll {
            let playheadVisible = playheadX >= currentScrollX &&
                                  playheadX < currentScrollX + visibleWidth * autoScrollThreshold
            if playheadVisible {
                timelineScrollController.userDidManuallyScroll = false
            } else {
                return
            }
        }

        let triggerX = currentScrollX + visibleWidth * autoScrollThreshold
        if playheadX >= triggerX {
            let newScrollX = playheadX - visibleWidth * autoScrollThreshold
            timelineScrollController.scrollTo(x: newScrollX)
        }
    }

    // On resume from pause: position the playhead at the left edge of the
    // visible area so it starts from the beginning and the timeline scrolls
    // when the playhead reaches the threshold. Clears the manual-scroll flag
    // so auto-scroll works going forward.
    private func handlePlaybackResumed(duration: Double) {
        let visibleWidth = timelineScrollController.visibleWidth
        guard visibleWidth > 0, duration > 0 else { return }

        let effectiveScale = max(timelineScale * magnifyScale, 1.0)
        let gridWidth = visibleWidth * effectiveScale
        let playheadX = (videoManager.currentTime / duration) * gridWidth
        let currentScrollX = timelineScrollController.currentScrollX

        timelineScrollController.stopAutoScrollFollow()
        timelineScrollController.userDidManuallyScroll = false
        if playheadX < currentScrollX || playheadX >= currentScrollX + visibleWidth {
            timelineScrollController.scrollTo(x: max(0, playheadX))
        }
    }

    // After zoom the pixel coordinate of the playhead shifts while the
    // NSScrollView keeps its old content offset, so the timeline would appear to
    // zoom around its left edge. Instead we keep the playhead pinned to its
    // current on-screen position (or centered if it was off-screen), so zooming
    // happens "around the playhead". Auto-scroll is suppressed until the user
    // pauses and resumes playback.
    private func handleZoomChanged(duration: Double) {
        timelineScrollController.stopAutoScrollFollow()
        timelineScrollController.userDidManuallyScroll = true

        let visibleWidth = timelineScrollController.visibleWidth
        let oldEffectiveScale = max(previousEffectiveScale, 1.0)
        let newEffectiveScale = max(timelineScale, 1.0)
        // Record the new baseline regardless, so a later zoom starts from here.
        previousEffectiveScale = newEffectiveScale

        guard visibleWidth > 0, duration > 0,
              abs(newEffectiveScale - oldEffectiveScale) > 0.0001 else { return }

        let ratio = max(0.0, min(videoManager.currentTime / duration, 1.0))
        let oldGridWidth = visibleWidth * oldEffectiveScale
        let newGridWidth = visibleWidth * newEffectiveScale

        // On-screen position of the playhead before the zoom. If it was outside
        // the viewport, anchor on the centre instead.
        let playheadViewportX = ratio * oldGridWidth - timelineScrollController.currentScrollX
        let anchorX = (playheadViewportX < 0 || playheadViewportX > visibleWidth)
            ? visibleWidth / 2
            : playheadViewportX

        let newScrollX = ratio * newGridWidth - anchorX
        // The content view resizes on the next layout pass, so jump after it.
        DispatchQueue.main.async {
            timelineScrollController.scrollTo(x: max(0, newScrollX))
        }
    }
    
    private func formatTimeForHover(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1.0)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }
    
    private func calculateTimeFromPosition(_ x: CGFloat, duration: Double, gridWidth: CGFloat) -> Double {
        guard duration > 0 && gridWidth > 0 else { return 0.0 }
        let time = (x / gridWidth) * duration
        return max(0.0, min(time, duration))
    }
    
    // MARK: - Окно видимости строк (ручная виртуализация)
    //
    // `LazyVStack` сам по себе правую колонку НЕ виртуализует: дорожки лежат внутри вложенного
    // горизонтального `ScrollView`, и внешний вертикальный скролл считает её контентом
    // фиксированной высоты — материализуются все строки. Поэтому окно считаем руками и применяем
    // к ОБЕИМ колонкам один и тот же диапазон, чтобы имена не разъехались с дорожками.
    //
    // Сверху и снизу вместо невидимых строк ставим `Color.clear` точной высоты — тогда общая
    // высота контента и, значит, диапазон вертикального скролла остаются прежними.
    //
    // Безопасно, потому что вертикального `scrollTo` в коде нет (горизонтальный идёт через
    // `timelineScrollController`). Появится — окно придётся учитывать и там.

    private static let timelineRowHeight: CGFloat = 30
    /// Запас строк за пределами вьюпорта — чтобы при быстром скролле не мигала пустота.
    private static let timelineWindowBuffer = 12

    @State private var timelineVerticalOffset: CGFloat = 0

    /// Штамп вместе со своей линией — для листов, поднятых из строки в окно (TASK-007, 3.5).
    /// `id` берём у штампа: он уникален, а `.sheet(item:)` пересоздаёт лист при его смене.
    struct StampInLine: Identifiable {
        let line: TimelineLine
        let stamp: TimelineStamp
        var id: UUID { stamp.id }
    }

    @State private var stampForCommentEdit: StampInLine?
    @State private var stampForSessionPick: StampInLine?

    /// `ScreenshotMetadata` не `Identifiable`, а `.sheet(item:)` этого требует — оборачиваем.
    struct ScreenshotEditTarget: Identifiable {
        let screenshot: ScreenshotMetadata
        var id: String { screenshot.screenshotName }
    }

    @State private var screenshotForTagEditing: ScreenshotEditTarget?

    /// Строка вместе со своим индексом в общем списке — индекс нужен строке для вертикального
    /// переноса штампа, а идентичность для `ForEach` остаётся по `line.id`.
    struct WindowedLine: Identifiable {
        let index: Int
        let line: TimelineLine
        var id: UUID { line.id }
    }

    /// Строки для отрисовки с учётом поиска по клипам: число строк не меняется (иначе разъедется
    /// с колонкой имён) — фильтруем только штампы внутри строк. Без активного поиска отдаём
    /// исходные строки без копий (быстрый путь).
    private var displayLines: [TimelineLine] {
        // visibleLines, а не lines: служебный таймлайн счётчиков скрыт, пока его не позвали ⌘⌃0.
        let all = timelineData.visibleLines
        guard clipFilter.hasActiveFilters() else { return all }
        return all.map { line in
            var copy = line
            copy.stamps = line.stamps.filter { clipFilter.matches(stamp: $0) }
            return copy
        }
    }

    /// Видимое окно строк в виде массива с индексами. Аллокация здесь безобидна: элементов
    /// столько, сколько строк на экране (~30), а не сколько их в проекте.
    private func windowedLines(range: Range<Int>, in lines: [TimelineLine]) -> [WindowedLine] {
        range.map { WindowedLine(index: $0, line: lines[$0]) }
    }

    /// Штампы этой строки, попавшие в ⌘-выбор. Передаём в строку именно подмножество, а не весь
    /// `stampsSelectedForSportCut`: иначе выбор в одной строке менял бы параметр у ВСЕХ строк и
    /// ломал сравнение, из-за которого они и пропускают перерисовку.
    private func bulkSelectionIDs(in line: TimelineLine) -> Set<UUID> {
        let selected = timelineData.stampsSelectedForSportCut
        guard !selected.isEmpty else { return [] }
        var result: Set<UUID> = []
        for stamp in line.stamps where selected.contains(stamp.id) {
            result.insert(stamp.id)
        }
        return result
    }

    private func visibleLineRange(count: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let rowHeight = Self.timelineRowHeight
        let viewportHeight = max(parentWindowHeight, rowHeight)
        let firstVisible = Int(max(0, timelineVerticalOffset) / rowHeight)
        let visibleCount = Int(viewportHeight / rowHeight) + 1

        let lower = max(0, firstVisible - Self.timelineWindowBuffer)
        let upper = min(count, firstVisible + visibleCount + Self.timelineWindowBuffer)
        return lower..<max(lower, upper)
    }

    /// Невидимый измеритель вертикального смещения. Живёт в `.background` контента, поэтому
    /// не влияет ни на высоту, ни на попадания мыши.
    private var timelineScrollOffsetTracker: some View {
        GeometryReader { geo in
            let offset = -geo.frame(in: .named("vTimelineScroll")).minY
            Color.clear
                .onAppear { updateTimelineVerticalOffset(offset) }
                .onChange(of: offset) { updateTimelineVerticalOffset($0) }
        }
        .allowsHitTesting(false)
    }

    /// Пишем `@State` только при смещении хотя бы на половину строки. Без этого порога каждый
    /// кадр скролла инвалидировал бы body — то есть виртуализация съела бы сама себя.
    private func updateTimelineVerticalOffset(_ offset: CGFloat) {
        let clamped = max(0, offset)
        guard abs(clamped - timelineVerticalOffset) >= Self.timelineRowHeight / 2 else { return }
        timelineVerticalOffset = clamped
    }

    @ViewBuilder
    private func timelineNameRows() -> some View {
        let lines = timelineData.visibleLines
        let range = visibleLineRange(count: lines.count)

        Color.clear
            .frame(width: 195, height: CGFloat(range.lowerBound) * Self.timelineRowHeight)

        ForEach(lines[range]) { line in
            if markupMode == .standard {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.6)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(lineNameFill(line))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(lineNameStroke(line), lineWidth: lineNameStrokeWidth(line))
                            )
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        Button(action: {
                            timelineData.selectLine(line.id)
                            showEditNameSheet = true
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.blue)
                                .padding(3)
                                .background(Circle().fill(Color.blue.opacity(0.1)))
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .help(^String.Titles.editTimelineName)

                        Button(action: {
                            TimelineDataManager.shared.removeLine(lineID: line.id)
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.red)
                                .padding(3)
                                .background(Circle().fill(Color.red.opacity(0.1)))
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .help(^String.Titles.timelineButtonDeleteTimeline)
                    }
                }
                .padding(.leading, 5)
                .frame(width: 195, height: 30, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if timelineData.isMergeSelectionActive {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            timelineData.toggleMergeSelection(line.id)
                        }
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let commandDown = NSEvent.modifierFlags.contains(.command)
                        if commandDown {
                            timelineData.selectAllSportCutExportStamps(in: line.id)
                        } else {
                            timelineData.selectLine(line.id)
                        }
                    }
                }
                .contextMenu {
                    Button(^String.Titles.editName) {
                        timelineData.selectLine(line.id)
                        showEditNameSheet = true
                    }
                    Button(^String.Titles.timelineButtonDeleteTimeline) {
                        TimelineDataManager.shared.removeLine(lineID: line.id)
                    }
                }
                .onDrag {
                    draggingLineID = line.id
                    return NSItemProvider(object: line.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: TimelineDropDelegate(
                    currentLine: line,
                    timelineData: timelineData,
                    draggingLineID: $draggingLineID
                ))
                .id("name-\(line.id)")
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.6)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(lineNameFill(line))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(lineNameStroke(line), lineWidth: lineNameStrokeWidth(line))
                            )
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        Button(action: {
                            TimelineDataManager.shared.removeLine(lineID: line.id)
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.red)
                                .padding(3)
                                .background(Circle().fill(Color.red.opacity(0.1)))
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .help(^String.Titles.timelineButtonDeleteTimeline)
                    }
                }
                .padding(.leading, 5)
                .frame(width: 195, height: 30, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if timelineData.isMergeSelectionActive {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            timelineData.toggleMergeSelection(line.id)
                        }
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let commandDown = NSEvent.modifierFlags.contains(.command)
                        if commandDown {
                            timelineData.selectAllSportCutExportStamps(in: line.id)
                        } else {
                            timelineData.selectLine(line.id)
                        }
                    }
                }
                .contextMenu {
                    Button(^String.Titles.timelineButtonDeleteTimeline) {
                        TimelineDataManager.shared.removeLine(lineID: line.id)
                    }
                }
                .onDrag {
                    draggingLineID = line.id
                    return NSItemProvider(object: line.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: TimelineDropDelegate(
                    currentLine: line,
                    timelineData: timelineData,
                    draggingLineID: $draggingLineID
                ))
                .id("name-\(line.id)")
            }
        }

        Color.clear
            .frame(width: 195,
                   height: CGFloat(lines.count - range.upperBound) * Self.timelineRowHeight)
    }

    @ViewBuilder
    private func timelineZStackContent(duration: Double, interval: Double, gridWidth: CGFloat, effectiveScale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TimeGridView(
                // Мелкие линии сетки идут в 5 раз чаще подписей, поэтому каждая
                // 5-я (жирная) линия попадает ровно под подпись времени.
                duration: duration,
                interval: interval / 5,
                width: gridWidth,
                height: 30 * CGFloat(timelineData.visibleLines.count + 1)
            )
            .padding(.top, markerHeadBand)
            
            VStack(spacing: 0) {
                // Здесь была ВТОРАЯ копия линейки времени. Она всегда полностью скрыта под
                // закреплённой шапкой (`pinnedTimelineHeaderOverlay` перекрывает ровно
                // markerHeadBand + 30 сверху вьюпорта, а при скролле линейка уезжает под неё),
                // то есть 240 `Text` строились вхолостую на каждый пересчёт. Оставлена только
                // распорка той же высоты — на ней держится выравнивание дорожек.
                // Тап по линейке (seek + снятие выделения) работает через закреплённую копию.
                // См. TASK-007, 2.4.
                Color.clear
                    .frame(width: gridWidth, height: 30)
                // Тот же диапазон, что и у колонки имён (`timelineNameRows`) — иначе колонки
                // разъедутся. Пустоты сверху/снизу держат общую высоту неизменной.
                // `displayLines` = строки с отфильтрованными по поиску штампами (число строк то же,
                // поэтому выравнивание с колонкой имён сохраняется).
                let lines = displayLines
                let range = visibleLineRange(count: lines.count)

                Color.clear
                    .frame(height: CGFloat(range.lowerBound) * Self.timelineRowHeight)

                // Идентичность — по `line.id`, как и была. Через индекс нельзя: при
                // переупорядочивании строк SwiftUI переиспользовал бы `@State` не той строки
                // (активный ресайз штампа, подсветка drop-таргета).
                ForEach(windowedLines(range: range, in: lines)) { item in
                    let line = item.line
                    TimelineLineView(
                        line: line,
                        scale: effectiveScale,
                        widthMax: gridWidth,
                        totalDuration: max(1, duration),
                        lineIndex: item.index,
                        linesCount: lines.count,
                        selectedStampID: timelineData.selectedStampID,
                        // Только id из ЭТОЙ строки: иначе ⌘-выбор в одной строке ломал бы
                        // равенство у всех остальных и они бы перерисовывались зря.
                        bulkSelectedStampIDs: bulkSelectionIDs(in: line),
                        isSelected: (line.id == timelineData.selectedLineID),
                        onSelect: { timelineData.selectLine(line.id) },
                        onEditLabelsRequest: { stampID in
                            UserDefaults.standard.set(line.id.uuidString, forKey: "editingStampLineID")
                            UserDefaults.standard.set(stampID.uuidString, forKey: "editingStampID")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                stampItemsEditSheetType = .lables
                            }
                        },
                        onEditTimeEventsRequest: { stampID in
                            UserDefaults.standard.set(line.id.uuidString, forKey: "editingStampLineID")
                            UserDefaults.standard.set(stampID.uuidString, forKey: "editingStampID")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                stampItemsEditSheetType = .timeEvents
                            }
                        },
                        onTagDragging: { tagEdgePosition in
                            self.tagEdgePosition = tagEdgePosition
                        },
                        onEditComment: { stamp in
                            stampForCommentEdit = StampInLine(line: line, stamp: stamp)
                        },
                        onPickSession: { stamp in
                            stampForSessionPick = StampInLine(line: line, stamp: stamp)
                        }
                    )
                    // `.equatable()` обязателен: SwiftUI НЕ использует `==` у View сам по себе,
                    // только через `EquatableView`. Без этого вызова конформанс `Equatable`
                    // у `TimelineLineView` ни на что не влияет и строки перерисовываются все.
                    .equatable()
                    .frame(height: 30)
                    .id("timeline-\(line.id)")
                }

                Color.clear
                    .frame(height: CGFloat(lines.count - range.upperBound) * Self.timelineRowHeight)
            }
            .padding(.bottom, 15) // for scroll indicator to not overlap timelines
            .padding(.top, markerHeadBand)

            // Интервальные теги, которые пишутся прямо сейчас: растущий штамп появляется на
            // дорожке сразу по старту записи, а не по её окончании. Слой пустой (и ни на что
            // не подписан), пока ничего не пишется. См. `IntervalRecordingPreviewOverlay`.
            IntervalRecordingPreviewOverlay(
                duration: duration,
                gridWidth: gridWidth,
                lines: displayLines,
                selectedLineID: timelineData.selectedLineID,
                rowHeight: Self.timelineRowHeight,
                topInset: 30
            )
            .padding(.top, markerHeadBand)

            // Ни одного чтения времени/позиции плейхеда в этом body: и `playheadDragController`,
            // и `PlaybackClock` наблюдает только сам TimelinePlayheadView. Раньше здесь считался
            // `timeOffsetToPixels` из `videoManager.currentTime` — из-за этой одной строки весь
            // FullControlView со всеми дорожками перестраивался 30 раз в секунду.
            TimelinePlayheadView(
                dragController: playheadDragController,
                scrollController: timelineScrollController,
                tagEdgePosition: tagEdgePosition,
                gridWidth: gridWidth,
                duration: duration,
                isResizingTag: videoManager.isResizingTag
            )
            .padding(.top, markerHeadBand)

            // Стебли меток рисунков — синяя полоска на всю высоту всех дорожек (как плейхед).
            // «Головы»-карандаши вынесены в закреплённую шапку (`PinnedTimelineRulerView`),
            // чтобы оставались кликабельны при вертикальном скролле; здесь — только стебли.
            ScreenshotMarkersView(
                duration: duration,
                gridWidth: gridWidth,
                totalHeight: 30 * CGFloat(timelineData.visibleLines.count + 1),
                part: .stemsOnly
            )
            .padding(.top, markerHeadBand)
            .allowsHitTesting(false)

            TimelineMouseTracker(
                duration: duration,
                gridWidth: gridWidth,
                lines: displayLines,
                tagLibrary: TagLibraryManager.shared,
                onStampUpdate: { stampInfo, location in
                    NotificationCenter.default.post(
                        name: .timelineStampHoverChanged,
                        object: nil,
                        userInfo: ["stampInfo": stampInfo as Any]
                    )
                }
            )
            .padding(.top, markerHeadBand)
            .allowsHitTesting(false)
        }
        .frame(width: gridWidth)
        .coordinateSpace(name: "timelineSpace")
        .contextMenu {
            if !timelineData.stampsSelectedForSportCut.isEmpty {
                Button(^String.Titles.viewingOpenInMode) {
                    WindowsManager.shared.openSportCutFromSelectedStamps(forceNewSession: false)
                }
                Button(^String.Titles.viewingAddSelectedToPlaylist) {
                    WindowsManager.shared.appendMarkupSelectionToOpenSportCutPlaylist()
                }
            }
        }
    }
    
    @ViewBuilder
    private func timelineContent(proxy: ScrollViewProxy) -> some View {
        // alignment: .top обязателен. Правая колонка выше левой (у неё `.padding(.bottom, 15)`
        // под индикатор скролла), и при выравнивании по центру — по умолчанию — столбец имён
        // опускался на половину разницы относительно своих дорожек.
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Пустая полоса сверху под «головы» меток рисунков в правой части —
                // чтобы левый столбец с названиями оставался выровнен с линейкой и дорожками.
                Color.clear
                    .frame(width: 195, height: markerHeadBand)
                ZStack(alignment: .leading) {
                    // Кнопки-бар (углового контрола) вынесен в закреплённую сверху шапку
                    // (`pinnedTimelineHeaderOverlay`) — здесь остаётся только пустая полоса для
                    // выравнивания строк дорожек. Полоса скроллится и прячется под закреплённой шапкой.
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.gray.opacity(0.05),
                            Color.gray.opacity(0.02)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 195, height: 30, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .id("header-row")
                
                timelineNameRows()
            }
            .frame(width: 195)
            .padding(.trailing, 5)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.05))
            )
            
            // Ширину меряем ФОНОВЫМ GeometryReader (не оборачивающим), чтобы у контента осталась
            // его реальная высота и вертикальный скролл долистывал до конца при любом размере окна.
            timelineScrollView(
                width: timelineRightColumnWidth,
                effectiveScale: timelineScale * magnifyScale,
                duration: effectiveVideoDuration,
                popupInfo: nil,
                popupLocation: nil
            )
            // Горизонтальный ScrollView иначе «жадный» по высоте (тянется на весь вьюпорт и режет
            // контент) — fixedSize по вертикали заставляет взять реальную высоту контента, тогда
            // вертикальный скролл долистывает до конца при любом размере окна.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { timelineRightColumnWidth = g.size.width }
                        .onChange(of: g.size.width) { timelineRightColumnWidth = $0 }
                }
            )
            .sheet(isPresented: $showAiReportSheet) {
                AiReportSheet(onSubmit: { teamName, opponentName, venue, matchDate in
                    generateAndDownloadAiReport(teamName: teamName,
                                                opponentName: opponentName,
                                                venue: venue,
                                                matchDate: matchDate)
                })
            }
            .sheet(isPresented: $showSimpleReportSheet) {
                AiReportSheet(onSubmit: { teamName, opponentName, venue, matchDate in
                    generateSimpleReport(teamName: teamName,
                                         opponentName: opponentName,
                                         venue: venue,
                                         matchDate: matchDate)
                })
            }
            .sheet(isPresented: $showEditNameSheet) {
                if let lineID = timelineData.selectedLineID,
                   let line = timelineData.lines.first(where: { $0.id == lineID }) {
                    EditTimelineNameSheet(lineName: line.name) { newName in
                        if let index = timelineData.lines.firstIndex(where: { $0.id == lineID }) {
                            timelineData.lines[index].name = newName
                            timelineData.updateTimelines()
                        }
                    }
                }
            }
        }
        // Костыль: при уменьшении окна добавляем внизу списка пустоту, равную тому, насколько окно
        // стало меньше стартового — чтобы скролл всегда долистывался до последней дорожки.
        .padding(.bottom, extraScrollBottomPadding)
        // Измеритель вертикального смещения для окна видимости строк. Именно `.background`:
        // так он получает геометрию контента и при этом не влияет ни на высоту, ни на попадания.
        .background(timelineScrollOffsetTracker)
    }

    /// Насколько окно уменьшилось относительно стартового размера (0, если больше/равно).
    private var extraScrollBottomPadding: CGFloat {
        guard standardWindowHeight > 0, currentWindowHeight > 0 else { return 0 }
        return max(0, standardWindowHeight - currentWindowHeight)
    }

    func generateAndDownloadAiReport(teamName: String, opponentName: String, venue: String, matchDate: String) {
        let fullLines = transformToFullTimelineLines()
        
        struct AIReportRequest: Encodable {
            let match_data: MatchData
            let team_name: String
            let opponent_name: String
            let venue: String
            let match_date: String
            
            struct MatchData: Encodable {
                let data: [FullTimelineLine]
            }
        }
        
        let request = AIReportRequest(
            match_data: AIReportRequest.MatchData(data: fullLines),
            team_name: teamName,
            opponent_name: opponentName,
            venue: venue,
            match_date: matchDate
        )
        
        let appLocale = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        let locale = appLocale.hasPrefix("ru") ? "ru" : "en"
        guard let url = URL(string: "https://razmetka.youchip.pro/api/generate-interactive-report?locale=\(locale)") else {
            print("FullControlView: Invalid URL for generate-interactive-report")
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        isExporting = true
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            urlRequest.httpBody = try encoder.encode(request)
            
            URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                DispatchQueue.main.async {
                    self.isExporting = false
                    
                    if let error = error {
                        self.errorMessage = String.Titles.fullControlAiReportErrorGeneration.format(error.localizedDescription)
                        self.showErrorAlert = true
                        return
                    }
                    
                    guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                        self.errorMessage = ^String.Titles.fullControlErrorNoServerData
                        self.showErrorAlert = true
                        return
                    }
                    
                    if httpResponse.statusCode == 200 {
                        self.showHtmlReportInWebView(data: data, teamName: teamName, opponentName: opponentName)
                    } else {
                        var errorMsg = String.Titles.fullControlErrorServer.format(String(httpResponse.statusCode))
                        if let responseString = String(data: data, encoding: .utf8) {
                            errorMsg += "\n\(responseString)"
                        }
                        self.errorMessage = errorMsg
                        self.showErrorAlert = true
                    }
                }
            }.resume()
        } catch {
            DispatchQueue.main.async {
                self.isExporting = false
                self.errorMessage = String.Titles.fullControlErrorEncodingRequest.format(error.localizedDescription)
                self.showErrorAlert = true
            }
        }
    }
    
    func generateSimpleReport(teamName: String, opponentName: String, venue: String, matchDate: String) {
        let fullLines = transformToFullTimelineLines()
        
        struct SimpleReportRequest: Encodable {
            let match_data: MatchData
            let team_name: String
            let opponent_name: String
            let venue: String
            let match_date: String
            
            struct MatchData: Encodable {
                let data: [FullTimelineLine]
            }
        }
        
        let request = SimpleReportRequest(
            match_data: SimpleReportRequest.MatchData(data: fullLines),
            team_name: teamName,
            opponent_name: opponentName,
            venue: venue,
            match_date: matchDate
        )
        
        let appLocale = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        let locale = appLocale.hasPrefix("ru") ? "ru" : "en"
        guard let url = URL(string: "https://razmetka.youchip.pro/api/generate-match-report?locale=\(locale)") else {
            print("FullControlView: Invalid URL for generate-match-report")
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        isExporting = true
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            urlRequest.httpBody = try encoder.encode(request)
            
            URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                DispatchQueue.main.async {
                    self.isExporting = false
                    
                    if let error = error {
                        self.errorMessage = String.Titles.fullControlSimpleReportErrorGeneration.format(error.localizedDescription)
                        self.showErrorAlert = true
                        return
                    }
                    
                    guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                        self.errorMessage = ^String.Titles.fullControlErrorNoServerData
                        self.showErrorAlert = true
                        return
                    }
                    
                    if httpResponse.statusCode == 200 {
                        self.saveReportFile(data: data, teamName: teamName, opponentName: opponentName)
                    } else {
                        var errorMsg = String.Titles.fullControlErrorServer.format(String(httpResponse.statusCode))
                        if let responseString = String(data: data, encoding: .utf8) {
                            errorMsg += "\n\(responseString)"
                        }
                        self.errorMessage = errorMsg
                        self.showErrorAlert = true
                    }
                }
            }.resume()
        } catch {
            DispatchQueue.main.async {
                self.isExporting = false
                self.errorMessage = String.Titles.fullControlErrorEncodingRequest.format(error.localizedDescription)
                self.showErrorAlert = true
            }
        }
    }
    
    func showHtmlReportInWebView(data: Data, teamName: String, opponentName: String) {
        guard let htmlString = String(data: data, encoding: .utf8) else {
            errorMessage = ^String.Titles.fullControlErrorDataToHtml
            showErrorAlert = true
            return
        }
        
        WindowsManager.shared.showReportWindow(
            htmlString: htmlString,
            teamName: teamName,
            opponentName: opponentName
        )
    }
    
    func saveReportFile(data: Data, teamName: String, opponentName: String) {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["pdf"]
        panel.nameFieldStringValue = String.Titles.aiReportFileNameFormat.format(teamName, opponentName)
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
            } catch {
                errorMessage = String.Titles.aiReportSaveError.format(error.localizedDescription)
                showErrorAlert = true
            }
        }
    }
    
    /// Live / review switch for the timelines header bar (no extra «Режим» caption).
    @ViewBuilder
    private func liveReviewToggleCompact() -> some View {
        if videoManager.isLiveMode {
            HStack(spacing: 4) {
                Button(action: {
                    if videoManager.isReviewMode {
                        videoManager.exitReviewMode()
                        WindowsManager.shared.closeReviewWindow()
                    }
                }) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(videoManager.isReviewMode ? Color.gray.opacity(0.5) : Color.red)
                            .frame(width: 6, height: 6)
                        Text("Live")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(!videoManager.isReviewMode ? .red : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(^String.Titles.viewingLiveModeHelp)
                
                Button(action: {
                    if !videoManager.isReviewMode {
                        videoManager.enterReviewMode()
                        WindowsManager.shared.openReviewWindow()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "gobackward")
                            .font(.system(size: 9, weight: .semibold))
                        Text(^String.Titles.viewingReviewLabel)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(videoManager.isReviewMode ? .orange : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(^String.Titles.viewingReviewHelp)
            }
        }
    }
    
    @ViewBuilder
    private func timelineToolsIconButton(systemImage: String, helpText: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
    
    @ViewBuilder
    /// Закреплённая сверху шапка таймлайнов: бар-кнопки (слева) + линейка времени с треугольником
    /// плейхеда (справа). Всегда статична сверху — вертикально скроллятся только дорожки под ней.
    /// Непрозрачный фон перекрывает уехавшую под неё исходную полосу.
    private var pinnedTimelineHeaderOverlay: some View {
        GeometryReader { geo in
            let rightWidth = max(1, geo.size.width - 200) // 195 (столбец имён) + 5 (padding)
            let effectiveScale = timelineScale * magnifyScale
            let gridWidth = rightWidth * max(effectiveScale, 1.0)
            let interval = calculateTimeGridInterval(gridWidth: gridWidth, totalDuration: effectiveVideoDuration)

            HStack(spacing: 0) {
                // Слева — бар-кнопки (единственный экземпляр; из скроллящегося тела убран).
                VStack(spacing: 0) {
                    Color.clear.frame(height: markerHeadBand)
                    ZStack(alignment: .leading) {
                        LinearGradient(
                            gradient: Gradient(colors: [Color.gray.opacity(0.05), Color.gray.opacity(0.02)]),
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(width: 195, height: 30, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color.gray.opacity(0.2), lineWidth: 0.5))

                        timelineTableCornerControls()
                            .frame(width: 195, height: 30, alignment: .leading)
                    }
                }
                .frame(width: 195)
                .padding(.trailing, 5)

                // Справа — линейка времени, синхронная горизонтальному скроллу дорожек.
                PinnedTimelineRulerView(
                    controller: timelineScrollController,
                    videoManager: videoManager,
                    dragController: playheadDragController,
                    duration: effectiveVideoDuration,
                    gridWidth: gridWidth,
                    interval: interval,
                    viewportWidth: rightWidth,
                    band: markerHeadBand,
                    markersTotalHeight: 30 * CGFloat(timelineData.visibleLines.count + 1),
                    onEditScreenshotTags: { screenshot in
                        screenshotForTagEditing = ScreenshotEditTarget(screenshot: screenshot)
                    }
                )
            }
            .frame(width: geo.size.width, height: markerHeadBand + 30, alignment: .topLeading)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(height: markerHeadBand + 30)
        .allowsHitTesting(!isEditorModeActive && !isScreenshotDisplayActive)
    }

    private func timelineTableCornerControls() -> some View {
        HStack(spacing: 3) {
            if timelineData.isMergeSelectionActive {
                mergeSelectionBar()
            }
            if !timelineData.isMergeSelectionActive {
                if markupMode == .standard {
                    Button {
                        showAddLineSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .help(^String.Titles.fullControlButtonAddTimeline)
                }

                // Объединение таймлайнов доступно в обоих режимах разметки.
                Button {
                    timelineData.beginMergeSelection()
                } label: {
                    Image(systemName: "arrow.triangle.merge")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help(^String.Titles.fullControlButtonMergeTimelines)
            }

            if !timelineData.isMergeSelectionActive {
            HStack(spacing: 1) {
                Button(action: {
                    WindowsManager.shared.setMarkupMode(.standard)
                }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 10, weight: .medium))
                        .frame(minWidth: 22, minHeight: 22)
                        .background(markupMode == .standard ? Color.blue : Color.gray.opacity(0.12))
                        .foregroundColor(markupMode == .standard ? .white : .primary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(^String.Titles.fullControlLabelStandard)
                
                Button(action: {
                    WindowsManager.shared.setMarkupMode(.tagBased)
                }) {
                    Image(systemName: "tag")
                        .font(.system(size: 10, weight: .medium))
                        .frame(minWidth: 22, minHeight: 22)
                        .background(markupMode == .tagBased ? Color.blue : Color.gray.opacity(0.12))
                        .foregroundColor(markupMode == .tagBased ? .white : .primary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(^String.Titles.tags)
            }
            .help(^String.Titles.fullControlModeHelp)
            
            Button {
                showZoomPopover.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 10, weight: .medium))
                    Text(String(format: "%.1fx", timelineScale))
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(minHeight: 22)
                .padding(.horizontal, 6)
                .background(Color.gray.opacity(0.12))
                .foregroundColor(.primary)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help(^String.Titles.fullControlButtonTimelineZoomIn)
            .popover(isPresented: $showZoomPopover, arrowEdge: .bottom) {
                zoomPopoverContent()
            }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
    }

    /// Zoom control shown in a popover so it doesn't take up space in the
    /// timeline corner toolbar (which would otherwise hide the merge button).
    @ViewBuilder
    private func zoomPopoverContent() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "minus.magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Ползунок зумит вокруг плейхеда (см. handleZoomChanged), а не вокруг курсора.
            Slider(value: $timelineScale, in: 1.0...10.0)
                .controlSize(.small)
                .frame(width: 180)

            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Text(String(format: "%.1fx", timelineScale))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func isMergeSelected(_ line: TimelineLine) -> Bool {
        timelineData.isMergeSelectionActive && timelineData.mergeSelectedLineIDs.contains(line.id)
    }

    private func lineNameFill(_ line: TimelineLine) -> Color {
        if isMergeSelected(line) { return Color.green.opacity(0.25) }
        return line.id == timelineData.selectedLineID ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1)
    }

    private func lineNameStroke(_ line: TimelineLine) -> Color {
        if isMergeSelected(line) { return Color.green.opacity(0.7) }
        return line.id == timelineData.selectedLineID ? Color.blue.opacity(0.4) : Color.gray.opacity(0.2)
    }

    private func lineNameStrokeWidth(_ line: TimelineLine) -> CGFloat {
        isMergeSelected(line) ? 1.5 : 0.5
    }

    /// Compact Done / Cancel bar shown in the timeline corner while choosing timelines to merge.
    @ViewBuilder
    private func mergeSelectionBar() -> some View {
        Button {
            timelineData.commitMergeSelection()
        } label: {
            Text(^String.Titles.done)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(timelineData.mergeSelectedLineIDs.isEmpty ? Color.gray.opacity(0.5) : Color.green)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(timelineData.mergeSelectedLineIDs.isEmpty)
        .help(^String.Titles.fullControlMergeTimelinesHint)

        Button {
            timelineData.cancelMergeSelection()
        } label: {
            Text(^String.Titles.cancelButtonTitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)

        Text("\(timelineData.mergeSelectedLineIDs.count)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
    }

    private var playbackActions: VideoControlPanelActions {
        videoManager.isReviewMode
            ? .init(
                seekBackward10: { videoManager.seekReview(by: -10) },
                seekBackward5: { videoManager.seekReview(by: -5) },
                togglePlayPause: { videoManager.toggleReviewPlayPause() },
                seekForward5: { videoManager.seekReview(by: 5) },
                seekForward10: { videoManager.seekReview(by: 10) },
                changeSpeed: { videoManager.changeReviewPlaybackSpeed(to: $0) }
            )
            : .init(
                seekBackward10: { videoManager.seek(by: -10) },
                seekBackward5: { videoManager.seek(by: -5) },
                togglePlayPause: { videoManager.togglePlayPause() },
                seekForward5: { videoManager.seek(by: 5) },
                seekForward10: { videoManager.seek(by: 10) },
                changeSpeed: { videoManager.changePlaybackSpeed(to: $0) }
            )
    }

    private func exportSimpleJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(timelineData.lines)
            let panel = NSSavePanel()
            panel.allowedFileTypes = ["json"]
            panel.nameFieldStringValue = ^String.Titles.fullControlExportSimpleJsonFileName
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            errorMessage = String.Titles.fullControlExportJsonSaveError.format(error.localizedDescription)
            showErrorAlert = true
        }
    }
    
    private func exportFullJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let fullLines = transformToFullTimelineLines()
        do {
            let wrapper = ["data": fullLines]
            let data = try encoder.encode(wrapper)
            let panel = NSSavePanel()
            panel.allowedFileTypes = ["json"]
            panel.nameFieldStringValue = ^String.Titles.fullControlExportFullJsonFileName
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            errorMessage = String.Titles.fullControlExportFullJsonSaveError.format(error.localizedDescription)
            showErrorAlert = true
        }
    }
    
    private func exportXML() {
        let tagLibrary = TagLibraryManager.shared

        // Collect all stamps from non-drawings timelines, sorted by start time
        var allStamps: [(stamp: TimelineStamp, tagName: String, labelNames: [String], colorHex: String)] = []
        for line in timelineData.lines {
            if line.isServiceTimeline { continue }
            for stamp in line.stamps {
                let tag = tagLibrary.findTagById(stamp.idTag)
                let tagName = tag?.name ?? stamp.label
                let colorHex = tag?.color ?? stamp.colorHex
                let labelNames = stamp.labelIDs.compactMap { tagLibrary.findLabelById($0)?.name }
                allStamps.append((stamp: stamp, tagName: tagName, labelNames: labelNames, colorHex: colorHex))
            }
        }
        allStamps.sort { $0.stamp.timeStartSeconds < $1.stamp.timeStartSeconds }

        // Build unique codes with colors for ROWS section (preserve first-seen order)
        var seenCodes = Set<String>()
        var rows: [(code: String, colorHex: String)] = []
        for entry in allStamps {
            if seenCodes.insert(entry.tagName).inserted {
                rows.append((code: entry.tagName, colorHex: entry.colorHex))
            }
        }

        // XML builder
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
        }

        // Convert hex color "RRGGBB" → 0-65535 components
        func hexToRGB65k(_ hex: String) -> (r: Int, g: Int, b: Int) {
            let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var value: UInt64 = 0
            Scanner(string: clean).scanHexInt64(&value)
            let r = Int((value >> 16) & 0xFF) * 257
            let g = Int((value >> 8)  & 0xFF) * 257
            let b = Int( value        & 0xFF) * 257
            return (r, g, b)
        }

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<file>\n<ALL_INSTANCES>\n"

        for (index, entry) in allStamps.enumerated() {
            xml += "<instance>\n"
            xml += "<ID>\(index + 1)</ID>\n"
            xml += "<start>\(entry.stamp.timeStartSeconds)</start>\n"
            xml += "<end>\(entry.stamp.timeFinishSeconds)</end>\n"
            xml += "<code>\(esc(entry.tagName))</code>\n"
            if !entry.labelNames.isEmpty {
                xml += "<free_text>\(esc(entry.labelNames.joined(separator: ", ")))</free_text>\n"
            }
            xml += "</instance>\n"
        }

        xml += "</ALL_INSTANCES>\n<ROWS>\n"

        for row in rows {
            let (r, g, b) = hexToRGB65k(row.colorHex)
            xml += "<row>\n"
            xml += "<code>\(esc(row.code))</code>\n"
            xml += "<R>\(r)</R>\n"
            xml += "<G>\(g)</G>\n"
            xml += "<B>\(b)</B>\n"
            xml += "</row>\n"
        }

        xml += "</ROWS>\n</file>"

        let panel = NSSavePanel()
        panel.allowedFileTypes = ["xml"]
        panel.nameFieldStringValue = ^String.Titles.fullControlExportXmlFileName
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try xml.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Error saving XML: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }

    /// Резолвер имён для CSV-экспорта разметки на основе глобальной библиотеки тегов.
    static func markupCSVResolver() -> CSVNameResolver {
        let lib = TagLibraryManager.shared
        return CSVNameResolver(
            tagName: { lib.findTagById($0)?.name ?? $0 },
            labelName: { lib.findLabelById($0)?.name ?? $0 },
            labelGroupName: { id in lib.allLabelGroups.first(where: { $0.lables.contains(id) })?.name ?? "Лейблы" },
            eventName: { id in lib.allTimeEvents.first(where: { $0.id == id })?.name ?? id }
        )
    }

    private func exportExcel() {
        let data = MarkupExcelExporter.makeWorkbookData(
            lines: timelineData.lines,
            tagLibrary: TagLibraryManager.shared
        )
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["xlsx"]
        panel.nameFieldStringValue = ^String.Titles.fullControlExportExcelFileName
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
            } catch {
                errorMessage = String.Titles.fullControlExportExcelSaveError.format(error.localizedDescription)
                showErrorAlert = true
            }
        }
    }

    private var isAnyExportSheetShowing: Bool {
        showExportModeSheet || showTagSelectionSheet || showLabelSelectionSheet ||
        showEventSelectionSheet || multiTagSelectionItem != nil || multiLabelSelectionItem != nil
    }

    private func openCutsExportCurrentTimeline() {
        selectedExportType = .currentTimeline
        exitFullscreenAndShowExportSheet()
    }

    private func openCutsExportAllTimelines() {
        selectedExportType = .allTimelines
        exitFullscreenAndShowExportSheet()
    }

    private func openCutsExportDrawings() {
        selectedExportType = .drawingsTimeline
        exitFullscreenAndShowExportSheet()
    }

    /// Выходит из fullscreen (если нужно) перед показом sheet экспорта,
    /// чтобы окно не растягивалось на весь экран.
    private func exitFullscreenAndShowExportSheet() {
        guard !showExportModeSheet else { return }

        // Выходим из fullscreen только для окон разметки.
        let markupWindows = [
            WindowsManager.shared.controlWindow?.window,
            WindowsManager.shared.videoWindow?.window,
            WindowsManager.shared.tagLibraryWindow?.window
        ].compactMap { $0 }

        var needsDelay = false
        for w in markupWindows where w.styleMask.contains(.fullScreen) {
            w.toggleFullScreen(nil)
            needsDelay = true
        }

        if needsDelay {
            // Даём macOS время на анимацию выхода из fullscreen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard !self.showExportModeSheet else { return }
                self.showExportModeSheet = true
            }
        } else {
            showExportModeSheet = true
        }
    }

    private var stampHoverInlineInfo: AttributedString? {
        hoveredStampInfo
    }
    
    @ViewBuilder
    private var inlineControlsBar: some View {
        HStack(spacing: 6) {
            VideoControlPanelView(
                width: 1800,
                playbackSpeed: videoManager.isReviewMode ? videoManager.reviewPlaybackSpeed : videoManager.playbackSpeed,
                forViewerMode: true,
                forceHorizontalLayout: true,
                actions: playbackActions
            )
            liveReviewToggleCompact()

            Divider()
                .frame(height: 20)

            timelineFilterMenuButton

            clipSearchButton

            clipAutoSaveButton

            clipAutoExportToggle

            Text(stampHoverInlineInfo ?? AttributedString(" "))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .opacity(stampHoverInlineInfo == nil ? 0 : 1)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
//                if CameraLogger.shared.hasLogs {
//                    timelineToolsIconButton(systemImage: "doc.text", helpText: "Экспорт логов камеры") {
//                        exportCameraLogs()
//                    }
//                    timelineToolsIconButton(systemImage: "trash", helpText: "Очистить логи камеры") {
//                        CameraLogger.shared.clearLogs()
//                    }
//                }

                timelineToolsIconButton(systemImage: "map", helpText: ^String.Titles.map) {
                    WindowsManager.shared.showFieldMapVisualizationPicker()
                }
                Menu {
                    Button(^String.Titles.viewingNewSession) {
                        WindowsManager.shared.showSportCutNewSessionFromMarkup()
                    }
                    let existing = sportCutSessionManager.sessions
                    if !existing.isEmpty {
                        Divider()
                        ForEach(existing, id: \.id) { sess in
                            Button(sess.name) {
                                WindowsManager.shared.openSportCutSessionFromMarkup(existingSessionID: sess.id)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
                .help(^String.Titles.view)

                timelineToolsIconButton(systemImage: "photo.on.rectangle.angled", helpText: ^String.Titles.screenshots) {
                    WindowsManager.shared.showScreenshots()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    /// Имя папки автосейва для подписи на кнопке: если длиннее 15 символов — сокращаем
    /// по центру («пап…ка»), оставляя последние 2 символа. Итог — 15 знаков.
    private var truncatedFolderName: String {
        let name = clipAutoSaveManager.folderName ?? ""
        guard name.count > 15 else { return name }
        return String(name.prefix(12)) + "…" + String(name.suffix(2))
    }

    /// Индикатор папки автосохранения клипов (Cmd+S).
    /// Зелёная с именем папки — папка настроена; красная с надписью — надо выбрать.
    @ViewBuilder
    private var clipAutoSaveButton: some View {
        let configured = clipAutoSaveManager.isFolderConfigured
        Menu {
            if configured {
                if let name = clipAutoSaveManager.folderName {
                    Text(String(format: ^String.Titles.clipAutoSaveCurrentFolder, name))
                }
                Button(^String.Titles.clipAutoSaveChangeFolder) {
                    clipAutoSaveManager.pickFolder()
                }
                Button(^String.Titles.clipAutoSaveResetFolder, role: .destructive) {
                    clipAutoSaveManager.resetFolder()
                }
            } else {
                Button(^String.Titles.clipAutoSavePickFolder) {
                    clipAutoSaveManager.pickFolder()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: configured ? "folder.fill.badge.checkmark" : "folder.badge.questionmark")
                    .font(.system(size: 12, weight: .medium))
                if configured {
                    Text(truncatedFolderName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                } else {
                    Text(^String.Titles.clipAutoSaveNotConfiguredBadge)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundColor(configured ? .green : .red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill((configured ? Color.green : Color.red).opacity(0.12))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(configured
              ? String(format: ^String.Titles.clipAutoSaveConfiguredHelp, clipAutoSaveManager.folderName ?? "")
              : ^String.Titles.clipAutoSaveNotConfiguredMessage)
        .onAppear {
            clipAutoSaveManager.refreshFolderState()
        }
    }

    /// Флаг авто-экспорта клипа на каждый добавленный тег — рядом с кнопкой папки автосейва.
    @ViewBuilder
    private var clipAutoExportToggle: some View {
        let on = clipAutoSaveManager.isAutoExportEnabled
        Button {
            clipAutoSaveManager.setAutoExportEnabled(!on)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .medium))
                Text(^String.Titles.clipAutoExportBadge)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(on ? .accentColor : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill((on ? Color.accentColor : Color.gray).opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .help(^String.Titles.clipAutoExportBadge)
    }

    /// Поиск по клипам: открывает лист поиска; подсвечивается, когда фильтр активен, рядом — сброс.
    private var clipSearchButton: some View {
        HStack(spacing: 4) {
            Button(action: { showClipSearchSheet = true }) {
                Image(systemName: clipFilter.hasActiveFilters() ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(clipFilter.hasActiveFilters() ? .blue : .primary)
                    .padding(6)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help(^String.Titles.clipSearchTitle)

            if clipFilter.hasActiveFilters() {
                Button(action: { clipFilter.clearFilters() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(^String.Titles.reset)
            }
        }
    }

    private var timelineFilterMenuButton: some View {
        Menu {
            Button(^String.Titles.viewingSortReset) {
                applyTimelineSort(mode: .original)
            }

            Divider()

            Button(^String.Titles.viewingSortAlphaAsc) {
                applyTimelineSort(mode: .nameAsc)
            }
            Button(^String.Titles.viewingSortAlphaDesc) {
                applyTimelineSort(mode: .nameDesc)
            }

            Divider()

            Button(^String.Titles.viewingSortTagCountDesc) {
                applyTimelineSort(mode: .tagCountDesc)
            }
            Button(^String.Titles.viewingSortTagCountAsc) {
                applyTimelineSort(mode: .tagCountAsc)
            }

            Divider()

            Button(^String.Titles.viewingSortLastTagChronological) {
                applyTimelineSort(mode: .lastTagChronological)
            }
            Button(^String.Titles.viewingSortLastTagReverse) {
                applyTimelineSort(mode: .lastTagChronologicalReverse)
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .padding(6)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(^String.Titles.viewingTimelineFiltersHelp)
    }
    
    private func exportCameraLogs() {
        let logger = CameraLogger.shared
        guard logger.hasLogs else { return }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["txt"]
        panel.nameFieldStringValue = "cameraLogs.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try FileManager.default.copyItem(at: logger.logFileURL, to: url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.copyItem(at: logger.logFileURL, to: url)
            }
        }
    }

    private func applyTimelineSort(mode: TimelineLineSortMode) {
        if timelineLineSortMode == .original, mode != .original {
            originalLineOrderIDs = timelineData.lines.map(\.id)
        }
        
        timelineLineSortMode = mode
        
        switch mode {
        case .original:
            guard let originalIDs = originalLineOrderIDs else {
                return
            }
            let byId = Dictionary(uniqueKeysWithValues: timelineData.lines.map { ($0.id, $0) })
            let originalOrdered: [TimelineLine] = originalIDs.compactMap { byId[$0] }
            let extras: [TimelineLine] = timelineData.lines.filter { line in
                !originalIDs.contains(line.id)
            }
            timelineData.lines = originalOrdered + extras
            
        case .nameAsc:
            timelineData.lines.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .nameDesc:
            timelineData.lines.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
            }
            
        case .tagCountDesc:
            timelineData.lines.sort {
                let c0 = $0.stamps.count
                let c1 = $1.stamps.count
                if c0 != c1 { return c0 > c1 }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .tagCountAsc:
            timelineData.lines.sort {
                let c0 = $0.stamps.count
                let c1 = $1.stamps.count
                if c0 != c1 { return c0 < c1 }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .lastTagChronological:
            timelineData.lines.sort {
                let t0 = lastTagMoment(for: $0)
                let t1 = lastTagMoment(for: $1)
                
                if t0 != t1 { return t0 < t1 }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .lastTagChronologicalReverse:
            timelineData.lines.sort {
                let t0 = lastTagMoment(for: $0)
                let t1 = lastTagMoment(for: $1)
                
                if t0 != t1 { return t0 > t1 }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        // Служебные линии всегда сверху и в фиксированном порядке: рисунки, под ними счётчики.
        let drawings = timelineData.lines.filter { $0.isDrawingsTimeline }
        let clocks = timelineData.lines.filter { $0.isClocksTimeline }
        let rest = timelineData.lines.filter { !$0.isServiceTimeline }
        timelineData.lines = drawings + clocks + rest
    }
    
    /// Proxy for "date added": the finish time of the most recently marked tag in the line.
    private func lastTagMoment(for line: TimelineLine) -> Double {
        line.stamps.map(\.timeFinishSeconds).max() ?? .greatestFiniteMagnitude
    }
    
    private func formatTotalSelectedTagsDuration() -> String {
        let selectedIDs = timelineData.stampsSelectedForSportCut
        let totalSeconds = timelineData.lines
            .flatMap(\.stamps)
            .filter { selectedIDs.contains($0.id) }
            .reduce(0.0) { $0 + max(0.0, $1.duration) }
        
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        let milliseconds = Int((totalSeconds.truncatingRemainder(dividingBy: 1.0)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    inlineControlsBar
                    scrollBlock()
                }
                
                // Unlinked screenshot popups at the top center
                VStack(spacing: 8) {
                    ForEach(timelineData.unlinkedScreenshotPopups) { popup in
                        UnlinkedScreenshotPopupView(popup: popup)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .frame(minWidth: 800, minHeight: 300)
            .onAppear {
                if standardWindowHeight == 0 { standardWindowHeight = geo.size.height }
                currentWindowHeight = geo.size.height
            }
            .onChange(of: geo.size.height) { newHeight in
                if standardWindowHeight == 0 { standardWindowHeight = newHeight }
                currentWindowHeight = newHeight
            }
            .overlay {
                if isExporting {
                    // Прогресс читается ВНУТРИ оверлея — так тики `progress` перерисовывают
                    // только его, а не весь FullControlView с дорожками.
                    ExportProgressOverlay(exportHelper: exportHelper)
                }
            }
            .onAppear {
                parentWindowHeight = geo.size.height
                setupKeyboardShortcuts()
                
                guard notificationObservers.isEmpty else { return }
                
                let editorObserver = NotificationCenter.default.addObserver(forName: .editorModeChanged, object: nil, queue: .main) { notification in
                    if let isActive = notification.object as? Bool {
                        self.isEditorModeActive = isActive
                    }
                }
                
                let screenshotObserver = NotificationCenter.default.addObserver(forName: .screenshotDisplayChanged, object: nil, queue: .main) { notification in
                    if let isActive = notification.object as? Bool {
                        self.isScreenshotDisplayActive = isActive
                    }
                }
                
                let markupModeObserver = NotificationCenter.default.addObserver(forName: .markupModeChanged, object: nil, queue: .main) { notification in
                    if let newMode = notification.object as? MarkupMode {
                        self.markupMode = newMode
                    } else {
                        self.markupMode = MarkupMode.current
                    }
                    // Merging is a standard-mode action; leaving that mode drops the selection.
                    if self.markupMode != .standard {
                        self.timelineData.cancelMergeSelection()
                    }
                }
                
                let hoverObserver = NotificationCenter.default.addObserver(
                    forName: .timelineStampHoverChanged,
                    object: nil,
                    queue: .main
                ) { notification in
                    if let userInfo = notification.userInfo {
                        if let stampInfo = userInfo["stampInfo"] as? AttributedString {
                            hoveredStampInfo = stampInfo
                        } else {
                            hoveredStampInfo = nil
                        }
                    }
                }
                
                notificationObservers = [editorObserver, screenshotObserver, markupModeObserver, hoverObserver]
            }
            .onDisappear {
                if let monitor = keyEventMonitor {
                    NSEvent.removeMonitor(monitor)
                    keyEventMonitor = nil
                }
                notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
                notificationObservers.removeAll()
            }
            .onChange(of: geo.size) { newSize in
                parentWindowHeight = newSize.height
            }
        }
        .sheet(isPresented: $showAddLineSheet) {
            AddLineSheet { newLineName in
                timelineData.addLine(name: newLineName)
            }
        }
        .sheet(isPresented: $showClipSearchSheet) {
            MarkupClipSearchSheet(filter: clipFilter)
        }
        // Оба листа подняты из `TimelineLineView` сюда: на строке они означали по два
        // presentation-хоста на каждую строку. См. TASK-007, 3.5.
        .sheet(item: $stampForCommentEdit) { item in
            StampCommentEditSheet(stamp: item.stamp) { newComment in
                let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
                if let lineIndex = timelineData.lines.firstIndex(where: { $0.id == item.line.id }),
                   let stampIndex = timelineData.lines[lineIndex].stamps.firstIndex(where: { $0.id == item.stamp.id }) {
                    timelineData.lines[lineIndex].stamps[stampIndex].comment = trimmed.isEmpty ? nil : newComment
                    timelineData.updateTimelines()
                }
                stampForCommentEdit = nil
            }
        }
        // Один лист на окно вместо одного на каждый экземпляр `ScreenshotMarkersView`.
        // Костыль с двойным `asyncAfter` («переоткрыть лист, чтобы обновились данные») больше не
        // нужен: `.sheet(item:)` строит содержимое в момент установки item'а, то есть по свежим
        // данным. См. TASK-007, 4.3.
        .sheet(item: $screenshotForTagEditing) { target in
            ScreenshotTagEditorSheet(
                screenshot: target.screenshot,
                onSave: { updatedStampIds in
                    ScreenshotsMetadataManager.shared.updateScreenshotRelatedStamps(
                        screenshotName: target.screenshot.screenshotName,
                        relatedStampIds: updatedStampIds
                    )
                    screenshotForTagEditing = nil
                },
                onCancel: { screenshotForTagEditing = nil }
            )
        }
        .sheet(item: $stampForSessionPick) { item in
            SportCutSessionPickerSheet(
                title: ^String.Titles.viewingToExistingSession,
                sessions: SportCutSessionManager.shared.sessions
            ) { sessionID in
                WindowsManager.shared.appendStampsToSportCutSession(
                    pairs: [(item.line, item.stamp)],
                    sessionID: sessionID
                )
                stampForSessionPick = nil
            } onCancel: {
                stampForSessionPick = nil
            }
        }
        .sheet(item: $stampItemsEditSheetType) { sheetType in
            StampEditSheet(sheetType: sheetType)
        }
        .sheet(isPresented: $showExportModeSheet) {
            ExportModeSelectionSheet(
                onSelect: { mode in
                    isExporting = true
                    exportHelper.performExport(selectedExportType: selectedExportType, mode: mode, withScreenshots: exportWithDrawings, watermarkOptions: exportWatermarkOptions) { error in
                        isExporting = false
                        showExportModeSheet = false
                        if let error {
                            showErrorAlert = true
                            errorMessage = error.localizedDescription
                        }
                    }
                },
                exportWithDrawings: $exportWithDrawings,
                watermarkOptions: $exportWatermarkOptions
            )
        }
        .sheet(isPresented: $showLabelSelectionSheet) {
            LabelSelectionSheetView(
                uniqueLabels: uniqueLabelsFromTimelines(),
                onLabelSelected: { selectedLabel in
                    
                    let availableTags = tagsForLabel(selectedLabel)
                    
                    if !availableTags.isEmpty {
                        showLabelSelectionSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showMultiTagSelection(for: selectedLabel)
                        }
                    } else {
                        selectedExportType = .label(selectedLabel: selectedLabel)
                        showLabelSelectionSheet = false
                        showExportModeSheet = true
                    }
                },
                onSkip: {
                    showLabelSelectionSheet = false
                },
                showMultiSelection: true
            )
            .frame(width: 300, height: 300)
        }
        
        
        
        .sheet(item: $multiTagSelectionItem) { item in
            if let label = item.label {
                let availableTags = tagsForLabel(label)
                
                MultiTagSelectionSheetView(
                    availableTags: availableTags,
                    onDone: { selectedTags in
                        selectedExportType = .labelWithTags(selectedLabel: label, selectedTags: selectedTags)
                        multiTagSelectionItem = nil
                        showExportModeSheet = true
                    },
                    onSkip: {
                        selectedExportType = .label(selectedLabel: label)
                        multiTagSelectionItem = nil
                        showExportModeSheet = true
                    }
                )
                .frame(width: 400, height: 300)
            }
        }
        
        .sheet(item: $multiLabelSelectionItem) { item in
            if let tag = item.tag {
                let availableLabels = labelsForTag(tag)
                
                MultiLabelSelectionSheetView(
                    availableLabels: availableLabels,
                    onDone: { selectedLabels in
                        selectedExportType = .tagWithLabels(selectedTag: tag, selectedLabels: selectedLabels)
                        multiLabelSelectionItem = nil
                        showExportModeSheet = true
                    },
                    onSkip: {
                        selectedExportType = .tag(selectedTag: tag)
                        multiLabelSelectionItem = nil
                        showExportModeSheet = true
                    }
                )
                .frame(width: 400, height: 300)
            }
        }
        
        .sheet(isPresented: $showEventSelectionSheet) {
            EventSelectionSheetView(timeEvents: uniqueEventsFromTimelines()) { selectedEvent in
                selectedExportType = .timeEvent(selectedEvent: selectedEvent)
                showEventSelectionSheet = false
                showExportModeSheet = true
            }
            .frame(width: 300, height: 300)
        }
        
        .sheet(isPresented: $showTagSelectionSheet) {
            TagSelectionSheetView(
                uniqueTags: uniqueTagsFromTimelines(),
                onSelect: { selectedTag in
                    selectedExportType = .tag(selectedTag: selectedTag)
                    showTagSelectionSheet = false
                    showExportModeSheet = true
                },
                onSelectWithLabels: { selectedTag in
                    showTagSelectionSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showMultiLabelSelection(for: selectedTag)
                    }
                }
            )
            .frame(width: 300, height: 300)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsExportMarkupJSONFull)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            exportFullJSON()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsExportMarkupJSONSimple)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            exportSimpleJSON()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsExportMarkupXML)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            exportXML()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsExportMarkupExcel)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            exportExcel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsExportMarkupCSV)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            showCSVExport = true
        }
        .sheet(isPresented: $showCSVExport) {
            CSVExportSheet(
                lines: timelineData.lines,
                resolver: Self.markupCSVResolver(),
                defaultFileName: "markup"
            ) { showCSVExport = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsExportCutsCurrentTimeline)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            guard !isAnyExportSheetShowing else { return }
            openCutsExportCurrentTimeline()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsExportCutsAllTimelines)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            guard !isAnyExportSheetShowing else { return }
            openCutsExportAllTimelines()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsExportCutsDrawings)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            guard !isAnyExportSheetShowing else { return }
            openCutsExportDrawings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsExportCutsByTags)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            guard !isAnyExportSheetShowing else { return }
            showTagSelectionSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsExportCutsByLabels)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            guard !isAnyExportSheetShowing else { return }
            showLabelSelectionSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsExportCutsByEvents)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            guard !isAnyExportSheetShowing else { return }
            showEventSelectionSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsReportSimple)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            showSimpleReportSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsReportAdvanced)) { _ in
            guard ActiveWindowManager.shared.isMarkerWindowActive() else { return }
            showAiReportSheet = true
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text(^String.Titles.alertsErrorTitle),
                message: Text(errorMessage),
                dismissButton: .default(Text(^String.Titles.alertsOkTitle))
            )
        }
    }
    
    struct StampEditSheet: View {
        @ObservedObject var timelineData = TimelineDataManager.shared
        let sheetType: StampEditSheetType
        
        var body: some View {
            if let lineIDString = UserDefaults.standard.string(forKey: "editingStampLineID"),
               let stampIDString = UserDefaults.standard.string(forKey: "editingStampID"),
               let lineID = UUID(uuidString: lineIDString),
               let stampID = UUID(uuidString: stampIDString) {
                
                if let lineIndex = timelineData.lines.firstIndex(where: { $0.id == lineID }),
                   let stampIndex = timelineData.lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) {
                    
                    let currentIds: [String] = switch sheetType {
                    case .lables:
                        timelineData.lines[lineIndex].stamps[stampIndex].labelIDs
                    case .timeEvents:
                        timelineData.lines[lineIndex].stamps[stampIndex].timeEvents
                    }
                    let stampName = timelineData.lines[lineIndex].stamps[stampIndex].label
                    let tagId = timelineData.lines[lineIndex].stamps[stampIndex].idTag
                    
                    if let tag = TagLibraryManager.shared.findTagById(tagId) {
                        StampItemsSelectionSheet(
                            sheetType: sheetType,
                            stampName: stampName,
                            initialIds: currentIds,
                            tag: tag,
                            tagLibrary: TagLibraryManager.shared,
                            isDop: true,
                            onDone: { newIds in
                                switch sheetType {
                                case .lables:
                                    let tagLibrary = TagLibraryManager.shared
                                    let fullLabels = newIds.compactMap { labelID -> FullLabelWithGroup? in
                                        guard let label = tagLibrary.findLabelById(labelID) else { return nil }
                                        let groupId = tagLibrary.allLabelGroups.first(where: { $0.lables.contains(labelID) })?.id ?? ""
                                        return FullLabelWithGroup(id: label.id, name: label.name, description: label.description, lableGroupId: groupId)
                                    }
                                    timelineData.updateStampLabels(
                                        lineID: lineID,
                                        stampID: stampID,
                                        newLabels: fullLabels
                                    )
                                case .timeEvents:
                                    timelineData.updateStampTimeEvents(
                                        lineID: lineID,
                                        stampID: stampID,
                                        newEvents: newIds
                                    )
                                }
                            }, onCancel: { return }
                        )
                    } else {
                        Text(^String.Titles.fullControlExportErrorStampNotFound)
                    }
                } else {
                    Text(^String.Titles.fullControlExportErrorStampNotFound)
                }
            } else {
                Text(^String.Titles.fullControlExportErrorStampNotFound)
            }
        }
    }
    
    
    func showMultiTagSelection(for label: Label) {
        multiTagSelectionItem = MultiSelectionItem(label: label)
    }

        
    func showMultiLabelSelection(for tag: Tag) {
        multiLabelSelectionItem = MultiSelectionItem(tag: tag)
    }

    func uniqueEventsFromTimelines() -> [TimeEvent] {
        let eventIDs = Set(timelineData.lines.flatMap { line in
            line.stamps.flatMap { stamp in
                stamp.timeEvents
            }
        })
        
        return TagLibraryManager.shared.allTimeEvents.filter { event in
            eventIDs.contains(event.id)
        }
    }
    
    func transformToFullTimelineLines() -> [FullTimelineLine] {
        let tagLibrary = TagLibraryManager.shared
        
        return TimelineDataManager.shared.lines.map { line in
            let fullStamps = line.stamps.map { stamp -> FullTimelineStamp in
                let fullTags: [FullTagWithGroup] = stamp.idTags.compactMap { tagID in
                    guard let tag = tagLibrary.findTagById(tagID) else { return nil }
                    var tagGroup: TagGroupInfo? = nil
                    for group in tagLibrary.allTagGroups {
                        if group.tags.contains(tagID) {
                            tagGroup = TagGroupInfo(id: group.id, name: group.name)
                            break
                        }
                    }
                    return FullTagWithGroup(
                        id: tag.id,
                        primaryID: tag.primaryID,
                        name: tag.name,
                        description: tag.description,
                        color: tag.color,
                        defaultTimeBefore: tag.defaultTimeBefore,
                        defaultTimeAfter: tag.defaultTimeAfter,
                        collection: tag.collection ?? "",
                        hotkey: tag.hotkey,
                        labelHotkeys: tag.labelHotkeys,
                        group: tagGroup
                    )
                }
                
                let fullTimeEvents = stamp.timeEvents.compactMap { eventID in
                    tagLibrary.allTimeEvents.first(where: { $0.id == eventID })
                }
                
                return FullTimelineStamp(
                    id: stamp.id,
                    timeStart: stamp.timeStartString,
                    timeFinish: stamp.timeFinishString,
                    tags: fullTags,
                    labels: stamp.labels,
                    timeEvents: fullTimeEvents,
                    position: stamp.position
                )
            }
            
            return FullTimelineLine(id: line.id, name: line.name, stamps: fullStamps)
        }
    }
    
    // MARK: - Export pickers (tag/label lists)
    //
    // These build the tag/label choices for "export cuts by tag/label". They resolve
    // each id against the global pool but fall back to the data embedded in the stamp
    // itself (`stamp.label`/`stamp.colorHex` for tags, `stamp.labels` for labels), so
    // markup imported from other tools — whose collection isn't installed locally — is
    // still selectable. Purely additive: pooled entries win, we only fill the gaps.

    /// Resolves a tag id from the pool, or synthesizes one from the stamp it appears on.
    private func resolvedTag(id tagId: String, from stamp: TimelineStamp) -> Tag {
        if let pooled = TagLibraryManager.shared.findTagById(tagId) { return pooled }
        return Tag(
            id: tagId,
            primaryID: stamp.primaryID,
            name: stamp.label,
            description: "",
            color: stamp.colorHex,
            defaultTimeBefore: 0,
            defaultTimeAfter: 0,
            collection: nil,
            lablesGroup: [],
            hotkey: nil,
            labelHotkeys: nil,
            mapEnabled: false,
            isInterval: true
        )
    }

    /// Resolves a label from the pool, or synthesizes it from the stamp's embedded label.
    private func resolvedLabel(_ item: FullLabelWithGroup) -> Label? {
        if let pooled = TagLibraryManager.shared.findLabelById(item.id) { return pooled }
        return item.name.isEmpty ? nil : Label(id: item.id, name: item.name, description: item.description)
    }

    func uniqueLabelsFromTimelines() -> [Label] {
        var result: [Label] = []
        var seen = Set<String>()
        for line in timelineData.lines {
            for stamp in line.stamps {
                for item in stamp.labels where seen.insert(item.id).inserted {
                    if let label = resolvedLabel(item) { result.append(label) }
                }
            }
        }
        return result
    }

    func labelsForTag(_ tag: Tag) -> [Label] {
        var result: [Label] = []
        var seen = Set<String>()
        for line in timelineData.lines {
            for stamp in line.stamps where stamp.idTags.contains(tag.id) {
                for item in stamp.labels where seen.insert(item.id).inserted {
                    if let label = resolvedLabel(item) { result.append(label) }
                }
            }
        }
        return result
    }

    func tagsForLabel(_ label: Label) -> [Tag] {
        var result: [Tag] = []
        var seen = Set<String>()
        for line in timelineData.lines {
            for stamp in line.stamps where stamp.labelIDs.contains(label.id) {
                // Process the main tag first so its name (stamp.label) matches when synthesized.
                let orderedIds = [stamp.idTag] + stamp.idTags.filter { $0 != stamp.idTag }
                for tagId in orderedIds where !tagId.isEmpty && seen.insert(tagId).inserted {
                    result.append(resolvedTag(id: tagId, from: stamp))
                }
            }
        }
        return result
    }

    func uniqueTagsFromTimelines() -> [Tag] {
        var result: [Tag] = []
        var seen = Set<String>()
        for line in timelineData.lines {
            for stamp in line.stamps {
                let orderedIds = [stamp.idTag] + stamp.idTags.filter { $0 != stamp.idTag }
                for tagId in orderedIds where !tagId.isEmpty && seen.insert(tagId).inserted {
                    result.append(resolvedTag(id: tagId, from: stamp))
                }
            }
        }
        return result
    }
    
}

// MARK: - Export progress overlay

/// Оверлей прогресса экспорта.
///
/// Существует отдельной вьюхой ровно затем, чтобы подписка на `ExportHelper` жила здесь.
/// Если держать хелпер как `@StateObject` в `FullControlView`, каждый тик `progress`
/// пересчитывает body со всеми дорожками таймлайна — на больших проектах это подвешивало
/// главный поток. Общее правило: частообновляемый `ObservableObject` не должен наблюдаться
/// вьюхой с тяжёлым списком — изолируй чтение в маленького ребёнка (см. TASK-007).
struct ExportProgressOverlay: View {

    @ObservedObject var exportHelper: ExportHelper

    var body: some View {
        VStack(spacing: 16) {
            CircularPercentProgressView(progress: Double(exportHelper.progress))
                .frame(width: 80, height: 80)
            Button(^String.Titles.cancelButtonTitle) {
                exportHelper.cancelExport()
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .padding(30)
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .shadow(radius: 20)
        .transition(.opacity)
    }
}

struct LabelSelectionSheetView: View {
    let uniqueLabels: [Label]
    let onLabelSelected: (Label) -> Void
    let onSkip: () -> Void
    let showMultiSelection: Bool
    
    var body: some View {
        VStack {
            Text(^String.Titles.selectLabelForExport)
                .font(.headline)
                .padding()
            
            List(uniqueLabels, id: \.id) { label in
                if showMultiSelection {
                    Button(action: {
                        onLabelSelected(label)
                    }) {
                        HStack {
                            Text(label.name)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                } else {
                    Button(action: {
                        onLabelSelected(label)
                    }) {
                        Text(label.name)
                    }
                }
            }
            
            Button(^String.Titles.skip) {
                onSkip()
            }
            .padding()
        }
        .frame(width: 300, height: 300)
    }
}

struct MultiTagSelectionSheetView: View {
    let availableTags: [Tag]
    @State private var selectedTags: Set<String> = []
    let onDone: ([Tag]) -> Void
    let onSkip: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            Text(^String.Titles.selectTagsForExport)
                .font(.headline)
                .padding()
            
            if availableTags.isEmpty {
                Text(^String.Titles.noAvailableTags)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List(availableTags, id: \.id) { tag in
                    HStack {
                        Image(systemName: selectedTags.contains(tag.id) ? "checkmark.square.fill" : "square")
                            .foregroundColor(selectedTags.contains(tag.id) ? .blue : .secondary)
                        Text(tag.name)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedTags.contains(tag.id) {
                            selectedTags.remove(tag.id)
                        } else {
                            selectedTags.insert(tag.id)
                        }
                    }
                }
            }
            
            HStack {
                Button(^String.Titles.skip) {
                    onSkip()
                }
                
                Spacer()
                
                Button(^String.Titles.done) {
                    let selected = availableTags.filter { selectedTags.contains($0.id) }
                    onDone(selected)
                }
                .disabled(selectedTags.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
        .onAppear {
        }
    }
}

struct MultiLabelSelectionSheetView: View {
    let availableLabels: [Label]
    @State private var selectedLabels: Set<String> = []
    let onDone: ([Label]) -> Void
    let onSkip: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            Text(^String.Titles.selectLabelsForExport)
                .font(.headline)
                .padding()
            
            if availableLabels.isEmpty {
                Text(^String.Titles.noAvailableLabels)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List(availableLabels, id: \.id) { label in
                    HStack {
                        Image(systemName: selectedLabels.contains(label.id) ? "checkmark.square.fill" : "square")
                            .foregroundColor(selectedLabels.contains(label.id) ? .blue : .secondary)
                        Text(label.name)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedLabels.contains(label.id) {
                            selectedLabels.remove(label.id)
                        } else {
                            selectedLabels.insert(label.id)
                        }
                    }
                }
            }
            
            HStack {
                Button(^String.Titles.skip) {
                    onSkip()
                }
                
                Spacer()
                
                Button(^String.Titles.done) {
                    let selected = availableLabels.filter { selectedLabels.contains($0.id) }
                    onDone(selected)
                }
                .disabled(selectedLabels.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
        .onAppear {
            print("\(availableLabels.map { $0.name })")
        }
    }
}

struct TimelineDropDelegate: DropDelegate {
    let currentLine: TimelineLine
    let timelineData: TimelineDataManager
    /// Id перетаскиваемого таймлайна (устанавливается в `.onDrag`).
    @Binding var draggingLineID: UUID?

    /// Разрешаем «перемещение» — иначе dropEntered может не срабатывать и не будет живого reorder.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    /// Живой reorder: как только курсор с перетаскиваемым таймлайном заходит на другой — меняем порядок.
    /// Это работает и когда дроп приходится «между» элементами, а не строго на объект.
    func dropEntered(info: DropInfo) {
        guard let dragged = draggingLineID, dragged != currentLine.id else { return }
        reorderTimelines(draggedID: dragged, targetID: currentLine.id)
    }

    func performDrop(info: DropInfo) -> Bool {
        // Порядок уже изменён вживую в dropEntered — здесь фиксируем и сохраняем.
        draggingLineID = nil
        timelineData.updateTimelines()
        return true
    }

    func dropExited(info: DropInfo) {}

    private func reorderTimelines(draggedID: UUID, targetID: UUID) {
        guard let draggedIndex = timelineData.lines.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = timelineData.lines.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let draggedLine = timelineData.lines.remove(at: draggedIndex)
        // При движении вниз обычно вставляем перед целью, но если цель — последняя строка,
        // разрешаем встать в самый низ (иначе последнюю позицию не получить).
        let newTargetIndex: Int
        if draggedIndex < targetIndex {
            newTargetIndex = (targetIndex == timelineData.lines.count) ? targetIndex : targetIndex - 1
        } else {
            newTargetIndex = targetIndex
        }
        timelineData.lines.insert(draggedLine, at: newTargetIndex)
    }
}

struct CompactButtonStyle: ButtonStyle {
    let icon: String
    let color: Color
    let showText: Bool
    let text: String
    
    init(icon: String, color: Color, showText: Bool = false, text: String = ^String.Titles.report) {
        self.icon = icon
        self.color = color
        self.showText = showText
        self.text = text
    }
    
    func makeBody(configuration: Configuration) -> some View {
        if showText {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(text)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        } else {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .padding(6)
                .background(color.opacity(0.1))
                .foregroundColor(color)
                .cornerRadius(6)
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

struct ExportButtonStyle: ButtonStyle {
    let icon: String
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
            configuration.label
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .cornerRadius(8)
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ZoomButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Image(systemName: "minus.magnifyingglass")
            .font(.system(size: 14, weight: .medium))
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .foregroundColor(.primary)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct TimelineMouseTracker: NSViewRepresentable {
    let duration: Double
    let gridWidth: CGFloat
    let lines: [TimelineLine]
    let tagLibrary: TagLibraryManager
    let onStampUpdate: (AttributedString?, CGPoint?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.duration = duration
        view.gridWidth = gridWidth
        view.lines = lines
        view.tagLibrary = tagLibrary
        view.onStampUpdate = onStampUpdate
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let trackingView = nsView as? TrackingView {
            trackingView.duration = duration
            trackingView.gridWidth = gridWidth
            trackingView.lines = lines
            trackingView.tagLibrary = tagLibrary
            trackingView.onStampUpdate = onStampUpdate
        }
    }
    
    class TrackingView: NSView {
        var duration: Double = 0
        var gridWidth: CGFloat = 0
        var lines: [TimelineLine] = []
        var tagLibrary: TagLibraryManager?
        var onStampUpdate: ((AttributedString?, CGPoint?) -> Void)?
        private var trackingArea: NSTrackingArea?
        private var lastUpdateTime: TimeInterval = 0
        private let updateInterval: TimeInterval = 0.1
        private let lineHeight: CGFloat = 30
        private let headerHeight: CGFloat = 30
        
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            
            if let trackingArea = trackingArea {
                removeTrackingArea(trackingArea)
            }
            
            // .activeAlways (не .activeInKeyWindow): наведение на штамп должно показывать
            // строчку с инфой сразу, даже если окно таймлайнов ещё не активно — иначе
            // пользователю приходится сначала кликом активировать окно, потом наводить.
            // Клик по штампу и так проходит сразу (FirstMouseHostingController), наведение
            // должно вести себя так же.
            let options: NSTrackingArea.Options = [
                .activeAlways,
                .mouseMoved,
                .inVisibleRect
            ]
            
            trackingArea = NSTrackingArea(
                rect: bounds,
                options: options,
                owner: self,
                userInfo: nil
            )
            
            if let trackingArea = trackingArea {
                addTrackingArea(trackingArea)
            }
        }
        
        override func mouseMoved(with event: NSEvent) {
            let currentTime = event.timestamp
            if currentTime - lastUpdateTime < updateInterval {
                return
            }
            lastUpdateTime = currentTime
            
            let locationInView = convert(event.locationInWindow, from: nil)
            let relativeX = locationInView.x
            let relativeY = locationInView.y
            
            guard duration > 0 && gridWidth > 0 else {
                onStampUpdate?(nil, nil)
                return
            }
            
            
            let yFromTop = bounds.height - relativeY
            
            guard yFromTop > headerHeight else {
                onStampUpdate?(nil, nil)
                return
            }
            
            let lineIndex = Int((yFromTop - headerHeight) / lineHeight)
            
            guard lineIndex >= 0 && lineIndex < lines.count else {
                onStampUpdate?(nil, nil)
                return
            }
            
            let line = lines[lineIndex]
            
            let clampedX = max(0.0, min(relativeX, gridWidth))
            let time = (clampedX / gridWidth) * duration
            let clampedTime = max(0.0, min(time, duration))
            
            let foundStamp = line.stamps.last { stamp in
                let startRatio = stamp.timeStartSeconds / duration
                let durationRatio = (stamp.timeFinishSeconds - stamp.timeStartSeconds) / duration
                let stampPixelX = startRatio * gridWidth
                let stampPixelWidth = max(durationRatio * gridWidth, 10)
                return clampedX >= stampPixelX && clampedX <= stampPixelX + stampPixelWidth
            }
            
            if let stamp = foundStamp, let tagLibrary = tagLibrary {
                let tag = tagLibrary.findTagById(stamp.idTag)
                let tagName = tag?.name ?? stamp.label
                let currentTagOrdinal = stamp.chronologicalOrdinalAmongSameTag(in: lines)

                let sep = " • "
                var info = AttributedString()
                func add(_ text: String, bold: Bool = false) {
                    var piece = AttributedString(text)
                    if bold { piece.font = .system(size: 13, weight: .semibold) }
                    info += piece
                }

                // «Порядковый номер. Тег»
                add("\(currentTagOrdinal). \(tagName)")

                // Общие события через запятую
                let eventNames = stamp.timeEvents.compactMap { eventID in
                    tagLibrary.findTimeEventById(eventID)?.name
                }
                if !eventNames.isEmpty {
                    add(sep + eventNames.joined(separator: ", "))
                }

                // Лейблы, сгруппированные по группам. Имя группы — жирным. Префер пула
                // (учитывает переименования), иначе имя, вшитое в штамп (для импортов).
                // Если группа неизвестна (нет в пуле) — показываем лейблы без префикса.
                var knownGroups: [(name: String, labels: [String])] = []
                var indexByGroup: [String: Int] = [:]
                var ungrouped: [String] = []
                for item in stamp.labels {
                    let labelName: String
                    if let pooled = tagLibrary.findLabelById(item.id)?.name, !pooled.isEmpty {
                        labelName = pooled
                    } else if !item.name.isEmpty {
                        labelName = item.name
                    } else {
                        continue
                    }
                    let groupName = tagLibrary.allLabelGroups.first(where: { $0.lables.contains(item.id) })?.name
                        ?? tagLibrary.allLabelGroups.first(where: { $0.id == item.lableGroupId })?.name
                    if let groupName, !groupName.isEmpty {
                        if let idx = indexByGroup[groupName] {
                            knownGroups[idx].labels.append(labelName)
                        } else {
                            indexByGroup[groupName] = knownGroups.count
                            knownGroups.append((name: groupName, labels: [labelName]))
                        }
                    } else {
                        ungrouped.append(labelName)
                    }
                }
                for group in knownGroups {
                    add(sep)
                    add("\(group.name):", bold: true)
                    add(" " + group.labels.joined(separator: ", "))
                }
                if !ungrouped.isEmpty {
                    add(sep + ungrouped.joined(separator: ", "))
                }

                // Длина клипа
                add(sep + formatTimeStringCompact(stamp.duration))

                // Комментарий (если есть)
                if let comment = stamp.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !comment.isEmpty {
                    add(sep + comment)
                }

                onStampUpdate?(info, nil)
            } else {
                onStampUpdate?(nil, nil)
            }
        }
        
        override func mouseExited(with event: NSEvent) {
            onStampUpdate?(nil, nil)
        }
        
        private func formatTimeString(_ seconds: Double) -> String {
            let minutes = Int(seconds) / 60
            let secs = Int(seconds) % 60
            let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1.0)) * 1000)
            return String(format: "%02d:%02d.%03d", minutes, secs, milliseconds)
        }
        
        private func formatTimeStringCompact(_ seconds: Double) -> String {
            let minutes = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}

extension TimelineMouseTracker: Equatable {
    static func == (lhs: TimelineMouseTracker, rhs: TimelineMouseTracker) -> Bool {
        lhs.duration == rhs.duration &&
        lhs.gridWidth == rhs.gridWidth &&
        lhs.lines == rhs.lines
    }
}

// MARK: - Screenshot Markers View

struct ScreenshotMarkersView: View {
    /// Что рисуем: голову-карандаш (кликабельна, живёт в закреплённой шапке) и/или стебель
    /// (синяя полоска на всю высоту дорожек, живёт в скролле — как плейхед).
    enum RenderPart { case full, headsOnly, stemsOnly }

    let duration: Double
    let gridWidth: CGFloat
    let totalHeight: CGFloat
    /// На сколько поднять «голову» метки (синий карандаш) над линейкой, чтобы её
    /// не перекрывал плейхед. Стебель метки при этом остаётся на своём месте.
    var headLift: CGFloat = 0
    /// Голова и стебель разнесены по разным контейнерам: голова — в закреплённой шапке
    /// (иначе уезжает при вертикальном скролле), стебель — в скролле (иначе обрезается шапкой).
    var part: RenderPart = .full

    @ObservedObject var screenshotsManager = ScreenshotsMetadataManager.shared
    /// Без `@ObservedObject`: плеер здесь нужен только чтобы вызвать `seek`/`pause` по нажатию.
    /// Подписка тянула эту вьюху в перерисовку на каждое изменение плеера, а вместе с ней —
    /// проверку наличия файлов на диске. См. TASK-007.
    private let videoManager = VideoPlayerManager.shared
    /// Эти двое остаются наблюдаемыми: `timelineData` читается в контенте контекстного меню
    /// (`getAvailableStampsForScreenshot`), `tagLibrary` — в поповере со связанными тегами.
    @ObservedObject var timelineData = TimelineDataManager.shared
    @ObservedObject var tagLibrary = TagLibraryManager.shared

    @State private var hoveredScreenshot: String? = nil
    /// Лист редактирования привязанных тегов живёт в окне, а не здесь: эта вьюха создаётся
    /// ДВАЖДЫ (стебли в скролле + головы в закреплённой шапке), то есть было два хоста листа
    /// на один лист. См. TASK-007, 4.3.
    var onEditRelatedTags: (ScreenshotMetadata) -> Void = { _ in }
    
    private func getCurrentFile() -> FilesFile? {
        guard let videoId = timelineData.currentVideoId else {
            return nil
        }
        return VideoFilesManager.shared.files.first(where: { $0.videoData.id == videoId })
    }
    
    /// Папка скриншотов для текущей сессии: для live — Documents/Screenshots/currentVideoId, иначе из filesFile.
    private func getCurrentScreenshotsFolder() -> URL? {
        if WindowsManager.shared.isLiveSession {
            let videoId = WindowsManager.shared.currentVideoId
            guard !videoId.isEmpty,
                  let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            return documentsDir.appendingPathComponent("Screenshots").appendingPathComponent(videoId)
        }
        return getCurrentFile()?.screenshotsFolder
    }
    
    /// Id текущего видео (для live — currentVideoId, иначе из filesFile).
    private func getCurrentVideoId() -> String? {
        if WindowsManager.shared.isLiveSession {
            let id = WindowsManager.shared.currentVideoId
            return id.isEmpty ? nil : id
        }
        return getCurrentFile()?.videoData.id
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(screenshotsManager.screenshots, id: \.screenshotName) { screenshot in
                // Проверка по кэшу менеджера, а НЕ обращение к диску: раньше здесь на каждый
                // пересчёт body вызывался `FileManager.fileExists` на каждый скриншот.
                if screenshotsManager.hasImageFile(for: screenshot) {
                    screenshotMarker(for: screenshot)
                }
            }
        }
    }
    
    private func screenshotMarker(for screenshot: ScreenshotMetadata) -> some View {
        // Клампим влево: у начала длинного видео маркер (кружок) иначе уезжает в отрицательную
        // координату и прячется под левым столбцом с названиями таймлайнов — по нему нельзя кликнуть.
        let rawX = duration > 0 ? (screenshot.videoTime / duration) * gridWidth - 7 : 0
        let xPosition = max(rawX, 1)
        let hasRelatedTags = !screenshot.relatedStampIds.isEmpty
        
        // Стебель метки идёт по дорожкам, а «голова» (карандаш) поднята на headLift
        // в верхнюю полосу — там её не перекрывает плейхед и по ней можно кликнуть.
        return ZStack(alignment: .top) {
            if part != .headsOnly {
                Rectangle()
                    .fill(hasRelatedTags ? Color.blue.opacity(0.5) : Color.gray.opacity(0.5))
                    .frame(width: 2, height: totalHeight)
            }

            if part != .stemsOnly {
            Button(action: {
                videoManager.seek(to: screenshot.videoTime)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    videoManager.player?.pause()
                }
            }) {
                Image(systemName: hasRelatedTags ? "pencil.circle.fill" : "pencil.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(hasRelatedTags ? Color.blue.opacity(0.9) : Color.gray.opacity(0.7))
                    .background(
                        Circle()
                            .fill(Color(NSColor.windowBackgroundColor))
                            .padding(1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .help(String.Titles.fullControlScreenshotGoToHelp.format(formatTime(screenshot.videoTime)))
            .contextMenu {
                Button(^String.Titles.fullControlEdit) {
                    openScreenshotInEditor(screenshot)
                }

                let availableStamps = getAvailableStampsForScreenshot(screenshot)
                if !availableStamps.isEmpty {
                    Button(^String.Titles.fullControlEditBoundTags) {
                        onEditRelatedTags(screenshot)
                    }
                }

                Button(^String.Titles.deleteButtonTitle) {
                    deleteScreenshot(screenshot)
                }
            }
            .popover(isPresented: Binding(
                get: { hoveredScreenshot == screenshot.screenshotName },
                set: { if !$0 { hoveredScreenshot = nil } }
            ), arrowEdge: .top) {
                screenshotTagsPopover(for: screenshot)
            }
            .onHover { isHovering in
                if isHovering && hasRelatedTags {
                    hoveredScreenshot = screenshot.screenshotName
                } else {
                    hoveredScreenshot = nil
                }
            }
            .offset(y: -headLift)
            }
        }
        // Голова (карандаш) центрируется на позиции времени за счёт `-7` в rawX. Стебель рисуется
        // отдельным View шириной 2pt, поэтому без сдвига он оказывается на половину «шарика» левее
        // головы — компенсируем на +7 (половина головы), чтобы полоска шла ровно под центром головы.
        .offset(x: xPosition - 1 + (part == .stemsOnly ? 7 : 0))
    }
    
    private func screenshotTagsPopover(for screenshot: ScreenshotMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(^String.Titles.relatedTags)
                .font(.headline)
                .padding(.bottom, 4)
            
            ForEach(getRelatedStamps(for: screenshot), id: \.id) { stamp in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: stamp.colorHex) ?? .gray)
                        .frame(width: 8, height: 8)
                    
                    if let tag = tagLibrary.findTagById(stamp.idTag) {
                        Text(tag.name)
                            .font(.system(size: 12))
                    } else {
                        Text(stamp.label)
                            .font(.system(size: 12))
                    }
                    
                    Spacer()
                    
                    Text("\(formatTime(stamp.timeStartSeconds)) - \(formatTime(stamp.timeFinishSeconds))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 200, maxWidth: 300)
    }
    
    private func getRelatedStamps(for screenshot: ScreenshotMetadata) -> [TimelineStamp] {
        var stamps: [TimelineStamp] = []
        
        for line in timelineData.lines {
            for stamp in line.stamps {
                if screenshot.relatedStampIds.contains(stamp.id) {
                    stamps.append(stamp)
                }
            }
        }
        
        return stamps
    }
    
    private func getAvailableStampsForScreenshot(_ screenshot: ScreenshotMetadata) -> [(line: TimelineLine, stamp: TimelineStamp)] {
        var availableStamps: [(line: TimelineLine, stamp: TimelineStamp)] = []
        
        for line in timelineData.lines {
            if line.isServiceTimeline { continue }
            
            for stamp in line.stamps {
                let screenshotTime = screenshot.videoTime
                if screenshotTime >= stamp.timeStartSeconds && screenshotTime <= stamp.timeFinishSeconds {
                    availableStamps.append((line: line, stamp: stamp))
                }
            }
        }
        
        return availableStamps
    }
    
    private func deleteScreenshot(_ screenshot: ScreenshotMetadata) {
        guard let screenshotsFolder = getCurrentScreenshotsFolder() else {
            print("FullControlView: screenshots folder not found for deletion")
            return
        }
        let imageFileName = screenshot.screenshotName.hasSuffix(".png") ? screenshot.screenshotName : "\(screenshot.screenshotName).png"
        let imageURL = screenshotsFolder.appendingPathComponent(imageFileName)
        let jsonURL = screenshotsFolder.appendingPathComponent("\(screenshot.screenshotName).json")
        
        do {
            if FileManager.default.fileExists(atPath: imageURL.path) {
                try FileManager.default.removeItem(at: imageURL)
                print("FullControlView: Removed image file: \(imageFileName)")
            }
            
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                try FileManager.default.removeItem(at: jsonURL)
                print("FullControlView: Removed metadata file: \(screenshot.screenshotName).json")
            }
        } catch {
            print("FullControlView: Error deleting screenshot files: \(error.localizedDescription)")
            return
        }
        
        deleteScreenshotStampFromTimeline(screenshotName: screenshot.screenshotName)
        
        screenshotsManager.removeScreenshot(screenshotName: screenshot.screenshotName)
    }
    
    /// Seeks video to screenshot time and opens editor with state restored from metadata (all objects editable again).
    private func openScreenshotInEditor(_ screenshot: ScreenshotMetadata) {
        guard let screenshotsFolder = getCurrentScreenshotsFolder(),
              let videoId = getCurrentVideoId() else {
            print("FullControlView: screenshots folder or videoId not found for opening editor")
            return
        }
        let payload = OpenEditorForScreenshotPayload(
            screenshot: screenshot,
            screenshotsFolder: screenshotsFolder,
            videoId: videoId
        )
        NotificationCenter.default.post(name: .openEditorForScreenshot, object: payload)
    }
    
    private func deleteScreenshotStampFromTimeline(screenshotName: String) {
        guard let screenshotLine = timelineData.lines.first(where: { $0.isDrawingsTimeline }) else {
            print("FullControlView: Drawings timeline not found")
            return
        }
        
        guard let screenshotsFolder = getCurrentScreenshotsFolder() else {
            print("FullControlView: screenshots folder not found for stamp check")
            return
        }
        let imageFileName = screenshotName.hasSuffix(".png") ? screenshotName : "\(screenshotName).png"
        let imageURL = screenshotsFolder.appendingPathComponent(imageFileName)
        
        if !FileManager.default.fileExists(atPath: imageURL.path) {
            if let stamp = screenshotLine.stamps.first(where: { stamp in
                stamp.label == screenshotName || stamp.label.contains(screenshotName)
            }) {
                let stampID = stamp.id
                let stampLabel = stamp.label
                timelineData.removeStamp(lineID: screenshotLine.id, stampID: stampID)
                print("FullControlView: Removed stamp '\(stampLabel)' from drawings timeline (file does not exist)")
            } else {
                print("FullControlView: Stamp named '\(screenshotName)' not found on drawings timeline")
            }
        } else {
            print("FullControlView: Screenshot file '\(screenshotName)' exists, stamp not removed")
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Screenshot Tag Editor Sheet

struct ScreenshotTagEditorSheet: View {
    let screenshot: ScreenshotMetadata
    let onSave: ([UUID]) -> Void
    let onCancel: () -> Void
    
    @State private var selectedStampIds: Set<UUID>
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    
    init(screenshot: ScreenshotMetadata, 
         onSave: @escaping ([UUID]) -> Void,
         onCancel: @escaping () -> Void) {
        self.screenshot = screenshot
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedStampIds = State(initialValue: Set(screenshot.relatedStampIds))
    }
    
    private var availableStamps: [(line: TimelineLine, stamp: TimelineStamp)] {
        var stamps: [(line: TimelineLine, stamp: TimelineStamp)] = []
        
        for line in timelineData.lines {
            if line.isServiceTimeline { continue }
            
            for stamp in line.stamps {
                // Проверяем пересечение времени
                let screenshotTime = screenshot.videoTime
                if screenshotTime >= stamp.timeStartSeconds && screenshotTime <= stamp.timeFinishSeconds {
                    stamps.append((line: line, stamp: stamp))
                }
            }
        }
        
        return stamps
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text(^String.Titles.fullControlEditBoundTagsTitle)
                .font(.headline)
                .padding(.top)
            
            Text(String.Titles.fullControlScreenshotLabel.format(formatTime(screenshot.videoTime)))
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
            if availableStamps.isEmpty {
                Text(^String.Titles.fullControlNoTagsForBinding)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(availableStamps, id: \.stamp.id) { item in
                            let stamp = item.stamp
                            let line = item.line
                            let isSelected = selectedStampIds.contains(stamp.id)
                            
                            HStack(spacing: 12) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isSelected ? .blue : .secondary)
                                    .font(.system(size: 16))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color(hex: stamp.colorHex) ?? .gray)
                                            .frame(width: 8, height: 8)
                                        
                                        if let tag = tagLibrary.findTagById(stamp.idTag) {
                                            Text(tag.name)
                                                .font(.system(size: 13, weight: .medium))
                                        } else {
                                            Text(stamp.label)
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                    }
                                    
                                    Text(String.Titles.fullControlTimelineLabel.format(line.name))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    
                                    Text("\(formatTime(stamp.timeStartSeconds)) - \(formatTime(stamp.timeFinishSeconds))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelected {
                                    selectedStampIds.remove(stamp.id)
                                } else {
                                    selectedStampIds.insert(stamp.id)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                Button(^String.Titles.collectionsButtonCancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button(^String.Titles.saveButtonTitle) {
                    onSave(Array(selectedStampIds))
                }
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 450, height: 250)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Unlinked Screenshot Popup View

struct UnlinkedScreenshotPopupView: View {
    let popup: UnlinkedScreenshotPopup
    @ObservedObject var timelineData = TimelineDataManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 18))
            
            Text(popup.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    timelineData.dismissPopup(id: popup.id)
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.5), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .frame(maxWidth: 600)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                timelineData.dismissPopup(id: popup.id)
            }
        }
    }
}

public extension ToolbarContent {

    func disableGlassEffect() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            return sharedBackgroundVisibility(.hidden)
        } else {
            return self
        }
    }
}

