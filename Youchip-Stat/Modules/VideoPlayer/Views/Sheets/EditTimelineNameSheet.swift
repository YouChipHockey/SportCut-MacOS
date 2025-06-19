//
//  EditTimelineNameSheet.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct EditTimelineNameSheet: View {
    
    @Environment(\.presentationMode) var presentationMode
    @State private var lineName: String
    let onSave: (String) -> Void
    
    init(lineName: String, onSave: @escaping (String) -> Void) {
        _lineName = State(initialValue: lineName)
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Редактировать название таймлайна")
                .font(.headline)
            
            FocusAwareTextField(text: $lineName, placeholder: "Название таймлайна")
                .padding()
            
            HStack {
                Button("Отмена") {
                    NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
                    presentationMode.wrappedValue.dismiss()
                }
                
                Button("Сохранить") {
                    if !lineName.isEmpty {
                        onSave(lineName)
                        NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .disabled(lineName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            NotificationCenter.default.post(name: NSNotification.Name("EditTimelineSheetAppeared"), object: nil)
        }
    }
    
}
