//
//  SportCutSlidesEditor.swift
//  Youchip-Stat
//
//  UI for authoring title slides between playlist clips (presentation mode).
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Slides manager (ordered sequence of clips + slides)

struct SportCutSlidesManagerSheet: View {

    let sessionID: UUID
    let playlistID: UUID
    let onClose: () -> Void

    @ObservedObject private var sessionManager = SportCutSessionManager.shared
    @State private var editingSlide: SportCutSlide?

    private var playlist: SportCutPlaylist? {
        sessionManager.sessions.first(where: { $0.id == sessionID })?
            .playlistGroups.flatMap(\.playlists).first(where: { $0.id == playlistID })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "rectangle.stack.badge.plus").foregroundColor(.purple)
                Text(^String.Titles.sportCutSlidesManage).font(.headline)
                Spacer()
                Button(^String.Titles.sportCutSlideDone) { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider()

            if let playlist {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0...playlist.events.count, id: \.self) { position in
                            slidesAt(position: position, playlist: playlist)
                            insertButton(position: position)
                            if position < playlist.events.count {
                                clipRow(index: position, playlist: playlist)
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                Spacer()
                Text(^String.Titles.sportCutSessionNotFound).foregroundColor(.secondary)
                Spacer()
            }
        }
        .frame(width: 460, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: $editingSlide) { slide in
            SportCutSlideEditorSheet(slide: slide) { updated in
                guard var session = sessionManager.sessions.first(where: { $0.id == sessionID }) else { return }
                sessionManager.updateSlide(in: &session, playlistID: playlistID, slide: updated)
                editingSlide = nil
            } onCancel: {
                editingSlide = nil
            }
        }
    }

    @ViewBuilder
    private func slidesAt(position: Int, playlist: SportCutPlaylist) -> some View {
        ForEach(playlist.slides.filter { $0.position == position }) { slide in
            HStack(spacing: 10) {
                Image(nsImage: SportCutSlideRenderer.renderImage(for: slide, size: CGSize(width: 96, height: 54)))
                    .resizable().frame(width: 64, height: 36).cornerRadius(4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slide.title.isEmpty ? ^String.Titles.sportCutSlideUntitled : slide.title)
                        .font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(String.Titles.sportCutSlideDurationSec.format(Int(slide.durationSeconds)))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { editingSlide = slide }) {
                    Image(systemName: "pencil").foregroundColor(.blue)
                }.buttonStyle(PlainButtonStyle())
                Button(action: { removeSlide(slide) }) {
                    Image(systemName: "trash").foregroundColor(.red)
                }.buttonStyle(PlainButtonStyle())
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.3), lineWidth: 1))
        }
    }

    private func insertButton(position: Int) -> some View {
        Button(action: { addSlide(at: position) }) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.system(size: 12))
                Text(^String.Titles.sportCutSlideInsertHere).font(.system(size: 11))
            }
            .foregroundColor(.purple)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func clipRow(index: Int, playlist: SportCutPlaylist) -> some View {
        let event = playlist.events[index]
        return HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
                .frame(width: 22)
            Circle().fill(Color(hex: event.color)).frame(width: 10, height: 10)
            Text(event.tagName).font(.system(size: 12)).lineLimit(1)
            Spacer()
            Image(systemName: "film").foregroundColor(.secondary).font(.system(size: 11))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
    }

    private func addSlide(at position: Int) {
        guard var session = sessionManager.sessions.first(where: { $0.id == sessionID }) else { return }
        let slide = SportCutSlide(position: position)
        sessionManager.addSlide(in: &session, playlistID: playlistID, slide: slide)
        editingSlide = slide
    }

    private func removeSlide(_ slide: SportCutSlide) {
        guard var session = sessionManager.sessions.first(where: { $0.id == sessionID }) else { return }
        sessionManager.removeSlide(in: &session, playlistID: playlistID, slideID: slide.id)
    }
}

// MARK: - Single slide editor

struct SportCutSlideEditorSheet: View {

    let onSave: (SportCutSlide) -> Void
    let onCancel: () -> Void

    @State private var slide: SportCutSlide
    @State private var bgColor: Color
    @State private var bgHex: String
    @State private var textColor: Color
    @State private var textHex: String

    init(slide: SportCutSlide, onSave: @escaping (SportCutSlide) -> Void, onCancel: @escaping () -> Void) {
        _slide = State(initialValue: slide)
        _bgColor = State(initialValue: Color(hex: slide.backgroundColorHex))
        _bgHex = State(initialValue: slide.backgroundColorHex)
        _textColor = State(initialValue: Color(hex: slide.textColorHex))
        _textHex = State(initialValue: slide.textColorHex)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(^String.Titles.sportCutSlideEditTitle).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preview

                    field(^String.Titles.sportCutSlideTitleField) {
                        TextField(^String.Titles.sportCutSlideTitlePlaceholder, text: $slide.title)
                            .textFieldStyle(.roundedBorder)
                    }

                    field(^String.Titles.sportCutSlideDuration) {
                        HStack {
                            Stepper(value: $slide.durationSeconds, in: 1...60, step: 1) {
                                Text(String.Titles.sportCutSlideDurationSec.format(Int(slide.durationSeconds)))
                            }
                        }
                    }

                    field(^String.Titles.sportCutSlideTextSize) {
                        HStack {
                            Slider(value: $slide.textSize, in: 24...240, step: 4)
                            Text("\(Int(slide.textSize))").frame(width: 40).foregroundColor(.secondary)
                        }
                    }

                    field(^String.Titles.sportCutSlideBackground) {
                        ColorPickerView(selectedColor: $bgColor, hexString: $bgHex)
                            .onChange(of: bgHex) { slide.backgroundColorHex = $0 }
                    }

                    field(^String.Titles.sportCutSlideTextColor) {
                        ColorPickerView(selectedColor: $textColor, hexString: $textHex)
                            .onChange(of: textHex) { slide.textColorHex = $0 }
                    }

                    field(^String.Titles.sportCutSlideLogo) {
                        HStack(spacing: 12) {
                            if let data = slide.imageData, let img = NSImage(data: data) {
                                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                                    .frame(height: 40)
                                Button(^String.Titles.delete) { slide.imageData = nil }
                                    .buttonStyle(.bordered)
                            } else {
                                Button {
                                    pickLogo()
                                } label: {
                                    SwiftUI.Label(^String.Titles.sportCutSlideAddLogo, systemImage: "photo.badge.plus")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Spacer()
                Button(^String.Titles.collectionsButtonCancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(^String.Titles.sportCutSlideSave) {
                    slide.backgroundColorHex = bgHex
                    slide.textColorHex = textHex
                    onSave(slide)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 460, height: 640)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var preview: some View {
        Image(nsImage: SportCutSlideRenderer.renderImage(for: previewSlide, size: CGSize(width: 400, height: 225)))
            .resizable()
            .aspectRatio(16.0/9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
    }

    /// Слайд с актуальными цветами из пикеров для превью.
    private var previewSlide: SportCutSlide {
        var s = slide
        s.backgroundColorHex = bgHex
        s.textColorHex = textHex
        return s
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
            content()
        }
    }

    private func pickLogo() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            slide.imageData = data
        }
    }
}
