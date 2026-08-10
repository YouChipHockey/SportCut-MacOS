//
//  SettingsView.swift
//  Youchip-Stat
//
//  Единый экран настроек приложения: язык, тема, экспорт (вотермарка), логотип клуба.
//  Открывается из главного меню (⌘,) и по кнопке-шестерёнке в верхней панели.
//

import SwiftUI

struct SettingsView: View {
    var onClose: (() -> Void)? = nil

    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var clubLogo = ClubLogoWatermarkManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    exportSection
                    clubLogoSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, minHeight: 620)
    }

    private var header: some View {
        HStack {
            Text(^String.Titles.settingsTitle)
                .font(.title2.weight(.semibold))
            Spacer()
            if onClose != nil {
                Button(^String.Titles.done) {
                    clubLogo.persist()
                    onClose?()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Секции

    private var exportSection: some View {
        section(title: ^String.Titles.settingsExportSection) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(^String.Titles.settingsExportWatermark, isOn: $settings.exportClipsWithWatermark)
                    .toggleStyle(.switch)
                Text(^String.Titles.settingsExportWatermarkHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var clubLogoSection: some View {
        section(title: ^String.Titles.clubLogoTitle) {
            // Встроенный редактор логотипа (без своей кнопки закрытия — onClose не передаём).
            ClubLogoWatermarkSettingsView()
                .frame(minHeight: 320)
        }
    }

    // MARK: - Хелпер секции

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
        )
    }
}
