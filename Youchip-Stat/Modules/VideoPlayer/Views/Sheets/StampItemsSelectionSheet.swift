//
//  StampItemsSelectionSheet.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct StampItemsSelectionSheet: View {
    
    let sheetType: StampEditSheetType
    let stampName: String
    let initialIds: [String]
    let tag: Tag?
    let tagLibrary: TagLibraryManager
    /// Лейблы, взятые из самой разметки проекта (импорт из Sportscode/Nacsport/Dartfish и т.п.).
    /// Их нет в пуле коллекций, поэтому передаём готовыми — иначе их нельзя было бы ни снять,
    /// ни увидеть. Показываются отдельной группой «Лейблы (импорт)».
    var importedLabels: [Label] = []
    var isDop: Bool = false
    let onDone: ([String]) -> Void
    let onCancel: () -> Void
    
    /// Ordered by click — NOT a Set. The pick order is what the user sees later in the
    /// tag info line and the viewer table (it flows through to `stamp.labels`), so it
    /// must be preserved here rather than collapsed into an arbitrary hash order.
    @State private var selectedItems: [String] = []
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var hotkeyManager = HotKeyManager.shared
    @State private var markupMode = MarkupMode.current
    @ObservedObject var timelineData = TimelineDataManager.shared
    @State private var hotkeyObserver: Any? = nil
    
    /// Группа лейблов для выбора — уже с разрешёнными лейблами (не по id): часть из них может
    /// не существовать в пуле коллекций (импортированная разметка).
    private struct LabelPickerGroup: Identifiable {
        let id: String
        let name: String
        let labels: [Label]
    }

    /// Groups keep the order set in the collection editor rather than being sorted by
    /// name, so the arrangement authored there is what the user sees while tagging.
    private var filteredLabelGroups: [LabelGroupData] {
        if let tag {
            // Optimize using Set for O(1) lookup
            let labelGroupIdsSet = Set(tag.lablesGroup)
            return tagLibrary.allLabelGroups.filter { labelGroupIdsSet.contains($0.id) }
        } else {
            return tagLibrary.allLabelGroups
        }
    }

    /// Что показываем в листе лейблов:
    /// 1. Свои группы тега — как и раньше, обычная разметка не меняется.
    /// 2. Если своих групп нет (тег из стороннего XML — его коллекция не установлена) —
    ///    группы ТЕКУЩЕЙ коллекции, чтобы можно было навесить наши лейблы.
    /// 3. Плюс «Лейблы (импорт)» — всё, что уже встречается в разметке этого проекта и не
    ///    попало в пункты выше. Без этой группы нанесённый импортом лейбл нельзя было снять.
    private var labelPickerGroups: [LabelPickerGroup] {
        let baseGroups: [LabelGroupData]
        if tag != nil {
            let own = filteredLabelGroups
            if own.isEmpty {
                baseGroups = tagLibrary.labelGroups.isEmpty ? tagLibrary.allLabelGroups : tagLibrary.labelGroups
            } else {
                baseGroups = own
            }
        } else {
            baseGroups = tagLibrary.allLabelGroups
        }

        var result: [LabelPickerGroup] = []
        var shownIds = Set<String>()
        for group in baseGroups {
            let labels = group.lables.compactMap { tagLibrary.findLabelById($0) }
            guard !labels.isEmpty else { continue }
            labels.forEach { shownIds.insert($0.id) }
            result.append(LabelPickerGroup(id: group.id, name: group.name, labels: labels))
        }

        var seenImported = Set<String>()
        let rest = importedLabels.filter { !shownIds.contains($0.id) && seenImported.insert($0.id).inserted }
        if !rest.isEmpty {
            result.append(LabelPickerGroup(
                id: "imported-labels",
                name: ^String.Titles.xmlImportNotesLabelGroupName,
                labels: rest
            ))
        }
        return result
    }
    
    /// Высота окна, из которого открыт лист. Лист — часть этого окна, поэтому он не должен
    /// быть выше него: при большом списке лейблов (импортированная разметка — их там десятки)
    /// он раздувался до 75% экрана и вылезал за окно вверх/вниз.
    @State private var hostWindowHeight: CGFloat? = NSApp.keyWindow?.frame.height

    /// Сколько по вертикали можно отдать самому списку. Из высоты окна вычитаем шапку листа
    /// («Timestamp: …», строка про таймлайн) и строку кнопок с отступами.
    private var maxSheetContentHeight: CGFloat {
        let screenCap = (NSScreen.main?.visibleFrame.height ?? 600) * 0.75
        guard let host = hostWindowHeight, host > 0 else { return min(screenCap, 420) }
        return max(180, min(screenCap, host - 190))
    }
    
    private let timeEvents: [TimeEvent]
    
    init(sheetType: StampEditSheetType, stampName: String, initialIds: [String], tag: Tag?, tagLibrary: TagLibraryManager, importedLabels: [Label] = [], isDop: Bool = false, onDone: @escaping ([String]) -> Void, onCancel: @escaping () -> Void) {
        self.sheetType = sheetType
        self.stampName = stampName
        self.initialIds = initialIds
        self.tag = tag
        self.tagLibrary = tagLibrary
        self.importedLabels = importedLabels
        self.isDop = isDop
        self.onDone = onDone
        self.onCancel = onCancel
        
        // Initialize timeEvents - use cached data from TagLibraryManager instead of loading collections
        guard let tag else {
            timeEvents = []
            return
        }
        
        // Fast lookup: check standard collections first (already loaded)
        if let standardCollection = tagLibrary.standardCollections.first(where: { $0.tags.contains(where: { $0.id == tag.id }) }) {
            timeEvents = standardCollection.timeEvents
            return
        }
        
        // Check user collections from cache (already loaded in allTags/allTagGroups)
        // Find which collection contains this tag by checking tagLibrary.allTags
        if tagLibrary.allTags.contains(where: { $0.id == tag.id }) {
            // Tag exists in loaded collections, find timeEvents from allTimeEvents
            // Since we don't know which collection, we'll use all available timeEvents
            // This is faster than loading collections synchronously
            timeEvents = tagLibrary.allTimeEvents
            return
        }
        
        timeEvents = []
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if markupMode == .tagBased && tag != nil {
                Text("\(^String.Titles.labelSheetInfoTagAdd) \(tag?.name ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            } else if markupMode == .standard && timelineData.selectedLineID == nil {
                Text(^String.Titles.labelSheetErrorNoTimeline)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(.bottom, 4)
            }
            
            Text("\(^String.Titles.labelSheetTimestamp) \(stampName)")
                .font(.headline)
            
            ScrollView {
                switch sheetType {
                case .lables:
                    stackForLabelsLayout()
                case .timeEvents:
                    stackForTimeEventsLayout()
                }
            }
            .frame(maxHeight: maxSheetContentHeight)
            
            HStack {
                Spacer()
                Button(^String.Titles.collectionsButtonCancel) {
                    dismissSheet()
                }
                Button(^String.Titles.collectionsButtonAdd) {
                    completeSelection()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: isDop ? 0 : 400)
        .fixedSize(horizontal: false, vertical: true)
        // Точный размер окна-хозяина известен только после показа листа (`sheetParent`).
        .background(SheetHostWindowAccessor { height in
            if hostWindowHeight != height { hostWindowHeight = height }
        })
        .onAppear {
            // Keep the previously stored order; drop any accidental duplicates.
            var seen = Set<String>()
            selectedItems = initialIds.filter { seen.insert($0).inserted }
            setupLabelHotkeys()
            markupMode = MarkupMode.current
        }
        .onDisappear {
            cleanupHotkeys()
        }
    }
    
    // MARK: - Helpers

    /// Toggles an item, appending on select so the pick order is preserved.
    private func toggleSelection(_ id: String) {
        if let index = selectedItems.firstIndex(of: id) {
            selectedItems.remove(at: index)
        } else {
            selectedItems.append(id)
        }
    }

    private func stackForLabelsLayout() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(labelPickerGroups) { group in
                DisclosureGroup(isExpanded: .constant(true)) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)],
                        spacing: 16
                    ) {
                        ForEach(group.labels, id: \.id) { label in
                            Button {
                                toggleSelection(label.id)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(
                                        systemName: selectedItems.contains(label.id)
                                        ? "checkmark.square"
                                        : "square"
                                    )
                                    Text(label.name)
                                        .lineLimit(1)
                                        .font(.system(size: 12))

                                    if let tagHotkeys = tag?.labelHotkeys,
                                       let hotkey = tagHotkeys[label.id], !hotkey.isEmpty {
                                        Spacer()
                                        Text(hotkey)
                                            .font(.system(size: 9, weight: .light))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.black.opacity(0.15))
                                            .cornerRadius(3)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(selectedItems.contains(label.id)
                                            ? Color.blue.opacity(0.2)
                                            : Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                } label: {
                    Text(group.name)
                        .font(.subheadline)
                        .bold()
                }
            }
        }
    }
    
    private func stackForTimeEventsLayout() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: .constant(true)) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)],
                    spacing: 16
                ) {
                    ForEach(timeEvents, id: \.self) { event in
                        Button {
                            toggleSelection(event.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(
                                    systemName: selectedItems.contains(event.id)
                                    ? "checkmark.square"
                                    : "square"
                                )
                                Text(event.name)
                                    .lineLimit(1)
                                    .font(.system(size: 12))
                                
                                if let tagHotkeys = tag?.labelHotkeys,
                                   let hotkey = tagHotkeys[event.id], !hotkey.isEmpty {
                                    Spacer()
                                    Text(hotkey)
                                        .font(.system(size: 9, weight: .light))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.black.opacity(0.15))
                                        .cornerRadius(3)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedItems.contains(event.id)
                                        ? Color.blue.opacity(0.2)
                                        : Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
            } label: {
                Text(^String.Titles.commonEvents)
                    .font(.subheadline)
                    .bold()
            }
        }
    }
    
    private func setupLabelHotkeys() {
        hotkeyManager.enableLabelHotkeyMode()
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .labelHotkeyPressed,
            object: nil,
            queue: .main
        ) { notification in
            if let labelInfo = notification.object as? (labelId: String, tagId: String),
               labelInfo.tagId == tag?.id {
                toggleSelection(labelInfo.labelId)
            }
        }
    }
    
    private func cleanupHotkeys() {
        hotkeyManager.disableLabelHotkeyMode()
        if let observer = hotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
            hotkeyObserver = nil
        }
    }
    
    private func dismissSheet() {
        onCancel()
        presentationMode.wrappedValue.dismiss()
    }
    
    private func completeSelection() {
        onDone(selectedItems)
        presentationMode.wrappedValue.dismiss()
    }
    
}

