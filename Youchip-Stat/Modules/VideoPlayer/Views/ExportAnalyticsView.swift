//
//  ExportAnalyticsView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI

struct ExportAnalyticsView: View {
    let analyticsView: AnalyticsView
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(^String.Titles.layoutAnalytics)
                .font(.largeTitle)
                .bold()
                .padding(.bottom, 20)
            
            analyticsView.SummarySection()
            analyticsView.TagDistributionSection()
            analyticsView.LabelUsageSection()
            analyticsView.TimelineStatisticsSection()
            analyticsView.TagDensitySection()
            analyticsView.TopLabelsSection()
            analyticsView.TagDurationStatsSection()
            
            if !analyticsView.anomalies.isEmpty {
                analyticsView.AnomaliesSection()
            }
            Text("\(^String.Titles.reportGenerated) \(formattedCurrentDate())")
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

extension NSView {
    func renderAsImage() -> NSImage {
        let imageRepresentation = bitmapImageRepForCachingDisplay(in: bounds)!
        cacheDisplay(in: bounds, to: imageRepresentation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(imageRepresentation)
        return image
    }
}
