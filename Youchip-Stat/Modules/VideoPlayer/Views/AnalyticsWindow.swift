import SwiftUI
import AppKit
import AVKit
import Charts
import Foundation
import UniformTypeIdentifiers

// Структуры данных для аналитики
struct TagStatistics {
    let tagName: String
    let duration: Double
    let percentage: Double
    let color: Color
}

struct TagUsageTimePoint {
    let timeLabel: String
    let timeMark: Double
    let tagCounts: [String: Int]
}

struct TopLabelUsage: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
}

struct TagDurationStat: Identifiable {
    var id: String { tagName }
    let tagName: String
    let averageDuration: Double
    let minDuration: Double
    let maxDuration: Double
    let color: Color
}

struct LabelUsage {
    let label: String
    let count: Int
}

struct TagDensityPoint {
    let time: Double
    let count: Int
}

struct TimelineStatistics {
    let name: String
    let tagCount: Int
    let totalDuration: Double
    let tagPercentages: [(tagName: String, percentage: Double)] // Добавляем информацию о процентах
}

// PieChartView для отображения круговой диаграммы
struct PieChartView: View {
    let statistics: [TagStatistics]

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2
            
            // Вычисляем начальные и конечные углы для каждого сегмента
            let angles = calculateAngles(for: statistics)
            
            ZStack {
                ForEach(0..<statistics.count, id: \.self) { index in
                    let startAngle = angles[index].start
                    let endAngle = angles[index].end
                    
                    Path { path in
                        path.move(to: center)
                        path.addArc(center: center, radius: radius, startAngle: Angle(degrees: startAngle), endAngle: Angle(degrees: endAngle), clockwise: false)
                        path.closeSubpath()
                    }
                    .fill(statistics[index].color)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func calculateAngles(for statistics: [TagStatistics]) -> [(start: Double, end: Double)] {
        var currentStartAngle: Double = 0.0
        var angles: [(start: Double, end: Double)] = []
        
        for stat in statistics {
            // Используем сразу проценты из статистики и преобразуем в углы
            let angle = (stat.percentage / 100) * 360.0
            let endAngle = currentStartAngle + angle
            angles.append((start: currentStartAngle, end: endAngle))
            currentStartAngle = endAngle
        }
        
        return angles
    }
}

// Легенда для отображения информации о тегах
struct TagStatisticsLegend: View {
    let statistics: [TagStatistics]
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(statistics, id: \.tagName) { stat in
                HStack {
                    Circle()
                        .fill(stat.color)
                        .frame(width: 12, height: 12)
                    Text("\(stat.tagName): \(Int(stat.duration)) шт. (\(String(format: "%.1f", stat.percentage))%)")
                        .font(.subheadline)
                }
            }
        }
        .padding()
    }
}

// Основной экран для аналитики
@available(macOS 12.0, *)
struct AnalyticsView: View {
    @ObservedObject var timelineData = TimelineDataManager.shared
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    
    private var tagUsageOverTime: [TagUsageTimePoint] {
            let videoLength = VideoPlayerManager.shared.videoDuration
            let intervalMinutes = 5.0 // 5-minute intervals
            let intervalSeconds = intervalMinutes * 60.0
            var timePoints: [TagUsageTimePoint] = []
            
            for startTime in stride(from: 0.0, to: videoLength, by: intervalSeconds) {
                let endTime = min(startTime + intervalSeconds, videoLength)
                let interval = (startTime, endTime)
                
                // Count tags per interval by type
                var tagCounts: [String: Int] = [:]
                
                for stamp in timelineData.lines.flatMap({ $0.stamps }) {
                    let stampStart = timeStringToSeconds(stamp.timeStart)
                    let stampEnd = timeStringToSeconds(stamp.timeFinish)
                    
                    // If the stamp overlaps with this interval
                    if max(stampStart, startTime) < min(stampEnd, endTime) {
                        tagCounts[stamp.label, default: 0] += 1
                    }
                }
                
                // Create time point for this interval
                let timePoint = TagUsageTimePoint(
                    timeLabel: "\(Int(startTime / 60))-\(Int(endTime / 60)) min",
                    timeMark: startTime,
                    tagCounts: tagCounts
                )
                timePoints.append(timePoint)
            }
            
            return timePoints
        }
        
