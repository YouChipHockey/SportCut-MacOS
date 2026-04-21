//
//  SportCutWatermarkOverlay.swift
//  Youchip-Stat
//

import SwiftUI

private struct WatermarkContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Styled overlay for current playlist event. Draggable with persisted offset; stays inside the video tile.
struct SportCutWatermarkOverlay: View {
    @ObservedObject var playerManager: SportCutPlayerManager
    @ObservedObject private var sessionManager = SportCutSessionManager.shared

    @State private var measuredSize: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero

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
                let W = geo.size.width
                let H = geo.size.height
                let w = max(measuredSize.width, 1)
                let h = max(measuredSize.height, 1)
                let anchorX = W * SportCutPlayerManager.watermarkAnchorFraction
                let bottomInset = SportCutPlayerManager.watermarkBottomInset
                let base = playerManager.watermarkDragOffset
                let drag = dragTranslation

                let rawX = anchorX + base.width + drag.width
                let rawYTop = H - bottomInset - h + base.height + drag.height
                let x = min(max(rawX, 0), max(0, W - w))
                let yTop = min(max(rawYTop, 0), max(0, H - h))

                watermarkCard(maxContentWidth: max(0, W - 4))
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: WatermarkContentSizeKey.self, value: g.size)
                        }
                    )
                    .onPreferenceChange(WatermarkContentSizeKey.self) { measuredSize = $0 }
                    .position(x: x + w * 0.5, y: yTop + h * 0.5)
                    .gesture(
                        DragGesture()
                            .updating($dragTranslation) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                playerManager.commitWatermarkDrag(
                                    delta: value.translation,
                                    container: geo.size,
                                    watermark: measuredSize
                                )
                            }
                    )
                    .onChange(of: geo.size) { newSize in
                        playerManager.syncWatermarkOffsetWithinVideoBounds(container: newSize, watermark: measuredSize)
                    }
                    .onChange(of: measuredSize) { newSize in
                        playerManager.syncWatermarkOffsetWithinVideoBounds(container: geo.size, watermark: newSize)
                    }
            }
            .clipped()
        }
    }

    @ViewBuilder
    private func watermarkCard(maxContentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasLine1, let event = playerManager.currentEvent {
                eventRow(event: event, maxContentWidth: maxContentWidth)
            }
            if hasLine2, let comment = commentText {
                Text(comment)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .frame(maxWidth: maxContentWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: maxContentWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.58))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func eventRow(event: SportCutEvent, maxContentWidth: CGFloat) -> some View {
        let labelsText = labelModels.map(\.name).joined(separator: ", ")
        let timeEventsText = timeEventModels.map(\.name).joined(separator: ", ")

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(event.tagName.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
                    .lineLimit(nil)
                    .fixedSize(horizontal: true, vertical: false)
                if !timeEventsText.isEmpty {
                    Text(timeEventsText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                        .lineLimit(nil)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: maxContentWidth, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)

            if !labelsText.isEmpty {
                Text(labelsText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(nil)
                    .frame(maxWidth: maxContentWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: maxContentWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }
}
