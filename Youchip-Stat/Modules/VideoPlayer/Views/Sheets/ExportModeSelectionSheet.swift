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
    @Binding var exportWithDrawings: Bool
    @Binding var watermarkOptions: ExportWatermarkOptions
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(^String.Titles.exportAs)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Toggle(^String.Titles.exportWithDrawings, isOn: $exportWithDrawings)
                .help(^String.Titles.exportWithDrawingsHelp)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Toggle(^String.Titles.exportAddEpisodeNumbering, isOn: $watermarkOptions.showEpisodeNumbering)
                Toggle(^String.Titles.exportAddTagAndLabels, isOn: $watermarkOptions.showTagAndLabels)
                Toggle(^String.Titles.exportAddComment, isOn: $watermarkOptions.showComment)
            }
            
            Divider()
            
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
            .frame(maxWidth: .infinity, alignment: .center)
            
            Button(^String.Titles.collectionsButtonCancel) {
                presentationMode.wrappedValue.dismiss()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .frame(width: 380, height: 360)
    }
    
}
