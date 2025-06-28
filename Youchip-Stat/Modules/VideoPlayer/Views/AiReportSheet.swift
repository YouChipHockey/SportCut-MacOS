//
//  AiReportSheet.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/29/25.
//

import SwiftUI
import Foundation

struct AiReportSheet: View {
    @Environment(\.presentationMode) var presentationMode
    
    @State private var teamName: String = ""
    @State private var opponentName: String = ""
    @State private var venue: String = ""
    @State private var matchDate: String = ""
    
    var onSubmit: (String, String, String, String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Генерация ИИ отчета")
                .font(.headline)
            
            Form {
                TextField("Название команды", text: $teamName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Название команды соперника", text: $opponentName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Место проведения", text: $venue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Дата матча", text: $matchDate)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            HStack {
                Button("Отмена") {
                    NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
                    presentationMode.wrappedValue.dismiss()
                }
                
                Button("Сгенерировать") {
                    NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
                    onSubmit(teamName, opponentName, venue, matchDate)
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            NotificationCenter.default.post(name: NSNotification.Name("EditTimelineSheetAppeared"), object: nil)
        }
        .frame(width: 400)
        .padding()
    }
}
