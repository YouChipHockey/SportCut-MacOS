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

            clubLogoToggle

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
        .frame(width: 380, height: 410)
    }

    /// Тумблер логотипа клуба — независим от текстового вотермарка.
    /// Доступен только если логотип задан в настройках.
    @ViewBuilder
    private var clubLogoToggle: some View {
        let hasLogo = ClubLogoWatermarkManager.shared.hasLogo
        VStack(alignment: .leading, spacing: 4) {
            Toggle(^String.Titles.exportShowClubLogo, isOn: $watermarkOptions.showClubLogo)
                .disabled(!hasLogo)
            if !hasLogo {
                Text(^String.Titles.exportClubLogoNotConfigured)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

}
