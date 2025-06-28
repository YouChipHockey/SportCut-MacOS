//
//  EventSelectionSheetView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct EventSelectionSheetView: View {
    
    let timeEvents: [TimeEvent]
    let onSelect: (TimeEvent) -> Void
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            Text(^String.Titles.selectEventForExport)
                .font(.headline)
            
            List {
                Section(header: Text(^String.Titles.availableEvents).font(.subheadline).bold()) {
                    ForEach(timeEvents) { event in
                        Button(event.name) {
                            onSelect(event)
                        }
                    }
                }
            }
            .frame(width: 300)
            
            Button(^String.Titles.collectionsButtonCancel) {
                presentationMode.wrappedValue.dismiss()
            }
            .padding(.top, 10)
        }
        .padding()
    }
    
}
