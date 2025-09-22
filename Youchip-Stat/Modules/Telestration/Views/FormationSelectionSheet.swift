//
//  FormationSelectionSheet.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import SwiftUI

struct FormationSelectionSheet: View {
    @ObservedObject var viewModel: PolygonEditorViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            if let selectedObject = viewModel.selectedObjectForTemplate {
                Text("\(^String.Titles.selectFormation) \(selectedObject.positions.count) \(^String.Titles.players)")
                    .font(.headline)
                
                let availableFormations = viewModel.getAvailableFormations(for: selectedObject)
                
                if availableFormations.isEmpty {
                    Text("\(^String.Titles.noAvailableFormations) \(selectedObject.positions.count) \(^String.Titles.players)")
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            ForEach(availableFormations, id: \.id) { formation in
                                FormationCard(formation: formation) {
                                    viewModel.createTemplate(using: formation)
                                    presentationMode.wrappedValue.dismiss()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                }
            }
            
            Button(^String.Titles.cancel) {
                viewModel.cancelTemplateCreation()
                presentationMode.wrappedValue.dismiss()
            }
        }
        .padding()
        .frame(width: 500)
    }
}
