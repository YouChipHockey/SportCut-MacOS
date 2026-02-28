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
    
    @State private var scrollOffset: CGFloat = 0
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    @ObservedObject var focusManager = FocusStateManager.shared
    @ObservedObject var hotkeyManager = HotKeyManager.shared
    @StateObject var exportHelper = ExportHelper()
    
    @State private var markupMode: MarkupMode = MarkupMode.current
    @State private var showMarkupModeToggle = false
    
    @State private var sliderValue: Double = 0.0
    @State private var showAddLineSheet = false
    @State private var isExporting: Bool = false
    @State private var stampItemsEditSheetType: StampEditSheetType? = nil
    @State private var showFieldMapVisualizationPicker = false
    @State private var editingStampLineID: UUID?
    @State private var editingStampID: UUID?
    @State private var timelineScale: CGFloat = 1.0
    @GestureState private var magnifyScale: CGFloat = 1.0
    @State private var keyEventMonitor: Any?
    @State private var tagEdgePosition: CGFloat? = nil
    
    @State private var isEditorModeActive = false
    @State private var isScreenshotDisplayActive = false
    
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
        guard let currentBookmark = timelineData.currentBookmark else {
            return nil
        }
        return VideoFilesManager.shared.files.first(where: { $0.videoData.bookmark == currentBookmark })
    }
    
    private func setupKeyboardShortcuts() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if focusManager.isAnyTextFieldFocused {
                return event
            }
            
            switch event.keyCode {
            /// removed because it blocks "escape" from handling cancelAction in sheets
//            case 53:
//                timelineData.selectStamp(stampID: nil)
//                return nil
            case 51:
                if event.modifierFlags.contains(.option) {
                    if let stampID = timelineData.selectedStampID {
                        for line in timelineData.lines {
                            if line.stamps.contains(where: { $0.id == stampID }) {
                                timelineData.removeStamp(lineID: line.id, stampID: stampID)
                                break
                            }
                        }
                        return nil
                    }
                }
                return event
            default:
                return event
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
    
    @State private var showLabelSelectionSheet: Bool = false
    @State private var showMultiLabelSelectionSheet: Bool = false
    @State private var showMultiTagSelectionSheet: Bool = false
    @State private var selectedLabelForMultiSelection: Label?
    @State private var selectedTagForMultiSelection: Tag?
    
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var hoveredStampInfo: String? = nil
    @State private var isHoveringOnPopup = false

    @State private var isLoading = false
    @State private var availableTags: [Tag] = []
    @State private var availableLabels: [Label] = []
    
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
                ScrollView(.vertical) {
                    ScrollViewReader { scrollProxy in
                        timelineContent(proxy: scrollProxy)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                            let duration = max(1.0, videoManager.videoDuration)
                            let potentialInterval = calculateTimeGridInterval(scale: newScale, totalDuration: duration)
                            if potentialInterval >= 0.5 {
                                timelineScale = max(1.0, newScale)
                            } else {
                                let baseInterval = 5.0
                                let maxScale = baseInterval / 0.5
                                timelineScale = maxScale
                            }
                        }
                )
                .disabled(isEditorModeActive || isScreenshotDisplayActive)
                .opacity(isEditorModeActive || isScreenshotDisplayActive ? 0.5 : 1.0)
            }
            
            if let stampInfo = hoveredStampInfo {
                stampHoverPopup(stampInfo: stampInfo)
                    .padding(.top, 16)
                    .padding(.trailing, 20)
                    .allowsHitTesting(false)
                    .onHover { hovering in
                        isHoveringOnPopup = hovering
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func calculateTimeGridInterval(scale: CGFloat, totalDuration: Double) -> Double {
        let baseCount = 20 * scale
        let baseInterval = totalDuration / baseCount
        
        return max(0.5, baseInterval)
    }
    
    private func timelineScrollView(geo: GeometryProxy, effectiveScale: CGFloat, duration: Double, popupInfo: String?, popupLocation: CGPoint?) -> some View {
        let interval = calculateTimeGridInterval(scale: effectiveScale, totalDuration: duration)
        let gridWidth = geo.size.width * max(effectiveScale, 1.0)
        
        return ScrollView(.horizontal) {
            HStack(spacing: 0) {
                timelineZStackContent(
                    duration: duration,
                    interval: interval,
                    gridWidth: gridWidth,
                    effectiveScale: effectiveScale
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))

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
    
    @ViewBuilder
    private func timelineZStackContent(duration: Double, interval: Double, gridWidth: CGFloat, effectiveScale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TimeGridView(
                duration: duration,
                interval: interval,
                width: gridWidth,
                height: 30 * CGFloat(timelineData.lines.count + 1)
            )
            
            VStack(spacing: 0) {
                TimelineTimestampsHeaderView(
                    duration: duration,
                    interval: interval,
                    width: gridWidth
                )
                .frame(height: 30)
                
                ForEach(timelineData.lines) { line in
                    TimelineLineView(
                        videoManager: VideoPlayerManager.shared,
                        timelineData: TimelineDataManager.shared,
                        line: line,
                        scale: effectiveScale,
                        widthMax: gridWidth,
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
                        tagLibrary: TagLibraryManager.shared,
                        scrollOffset: $scrollOffset
                    )
                    .frame(height: 30)
                    .id("timeline-\(line.id)")
                }
                
            }
            .padding(.bottom, 15) // for scroll indicator to not overlap timelines
            
            ScreenshotMarkersView(
                duration: duration,
                gridWidth: gridWidth,
                totalHeight: 30 * CGFloat(timelineData.lines.count + 1)
            )
            
            let timeOffsetToPixels = duration > 0 ? (videoManager.currentTime / duration) * gridWidth : 0
            Rectangle()
                .fill(Color.red)
                .frame(width: 2)
                .offset(x: tagEdgePosition ?? timeOffsetToPixels)
            
            TimelineMouseTracker(
                duration: duration,
                gridWidth: gridWidth,
                lines: timelineData.lines,
                tagLibrary: TagLibraryManager.shared,
                onStampUpdate: { stampInfo, location in
                    NotificationCenter.default.post(
                        name: .timelineStampHoverChanged,
                        object: nil,
                        userInfo: ["stampInfo": stampInfo as Any]
                    )
                }
            )
            .allowsHitTesting(false)
        }
        .frame(width: gridWidth)
        .coordinateSpace(name: "timelineSpace")
    }
    
    @ViewBuilder
    private func timelineContent(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
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
                .id("header-row")
                
                ForEach(timelineData.lines) { line in
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
                                            .fill((line.id == timelineData.selectedLineID) ?
                                                  Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke((line.id == timelineData.selectedLineID) ?
                                                    Color.blue.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 0.5)
                                    )
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            timelineData.selectLine(line.id)
                                        }
                                    }
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Button(action: {
                                    timelineData.selectLine(line.id)
                                    showEditNameSheet = true
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.blue)
                                        .padding(3)
                                        .background(
                                            Circle()
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .help(^String.Titles.editTimelineName)
                                
                                Button(action: {
                                    let isSelectedLine = (TimelineDataManager.shared.selectedLineID == line.id)
                                    TimelineDataManager.shared.lines.removeAll { $0.id == line.id }
                                    if isSelectedLine {
                                        TimelineDataManager.shared.selectedLineID = nil
                                    }
                                    TimelineDataManager.shared.updateTimelines()
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.red)
                                        .padding(3)
                                        .background(
                                            Circle()
                                                .fill(Color.red.opacity(0.1))
                                        )
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .help(^String.Titles.timelineButtonDeleteTimeline)
                            }
                        }
                        .padding(.leading, 5)
                        .frame(width: 195, height: 30, alignment: .leading)
                        .contextMenu {
                            Button(^String.Titles.editName) {
                                timelineData.selectLine(line.id)
                                showEditNameSheet = true
                            }
                            Button(^String.Titles.timelineButtonDeleteTimeline) {
                                let isSelectedLine = (TimelineDataManager.shared.selectedLineID == line.id)
                                TimelineDataManager.shared.lines.removeAll { $0.id == line.id }
                                if isSelectedLine {
                                    TimelineDataManager.shared.selectedLineID = nil
                                }
                                TimelineDataManager.shared.updateTimelines()
                            }
                        }
                        .onDrag {
                            return NSItemProvider(object: line.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TimelineDropDelegate(
                            currentLine: line,
                            timelineData: timelineData
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
                                            .fill((line.id == timelineData.selectedLineID) ?
                                                  Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke((line.id == timelineData.selectedLineID) ?
                                                    Color.blue.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 0.5)
                                    )
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            timelineData.selectLine(line.id)
                                        }
                                    }
                            }
                            
                            Spacer()

                            HStack(spacing: 4) {
                                Button(action: {
                                    let isSelectedLine = (TimelineDataManager.shared.selectedLineID == line.id)
                                    TimelineDataManager.shared.lines.removeAll { $0.id == line.id }
                                    if isSelectedLine {
                                        TimelineDataManager.shared.selectedLineID = nil
                                    }
                                    TimelineDataManager.shared.updateTimelines()
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.red)
                                        .padding(3)
                                        .background(
                                            Circle()
                                                .fill(Color.red.opacity(0.1))
                                        )
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .help(^String.Titles.timelineButtonDeleteTimeline)
                            }
                        }
                        .padding(.leading, 5)
                        .frame(width: 195, height: 30, alignment: .leading)
                        .contextMenu {
                            Button(^String.Titles.timelineButtonDeleteTimeline) {
                                let isSelectedLine = (TimelineDataManager.shared.selectedLineID == line.id)
                                TimelineDataManager.shared.lines.removeAll { $0.id == line.id }
                                if isSelectedLine {
                                    TimelineDataManager.shared.selectedLineID = nil
                                }
                                TimelineDataManager.shared.updateTimelines()
                            }
                        }
                        .onDrag {
                            return NSItemProvider(object: line.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TimelineDropDelegate(
                            currentLine: line,
                            timelineData: timelineData
                        ))
                        .id("name-\(line.id)")
                    }
                }
            }
            .frame(width: 195)
            .padding(.trailing, 5)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.05))
            )
            
            GeometryReader { geo in
                timelineScrollView(
                    geo: geo,
                    effectiveScale: timelineScale * magnifyScale,
                    duration: max(1.0, videoManager.videoDuration),
                    popupInfo: nil,
                    popupLocation: nil
                )
            }
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
        
        let locale = Locale.current.identifier.hasPrefix("ru") ? "ru" : "en"
        print("Locale.current.identifier", Locale.current.identifier)
        guard let url = URL(string: "https://razmetka.youchip.pro/api/generate-interactive-report?locale=\(locale)") else {
            print("Invalid URL")
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
                        self.errorMessage = "Ошибка генерации AI отчета: \(error.localizedDescription)"
                        self.showErrorAlert = true
                        return
                    }
                    
                    guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                        self.errorMessage = "Ошибка: нет данных от сервера"
                        self.showErrorAlert = true
                        return
                    }
                    
                    if httpResponse.statusCode == 200 {
                        self.showHtmlReportInWebView(data: data, teamName: teamName, opponentName: opponentName)
                    } else {
                        var errorMsg = "Ошибка сервера: \(httpResponse.statusCode)"
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
                self.errorMessage = "Ошибка кодирования запроса: \(error.localizedDescription)"
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
        
        let locale = Locale.current.identifier.hasPrefix("ru") ? "ru" : "en"
        guard let url = URL(string: "https://razmetka.youchip.pro/api/generate-match-report?locale=\(locale)") else {
            print("Invalid URL")
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
                        self.errorMessage = "Ошибка генерации простого отчета: \(error.localizedDescription)"
                        self.showErrorAlert = true
                        return
                    }
                    
                    guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                        self.errorMessage = "Ошибка: нет данных от сервера"
                        self.showErrorAlert = true
                        return
                    }
                    
                    if httpResponse.statusCode == 200 {
                        self.saveReportFile(data: data, teamName: teamName, opponentName: opponentName)
                    } else {
                        var errorMsg = "Ошибка сервера: \(httpResponse.statusCode)"
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
                self.errorMessage = "Ошибка кодирования запроса: \(error.localizedDescription)"
                self.showErrorAlert = true
            }
        }
    }
    
    func showHtmlReportInWebView(data: Data, teamName: String, opponentName: String) {
        guard let htmlString = String(data: data, encoding: .utf8) else {
            errorMessage = "Ошибка: не удалось преобразовать данные в HTML"
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
    
    
    @ViewBuilder
    private func compactControlPanel(width: CGFloat) -> some View {
        let isSmallScreen = width < 1700
        
        HStack(alignment: .top, spacing: 12) {
            VideoControlPanelView(
                width: width,
                playbackSpeed: videoManager.playbackSpeed,
                forViewerMode: false,
                actions: .init(
                    seekBackward10: { videoManager.seek(by: -10) },
                    seekBackward5: { videoManager.seek(by: -5) },
                    togglePlayPause: { videoManager.togglePlayPause() },
                    seekForward5: { videoManager.seek(by: 5) },
                    seekForward10: { videoManager.seek(by: 10) },
                    changeSpeed: { videoManager.changePlaybackSpeed(to: $0) }
                )
            )
            
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.timelines)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                if isSmallScreen {
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            if markupMode == .standard {
                                Button {
                                    showAddLineSheet = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.green)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help(^String.Titles.fullControlButtonAddTimeline)
                            }
                            
                            HStack(spacing: 2) {
                                Button(action: {
                                    WindowsManager.shared.setMarkupMode(.standard)
                                }) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "list.bullet")
                                            .font(.system(size: 10))
                                        Text("Standard")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(markupMode == .standard ? Color.blue : Color.gray.opacity(0.1))
                                    .foregroundColor(markupMode == .standard ? .white : .primary)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button(action: {
                                    WindowsManager.shared.setMarkupMode(.tagBased)
                                }) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "tag")
                                            .font(.system(size: 10))
                                        Text("Tags")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(markupMode == .tagBased ? Color.blue : Color.gray.opacity(0.1))
                                    .foregroundColor(markupMode == .tagBased ? .white : .primary)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .help(^String.Titles.fullControlModeHelp)
                            Spacer()
                        }
                        
                        HStack(spacing: 4) {
                            Text("Zoom")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Button {
                                timelineScale = max(1.0, timelineScale - 0.5)
                            } label: {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(CompactButtonStyle(icon: "minus.magnifyingglass", color: .gray))
                            .help(^String.Titles.fullControlButtonTimelineZoomOut)
                            
                            Text(String(format: "%.1fx", timelineScale))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                            
                            Button {
                                timelineScale += 0.5
                            } label: {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(CompactButtonStyle(icon: "plus.magnifyingglass", color: .gray))
                            .help(^String.Titles.fullControlButtonTimelineZoomIn)
                            Spacer()
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        if markupMode == .standard {
                            Button {
                                showAddLineSheet = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help(^String.Titles.fullControlButtonAddTimeline)
                        }
                        
                        HStack(spacing: 2) {
                            Button(action: {
                                WindowsManager.shared.setMarkupMode(.standard)
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "list.bullet")
                                        .font(.system(size: 10))
                                    Text("Standard")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(markupMode == .standard ? Color.blue : Color.gray.opacity(0.1))
                                .foregroundColor(markupMode == .standard ? .white : .primary)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                WindowsManager.shared.setMarkupMode(.tagBased)
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "tag")
                                        .font(.system(size: 10))
                                    Text("Tags")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(markupMode == .tagBased ? Color.blue : Color.gray.opacity(0.1))
                                .foregroundColor(markupMode == .tagBased ? .white : .primary)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .help(^String.Titles.fullControlModeHelp)
                        
                        HStack(spacing: 4) {
                            Text("Zoom")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Button {
                                timelineScale = max(1.0, timelineScale - 0.5)
                            } label: {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(CompactButtonStyle(icon: "minus.magnifyingglass", color: .gray))
                            .help(^String.Titles.fullControlButtonTimelineZoomOut)
                            
                            Text(String(format: "%.1fx", timelineScale))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                            
                            Button {
                                timelineScale += 0.5
                            } label: {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(CompactButtonStyle(icon: "plus.magnifyingglass", color: .gray))
                            .help(^String.Titles.fullControlButtonTimelineZoomIn)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.exportReports)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                if isSmallScreen {
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Menu {
                                Button(^String.Titles.fullControlButtonJSONSimple) {
                                    exportSimpleJSON()
                                }
                                Button(^String.Titles.fullControlButtonJSONFull) {
                                    exportFullJSON()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("JSON")
                                        .font(.system(size: 10, weight: .medium))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.purple.opacity(0.1))
                                .foregroundColor(.purple)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Menu {
                                Button(^String.Titles.fullControlButtonExportTimeline) {
                                    selectedExportType = .currentTimeline
                                    showExportModeSheet = true
                                }
                                Button(^String.Titles.fullControlButtonExportAll) {
                                    selectedExportType = .allTimelines
                                    showExportModeSheet = true
                                }
                                Button(^String.Titles.fullControlButtonExportDrawings) {
                                    selectedExportType = .drawingsTimeline
                                    showExportModeSheet = true
                                }
                                Button(^String.Titles.fullControlButtonExportTags) {
                                    showTagSelectionSheet = true
                                }
                                Button(^String.Titles.fullControlButtonExportLabels) {
                                    showLabelSelectionSheet = true
                                }
                                Button(^String.Titles.fullControlButtonExportEvents) {
                                    showEventSelectionSheet = true
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "video")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Export")
                                        .font(.system(size: 10, weight: .medium))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            Spacer()
                        }
                        
                        HStack(spacing: 8) {
                            Button(^String.Titles.aIReports) {
                                showAiReportSheet = true
                            }
                            .buttonStyle(CompactButtonStyle(icon: "brain", color: .indigo, showText: true))
                            
                        Button(^String.Titles.simpleReport) {
                            showSimpleReportSheet = true
                        }
                        .buttonStyle(CompactButtonStyle(icon: "doc.text", color: .pink, showText: true, text: ^String.Titles.simpleReport))
                        
                        Button(^String.Titles.view) {
                            WindowsManager.shared.showViewerWindow()
                        }
                        .buttonStyle(CompactButtonStyle(icon: "eye", color: .purple, showText: true, text: ^String.Titles.view))
                            Spacer()
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Menu {
                            Button(^String.Titles.fullControlButtonJSONSimple) {
                                exportSimpleJSON()
                            }
                            Button(^String.Titles.fullControlButtonJSONFull) {
                                exportFullJSON()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 12, weight: .medium))
                                Text("JSON")
                                    .font(.system(size: 10, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.1))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Menu {
                            Button(^String.Titles.fullControlButtonExportTimeline) {
                                selectedExportType = .currentTimeline
                                showExportModeSheet = true
                            }
                            Button(^String.Titles.fullControlButtonExportAll) {
                                selectedExportType = .allTimelines
                                showExportModeSheet = true
                            }
                            Button(^String.Titles.fullControlButtonExportDrawings) {
                                selectedExportType = .drawingsTimeline
                                showExportModeSheet = true
                            }
                            Button(^String.Titles.fullControlButtonExportTags) {
                                showTagSelectionSheet = true
                            }
                            Button(^String.Titles.fullControlButtonExportLabels) {
                                showLabelSelectionSheet = true
                            }
                            Button(^String.Titles.fullControlButtonExportEvents) {
                                showEventSelectionSheet = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "video")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Export")
                                    .font(.system(size: 10, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        
                        Button(^String.Titles.aIReports) {
                            showAiReportSheet = true
                        }
                        .buttonStyle(CompactButtonStyle(icon: "brain", color: .indigo, showText: true))
                        
                        
                        Button(^String.Titles.simpleReport) {
                            showSimpleReportSheet = true
                        }
                        .buttonStyle(CompactButtonStyle(icon: "doc.text", color: .pink, showText: true, text: ^String.Titles.simpleReport))
                        
                        Button(^String.Titles.view) {
                            WindowsManager.shared.showViewerWindow()
                        }
                        .buttonStyle(CompactButtonStyle(icon: "eye", color: .purple, showText: true, text: ^String.Titles.view))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(^String.Titles.tools)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                if isSmallScreen {
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Button(^String.Titles.fullControlButtonScreenshots) {
                                WindowsManager.shared.showScreenshots()
                            }
                            .buttonStyle(CompactButtonStyle(icon: "camera", color: .teal, showText: true, text: ^String.Titles.screenshots))
                            Spacer()
                        }
                        
                        HStack(spacing: 8) {
                            Menu {
                                Button(^String.Titles.configureVisualization) {
                                    WindowsManager.shared.showFieldMapConfigurationWindow()
                                }
                                Button(^String.Titles.fullControlButtonMap) {
                                    WindowsManager.shared.showFieldMapVisualizationPicker()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "map")
                                        .font(.system(size: 12, weight: .medium))
                                    Text(^String.Titles.map)
                                        .font(.system(size: 10, weight: .medium))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.brown.opacity(0.1))
                                .foregroundColor(.brown)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            Spacer()
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Button(^String.Titles.fullControlButtonScreenshots) {
                            WindowsManager.shared.showScreenshots()
                        }
                        .buttonStyle(CompactButtonStyle(icon: "camera", color: .teal, showText: true, text: ^String.Titles.screenshots))
                        
                        Menu {
                            Button(^String.Titles.configureVisualization) {
                                WindowsManager.shared.showFieldMapConfigurationWindow()
                            }
                            Button(^String.Titles.fullControlButtonMap) {
                                WindowsManager.shared.showFieldMapVisualizationPicker()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "map")
                                    .font(.system(size: 12, weight: .medium))
                                Text(^String.Titles.map)
                                    .font(.system(size: 10, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.brown.opacity(0.1))
                            .foregroundColor(.brown)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            .disabled(isScreenshotDisplayActive)
            .opacity(isScreenshotDisplayActive ? 0.5 : 1.0)
        }
    }
    
    private func exportSimpleJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(timelineData.lines)
            let panel = NSSavePanel()
            panel.allowedFileTypes = ["json"]
            panel.nameFieldStringValue = "timelines_simple.json"
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            errorMessage = "Ошибка сохранения JSON: \(error.localizedDescription)"
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
            panel.nameFieldStringValue = "timelines_full.json"
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            errorMessage = "Ошибка сохранения полного JSON: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    private func stampHoverPopup(stampInfo: String) -> some View {
        let lines = stampInfo.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 4 else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .trailing, spacing: 6) {
                Text(lines[0].trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.trailing)
                
                Text(lines[1].trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
                
                Text(lines[2].trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                
                Text(lines[3].trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            .frame(maxWidth: 200)
        )
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    compactControlPanel(width: geo.size.width)
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
            .overlay {
                if isExporting {
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
            .onAppear {
                parentWindowHeight = geo.size.height
                setupKeyboardShortcuts()
                
                NotificationCenter.default.addObserver(forName: .editorModeChanged, object: nil, queue: .main) { notification in
                    if let isActive = notification.object as? Bool {
                        self.isEditorModeActive = isActive
                    }
                }
                
                NotificationCenter.default.addObserver(forName: .screenshotDisplayChanged, object: nil, queue: .main) { notification in
                    if let isActive = notification.object as? Bool {
                        self.isScreenshotDisplayActive = isActive
                    }
                }
                
                NotificationCenter.default.addObserver(forName: .markupModeChanged, object: nil, queue: .main) { notification in
                    if let newMode = notification.object as? MarkupMode {
                        self.markupMode = newMode
                    } else {
                        self.markupMode = MarkupMode.current
                    }
                }
                
                NotificationCenter.default.addObserver(
                    forName: .timelineStampHoverChanged,
                    object: nil,
                    queue: .main
                ) { notification in
                    if let userInfo = notification.userInfo {
                        if let stampInfo = userInfo["stampInfo"] as? String {
                            hoveredStampInfo = stampInfo
                        } else {
                            hoveredStampInfo = nil
                        }
                    }
                }
            }
            .onDisappear {
                if let monitor = keyEventMonitor {
                    NSEvent.removeMonitor(monitor)
                }
                NotificationCenter.default.removeObserver(self, name: .editorModeChanged, object: nil)
                NotificationCenter.default.removeObserver(self, name: .screenshotDisplayChanged, object: nil)
                NotificationCenter.default.removeObserver(self, name: .markupModeChanged, object: nil)
                NotificationCenter.default.removeObserver(self, name: .timelineStampHoverChanged, object: nil)
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
        .sheet(item: $stampItemsEditSheetType) { sheetType in
            StampEditSheet(sheetType: sheetType)
        }
        .sheet(isPresented: $showExportModeSheet) {
            ExportModeSelectionSheet(
                onSelect: { mode in
                    isExporting = true
                    exportHelper.performExport(selectedExportType: selectedExportType, mode: mode, withScreenshots: exportWithDrawings) { error in
                        isExporting = false
                        showExportModeSheet = false
                        if let error {
                            showErrorAlert = true
                            errorMessage = error.localizedDescription
                        }
                    }
                },
                exportWithDrawings: $exportWithDrawings
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
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Ошибка"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
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
                    
                    let currentIds = switch sheetType {
                    case .lables:
                        timelineData.lines[lineIndex].stamps[stampIndex].labels
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
                                    timelineData.updateStampLabels(
                                        lineID: lineID,
                                        stampID: stampID,
                                        newLabels: newIds
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
                let tag = tagLibrary.findTagById(stamp.idTag)
                var tagGroup: TagGroupInfo? = nil
                if let tagID = tag?.id {
                    for group in tagLibrary.allTagGroups {
                        if group.tags.contains(tagID) {
                            tagGroup = TagGroupInfo(id: group.id, name: group.name)
                            break
                        }
                    }
                }
                
                let fullTag = FullTagWithGroup(
                    id: tag?.id ?? "",
                    primaryID: tag?.primaryID,
                    name: tag?.name ?? stamp.label,
                    description: tag?.description ?? "",
                    color: tag?.color ?? "FFFFFF",
                    defaultTimeBefore: tag?.defaultTimeBefore ?? 0,
                    defaultTimeAfter: tag?.defaultTimeAfter ?? 0,
                    collection: tag?.collection ?? "",
                    hotkey: tag?.hotkey,
                    labelHotkeys: tag?.labelHotkeys,
                    group: tagGroup
                )
                
                let fullLabels = stamp.labels.compactMap { labelID -> FullLabelWithGroup? in
                    guard let label = tagLibrary.findLabelById(labelID) else { return nil }
                    
                    var labelGroup: LabelGroupInfo? = nil
                    for group in tagLibrary.allLabelGroups {
                        if group.lables.contains(labelID) {
                            labelGroup = LabelGroupInfo(id: group.id, name: group.name)
                            break
                        }
                    }
                    
                    return FullLabelWithGroup(
                        id: label.id,
                        name: label.name,
                        description: label.description,
                        group: labelGroup
                    )
                }
                
                let fullTimeEvents = stamp.timeEvents.compactMap { eventID in
                    tagLibrary.allTimeEvents.first(where: { $0.id == eventID })
                }
                
                return FullTimelineStamp(
                    id: stamp.id,
                    timeStart: stamp.timeStartString,
                    timeFinish: stamp.timeFinishString,
                    tag: fullTag,
                    labels: fullLabels,
                    timeEvents: fullTimeEvents,
                    position: stamp.position
                )
            }
            
            return FullTimelineLine(id: line.id, name: line.name, stamps: fullStamps)
        }
    }
    
    func uniqueLabelsFromTimelines() -> [Label] {
        let labelIDs = timelineData.lines.flatMap { line in
            line.stamps.flatMap { stamp in
                stamp.labels
            }
        }
        
        let uniqueLabelIDs = Array(Set(labelIDs))
        
        let labels = TagLibraryManager.shared.allLabels.filter { label in
            return uniqueLabelIDs.contains(label.id)
        }
        
        return labels
    }

    func labelsForTag(_ tag: Tag) -> [Label] {
        let labelIDs = timelineData.lines.flatMap { line in
            line.stamps.filter { $0.idTag == tag.id }
                .flatMap { $0.labels }
        }
        
        let uniqueLabelIDs = Array(Set(labelIDs))
        
        let labels = TagLibraryManager.shared.allLabels.filter { uniqueLabelIDs.contains($0.id) }
        return labels
    }

    func tagsForLabel(_ label: Label) -> [Tag] {
        let tagIDs = timelineData.lines.flatMap { line in
            line.stamps.filter { $0.labels.contains(label.id) }
                .map { $0.idTag }
        }
        
        let uniqueTagIDs = Array(Set(tagIDs))
        
        let tags = TagLibraryManager.shared.allTags.filter { uniqueTagIDs.contains($0.id) }
        return tags
    }
    
    func uniqueTagsFromTimelines() -> [Tag] {
        let tagIDs = timelineData.lines.flatMap { line in
            line.stamps.flatMap { stamp in
                [stamp.idTag]
            }
        }
        
        let uniqueTagIDs = Array(Set(tagIDs))
        
        let tags = TagLibraryManager.shared.allTags.filter { tag in
            return uniqueTagIDs.contains { $0 == tag.id }
        }
        
        return tags
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
    
    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [.text]).first else {
            return false
        }
        
        itemProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { (item, error) in
            if let data = item as? Data,
               let draggedLineIDString = String(data: data, encoding: .utf8),
               let draggedLineID = UUID(uuidString: draggedLineIDString),
               draggedLineID != currentLine.id {
                
                DispatchQueue.main.async {
                    reorderTimelines(draggedID: draggedLineID, targetID: currentLine.id)
                }
            }
        }
        
        return true
    }
    
    func dropEntered(info: DropInfo) {
    }
    
    func dropExited(info: DropInfo) {
    }
    
    private func reorderTimelines(draggedID: UUID, targetID: UUID) {
        guard let draggedIndex = timelineData.lines.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = timelineData.lines.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        
        let draggedLine = timelineData.lines.remove(at: draggedIndex)
        let newTargetIndex = draggedIndex < targetIndex ? targetIndex - 1 : targetIndex
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
    let onStampUpdate: (String?, CGPoint?) -> Void
    
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
        var onStampUpdate: ((String?, CGPoint?) -> Void)?
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
            
            let options: NSTrackingArea.Options = [
                .activeInKeyWindow,
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
            
            let foundStamp = line.stamps.first { stamp in
                clampedTime >= stamp.timeStartSeconds && clampedTime <= stamp.timeFinishSeconds
            }
            
            if let stamp = foundStamp, let tagLibrary = tagLibrary {
                let tag = tagLibrary.findTagById(stamp.idTag)
                let tagName = tag?.name ?? stamp.label
                
                let labelNames = stamp.labels.compactMap { labelID in
                    tagLibrary.findLabelById(labelID)?.name
                }
                let labelsString = labelNames.isEmpty ? "—" : labelNames.joined(separator: ", ")
                
                let startTime = formatTimeStringCompact(stamp.timeStartSeconds)
                let durationTime = formatTimeStringCompact(stamp.duration)
                
                let info = """
                \(tagName)
                \(line.name)
                \(labelsString)
                \(startTime) • \(durationTime)
                """
                
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
    let duration: Double
    let gridWidth: CGFloat
    let totalHeight: CGFloat
    
    @ObservedObject var screenshotsManager = ScreenshotsMetadataManager.shared
    @ObservedObject var videoManager = VideoPlayerManager.shared
    @ObservedObject var timelineData = TimelineDataManager.shared
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    
    @State private var hoveredScreenshot: String? = nil
    @State private var showScreenshotTagEditor: Bool = false
    @State private var editingScreenshot: ScreenshotMetadata? = nil
    @State private var isFirstOpen: Bool = true
    
    private func getCurrentFile() -> FilesFile? {
        guard let currentBookmark = timelineData.currentBookmark else {
            return nil
        }
        return VideoFilesManager.shared.files.first(where: { $0.videoData.bookmark == currentBookmark })
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(screenshotsManager.screenshots, id: \.screenshotName) { screenshot in
                if screenshotFileExists(for: screenshot) {
                    screenshotMarker(for: screenshot)
                }
            }
        }
        .sheet(isPresented: $showScreenshotTagEditor) {
            if let screenshot = editingScreenshot {
                ScreenshotTagEditorSheet(
                    screenshot: screenshot,
                    onSave: { updatedStampIds in
                        screenshotsManager.updateScreenshotRelatedStamps(
                            screenshotName: screenshot.screenshotName,
                            relatedStampIds: updatedStampIds
                        )
                        showScreenshotTagEditor = false
                        editingScreenshot = nil
                    },
                    onCancel: {
                        showScreenshotTagEditor = false
                        editingScreenshot = nil
                    }
                )
            }
        }
        .onChange(of: showScreenshotTagEditor) { isShowing in
            // При первом открытии делаем мгновенное переоткрытие для обновления данных
            if isShowing && isFirstOpen {
                isFirstOpen = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    // showScreenshotTagEditor = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        showScreenshotTagEditor = true
                    }
                }
            }
        }
    }
    
    private func screenshotFileExists(for screenshot: ScreenshotMetadata) -> Bool {
        guard let filesFile = getCurrentFile() else {
            return false
        }
        
        let screenshotsFolder = filesFile.screenshotsFolder
        let imageFileName = screenshot.screenshotName.hasSuffix(".png") ? screenshot.screenshotName : "\(screenshot.screenshotName).png"
        let imageURL = screenshotsFolder.appendingPathComponent(imageFileName)
        
        return FileManager.default.fileExists(atPath: imageURL.path)
    }
    
    private func screenshotMarker(for screenshot: ScreenshotMetadata) -> some View {
        let xPosition = duration > 0 ? (screenshot.videoTime / duration) * gridWidth - 7 : 0
        let hasRelatedTags = !screenshot.relatedStampIds.isEmpty
        
        return VStack(spacing: 0) {
            Button(action: {
                videoManager.seek(to: screenshot.videoTime)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    videoManager.player?.pause()
                }
            }) {
                Image(systemName: hasRelatedTags ? "pencil.circle.fill" : "pencil.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(hasRelatedTags ? Color.blue.opacity(0.7) : Color.gray.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Перейти к скриншоту: \(formatTime(screenshot.videoTime))")
            .padding(.bottom, 2)
            .contextMenu {
                Button("Редактировать") {
                    openScreenshotInEditor(screenshot)
                }
                
                let availableStamps = getAvailableStampsForScreenshot(screenshot)
                if !availableStamps.isEmpty {
                    Button("Редактировать привязанные теги") {
                        editingScreenshot = screenshot
                        showScreenshotTagEditor = true
                    }
                }
                
                Button("Удалить") {
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
            
            Rectangle()
                .fill(hasRelatedTags ? Color.blue.opacity(0.5) : Color.gray.opacity(0.5))
                .frame(width: 2, height: totalHeight)
        }
        .offset(x: xPosition - 1)
    }
    
    private func screenshotTagsPopover(for screenshot: ScreenshotMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Связанные теги")
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
            if line.isDrawingsTimeline { continue }
            
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
        guard let filesFile = getCurrentFile() else {
            print("❌ Не найден filesFile для удаления скриншота")
            return
        }
        
        let screenshotsFolder = filesFile.screenshotsFolder
        let imageFileName = screenshot.screenshotName.hasSuffix(".png") ? screenshot.screenshotName : "\(screenshot.screenshotName).png"
        let imageURL = screenshotsFolder.appendingPathComponent(imageFileName)
        let jsonURL = screenshotsFolder.appendingPathComponent("\(screenshot.screenshotName).json")
        
        do {
            if FileManager.default.fileExists(atPath: imageURL.path) {
                try FileManager.default.removeItem(at: imageURL)
                print("✅ Удален файл изображения: \(imageFileName)")
            }
            
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                try FileManager.default.removeItem(at: jsonURL)
                print("✅ Удален файл метаданных: \(screenshot.screenshotName).json")
            }
        } catch {
            print("❌ Ошибка удаления файлов скриншота: \(error.localizedDescription)")
            return
        }
        
        // Удаляем штамп с таймлайна "скриншоты"
        deleteScreenshotStampFromTimeline(screenshotName: screenshot.screenshotName)
        
        // Удаляем из менеджера
        screenshotsManager.removeScreenshot(screenshotName: screenshot.screenshotName)
    }
    
    /// Перематывает видео на момент скриншота и открывает редактор с восстановлением состояния из метаданных (все объекты снова редактируемые).
    private func openScreenshotInEditor(_ screenshot: ScreenshotMetadata) {
        guard let filesFile = getCurrentFile() else {
            print("❌ Не найден текущий файл для открытия редактора")
            return
        }
        let payload = OpenEditorForScreenshotPayload(
            screenshot: screenshot,
            screenshotsFolder: filesFile.screenshotsFolder,
            videoId: filesFile.videoData.id
        )
        NotificationCenter.default.post(name: .openEditorForScreenshot, object: payload)
    }
    
    private func deleteScreenshotStampFromTimeline(screenshotName: String) {
        guard let screenshotLine = timelineData.lines.first(where: { $0.isDrawingsTimeline }) else {
            print("ℹ️ Таймлайн рисунков не найден")
            return
        }
        
        // Проверяем, существует ли файл скриншота (если файл удален, значит можно удалять штамп)
        guard let filesFile = getCurrentFile() else {
            print("❌ Не найден filesFile для проверки скриншота")
            return
        }
        
        let screenshotsFolder = filesFile.screenshotsFolder
        let imageFileName = screenshotName.hasSuffix(".png") ? screenshotName : "\(screenshotName).png"
        let imageURL = screenshotsFolder.appendingPathComponent(imageFileName)
        
        // Если файл скриншота не существует, удаляем штамп с таймлайна
        if !FileManager.default.fileExists(atPath: imageURL.path) {
            // Ищем штамп с именем, совпадающим с именем скриншота
            if let stamp = screenshotLine.stamps.first(where: { stamp in
                stamp.label == screenshotName || stamp.label.contains(screenshotName)
            }) {
                let stampID = stamp.id
                let stampLabel = stamp.label
                timelineData.removeStamp(lineID: screenshotLine.id, stampID: stampID)
                print("✅ Удален штамп '\(stampLabel)' с таймлайна скриншотов (файл не существует)")
            } else {
                print("ℹ️ Штамп с именем '\(screenshotName)' не найден на таймлайне скриншотов")
            }
        } else {
            print("ℹ️ Файл скриншота '\(screenshotName)' существует, штамп не удаляется")
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
    
    // Вычисляем доступные штампы динамически
    private var availableStamps: [(line: TimelineLine, stamp: TimelineStamp)] {
        var stamps: [(line: TimelineLine, stamp: TimelineStamp)] = []
        
        for line in timelineData.lines {
            if line.isDrawingsTimeline { continue }
            
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
            Text("Редактирование привязанных тегов")
                .font(.headline)
                .padding(.top)
            
            Text("Скриншот: \(formatTime(screenshot.videoTime))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
            if availableStamps.isEmpty {
                Text("Нет доступных тегов для привязки")
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
                                    
                                    Text("Таймлайн: \(line.name)")
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
                Button("Отмена") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("Сохранить") {
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
