//
//  ExportModeSelectionSheet.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct ExportModeSelectionSheet: View {
    
    let onSelect: (ExportMode) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            Text(^String.Titles.exportAs)
                .font(.headline)
            HStack(spacing: 20) {
                Button(^String.Titles.movie) {
                    onSelect(.film)
                    presentationMode.wrappedValue.dismiss()
                }
                Button(^String.Titles.playlist) {
                    onSelect(.playlist)
                    presentationMode.wrappedValue.dismiss()
                }
            }
            Button(^String.Titles.collectionsButtonCancel) {
                presentationMode.wrappedValue.dismiss()
            }
        }
        .padding()
        .frame(width: 300)
    }
    
}
