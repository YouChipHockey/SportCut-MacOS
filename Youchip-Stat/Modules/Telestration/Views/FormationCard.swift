//
//  FormationCard.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import SwiftUI

struct FormationCard: View {
    let formation: FootballFormation
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Rectangle()
                        .fill(Color.green.opacity(0.1))
                        .frame(height: 80)
                    
                    ForEach(Array(formation.positions.enumerated()), id: \.offset) { index, position in
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .position(
                                x: position.x * 60 + 20,
                                y: position.y * 60 + 10
                            )
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                
                VStack(spacing: 4) {
                    Text(formation.name)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text(formation.category)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
