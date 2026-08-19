//
//  TimelineDataManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers
import UserNotifications

class TimelineDataManager: ObservableObject {
    
    static let shared = TimelineDataManager()
    @Published var lines: [TimelineLine] = [] {
        didSet {
            // Удалили все таймлайны → чистим историю разметки тегов.
            if lines.isEmpty && !oldValue.isEmpty {
                VideoMarkupActivityBanner.shared.clearTagMarkupHistoryForNewVideoSession()
            }
        }
    }
    @Published var selectedLineID: UUID? = nil
    @Published var selectedStampID: UUID? = nil
    /// Показывать ли линии счётчиков (у каждого секундомера/таймера своя). По умолчанию показаны —
    /// работа счётчиков такая же разметка, как интервальные теги; ⌘⌃0 скрывает их все разом,
    /// когда нужно видеть только теги.
    @Published var showClocksTimeline: Bool = true

    /// Линии для ОТРИСОВКИ. Данные (сохранение, экспорт, пересмотр) всегда работают с `lines`,
    /// скрывается только показ.
    var visibleLines: [TimelineLine] {
        showClocksTimeline ? lines : lines.filter { !$0.isClocksTimeline }
    }

    /// ⌘⌃0 — показать/скрыть ВСЕ линии счётчиков разом.
    func toggleClocksTimelineVisibility() {
        showClocksTimeline.toggle()
        updateTimelines()
    }
    /// Последний добавленный на таймлайн штамп (id) — независимо от линии/режима разметки.
    /// Используется для привязки лейблов простым ЛКМ к «последнему по времени добавления» тегу.
    private(set) var lastAddedStampID: UUID? = nil
    /// Stamps toggled with ⌘-click for «open in SportCut» bulk action.
    @Published var stampsSelectedForSportCut: Set<UUID> = []
    @Published var unlinkedScreenshotPopups: [UnlinkedScreenshotPopup] = []
    /// «Объединить таймлайны»: активен режим выбора линий для объединения.
    @Published var isMergeSelectionActive: Bool = false
    /// Линии, выбранные для объединения (по нажатию на название).
    @Published var mergeSelectedLineIDs: Set<UUID> = []
    var currentBookmark: Data?
    var currentVideoId: String?
    
