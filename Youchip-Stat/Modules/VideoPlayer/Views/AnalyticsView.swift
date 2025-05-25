//
//  AnalyticsView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI
import AppKit
import AVKit
import Charts
import Foundation
import UniformTypeIdentifiers

struct AnalyticsView: View {
    @ObservedObject var timelineData = TimelineDataManager.shared
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    
    private var topUsedLabels: [TopLabelUsage] {
        var allLabelCounts: [String: Int] = [:]
        
        for (_, labelUsages) in labelStatistics {
            for usage in labelUsages {
                allLabelCounts[usage.label, default: 0] += usage.count
            }
        }
        return allLabelCounts.map { label, count in
            TopLabelUsage(label: label, count: count)
        }.sorted { $0.count > $1.count }.prefix(10).map { $0 }
    }
    
    private var tagDurationStats: [TagDurationStat] {
        let allStamps = timelineData.lines.flatMap { $0.stamps }
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
    
    private var tagStatistics: [TagStatistics] {
        let allStamps = timelineData.lines.flatMap { $0.stamps }
        
        if allStamps.isEmpty {
            return []
        }
        
        var statsByTag: [String: Int] = [:]
        for stamp in allStamps {
            statsByTag[stamp.label, default: 0] += 1
        }
        
        let totalCount = allStamps.count
        
        let sortedStats = statsByTag.sorted { $0.value > $1.value }
        var result: [TagStatistics] = []
        var accumulatedPercentage = 0.0
        for (i, (tagName, count)) in sortedStats.enumerated() {
            let tag = tagLibrary.tags.first { $0.name == tagName }
            let percentage: Double
            if i == sortedStats.count - 1 {
                percentage = 100.0 - accumulatedPercentage
            } else {
                percentage = Double(count) / Double(totalCount) * 100
                accumulatedPercentage += percentage
            }
            
            result.append(TagStatistics(
                tagName: tagName,
                duration: Double(count),
                percentage: percentage,
                color: tag.map { Color(hex: $0.color) } ?? .gray
            ))
        }
        
        return result
    }
    
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
    
    private var tagDensity: [TagDensityPoint] {
        let videoLength = VideoPlayerManager.shared.videoDuration
        let totalPointsTarget = 5400
        let interval = max(1.0, videoLength / Double(totalPointsTarget))
        var points: [TagDensityPoint] = []
        
        
        let allStamps = timelineData.lines.flatMap { $0.stamps }
        let stampRanges = allStamps.map { stamp -> (start: Double, end: Double) in
            let start = timeStringToSeconds(stamp.timeStart)
            let end = timeStringToSeconds(stamp.timeFinish)
            return (start, end)
        }
        
        for time in stride(from: 0.0, to: videoLength, by: interval) {
            let count = stampRanges.filter { time >= $0.start && time <= $0.end }.count
            points.append(TagDensityPoint(time: time, count: count))
        }
        
        return points
    }
    
    private var timelineStats: [TimelineStatistics] {
        timelineData.lines.map { line in
            let totalDuration = line.stamps.reduce(0.0) { $0 + $1.duration }
            
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
                tagPercentages: tagPercentages
            )
        }
    }
    
    var anomalies: [String] {
        var issues: [String] = []
        let shortStamps = timelineData.lines.flatMap { $0.stamps }.filter { $0.duration < 1.0 }
        if !shortStamps.isEmpty {
            issues.append("Найдены очень короткие события (меньше 1 секунды): \(shortStamps.count) шт.")
        }
        
        let emptyTimelines = timelineData.lines.filter { $0.stamps.isEmpty }
        if !emptyTimelines.isEmpty {
            issues.append("Таймлайны без разметки: \(emptyTimelines.map { $0.name }.joined(separator: ", "))")
        }
        
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
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SummarySection()
                TagDistributionSection()
                LabelUsageSection()
                TimelineStatisticsSection()
                AnomaliesSection()
                TagDensitySection()
                TopLabelsSection()
                TagDurationStatsSection()
                AnomaliesSection()
            }
            .padding()
        }
    }
    
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
    
    @ViewBuilder
    func TagDistributionSection() -> some View {
        Text("Распределение тегов")
            .font(.title)
        
        HStack {
            PieChartView(statistics: tagStatistics)
                .frame(width: 200, height: 200)
            
            TagStatisticsLegend(statistics: tagStatistics)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
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
