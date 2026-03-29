//
//  SportCutWatermarkOverlay.swift
//  Youchip-Stat
//

import SwiftUI

/// First row: tag (caps) + label chips + time-event chips. Second row: playlist comment. Draggable.
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
            let base = playerManager.watermarkDragOffset
            let drag = dragTranslation
            VStack(spacing: 6) {
                if hasLine1, let event = playerManager.currentEvent {
                    eventRow(event: event)
                }
                if hasLine2, let comment = commentText {
                    Text(comment)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 420, alignment: .leading)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 16)
            .padding(.leading, 16)
        }
    }

    @ViewBuilder
    private func eventRow(event: SportCutEvent) -> some View {
        let baseColor = Color(hex: event.color)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Text(event.tagName.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 1)
                if let group = event.tagGroupName, !group.isEmpty {
                    Text(group.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            if !labelModels.isEmpty || !timeEventModels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(labelModels, id: \.id) { label in
                            LabelChip(label: label, baseColor: baseColor, fontSize: 9)
                        }
                        ForEach(timeEventModels, id: \.id) { te in
                            TimeEventChip(event: te, fontSize: 9)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
    }
}
