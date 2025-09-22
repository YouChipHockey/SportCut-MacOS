//
//  TemplateListItem.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import SwiftUI

struct TemplateListItem: View {
    let template: TemplateObject
    let viewModel: PolygonEditorViewModel
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(template.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if !template.isVisible {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(template.templateCustomization.fillColor)
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(template.templateCustomization.edgeColor)
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(template.templateCustomization.vertexColor)
                        .frame(width: 12, height: 12)
                    
                    Text(template.templateCustomization.lineStyle.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(template.isVisible ? Color.clear : Color.gray.opacity(0.1))
        .cornerRadius(4)
        .contextMenu {
            Button(template.isVisible ? ^String.Titles.hide : ^String.Titles.show) {
                viewModel.toggleTemplateVisibility(template)
            }
            
            Divider()
            
            Button(^String.Titles.delete, role: .destructive) {
                viewModel.deleteTemplate(template)
            }
        }
    }
}
