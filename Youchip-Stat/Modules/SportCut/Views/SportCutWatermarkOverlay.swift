//
//  SportCutWatermarkOverlay.swift
//  Youchip-Stat
//

import SwiftUI

/// Styled overlay for current playlist event. Draggable with persisted offset.
struct SportCutWatermarkOverlay: View {
    @ObservedObject var playerManager: SportCutPlayerManager
    @ObservedObject private var sessionManager = SportCutSessionManager.shared

    private var session: SportCutSession? {
        guard let sid = playerManager.sessionID else { return nil }
        return sessionManager.sessions.first { $0.id == sid }
    }

    private var source: SportCutSource? {
        guard let event = playerManager.currentEvent else { return nil }
        return session?.sources.first { $0.id == event.sourceID }
    }

    private var commentText: String? {
        guard let sessionID = playerManager.sessionID,
              let playlistID = playerManager.currentPlaylistID,
              let event = playerManager.currentEvent,
              let sess = sessionManager.sessions.first(where: { $0.id == sessionID }),
              let playlist = sess.playlistGroups.flatMap(\.playlists).first(where: { $0.id == playlistID }) else { return nil }
        let raw = playlist.eventComments[event.hiddenKey] ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var labelModels: [Label] {
        guard let event = playerManager.currentEvent, let src = source else { return [] }
        return event.labelIDs.compactMap { src.findLabel(byID: $0) }
    }

    private var timeEventModels: [TimeEvent] {
        guard let event = playerManager.currentEvent, let src = source else { return [] }
        return event.eventIDs.compactMap { id in src.timeEvents.first { $0.id == id } }
    }

    @GestureState private var dragTranslation: CGSize = .zero

    private var hasLine1: Bool {
        playerManager.showEventDataWatermark && playerManager.currentEvent != nil
    }

    private var hasLine2: Bool {
        playerManager.showCommentsWatermark && commentText != nil
    }

    var body: some View {
        if !hasLine1 && !hasLine2 { EmptyView() }
        else {
            GeometryReader { geo in
                let base = playerManager.watermarkDragOffset
                let drag = dragTranslation

                VStack(alignment: .leading, spacing: 6) {
                    if hasLine1, let event = playerManager.currentEvent {
                        eventRow(event: event)
                    }
                    if hasLine2, let comment = commentText {
                        Text(comment)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.58))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .offset(x: base.width + drag.width, y: base.height + drag.height)
                .gesture(
                    DragGesture()
                        .updating($dragTranslation) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            playerManager.commitWatermarkDrag(delta: value.translation)
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 16)
                .padding(.bottom, 78)
            }
        }
    }

    @ViewBuilder
    private func eventRow(event: SportCutEvent) -> some View {
        let labelsText = labelModels.map(\.name).joined(separator: ", ")
        let timeEventsText = timeEventModels.map(\.name).joined(separator: ", ")

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(event.tagName.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                if let group = event.tagGroupName, !group.isEmpty {
                    Text("\(group.uppercased()):")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }

            if !timeEventsText.isEmpty {
                Text(timeEventsText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !labelsText.isEmpty {
                Text(labelsText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
