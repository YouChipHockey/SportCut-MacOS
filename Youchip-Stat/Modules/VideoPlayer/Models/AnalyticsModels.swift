//
//  AnalyticsModels.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI

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
    let tagPercentages: [(tagName: String, percentage: Double)]
}
