//
//  MarkupPlaylistPickerSheet.swift
//  Youchip-Stat
//
//  Лист «Добавить в плейлист…» — выбор плейлиста открытой в правой панели сессии просмотра
//  (или создание нового) для тега/⌘-выборки из окна разметки.
//

import SwiftUI
import AppKit

// MARK: - Отслеживание Shift для drag-and-drop тегов в плейлист

/// Общий монитор клавиши Shift. Строки таймлайна `TimelineLineView` намеренно НЕ подписаны на
/// синглтоны ради производительности, но перетаскивание тега в плейлист должно включаться при
/// зажатом Shift — а это состояние надо знать в момент старта жеста. Shift переключается редко
/// (осознанное действие пользователя), поэтому один общий `@Published` дешевле, чем монитор на
/// каждую строку, и не мешает горячим путям воспроизведения/разметки.
final class TimelineDnDModifierMonitor: ObservableObject {
    static let shared = TimelineDnDModifierMonitor()

    @Published private(set) var isShiftDown = false
    private var monitor: Any?

    private init() {
        isShiftDown = NSEvent.modifierFlags.contains(.shift)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            let down = event.modifierFlags.contains(.shift)
            if self.isShiftDown != down {
                DispatchQueue.main.async { self.isShiftDown = down }
            }
            return event
        }
    }
}

// MARK: - Лист выбора плейлиста

struct MarkupPlaylistPickerSheet: View {
    let source: MarkupPlaylistPanelStore.AddToPlaylistSource
    let onDone: () -> Void

    @ObservedObject private var store = MarkupPlaylistPanelStore.shared
    @State private var newName: String = ""

    var body: some View {
        let playlists = store.playlistsForCurrentSession()
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(^String.Titles.markupPlaylistsPickPlaylistTitle)
                    .font(.headline)
                if let name = store.selectedSessionName {
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if playlists.isEmpty {
                Text(^String.Titles.markupPlaylistsNoPlaylists)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(playlists) { pl in
                            Button {
                                store.addToExistingPlaylist(source: source, playlistID: pl.id)
                                onDone()
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pl.name)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("\(pl.groupName) · \(pl.eventCount)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.blue)
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                TextField(^String.Titles.markupPlaylistsNewPlaylistNamePlaceholder, text: $newName)
                    .textFieldStyle(.roundedBorder)
                Button {
                    store.addToNewPlaylist(source: source, name: newName)
                    onDone()
                } label: {
                    SwiftUI.Label(^String.Titles.markupPlaylistsCreateNewPlaylist, systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            HStack {
                Button(^String.Titles.cancelButtonTitle) { onDone() }
                    .buttonStyle(PlainButtonStyle())
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 340, height: 430)
    }
}
