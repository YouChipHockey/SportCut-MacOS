//
//  FieldMapVisualizationView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/4/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FieldMapVisualizationView: View {
    
    let collection: CollectionBookmark
    let mode: VisualizationMode
    let stamps: [TimelineStamp]
    
    @State private var fieldImage: NSImage? = nil
    @State private var imageSize: CGSize = .zero
    @State private var imageFrame: CGRect = .zero
    @State private var selectedStamp: TimelineStamp? = nil
    @State private var fieldDimensions: (width: Int, height: Int) = (0, 0)
    @State private var visibleStampIDs: Set<UUID> = Set()
    @State private var filteredStampIDs: Set<UUID> = Set()
    @State private var contextMenuStamp: TimelineStamp? = nil
    @State private var showContextMenu = false
    @State private var contextMenuPosition = CGPoint.zero
    @State private var numberedStamps: [UUID: Int] = [:]
    
    @State private var filters = FieldMapFilters()
    @State private var showFilters = false
    
    enum DisplayMode {
        case tags
        case heatmap
    }
    
    @State private var displayMode: DisplayMode = .tags
    
    private var displayedStamps: [TimelineStamp] {
        stamps.filter { stamp in
            visibleStampIDs.contains(stamp.id) && filteredStampIDs.contains(stamp.id)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack {
                    Text("Список тегов")
                        .font(.headline)
                        .padding([.top, .horizontal])
                    
                    HStack {
                        Button(action: {
                            showFilters = true
                        }) {
                            HStack {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                Text("Фильтры")
                            }
                        }
                        .buttonStyle(.borderless)
                        
                        if filters.isAnyFilterActive {
                            Button(action: {
                                filters = FieldMapFilters()
                                updateFilteredStamps()
                            }) {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Сбросить фильтры")
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    List {
                        ForEach(stamps, id: \.id) { stamp in
                            HStack {
                                Toggle("", isOn: Binding(
                                    get: { visibleStampIDs.contains(stamp.id) },
                                    set: { isVisible in
                                        if isVisible {
                                            visibleStampIDs.insert(stamp.id)
                                        } else {
                                            visibleStampIDs.remove(stamp.id)
                                        }
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(CheckboxToggleStyle())
                                .disabled(!filteredStampIDs.contains(stamp.id))
                                .opacity(filteredStampIDs.contains(stamp.id) ? 1.0 : 0.5)
                                
                                Circle()
                                    .fill(Color(hex: stamp.colorHex))
                                    .frame(width: 10, height: 10)
                                
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(stamp.label)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                            .foregroundColor(filteredStampIDs.contains(stamp.id) ? .primary : .secondary)
                                        
                                        if let number = numberedStamps[stamp.id] {
                                            Text("(№\(number))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(width: 40, alignment: .leading)
                                        }
                                    }
                                    
                                    Text(stamp.timeStart)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if selectedStamp?.id == stamp.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedStamp = stamp
                            }
                            .opacity(filteredStampIDs.contains(stamp.id) ? 1.0 : 0.6)
                        }
                    }
                    
                    HStack {
                        if filters.isAnyFilterActive {
                            Text("Отфильтровано: \(filteredStampIDs.count) из \(stamps.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("Отображается: \(displayedStamps.count) из \(stamps.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                .frame(width: 250)
                
                Divider()
                
                VStack {
                    HStack {
                        Spacer()
                        Picker("Режим отображения", selection: $displayMode) {
                            Text("Теги").tag(DisplayMode.tags)
                            Text("Тепловая карта").tag(DisplayMode.heatmap)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 300)
                        Button(action: {
                                exportCurrentView()
                            }) {
                                Text("Экспорт")
                            }
                            .help("Экспортировать как изображение")
                            .buttonStyle(.borderless)
                            .padding(.leading, 8)
                    }
                    .frame(height: 30)
                    .padding([.top, .trailing])
                    
                    HStack {
                        ZStack {
                            if let image = fieldImage {
                                ZStack(alignment: .center) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .overlay(
                                            GeometryReader { geo in
                                                ZStack {
                                                    if displayMode == .tags {
                                                        ForEach(displayedStamps.filter { $0.position != nil }, id: \.id) { stamp in
                                                            if let position = stamp.position {
                                                                let screenPosition = fieldPositionToScreenPosition(
                                                                    position,
                                                                    fieldDimensions: (CGFloat(fieldDimensions.width), CGFloat(fieldDimensions.height)),
                                                                    imageSize: geo.size
                                                                )
                                                                
                                                                ZStack {
                                                                    Circle()
                                                                        .fill(Color(hex: stamp.colorHex))
                                                                        .frame(width: 20, height: 20)
                                                                    
                                                                    if let number = numberedStamps[stamp.id] {
                                                                        Text("\(number)")
                                                                            .font(.system(size: 10, weight: .bold))
                                                                            .foregroundColor(.white)
                                                                    }
                                                                    
                                                                    if selectedStamp?.id == stamp.id {
                                                                        Circle()
                                                                            .stroke(Color.black, lineWidth: 2)
                                                                            .frame(width: 22, height: 22)
                                                                        Circle()
                                                                            .stroke(Color.red, lineWidth: 2)
                                                                            .frame(width: 24, height: 24)
                                                                        Circle()
                                                                            .stroke(Color.black, lineWidth: 2)
                                                                            .frame(width: 26, height: 26)
                                                                    }
                                                                }
                                                                .position(screenPosition)
                                                                .contextMenu {
                                                                    stampContextMenu(stamp)
                                                                }
                                                            }
                                                        }
                                                    } else {
                                                        HeatMapView(
                                                            stamps: displayedStamps.filter { $0.position != nil },
                                                            fieldDimensions: (CGFloat(fieldDimensions.width), CGFloat(fieldDimensions.height)),
                                                            viewSize: geo.size
                                                        )
                                                        .opacity(0.7)
                                                    }
                                                }
                                            }
                                        )
                                }
                                .padding()
                            } else {
                                Text("Загрузка карты...")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        if let stamp = selectedStamp {
                            VStack {
                                Spacer()
                                
                                stampInfoView(stamp)
                                    .background(Color(NSColor.windowBackgroundColor))
                                    .cornerRadius(8)
                                    .shadow(radius: 5)
                                    .padding()
                            }
                        }
                    }
                }
            }
            .onAppear {
                loadFieldImageAndDimensions()
                initializeVisibility()
                assignStampNumbers()
            }
            .sheet(isPresented: $showFilters) {
                FieldMapFilterView(
                    filters: $filters,
                    stamps: stamps,
                    onApply: {
                        updateFilteredStamps()
                        showFilters = false
                    },
                    onReset: {
                        updateFilteredStamps()
                    },
                    onCancle: {
                        showFilters = false
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private func stampContextMenu(_ stamp: TimelineStamp) -> some View {
        if let number = numberedStamps[stamp.id] {
            Text("Тег №\(number): \(stamp.label)")
        } else {
            Text("Тег: \(stamp.label)")
        }
        
        Text("Время: \(stamp.timeStart) - \(stamp.timeFinish)")
        if let position = stamp.position {
            Text("Позиция: \(String(format: "x: %.2f, y: %.2f", position.x, position.y))")
        }
        Divider()
        Button("Информация") {
            selectedStamp = stamp
        }
        Button(visibleStampIDs.contains(stamp.id) ? "Скрыть" : "Показать") {
            if visibleStampIDs.contains(stamp.id) {
                visibleStampIDs.remove(stamp.id)
            } else {
                visibleStampIDs.insert(stamp.id)
            }
        }
        if !filteredStampIDs.contains(stamp.id) {
            Text("Тег не соответствует фильтрам")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
    
    private func exportCurrentView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let mapAreaID = "map-area-for-export"
            let captureWindow = self.makeMapCaptureView(id: mapAreaID)
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType.png]
            savePanel.canCreateDirectories = true
            savePanel.isExtensionHidden = false
            savePanel.title = "Сохранить карту"
            savePanel.message = "Выберите место для сохранения изображения карты"
            savePanel.nameFieldStringValue = "Карта поля.png"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                savePanel.beginSheetModal(for: captureWindow) { response in
                    if response == .OK, let url = savePanel.url {
                        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == mapAreaID }) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if let cgImage = CGWindowListCreateImage(
                                    .zero,
                                    .optionIncludingWindow,
                                    CGWindowID(window.windowNumber),
                                    [.boundsIgnoreFraming, .bestResolution]
                                ) {
                                    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                                    let image = NSImage(size: bitmapRep.size)
                                    image.addRepresentation(bitmapRep)
                                    if let croppedImage = self.cropWindowDecorations(image, window: window) {
                                        if let tiffData = croppedImage.tiffRepresentation,
                                           let bitmap = NSBitmapImageRep(data: tiffData),
                                           let pngData = bitmap.representation(using: .png, properties: [:]) {
                                            do {
                                                try pngData.write(to: url)
                                            } catch {
                                                self.showErrorAlert(message: "Ошибка при сохранении изображения: \(error.localizedDescription)")
                                            }
                                        }
                                    }
                                }
                                
                                window.close()
                            }
                        } else {
                            self.showErrorAlert(message: "Не удалось сделать снимок карты")
                        }
                    } else if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == mapAreaID }) {
                        window.close()
                    }
                }
            }
        }
    }
    
    private func cropWindowDecorations(_ image: NSImage, window: NSWindow) -> NSImage? {
        guard let contentView = window.contentView else { return image }
        
        let windowFrame = window.frame
        let contentRect = window.contentRect(forFrameRect: windowFrame)
        
        let titlebarHeight = windowFrame.height - contentRect.height
        let yOffset = titlebarHeight
        
        let croppedImage = NSImage(size: contentView.bounds.size)
        croppedImage.lockFocus()
        
        let destRect = NSRect(origin: .zero, size: contentView.bounds.size)
        let sourceRect = NSRect(
            x: 0,
            y: yOffset,
            width: image.size.width,
            height: image.size.height - yOffset
        )
        
        image.draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)
        croppedImage.unlockFocus()
        
        return croppedImage
    }
    
    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Ошибка экспорта"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "ОК")
        alert.runModal()
    }
    
    private func makeMapCaptureView(id: String) -> NSWindow {
        let captureContent = AnyView(
            ZStack {
                if let image = fieldImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay(
                            GeometryReader { geo in
                                ZStack {
                                    if displayMode == .tags {
                                        ForEach(displayedStamps.filter { $0.position != nil }, id: \.id) { stamp in
                                            if let position = stamp.position {
                                                let screenPosition = fieldPositionToScreenPosition(
                                                    position,
                                                    fieldDimensions: (CGFloat(fieldDimensions.width), CGFloat(fieldDimensions.height)),
                                                    imageSize: geo.size
                                                )
                                                
                                                ZStack {
                                                    Circle()
                                                        .fill(Color(hex: stamp.colorHex))
                                                        .frame(width: 20, height: 20)
                                                    
                                                    if let number = numberedStamps[stamp.id] {
                                                        Text("\(number)")
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundColor(.white)
                                                    }
                                                    
                                                    if selectedStamp?.id == stamp.id {
                                                        Circle()
                                                            .stroke(Color.black, lineWidth: 2)
                                                            .frame(width: 22, height: 22)
                                                        Circle()
                                                            .stroke(Color.red, lineWidth: 2)
                                                            .frame(width: 24, height: 24)
                                                        Circle()
                                                            .stroke(Color.black, lineWidth: 2)
                                                            .frame(width: 26, height: 26)
                                                    }
                                                }
                                                .position(screenPosition)
                                            }
                                        }
                                    } else {
                                        HeatMapView(
                                            stamps: displayedStamps.filter { $0.position != nil },
                                            fieldDimensions: (CGFloat(fieldDimensions.width), CGFloat(fieldDimensions.height)),
                                            viewSize: geo.size
                                        )
                                        .opacity(0.7)
                                    }
                                }
                            }
                        )
                } else {
                    Text("Карта не загружена")
                }
            }
        )
        
        let hostingController = NSHostingController(rootView: captureContent)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 1024, height: 768))
        window.styleMask = [.titled, .closable]
        window.title = "Экспорт карты"
        window.identifier = NSUserInterfaceItemIdentifier(rawValue: id)
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        return window
    }
    
    private func calculateActualImageSize(containerSize: CGSize, imageSize: CGSize, fitToWidth: Bool = true) -> CGSize {
        let aspectRatio = imageSize.height / imageSize.width
        let newWidth = containerSize.width
        let newHeight = newWidth * aspectRatio
        
        return CGSize(width: newWidth, height: newHeight)
    }
    
    private func fieldPositionToScreenPosition(_ fieldPosition: CGPoint, fieldDimensions: (width: CGFloat, height: CGFloat), imageSize: CGSize) -> CGPoint {
        let normalizedX = fieldPosition.x / fieldDimensions.width
        let normalizedY = fieldPosition.y / fieldDimensions.height
        
        return CGPoint(
            x: normalizedX * imageSize.width,
            y: normalizedY * imageSize.height
        )
    }
    
    private func stampPopupView(_ stamp: TimelineStamp) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Rectangle()
                    .fill(Color(hex: stamp.colorHex))
                    .frame(width: 14, height: 14)
                    .cornerRadius(2)
                
                Text(stamp.label)
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    showContextMenu = false
                }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            
            Divider()
            
            if let tagGroup = TagLibraryManager.shared.findTagGroupForTag(stamp.idTag) {
                HStack {
                    Text("Группа:")
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(tagGroup.name)
                        .font(.subheadline)
                }
            }
            
            HStack {
                Text("Время:")
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                Text("\(stamp.timeStart) - \(stamp.timeFinish)")
            }
            
            HStack {
                Text("Длительность:")
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                Text("\(String(format: "%.2f", stamp.duration)) сек")
            }
            
            if let position = stamp.position {
                HStack {
                    Text("Позиция:")
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(String(format: "x: %.2f м, y: %.2f м", position.x, position.y))
                }
            }
            
            if !stamp.labels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Лейблы:")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    
                    ForEach(getGroupedLabels(for: stamp.labels), id: \.0) { group, labels in
                        VStack(alignment: .leading) {
                            Text(group)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 8)
                            
                            ForEach(labels, id: \.id) { label in
                                HStack(spacing: 4) {
                                    Text("•")
                                    Text(label.name)
                                        .font(.caption)
                                }
                                .padding(.leading, 16)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            
            if !stamp.timeEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("События:")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    
                    ForEach(getEvents(for: stamp.timeEvents), id: \.id) { event in
                        HStack(spacing: 4) {
                            Text("•")
                            Text(event.name)
                                .font(.caption)
                        }
                        .padding(.leading, 8)
                    }
                }
            }
            
            HStack {
                Spacer()
                Button("Выбрать") {
                    selectedStamp = stamp
                    showContextMenu = false
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding()
        .frame(width: 300)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 5)
    }
    
    private func assignStampNumbers() {
        let sortedStamps = stamps.sorted {
            $0.label < $1.label
        }
        for (index, stamp) in sortedStamps.enumerated() {
            numberedStamps[stamp.id] = index + 1
        }
    }
    
    private func updateFilteredStamps() {
        if filters.isAnyFilterActive {
            filteredStampIDs = Set(stamps.filter { filters.shouldShowStamp($0) }.map { $0.id })
        } else {
            filteredStampIDs = Set(stamps.map { $0.id })
        }
    }
    
    private func initializeVisibility() {
        visibleStampIDs = Set(stamps.map { $0.id })
        filteredStampIDs = Set(stamps.map { $0.id })
    }
    
    private func stampInfoView(_ stamp: TimelineStamp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let number = numberedStamps[stamp.id] {
                    Text("Тег №\(number)")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Rectangle()
                    .fill(Color(hex: stamp.colorHex))
                    .frame(width: 14, height: 14)
                    .cornerRadius(2)
                
                Text(stamp.label)
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    selectedStamp = nil
                }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        if let tagGroup = TagLibraryManager.shared.findTagGroupForTag(stamp.idTag) {
                            detailRow(title: "Группа:", value: tagGroup.name)
                        }
                        
                        detailRow(title: "Время:", value: "\(stamp.timeStart) - \(stamp.timeFinish)")
                        
                        detailRow(title: "Длительность:", value: "\(String(format: "%.2f", stamp.duration)) сек")
                        
                        if let position = stamp.position {
                            detailRow(title: "Позиция:", value: String(format: "x: %.2f м, y: %.2f м", position.x, position.y))
                        }
                    }
                    
                    if !stamp.labels.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Лейблы:")
                                .foregroundColor(.secondary)
                                .font(.headline)
                                .padding(.bottom, 2)
                            
                            ForEach(getGroupedLabels(for: stamp.labels), id: \.0) { group, labels in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(.bottom, 2)
                                    
                                    ForEach(labels, id: \.id) { label in
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color.secondary)
                                                .frame(width: 6, height: 6)
                                            Text(label.name)
                                                .font(.body)
                                        }
                                        .padding(.leading, 8)
                                    }
                                }
                                .padding(.vertical, 2)
                                .padding(.leading, 8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    if !stamp.timeEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("События:")
                                .foregroundColor(.secondary)
                                .font(.headline)
                                .padding(.bottom, 2)
                            
                            ForEach(getEvents(for: stamp.timeEvents), id: \.id) { event in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(Color.secondary)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 6)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.name)
                                            .font(.body)
                                    }
                                }
                                .padding(.leading, 8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Group {
                        HStack(alignment: .center) {
                            Text("Цвет:")
                                .foregroundColor(.secondary)
                            Rectangle()
                                .fill(Color(hex: stamp.colorHex))
                                .frame(width: 20, height: 20)
                                .cornerRadius(4)
                            Text(stamp.colorHex)
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding()
        .frame(maxWidth: 400)
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func getGroupedLabels(for labelIDs: [String]) -> [(String, [Label])] {
        var groupedLabels: [String: [Label]] = [:]
        
        for labelID in labelIDs {
            if let label = TagLibraryManager.shared.findLabelById(labelID) {
                var groupName = "Без группы"
                
                for group in TagLibraryManager.shared.allLabelGroups {
                    if group.lables.contains(labelID) {
                        groupName = group.name
                        break
                    }
                }
                
                if groupedLabels[groupName] == nil {
                    groupedLabels[groupName] = []
                }
                groupedLabels[groupName]?.append(label)
            }
        }
        return groupedLabels.map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }
    
    private func getEvents(for eventIDs: [String]) -> [TimeEvent] {
        var events: [TimeEvent] = []
        
        for eventID in eventIDs {
            if let event = TagLibraryManager.shared.allTimeEvents.first(where: { $0.id == eventID }) {
                events.append(event)
            }
        }
        
        return events
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func loadFieldImageAndDimensions() {
        let collectionManager = CustomCollectionManager()
        guard collectionManager.loadCollectionFromBookmarks(named: collection.name),
              let playField = collectionManager.playField,
              let imageBookmark = playField.imageBookmark else {
            return
        }
        
        fieldDimensions = (Int(playField.width), Int(playField.height))
        
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: imageBookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if url.startAccessingSecurityScopedResource() {
                fieldImage = NSImage(contentsOf: url)
                url.stopAccessingSecurityScopedResource()
            }
        } catch {
            print("Error loading field image: \(error)")
        }
    }
    
    private func fieldPositionToScreenPosition(_ fieldPosition: CGPoint, fieldDimensions: (width: CGFloat, height: CGFloat), imageFrame: CGRect) -> CGPoint {
        let normalizedX = fieldPosition.x / fieldDimensions.width
        let normalizedY = fieldPosition.y / fieldDimensions.height
        return CGPoint(
            x: imageFrame.minX + (normalizedX * imageFrame.width),
            y: imageFrame.minY + (normalizedY * imageFrame.height)
        )
    }
}