        // Add property for top-used labels
        private var topUsedLabels: [TopLabelUsage] {
            // Collect all label usages across all tags
            var allLabelCounts: [String: Int] = [:]
            
            for (_, labelUsages) in labelStatistics {
                for usage in labelUsages {
                    allLabelCounts[usage.label, default: 0] += usage.count
                }
            }
            
            // Sort and return top 10
            return allLabelCounts.map { label, count in
                TopLabelUsage(label: label, count: count)
            }.sorted { $0.count > $1.count }.prefix(10).map { $0 }
        }
        
        // Add property for tag duration statistics
        private var tagDurationStats: [TagDurationStat] {
            let allStamps = timelineData.lines.flatMap { $0.stamps }
            
            // Calculate average, min, max duration for each tag type
            var statsByTag: [String: (count: Int, total: Double, min: Double, max: Double)] = [:]
            
            for stamp in allStamps {
                if let stats = statsByTag[stamp.label] {
                    let newMin = min(stats.min, stamp.duration)
                    let newMax = max(stats.max, stamp.duration)
                    statsByTag[stamp.label] = (stats.count + 1, stats.total + stamp.duration, newMin, newMax)
                } else {
                    statsByTag[stamp.label] = (1, stamp.duration, stamp.duration, stamp.duration)
                }
            }
            
            return statsByTag.map { tagName, stats in
                let tag = tagLibrary.tags.first { $0.name == tagName }
                return TagDurationStat(
                    tagName: tagName,
                    averageDuration: stats.total / Double(stats.count),
                    minDuration: stats.min,
                    maxDuration: stats.max,
                    color: tag.map { Color(hex: $0.color) } ?? .gray
                )
            }.sorted { $0.averageDuration > $1.averageDuration }
        }
    
    // Вычисленные статистики для тегов
    // Вычисленные статистики для тегов (по количеству, а не по длительности)
    private var tagStatistics: [TagStatistics] {
        let allStamps = timelineData.lines.flatMap { $0.stamps }
        
        if allStamps.isEmpty {
            return []
        }
        
        // Считаем количество каждого тега
        var statsByTag: [String: Int] = [:]
        for stamp in allStamps {
            statsByTag[stamp.label, default: 0] += 1
        }
        
        let totalCount = allStamps.count
        
        // Сортируем по убыванию количества
        let sortedStats = statsByTag.sorted { $0.value > $1.value }
        var result: [TagStatistics] = []
        
        // Рассчитываем точные проценты, чтобы в сумме получалось 100%
        var accumulatedPercentage = 0.0
        for (i, (tagName, count)) in sortedStats.enumerated() {
            let tag = tagLibrary.tags.first { $0.name == tagName }
            let percentage: Double
            
            // Для последнего элемента вычисляем процент так, чтобы сумма была ровно 100%
            if i == sortedStats.count - 1 {
                percentage = 100.0 - accumulatedPercentage
            } else {
                percentage = Double(count) / Double(totalCount) * 100
                accumulatedPercentage += percentage
            }
            
            result.append(TagStatistics(
                tagName: tagName,
                duration: Double(count), // используем поле duration для хранения количества
                percentage: percentage,
                color: tag.map { Color(hex: $0.color) } ?? .gray
            ))
        }
        
        return result
    }
    
