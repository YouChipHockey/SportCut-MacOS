//
//  AddLineSheet.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct AddLineSheet: View {
    
    @Environment(\.presentationMode) private var presentationMode
    @State private var lineName: String = ""
    let onAdd: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text(^String.Titles.fullControlButtonAddTimeline)
                .font(.headline)
            FocusAwareTextField(text: $lineName, placeholder: ^String.Titles.timelineName)
                .padding()
            HStack {
                Button(^String.Titles.collectionsButtonCancel) {
                    NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
                    presentationMode.wrappedValue.dismiss()
                }
                Button(^String.Titles.collectionsButtonAdd) {
                    onAdd(lineName)
                    NotificationCenter.default.post(name: NSNotification.Name("SheetDismissed"), object: nil)
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(lineName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            NotificationCenter.default.post(name: NSNotification.Name("AddLineSheetAppeared"), object: nil)
        }
    }
    
}
