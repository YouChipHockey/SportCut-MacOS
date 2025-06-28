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
            issues.append(String(format: ^String.Titles.analyticsIssueShortStamps, shortStamps.count))
        }
        
        let emptyTimelines = timelineData.lines.filter { $0.stamps.isEmpty }
        if !emptyTimelines.isEmpty {
            issues.append(String(format: ^String.Titles.analyticsIssueEmptyTimelines, emptyTimelines.map { $0.name }.joined(separator: ", ")))
        }
        
        for line in timelineData.lines {
            let stamps = line.stamps.sorted { timeStringToSeconds($0.timeStart) < timeStringToSeconds($1.timeStart) }
            for i in 0..<stamps.count {
                if i + 1 < stamps.count {
                    let current = stamps[i]
                    let next = stamps[i + 1]
                    if current.label == next.label && timeStringToSeconds(current.timeFinish) > timeStringToSeconds(next.timeStart) {
                        issues.append(String(format: ^String.Titles.tagsOverlapFormat, current.label, line.name))
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
        Text(^String.Titles.tagsDensityOverTime)
            .font(.title)
        
        if #available(macOS 13.0, *) {
            Chart(tagDensity, id: \.time) { point in
                LineMark(
                    x: .value(^String.Titles.time, point.time),
                    y: .value(^String.Titles.tagsCount, point.count)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value(^String.Titles.time, point.time),
                    y: .value(^String.Titles.tagsCount, point.count)
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
            .chartXAxisLabel(^String.Titles.videoTime)
            .chartYAxisLabel(^String.Titles.activeTagsCount)
            .frame(height: 250)
        } else {
            Text(^String.Titles.analyticsChartDensityNotAvailable)
        }
        
        VStack(alignment: .leading, spacing: 8) {
            if let maxDensity = tagDensity.max(by: { $0.count < $1.count }) {
                Text(String(format: ^String.Titles.analyticsTagDensityPeak, maxDensity.count, secondsToTimeString(maxDensity.time)))
                    .font(.headline)
            }
            
            let avgDensity = tagDensity.reduce(0.0) { $0 + Double($1.count) } / Double(max(1, tagDensity.count))
            Text(String(format: ^String.Titles.analyticsTagDensityAverage, avgDensity))
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    func TopLabelsSection() -> some View {
        Text(^String.Titles.analyticsLabelMostUsed)
            .font(.title)
        
        if #available(macOS 13.0, *), !topUsedLabels.isEmpty {
            Chart(topUsedLabels) { label in
                BarMark(
                    x: .value(^String.Titles.count, label.count),
                    y: .value(^String.Titles.label, label.label)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
            .chartXAxisLabel(^String.Titles.usageCount)
            .frame(height: 300)
        } else {
            Text(^String.Titles.analyticsChartNotAvailable)
        }
        
        VStack(alignment: .leading, spacing: 8) {
            Text(^String.Titles.analyticsLabelMostPopular)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    func TagDurationStatsSection() -> some View {
        Text(^String.Titles.tagsDurationStatistics)
            .font(.title)
        
        if #available(macOS 13.0, *), !tagDurationStats.isEmpty {
            Chart(tagDurationStats) { stat in
                BarMark(
                    x: .value(^String.Titles.tag, stat.tagName),
                    y: .value(^String.Titles.midDuration, stat.averageDuration)
                )
                .foregroundStyle(stat.color)
                
                RectangleMark(
                    x: .value(^String.Titles.tag, stat.tagName),
                    yStart: .value(^String.Titles.minDuration, stat.minDuration),
                    yEnd: .value(^String.Titles.maxDuration, stat.maxDuration),
                    width: 20
                )
                .foregroundStyle(stat.color.opacity(0.3))
            }
            .chartYAxisLabel(^String.Titles.durationSeconds)
            .frame(height: 300)
        } else {
            Text(^String.Titles.durationStatisticsUnavailable)
        }
        
        VStack(alignment: .leading, spacing: 8) {
            Text(^String.Titles.tagsDurationStatisticsByType)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(^String.Titles.durationStatisticsDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    func SummarySection() -> some View {
        Text(^String.Titles.generalStatistics)
            .font(.title)
        
        VStack(alignment: .leading, spacing: 10) {
            Text("\(^String.Titles.timelinesCount) \(timelineData.lines.count)")
            Text("\(^String.Titles.totalTagsCount) \(timelineData.lines.flatMap { $0.stamps }.count)")
            if let totalDuration = timelineData.lines.flatMap({ $0.stamps }).map({ $0.duration }).reduce(0, +) as Double? {
                Text("\(^String.Titles.analyticsStatsDurationTotal) \(secondsToTimeString(totalDuration))")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    func TagDistributionSection() -> some View {
        Text(^String.Titles.analyticsTitleDistribution)
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
        Text(^String.Titles.labelStatistics)
            .font(.title)
        
        ForEach(Array(labelStatistics.keys.sorted()), id: \.self) { tagName in
            if let stats = labelStatistics[tagName]?.prefix(5) {
                VStack(alignment: .leading) {
                    Text("\(^String.Titles.fieldMapTagTitleNoNumber) \(tagName)")
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
        Text(^String.Titles.timelineStatistics)
            .font(.title)
        
        ForEach(timelineStats, id: \.name) { stat in
            VStack(alignment: .leading) {
                Text(stat.name)
                    .font(.headline)
                Text("Количество тегов: \(stat.tagCount)")
                Text("\(^String.Titles.totalDuration) \(secondsToTimeString(stat.totalDuration))")
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
            Text(^String.Titles.detectedIssues)
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