    // Статистика использования лейблов
    private var labelStatistics: [String: [LabelUsage]] {
        var stats: [String: [String: Int]] = [:]
        
        for stamp in timelineData.lines.flatMap({ $0.stamps }) {
            if !stats.keys.contains(stamp.label) {
                stats[stamp.label] = [:]
            }
            
            for labelId in stamp.labels {
                if let label = tagLibrary.labels.first(where: { $0.id == labelId }) {
                    stats[stamp.label]?[label.name, default: 0] += 1
                }
            }
        }
        
        return stats.mapValues { labelCounts in
            labelCounts.map { LabelUsage(label: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
        }
    }
    
    // Плотность тегов по времени
    private var tagDensity: [TagDensityPoint] {
        let videoLength = VideoPlayerManager.shared.videoDuration
        // Используем переменный интервал, чтобы ограничить общее количество точек
        let totalPointsTarget = 5400 // Ограничиваем количество точек
        let interval = max(1.0, videoLength / Double(totalPointsTarget))
        var points: [TagDensityPoint] = []
        
        // Предварительно вычисляем все метки и их временные интервалы
        let allStamps = timelineData.lines.flatMap { $0.stamps }
        let stampRanges = allStamps.map { stamp -> (start: Double, end: Double) in
            let start = timeStringToSeconds(stamp.timeStart)
            let end = timeStringToSeconds(stamp.timeFinish)
            return (start, end)
        }
        
        for time in stride(from: 0.0, to: videoLength, by: interval) {
            // Считаем только один раз для каждого времени
            let count = stampRanges.filter { time >= $0.start && time <= $0.end }.count
            points.append(TagDensityPoint(time: time, count: count))
        }
        
        return points
    }
    
    // Статистика по таймлайнам
    private var timelineStats: [TimelineStatistics] {
        timelineData.lines.map { line in
            let totalDuration = line.stamps.reduce(0.0) { $0 + $1.duration }
            
            // Расчёт статистики по тегам в таймлайне
            let statsByTag: [String: Double] = line.stamps.reduce(into: [:]) { result, stamp in
                result[stamp.label, default: 0] += stamp.duration
            }
            
            let tagPercentages = statsByTag.map { tagName, duration in
                (tagName, (duration / totalDuration) * 100)
            }
            
            return TimelineStatistics(
                name: line.name,
                tagCount: line.stamps.count,
                totalDuration: totalDuration,
                tagPercentages: tagPercentages // Добавляем процентные соотношения тегов
            )
        }
    }
    
    // Аномалии
    var anomalies: [String] {
        var issues: [String] = []
        
        // Проверка на очень короткие события
        let shortStamps = timelineData.lines.flatMap { $0.stamps }.filter { $0.duration < 1.0 }
        if !shortStamps.isEmpty {
            issues.append("Найдены очень короткие события (меньше 1 секунды): \(shortStamps.count) шт.")
        }
        
        // Проверка на таймлайны без тегов
        let emptyTimelines = timelineData.lines.filter { $0.stamps.isEmpty }
        if !emptyTimelines.isEmpty {
            issues.append("Таймлайны без разметки: \(emptyTimelines.map { $0.name }.joined(separator: ", "))")
        }
        
        // Проверка на перекрытие тегов одного типа
        for line in timelineData.lines {
            let stamps = line.stamps.sorted { timeStringToSeconds($0.timeStart) < timeStringToSeconds($1.timeStart) }
            for i in 0..<stamps.count {
                if i + 1 < stamps.count {
                    let current = stamps[i]
                    let next = stamps[i + 1]
                    if current.label == next.label && timeStringToSeconds(current.timeFinish) > timeStringToSeconds(next.timeStart) {
                        issues.append("Перекрытие тегов '\(current.label)' в таймлайне '\(line.name)'")
                    }
                }
            }
        }
        
        return issues
    }
    
    // Тело вью
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Секция общей статистики
                SummarySection()
                
                // Секция распределения тегов
                TagDistributionSection()
                
                // Секция статистики по лейблам
                LabelUsageSection()
                
                // Секция статистики по таймлайнам
                TimelineStatisticsSection()
                
                // Секция аномалий
                AnomaliesSection()
                
                TagDensitySection()
                
                TagUsageOverTimeSection()
                
                TopLabelsSection()
                
                TagDurationStatsSection()
                
                HeatmapSection()
                
                AnomaliesSection()
            }
            .padding()
        }
    }
    
    // New section for tag density chart
        @ViewBuilder
        func TagDensitySection() -> some View {
            Text("Плотность тегов во времени")
                .font(.title)
            
            if #available(macOS 13.0, *) {
                Chart(tagDensity, id: \.time) { point in
                    LineMark(
                        x: .value("Время", point.time),
                        y: .value("Количество тегов", point.count)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Время", point.time),
                        y: .value("Количество тегов", point.count)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue.opacity(0.3), .blue.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxisLabel("Время видео (секунды)")
                .chartYAxisLabel("Количество активных тегов")
                .frame(height: 250)
            } else {
                Text("График плотности тегов доступен в macOS 13.0 и выше")
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if let maxDensity = tagDensity.max(by: { $0.count < $1.count }) {
                    Text("Пик плотности тегов: \(maxDensity.count) тегов на \(secondsToTimeString(maxDensity.time))")
                        .font(.headline)
                }
                
                let avgDensity = tagDensity.reduce(0.0) { $0 + Double($1.count) } / Double(max(1, tagDensity.count))
                Text("Средняя плотность тегов: \(String(format: "%.1f", avgDensity))")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        
        // New section for tag usage over time
        @ViewBuilder
        func TagUsageOverTimeSection() -> some View {
            Text("Распределение тегов по ходу видео")
                .font(.title)
            
            if #available(macOS 13.0, *), !tagUsageOverTime.isEmpty {
                Chart {
                    ForEach(tagLibrary.tags.prefix(5), id: \.id) { tag in
                        ForEach(tagUsageOverTime, id: \.timeLabel) { timePoint in
                            if let count = timePoint.tagCounts[tag.name], count > 0 {
                                BarMark(
                                    x: .value("Время", timePoint.timeLabel),
                                    y: .value("Количество", count)
                                )
                                .foregroundStyle(Color(hex: tag.color))
                                .position(by: .value("Тег", tag.name))
                            }
                        }
                    }
                }
                .chartXAxisLabel("Временные интервалы (минуты)")
                .chartYAxisLabel("Количество тегов")
                .frame(height: 300)
            } else {
                Text("График распределения тегов доступен в macOS 13.0 и выше")
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Этот график показывает, как разные типы тегов распределены по длительности видео")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        
        // New section for top labels bar chart
        @ViewBuilder
        func TopLabelsSection() -> some View {
            Text("Наиболее используемые лейблы")
                .font(.title)
            
            if #available(macOS 13.0, *), !topUsedLabels.isEmpty {
                Chart(topUsedLabels) { label in
                    BarMark(
                        x: .value("Количество", label.count),
                        y: .value("Лейбл", label.label)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
                .chartXAxisLabel("Количество использований")
                .frame(height: 300)
            } else {
                Text("График топ-лейблов доступен в macOS 13.0 и выше")
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Самые популярные лейблы по всем типам тегов")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        
        // New section for tag duration statistics
        @ViewBuilder
        func TagDurationStatsSection() -> some View {
            Text("Статистика длительности тегов")
                .font(.title)
            
            if #available(macOS 13.0, *), !tagDurationStats.isEmpty {
                Chart(tagDurationStats) { stat in
                    BarMark(
                        x: .value("Тег", stat.tagName),
                        y: .value("Средняя длительность", stat.averageDuration)
                    )
                    .foregroundStyle(stat.color)
                    
                    RectangleMark(
                        x: .value("Тег", stat.tagName),
                        yStart: .value("Мин. длительность", stat.minDuration),
                        yEnd: .value("Макс. длительность", stat.maxDuration),
                        width: 20
                    )
                    .foregroundStyle(stat.color.opacity(0.3))
                }
                .chartYAxisLabel("Длительность (секунды)")
                .frame(height: 300)
            } else {
                Text("График статистики длительности доступен в macOS 13.0 и выше")
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Статистика длительности тегов по типам")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Столбцы показывают среднюю длительность, а вертикальные линии - диапазон от минимальной до максимальной длительности")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        
        // New section for heatmap visualization
        @ViewBuilder
        func HeatmapSection() -> some View {
            Text("Тепловая карта активности")
                .font(.title)
            
            VStack(alignment: .center) {
                ZStack {
                    // Background grid
                    VStack(spacing: 0) {
                        ForEach(0..<10, id: \.self) { _ in
                            HStack(spacing: 0) {
                                ForEach(0..<20, id: \.self) { _ in
                                    Rectangle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        .background(Color.gray.opacity(0.05))
                                        .aspectRatio(1, contentMode: .fit)
                                }
                            }
                        }
                    }
                    
                    // Heat points based on tag density
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        let height = geometry.size.height
                        let videoLength = VideoPlayerManager.shared.videoDuration
                        
                        ForEach(tagDensity.indices, id: \.self) { index in
                            let point = tagDensity[index]
                            let x = width * (point.time / videoLength)
                            let maxCount = tagDensity.map { $0.count }.max() ?? 1
                            let intensity = Double(point.count) / Double(maxCount)
                            
                            Circle()
                                .fill(
                                    Color(
                                        hue: 0.6 - (0.6 * intensity),
                                        saturation: 0.8,
                                        brightness: 0.9
                                    )
                                )
                                .opacity(0.7)
                                .frame(width: 15 + (20 * intensity), height: 15 + (20 * intensity))
                                .position(x: x, y: height / 2)
                        }
                    }
                }
                .frame(height: 200)
                
                // Legend for heatmap
                HStack(spacing: 0) {
                    ForEach(0..<5) { i in
                        let intensity = Double(i) / 4.0
                        VStack {
                            Rectangle()
                                .fill(
                                    Color(
                                        hue: 0.6 - (0.6 * intensity),
                                        saturation: 0.8,
                                        brightness: 0.9
                                    )
                                )
                                .frame(height: 20)
                            Text(i == 0 ? "Низкая" : i == 4 ? "Высокая" : "")
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal, 40)
                
                Text("Плотность тегов по временной шкале видео")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    
    // Секция общей статистики
    @ViewBuilder
    func SummarySection() -> some View {
        Text("Общая статистика")
            .font(.title)
        
        VStack(alignment: .leading, spacing: 10) {
            Text("Количество таймлайнов: \(timelineData.lines.count)")
            Text("Общее количество тегов: \(timelineData.lines.flatMap { $0.stamps }.count)")
            if let totalDuration = timelineData.lines.flatMap({ $0.stamps }).map({ $0.duration }).reduce(0, +) as Double? {
                Text("Общая длительность разметки: \(secondsToTimeString(totalDuration))")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    // Секция распределения тегов
    @ViewBuilder
    func TagDistributionSection() -> some View {
        Text("Распределение тегов")
            .font(.title)
        
        HStack {
            // Круговая диаграмма
            PieChartView(statistics: tagStatistics)
                .frame(width: 200, height: 200)
            
            // Легенда
            TagStatisticsLegend(statistics: tagStatistics)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    // Секция статистики по лейблам
    @ViewBuilder
    func LabelUsageSection() -> some View {
        Text("Статистика по лейблам")
            .font(.title)
        
        ForEach(Array(labelStatistics.keys.sorted()), id: \.self) { tagName in
            if let stats = labelStatistics[tagName]?.prefix(5) {
                VStack(alignment: .leading) {
                    Text("Тег: \(tagName)")
                        .font(.headline)
                    ForEach(stats, id: \.label) { usage in
                        Text("\(usage.label): \(usage.count)")
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    // Секция статистики по таймлайнам
    @ViewBuilder
    func TimelineStatisticsSection() -> some View {
        Text("Статистика по таймлайнам")
            .font(.title)
        
        ForEach(timelineStats, id: \.name) { stat in
            VStack(alignment: .leading) {
                Text(stat.name)
                    .font(.headline)
                Text("Количество тегов: \(stat.tagCount)")
                Text("Общая длительность: \(secondsToTimeString(stat.totalDuration))")
                
                // Показать процентное соотношение тегов в таймлайне
                ForEach(stat.tagPercentages, id: \.tagName) { tagData in
                    Text("\(tagData.tagName): \(String(format: "%.1f", tagData.percentage))%")
                        .font(.subheadline)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // Секция аномалий
    @ViewBuilder
    func AnomaliesSection() -> some View {
        if !anomalies.isEmpty {
            Text("Обнаруженные проблемы")
                .font(.title)
            
            ForEach(anomalies, id: \.self) { issue in
                Text("• \(issue)")
                    .foregroundColor(.red)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

class AnalyticsWindowController: NSWindowController, NSWindowDelegate {
    init() {
        if #available(macOS 12.0, *) {
            let view = AnalyticsView()
            let hostingController = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Аналитика разметки"
            super.init(window: window)
            window.styleMask.insert(NSWindow.StyleMask.closable)
            window.delegate = self
            window.makeKeyAndOrderFront(nil)
            
            // Set window size and position
            if let screen = NSScreen.main {
                let screenFrame = screen.frame
                let windowSize = NSSize(width: 800, height: 600)
                let windowOrigin = NSPoint(
                    x: screenFrame.midX - windowSize.width/2,
                    y: screenFrame.midY - windowSize.height/2
                )
                window.setFrame(NSRect(origin: windowOrigin, size: windowSize), display: true)
            }
            
            // Add toolbar with export button
            setupToolbar()
        } else {
            let window = NSWindow()
            super.init(window: window)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowWillClose(_ notification: Notification) {
        self.window?.delegate = nil
        WindowsManager.shared.analyticsWindow = nil
    }
    
    // Setup toolbar with export button
    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "AnalyticsToolbar")
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        window?.toolbar = toolbar
    }
    
    // Изменяем метод и название с exportAsPDF на exportAsImage
    @objc func exportAsImage(_ sender: Any) {
        guard let window = self.window else { return }
        
        // Create save panel
        let savePanel = NSSavePanel()
        savePanel.title = "Экспорт аналитики в изображение"
        savePanel.nameFieldStringValue = "Аналитика_разметки.png"
        savePanel.allowedContentTypes = [UTType.jpeg]
        savePanel.canCreateDirectories = true
        
        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            if #available(macOS 12.0, *) {
                self?.captureScrollViewAndExportAsImage(to: url)
            }
        }
    }

    @available(macOS 12.0, *)
    private func captureScrollViewAndExportAsImage(to url: URL) {
        guard let window = self.window else { return }
        
        // Показываем индикатор прогресса
        let progressView = NSView(frame: NSRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height))
        progressView.wantsLayer = true
        progressView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        
        let progressIndicator = NSProgressIndicator(frame: NSRect(x: window.frame.width/2 - 30, y: window.frame.height/2 - 30, width: 60, height: 60))
        progressIndicator.style = .spinning
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        
        let label = NSTextField(frame: NSRect(x: window.frame.width/2 - 100, y: window.frame.height/2 + 40, width: 200, height: 30))
        label.stringValue = "Создание изображения..."
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.textColor = .white
        
        progressView.addSubview(progressIndicator)
        progressView.addSubview(label)
        window.contentView?.addSubview(progressView)
        
        // Используем временное представление без ScrollView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Найдем ScrollView внутри иерархии представлений
            if let scrollView = self.findScrollView(in: window.contentView) {
                // Получаем документ
                if let documentView = scrollView.documentView {
                    // Сохраняем текущие позиции прокрутки
                    let savedOrigin = scrollView.contentView.bounds.origin
                    
                    // Получаем полные размеры контента
                    let fullBounds = documentView.bounds
                    let totalHeight = documentView.bounds.height
                    let viewportHeight = scrollView.contentView.bounds.height
                    let viewportWidth = scrollView.contentView.bounds.width
                    
                    var imageParts: [NSImage] = []
                    
                    // Начинаем с верхней части документа и идем вниз
                    // Создаем массив смещений для прокрутки в правильном порядке сверху вниз
                    let yOffsets = stride(from: 0.0, to: totalHeight, by: viewportHeight).map { $0 }
                    
                    // Захватываем содержимое по частям
                    for yOffset in yOffsets {
                        // Прокручиваем к этой позиции
                        scrollView.contentView.scroll(to: NSPoint(x: 0, y: yOffset))
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                        
                        // Даем время на обновление представления
                        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
                        
                        // Определяем высоту этой части
                        let partHeight = min(viewportHeight, totalHeight - yOffset)
                        
                        // Захватываем часть содержимого
                        let partRect = NSRect(x: 0, y: yOffset, width: viewportWidth, height: partHeight)
                        let partImage = documentView.bitmapImageRepForCachingDisplay(in: partRect)
                        documentView.cacheDisplay(in: partRect, to: partImage!)
                        
                        let image = NSImage(size: NSSize(width: viewportWidth, height: partHeight))
                        image.addRepresentation(partImage!)
                        image.backgroundColor = NSColor.windowBackgroundColor
                        
                        // Добавляем изображение в начало массива, чтобы сохранить правильный порядок
                        imageParts.insert(image, at: 0)
                        
                        // Обновляем прогресс
                        DispatchQueue.main.async {
                            let progress = min(1.0, (yOffset + viewportHeight) / totalHeight)
                            label.stringValue = "Создание изображения... \(Int(progress * 100))%"
                        }
                    }
                    
                    // Возвращаем прокрутку в исходное положение
                    scrollView.contentView.scroll(to: savedOrigin)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                    
                    // Соединяем все части в одно большое изображение в правильном порядке
                    let finalImage = NSImage(size: NSSize(width: viewportWidth, height: totalHeight))
                    finalImage.lockFocus()
                    
                    // Размещаем изображения в правильном порядке - сверху вниз
                    var currentY = 0.0
                    for part in imageParts {
                        part.draw(in: NSRect(x: 0, y: currentY, width: viewportWidth, height: part.size.height))
                        currentY += part.size.height
                    }
                    
                    finalImage.unlockFocus()
                    
                    // Сохраняем изображение
                    if let tiffData = finalImage.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffData),
                       let imageData = bitmapRep.representation(using: .png, properties: [:]) {
                        
                        do {
                            try imageData.write(to: url)
                            DispatchQueue.main.async {
                                progressView.removeFromSuperview()
                                self.showSuccessNotification(filePath: url.path)
                            }
                        } catch {
                            DispatchQueue.main.async {
                                progressView.removeFromSuperview()
                                self.showExportError(message: "Не удалось сохранить изображение: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            progressView.removeFromSuperview()
                            self.showExportError(message: "Не удалось создать изображение")
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        progressView.removeFromSuperview()
                        self.showExportError(message: "Не удалось найти содержимое ScrollView")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    progressView.removeFromSuperview()
                    self.showExportError(message: "Не удалось найти ScrollView в окне")
                }
            }
        }
    }

    private func showSuccessNotification(filePath: String) {
        let notification = NSUserNotification()
        notification.title = "Экспорт успешно завершен"
        notification.informativeText = "Изображение сохранено по пути: \(filePath)"
        NSUserNotificationCenter.default.deliver(notification)
        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
    }
    
    private func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view = view else { return nil }
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }
        
        return nil
    }
    
    private func showExportError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Ошибка экспорта PDF"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
}

extension AnalyticsWindowController: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier.rawValue == "ExportImage" {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Экспорт в изображение"
            item.paletteLabel = "Экспорт в изображение"
            item.toolTip = "Экспортировать аналитику как изображение"
            item.image = NSImage(systemSymbolName: "arrow.down.doc.fill", accessibilityDescription: "Export")
            item.target = self
            item.action = #selector(exportAsImage(_:))
            return item
        }
        return nil
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [NSToolbarItem.Identifier(rawValue: "ExportImage")]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [NSToolbarItem.Identifier(rawValue: "ExportImage")]
    }
}

extension NSView {
    func renderAsImage() -> NSImage {
        let imageRepresentation = bitmapImageRepForCachingDisplay(in: bounds)!
        cacheDisplay(in: bounds, to: imageRepresentation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(imageRepresentation)
        return image
    }
}


@available(macOS 12.0, *)
struct ExportAnalyticsView: View {
    let analyticsView: AnalyticsView
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Аналитика разметки")
                .font(.largeTitle)
                .bold()
                .padding(.bottom, 20)
            
            analyticsView.SummarySection()
            analyticsView.TagDistributionSection()
            analyticsView.LabelUsageSection()
            analyticsView.TimelineStatisticsSection()
            analyticsView.TagDensitySection()
            analyticsView.TagUsageOverTimeSection()
            analyticsView.TopLabelsSection()
            analyticsView.TagDurationStatsSection()
            analyticsView.HeatmapSection()
            
            if !analyticsView.anomalies.isEmpty {
                analyticsView.AnomaliesSection()
            }
            Text("Отчет сгенерирован: \(formattedCurrentDate())")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, 20)
        }
        .padding()
        .background(Color.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func formattedCurrentDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: Date())
    }
}
