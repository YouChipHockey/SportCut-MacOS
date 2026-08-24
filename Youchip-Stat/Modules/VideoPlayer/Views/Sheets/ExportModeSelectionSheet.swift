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
    /// Когда задан — вью показывается в ОТДЕЛЬНОМ окне (экспорт из разметки), а не листом:
    /// закрытие идёт через этот колбэк (закрывает окно), а не `presentationMode`, и размер
    /// фиксированный (без `sheetFitsHostWindow`, который считает высоту от окна-хозяина листа).
    var onClose: (() -> Void)? = nil
    @Environment(\.presentationMode) var presentationMode

    /// «Родная» высота листа: тумблер счётчиков появляется только когда они есть в проекте.
    /// Дальше `sheetFitsHostWindow` ужмёт её под окно — иначе AppKit поднимает окно и лист
    /// вылезает за его края (в низком окне таймлайнов это и происходило).
    private var naturalHeight: CGFloat {
        ClockExportRecords.available().isEmpty ? 410 : 450
    }

    /// Общее закрытие: в оконном режиме — колбэк, в режиме листа — стандартный dismiss.
    private func dismiss() {
        if let onClose {
            onClose()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }

    var body: some View {
        if onClose == nil {
            core.sheetFitsHostWindow(width: 380, height: naturalHeight)
        } else {
            core.frame(width: 380, height: naturalHeight)
        }
    }

    private var core: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(^String.Titles.exportAs)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            // Настройки скроллятся, кнопки всегда видны: при низком окне лист ужимается,
            // и без этого «Фильм»/«Плейлист» уезжали за край.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(^String.Titles.exportWithDrawings, isOn: $exportWithDrawings)
                        .help(^String.Titles.exportWithDrawingsHelp)

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(^String.Titles.exportAddEpisodeNumbering, isOn: $watermarkOptions.showEpisodeNumbering)
                        Toggle(^String.Titles.exportAddTagAndLabels, isOn: $watermarkOptions.showTagAndLabels)
                        Toggle(^String.Titles.exportAddComment, isOn: $watermarkOptions.showComment)
                    }

                    Divider()

                    clockSelection

                    Divider()

                    clubLogoToggle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 20) {
                Button(^String.Titles.movie) {
                    onSelect(.film)
                    dismiss()
                }
                Button(^String.Titles.playlist) {
                    onSelect(.playlist)
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Button(^String.Titles.collectionsButtonCancel) {
                dismiss()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
    }

    /// Счётчики: ОДИН тумблер, без выбора записей. В файл идёт то же, что видно на экране, —
    /// все счётчики, попавшие в этот кусок видео (как в разметке и в просмотре).
    @ViewBuilder
    private var clockSelection: some View {
        if ClockExportRecords.available().isEmpty {
            EmptyView()
        } else {
            Toggle(^String.Titles.exportWithClocks, isOn: $watermarkOptions.showClocks)
                .help(^String.Titles.exportWithClocksHelp)
        }
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