    init() {
        lines = []
        if let first = lines.first {
            selectedLineID = first.id
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTagUpdated),
            name: .tagUpdated,
            object: nil
        )
    }
    
    func selectLine(_ lineID: UUID) {
        if MarkupMode.current == .standard {
            selectedLineID = lineID
        }
    }
    func selectStamp(stampID: UUID?) {
        selectedStampID = stampID
    }

    func toggleSportCutExportSelection(stampID: UUID) {
        if stampsSelectedForSportCut.contains(stampID) {
            stampsSelectedForSportCut.remove(stampID)
        } else {
            stampsSelectedForSportCut.insert(stampID)
        }
    }

    func clearSportCutExportSelection() {
        stampsSelectedForSportCut.removeAll()
    }
    
    /// cmd-клик по названию таймлайна выделяет все его штампы; повторный клик — снимает выделение (toggle).
    func selectAllSportCutExportStamps(in lineID: UUID) {
        guard let line = lines.first(where: { $0.id == lineID }) else { return }
        let stampIDs = line.stamps.map(\.id)
        guard !stampIDs.isEmpty else { return }
        if stampIDs.allSatisfy({ stampsSelectedForSportCut.contains($0) }) {
            stampsSelectedForSportCut.subtract(stampIDs)
        } else {
            stampsSelectedForSportCut.formUnion(stampIDs)
        }
    }
    /// Удаляет весь таймлайн (линию) вместе с его записями в истории разметки тегов.
    /// Записи истории убираем по одному экземпляру на штамп — только для обычных
    /// линий (в таймлайне рисунков `label` это имя скриншота, а не тег).
    func removeLine(lineID: UUID) {
        guard let line = lines.first(where: { $0.id == lineID }) else { return }
        if !line.isDrawingsTimeline {
            for stamp in line.stamps {
                VideoMarkupActivityBanner.shared.removeFromHistory(tagName: stamp.label)
            }
        }
        let wasSelected = (selectedLineID == lineID)
        let tagIdForMode = line.tagIdForMode
        lines.removeAll { $0.id == lineID }
        if wasSelected {
            selectedLineID = nil
        }
        updateTimelines()
        // Дорожки больше нет — интервальные теги, которые в неё писались, должны оборваться.
        // Иначе тег продолжал «писаться» невидимо, а на стопе штамп улетал в никуда
        // (в `standard` — вообще молча, из-за `guard let selectedLineID`).
        NotificationCenter.default.post(
            name: .timelineLineRemoved,
            object: RemovedTimelineLine(lineID: lineID, tagIdForMode: tagIdForMode, wasSelected: wasSelected)
        )
    }

    func removeStamp(lineID: UUID, stampID: UUID) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        
        let line = lines[lineIndex]
        
        // Проверяем, является ли это таймлайном рисунков
        let isDrawingsTimeline = line.isDrawingsTimeline
        
        // Если это таймлайн рисунков, удаляем файл скриншота
        if isDrawingsTimeline {
            if let stamp = line.stamps.first(where: { $0.id == stampID }) {
                deleteScreenshotFile(screenshotName: stamp.label)
            }
        }
        
        let removedLabel = line.stamps.first(where: { $0.id == stampID })?.label
        lines[lineIndex].stamps.removeAll(where: { $0.id == stampID })
        updateTimelines()

        // Удалённый тег убираем и из истории разметки.
        if let removedLabel, !isDrawingsTimeline {
            VideoMarkupActivityBanner.shared.removeFromHistory(tagName: removedLabel)
        }

        NotificationCenter.default.post(name: .stampCountsChanged, object: nil)
    }
    
    private func deleteScreenshotFile(screenshotName: String) {
        guard let videoId = currentVideoId,
              let filesFile = VideoFilesManager.shared.files.first(where: { $0.videoData.id == videoId }) else {
            print("❌ Не найден filesFile для удаления скриншота")
            return
        }
        
        let screenshotsFolder = filesFile.screenshotsFolder
        let imageFileName = screenshotName.hasSuffix(".png") ? screenshotName : "\(screenshotName).png"
        let imageURL = screenshotsFolder.appendingPathComponent(imageFileName)
        let jsonURL = screenshotsFolder.appendingPathComponent("\(screenshotName).json")
        
        // Удаляем файлы
        do {
            if FileManager.default.fileExists(atPath: imageURL.path) {
                try FileManager.default.removeItem(at: imageURL)
                print("✅ Удален файл изображения: \(imageFileName)")
            }
            
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                try FileManager.default.removeItem(at: jsonURL)
                print("✅ Удален файл метаданных: \(screenshotName).json")
            }
            
            // Удаляем из менеджера скриншотов
            ScreenshotsMetadataManager.shared.removeScreenshot(screenshotName: screenshotName)
        } catch {
            print("❌ Ошибка удаления файлов скриншота: \(error.localizedDescription)")
        }
    }
    
    func addLine(name: String) {
        guard MarkupMode.current == .standard else { return }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let newLine = TimelineLine(name: name)
        lines.append(newLine)
        selectedLineID = newLine.id
        updateTimelines()
    }
    
    // MARK: - Merge timelines

    /// Enters the "merge timelines" selection mode. Available in both markup modes
    /// (standard and tag-based): the merged result is a new free-form line.
    func beginMergeSelection() {
        mergeSelectedLineIDs = []
        isMergeSelectionActive = true
    }

    /// Toggles a timeline's membership in the current merge selection.
    func toggleMergeSelection(_ lineID: UUID) {
        guard isMergeSelectionActive else { return }
        if mergeSelectedLineIDs.contains(lineID) {
            mergeSelectedLineIDs.remove(lineID)
        } else {
            mergeSelectedLineIDs.insert(lineID)
        }
    }

    /// Exits merge mode without changes (Cancel / Esc).
    func cancelMergeSelection() {
        isMergeSelectionActive = false
        mergeSelectedLineIDs = []
    }

    /// Merges the selected timelines into a single *new* timeline appended at the end.
    /// The source lines are kept intact (non-destructive): the merged line receives
    /// copies of their stamps (fresh ids), ordered by start time. Works in both markup
    /// modes; the merged line is a free-form line (no `tagIdForMode`).
    func commitMergeSelection() {
        let selected = mergeSelectedLineIDs
        // Keep original on-screen order for a stable merged name.
        let selectedInOrder = lines.filter { selected.contains($0.id) }
        guard !selectedInOrder.isEmpty else {
            cancelMergeSelection()
            return
        }

        var mergedStamps: [TimelineStamp] = []
        for line in selectedInOrder {
            for stamp in line.stamps {
                mergedStamps.append(copyStamp(stamp))
            }
        }
        mergedStamps.sort { $0.timeStartSeconds < $1.timeStartSeconds }

        let mergedName = selectedInOrder.map { $0.name }.joined(separator: " + ")
        var newLine = TimelineLine(name: mergedName)
        newLine.stamps = mergedStamps

        // Originals stay put; the merged timeline is added as a new, separate row at the end.
        lines.append(newLine)
        selectedLineID = newLine.id

        isMergeSelectionActive = false
        mergeSelectedLineIDs = []
        updateTimelines()
    }

    /// Deep-copies a stamp with a fresh id so it can live in the merged timeline
    /// alongside the untouched original.
    private func copyStamp(_ stamp: TimelineStamp) -> TimelineStamp {
        TimelineStamp(
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
    }

    func findOrCreateTimelineForTag(tag: Tag) -> UUID {
        if let existingLine = lines.first(where: { $0.tagIdForMode == tag.id }) {
            return existingLine.id
        }
        let newLine = TimelineLine(name: tag.name, tagIdForMode: tag.id)
        lines.append(newLine)
        return newLine.id
    }
    
    func updateTagReferences(originalID: String, newID: String) {
        var updated = false
        
        for lineIndex in 0..<lines.count {
            for stampIndex in 0..<lines[lineIndex].stamps.count {
                if let tagIdx = lines[lineIndex].stamps[stampIndex].tagRefs.firstIndex(where: { $0.id == originalID }) {
                    let ref = lines[lineIndex].stamps[stampIndex].tagRefs[tagIdx]
                    lines[lineIndex].stamps[stampIndex].tagRefs[tagIdx] = StampTagRef(id: newID, tagGroupId: ref.tagGroupId)
                    updated = true
                }
            }
            
            if lines[lineIndex].tagIdForMode == originalID {
                lines[lineIndex].tagIdForMode = newID
                updated = true
            }
        }
        
        if updated {
            updateTimelines()
        }
    }
    
    func addStampToSelectedLine(
        tagRefs: [StampTagRef],
        primaryId: String?,
        name: String,
        timeStartSeconds: Double,
        timeFinishSeconds: Double,
        color: String,
        labels: [FullLabelWithGroup],
        position: CGPoint? = nil,
        mapFieldId: String? = nil,
        mapPositions: [StampMapPosition]? = nil,
        timeEvents: [String]? = nil
    ) {
        // Пользователь снова размечает — окно видео должно уйти из просмотра клипов плейлиста.
        MarkupPlaylistPanelStore.shared.returnToMarkupOnMarkupInteraction()
        let selectedEvents = timeEvents ?? Array(TagLibraryManager.shared.selectedTimeEvents)
        // Primary Counter тега кладём В штамп — чтобы пересмотр/просмотр/экспорт знали его и без
        // загруженной коллекции (в режиме просмотра её может не быть).
        let primaryClockId = TagLibraryManager.shared.findTagById(tagRefs.first?.id ?? "")?.primaryClockId
        var addedStampID: UUID? = nil
        // Итоговый набор позиций: приоритет у массива (мультикарта), иначе одиночная точка.
        let resolvedMapPositions: [StampMapPosition]? = {
            if let mapPositions, !mapPositions.isEmpty { return mapPositions }
            if let position { return [StampMapPosition(mapFieldId: mapFieldId, position: position)] }
            return nil
        }()
        let hasAnyPosition = !(resolvedMapPositions?.isEmpty ?? true)

        if MarkupMode.current == .standard {
            guard let lineID = selectedLineID,
                  let idx = lines.firstIndex(where: { $0.id == lineID }) else { return }

            let stamp = TimelineStamp(
                tagRefs: tagRefs,
                primaryID: primaryId,
                timeStartSeconds: timeStartSeconds,
                timeFinishSeconds: timeFinishSeconds,
                colorHex: color,
                label: name,
                labels: labels,
                timeEvents: selectedEvents,
                isActiveForMapView: hasAnyPosition,
                mapPositions: resolvedMapPositions,
                primaryClockId: primaryClockId
            )
            lines[idx].stamps.append(stamp)
            lastAddedStampID = stamp.id
            addedStampID = stamp.id

        } else {
            if let tag = TagLibraryManager.shared.findTagById(tagRefs.first?.id ?? "") {
                let lineID = findOrCreateTimelineForTag(tag: tag)

                if let idx = lines.firstIndex(where: { $0.id == lineID }) {
                    let stamp = TimelineStamp(
                        tagRefs: tagRefs,
                        primaryID: primaryId,
                        timeStartSeconds: timeStartSeconds,
                        timeFinishSeconds: timeFinishSeconds,
                        colorHex: color,
                        label: name,
                        labels: labels,
                        timeEvents: selectedEvents,
                        isActiveForMapView: hasAnyPosition,
                        mapPositions: resolvedMapPositions,
                        // В режиме «таймлайн на тег» этого не было: штампы уходили БЕЗ Primary
                        // Counter, и пересмотр/экспорт/просмотр не знали, какой счётчик показать.
                        primaryClockId: primaryClockId
                    )
                    lines[idx].stamps.append(stamp)
                    lastAddedStampID = stamp.id
                    addedStampID = stamp.id
                }
            }
        }

        updateTimelines()

        NotificationCenter.default.post(name: .stampCountsChanged, object: nil)

        // Авто-экспорт клипа добавленного тега в папку — только при включённом флаге (см. ClipAutoSaveManager).
        if let addedStampID {
            ClipAutoSaveManager.shared.autoSaveStampIfConfigured(stampID: addedStampID)
        }
    }
    
    /// Дописывает Primary Counter в штампы, которые его не несут (старые проекты и штампы из
    /// режима «таймлайн на тег», где он раньше не сохранялся). Тег резолвим один раз на id.
    /// Возвращает число дописанных штампов. Вызывается при открытии проекта.
    @discardableResult
    func backfillPrimaryClockIds() -> Int {
        var resolved: [String: String?] = [:]
        var filled = 0
        for lineIndex in lines.indices where !lines[lineIndex].isServiceTimeline {
            for stampIndex in lines[lineIndex].stamps.indices {
                let stamp = lines[lineIndex].stamps[stampIndex]
                guard stamp.primaryClockId == nil else { continue }
                let tagId = stamp.idTag
                guard !tagId.isEmpty else { continue }
                let value: String?
                if let cached = resolved[tagId] {
                    value = cached
                } else {
                    value = TagLibraryManager.shared.primaryClockId(forTagId: tagId)
                    resolved[tagId] = value
                }
                guard let value, !value.isEmpty else { continue }
                lines[lineIndex].stamps[stampIndex].primaryClockId = value
                filled += 1
            }
        }
        if filled > 0 { updateTimelines() }
        return filled
    }

    func updateStampLabels(lineID: UUID, stampID: UUID, newLabels: [FullLabelWithGroup]) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        guard let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else { return }
        lines[lineIndex].stamps[stampIndex].labels = newLabels
        updateTimelines()
    }
    
    /// Ставит тегу-штампу позицию на конкретной карте (инлайн-карта в раскладке связок).
    /// Помечаем штамп активным для карты — иначе он не попадёт в визуализацию.
    func updateStampPosition(lineID: UUID, stampID: UUID, position: CGPoint, mapFieldId: String) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        guard let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else { return }
        lines[lineIndex].stamps[stampIndex].setPosition(position, forFieldId: mapFieldId)
        lines[lineIndex].stamps[stampIndex].isActiveForMapView = true
        updateTimelines()
    }

    func updateStampTimeEvents(lineID: UUID, stampID: UUID, newEvents: [String]) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }) else { return }
        guard let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else { return }
        lines[lineIndex].stamps[stampIndex].timeEvents = newEvents
        updateTimelines()
    }
    
    func stampHasOverlaps(lineID: UUID, stampID: UUID) -> Bool {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              let stamp = lines[lineIndex].stamps.first(where: { $0.id == stampID }) else {
            return false
        }
        
        return lines[lineIndex].stamps.contains { otherStamp in
            guard otherStamp.id != stampID else { return false }
            
            let stampStart = stamp.timeStartSeconds
            let stampEnd = stamp.timeFinishSeconds
            let otherStart = otherStamp.timeStartSeconds
            let otherEnd = otherStamp.timeFinishSeconds
            return (stampStart < otherEnd && otherStart < stampEnd)
        }
    }
    
    func updateStampTime(
        lineID: UUID,
        stampID: UUID,
        newStart: Double? = nil,
        newEnd: Double? = nil,
        persistChanges: Bool = true,
        runScreenshotUnlinkCheck: Bool = true
    ) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else {
            return
        }
        
        var stamp = lines[lineIndex].stamps[stampIndex]
        let previousStart = stamp.timeStartSeconds
        let previousFinish = stamp.timeFinishSeconds

        if let newStartTime = newStart {
            let limitedStart = min(newStartTime, stamp.timeFinishSeconds - 0.5)
            stamp.timeStartSeconds = limitedStart
        }

        if let newEndTime = newEnd {
            let limitedEnd = max(newEndTime, stamp.timeStartSeconds + 0.5)
            stamp.timeFinishSeconds = limitedEnd
        }

        rescaleClockInfo(of: &stamp, oldStart: previousStart, oldFinish: previousFinish)
        lines[lineIndex].stamps[stampIndex] = stamp
        if persistChanges {
            updateTimelines()
        }
        
        // Check if any screenshots need to be unlinked due to time range change
        if runScreenshotUnlinkCheck {
            checkAndUnlinkScreenshotsOutsideStamp(stampID: stampID, newStart: stamp.timeStartSeconds, newEnd: stamp.timeFinishSeconds)
        }
    }

    /// Запись таймлайнов в то же хранилище, что и режим разметки (`UserDefaults` + немедленный сброс JSON на диск). Вызывается из SportCut после изменения границ тега.
    func persistProjectTimelinesForMarkupModel(
        _ timelines: [TimelineLine],
        videoId: String,
        editedStampID: UUID,
        editedLineID: UUID
    ) {
        InMemoryStorageManager.shared.saveTimelines(timelines, for: videoId)
        InMemoryStorageManager.shared.saveToDiskImmediate()

        if let currentId = currentVideoId, currentId == videoId {
            lines = timelines
            objectWillChange.send()
        }

        if let line = timelines.first(where: { $0.id == editedLineID }),
           let st = line.stamps.first(where: { $0.id == editedStampID }) {
            checkAndUnlinkScreenshotsOutsideStamp(
                stampID: editedStampID,
                newStart: st.timeStartSeconds,
                newEnd: st.timeFinishSeconds,
                lookupLines: timelines
            )
        }

        NotificationCenter.default.post(name: .stampCountsChanged, object: nil)
    }
    
    func updateTimelines() {
        guard let videoId = currentVideoId else {
            return
        }
        InMemoryStorageManager.shared.saveTimelines(lines, for: videoId)
    }
    
    @objc private func handleTagUpdated(_ notification: Notification) {
        guard let tagId = notification.userInfo?["tagId"] as? String else { return }
        let newName = notification.userInfo?["newName"] as? String
        
        var updated = false
        
        guard let updatedTag = TagLibraryManager.shared.findTagById(tagId) else { return }
        
        for lineIndex in 0..<lines.count {
            for stampIndex in 0..<lines[lineIndex].stamps.count {
                if lines[lineIndex].stamps[stampIndex].idTags.contains(tagId) {
                    lines[lineIndex].stamps[stampIndex].label = newName ?? updatedTag.name
                    updated = true
                }
            }
            
            if lines[lineIndex].tagIdForMode == tagId {
                lines[lineIndex].name = newName ?? updatedTag.name
                updated = true
            }
        }
        
        if updated {
            updateTimelines()
        }
    }
    
    func updateStampTimeRange(lineID: UUID, stampID: UUID, newStartTime: Double, newEndTime: Double) {
        guard let lineIndex = lines.firstIndex(where: { $0.id == lineID }),
              let stampIndex = lines[lineIndex].stamps.firstIndex(where: { $0.id == stampID }) else { return }

        var stamp = lines[lineIndex].stamps[stampIndex]
        let previousStart = stamp.timeStartSeconds
        let previousFinish = stamp.timeFinishSeconds
        stamp.timeStartSeconds = newStartTime
        stamp.timeFinishSeconds = newEndTime
        rescaleClockInfo(of: &stamp, oldStart: previousStart, oldFinish: previousFinish)
        lines[lineIndex].stamps[stampIndex] = stamp

        updateTimelines()
    }

    /// Границы штампа счётчика поехали (потянули за край) — доводим показания под новую длину,
    /// сохраняя темп счётчика. Для обычных штампов — no-op.
    private func rescaleClockInfo(of stamp: inout TimelineStamp, oldStart: Double, oldFinish: Double) {
        guard var info = stamp.clockInfo,
              stamp.timeStartSeconds != oldStart || stamp.timeFinishSeconds != oldFinish else { return }
        info.rescale(
            oldStart: oldStart,
            oldFinish: oldFinish,
            newStart: stamp.timeStartSeconds,
            newFinish: stamp.timeFinishSeconds
        )
        stamp.clockInfo = info
    }
    
    private func checkAndUnlinkScreenshotsOutsideStamp(
        stampID: UUID,
        newStart: Double,
        newEnd: Double,
        lookupLines: [TimelineLine]? = nil
    ) {
        let linesForLookup = lookupLines ?? lines
        let screenshots = ScreenshotsMetadataManager.shared.screenshots
        
        // Find the stamp to get its name
        var stampName: String = "тега"
        for line in linesForLookup {
            if let stamp = line.stamps.first(where: { $0.id == stampID }) {
                if let tag = TagLibraryManager.shared.findTagById(stamp.idTag) {
                    stampName = tag.name
                } else {
                    stampName = stamp.label
                }
                break
            }
        }
        
        for screenshot in screenshots {
            // Check if this screenshot is linked to the modified stamp
            guard screenshot.relatedStampIds.contains(stampID) else {
                continue
            }
            
            // Check if screenshot's videoTime is still within the stamp's time range
            let screenshotTime = screenshot.videoTime
            if screenshotTime < newStart || screenshotTime > newEnd {
                // Screenshot is now outside the stamp range, unlink it
                var updatedStampIds = screenshot.relatedStampIds
                updatedStampIds.removeAll { $0 == stampID }
                
                // Update the screenshot metadata
                ScreenshotsMetadataManager.shared.updateScreenshotRelatedStamps(
                    screenshotName: screenshot.screenshotName,
                    relatedStampIds: updatedStampIds
                )
                
                // Create popup for this unlinked screenshot
                let message = "Рисунок '\(screenshot.screenshotName)' отвязался от тега '\(stampName)' из-за изменения его длины"
                let popup = UnlinkedScreenshotPopup(
                    id: UUID(),
                    screenshotName: screenshot.screenshotName,
                    tagName: stampName,
                    message: message
                )
                
                DispatchQueue.main.async {
                    self.unlinkedScreenshotPopups.append(popup)
                    
                    // Auto-dismiss after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        self.unlinkedScreenshotPopups.removeAll { $0.id == popup.id }
                    }
                }
            }
        }
    }
    
    func dismissPopup(id: UUID) {
        unlinkedScreenshotPopups.removeAll { $0.id == id }
    }
    
}

// MARK: - Unlinked Screenshot Popup Model

struct UnlinkedScreenshotPopup: Identifiable {
    let id: UUID
    let screenshotName: String
    let tagName: String
    let message: String
}
