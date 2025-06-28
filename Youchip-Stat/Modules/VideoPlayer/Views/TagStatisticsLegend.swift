//
//  TagStatisticsLegend.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI

struct TagStatisticsLegend: View {
    let statistics: [TagStatistics]
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(statistics, id: \.tagName) { stat in
                HStack {
                    Circle()
                        .fill(stat.color)
                        .frame(width: 12, height: 12)
                    Text("\(stat.tagName): \(Int(stat.duration)) \(^String.Titles.itemsCount). (\(String(format: "%.1f", stat.percentage))%)")
                        .font(.subheadline)
                }
            }
        }
        .padding()
    }
}
