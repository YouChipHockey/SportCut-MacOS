//
//  SportCutWatermarkOverlay.swift
//  Youchip-Stat
//

import AppKit
import SwiftUI

private let sportCutWatermarkCornerRadius: CGFloat = 10
/// Max chip size relative to the video tile (`GeometryReader`).
/// Max chip width/height vs video tile; slightly above 0.65 reads a bit wider without dominating the frame.
private let sportCutWatermarkMaxSizeFraction: CGFloat = 0.75

private extension View {
    @ViewBuilder
    func sportCutWatermarkScrollDisabledIfAvailable() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollDisabled(true)
        } else {
            self
        }
    }
}

/// Tight text size (word-wrap at `maxLineWidth`) for layout; plain string mirrors line breaks.
/// When only the tag line is shown, measure with the same 13 pt semibold as SwiftUI — otherwise 12 pt medium
/// underestimates width and `frame(width:)` forces a spurious wrap (e.g. short Cyrillic "ее").
private func sportCutWatermarkTextContentSize(text: String, maxLineWidth: CGFloat, tagLineOnly: Bool) -> CGSize {
    let maxW = max(1, maxLineWidth)
    let font: NSFont = tagLineOnly
        ? NSFont.systemFont(ofSize: 13, weight: .semibold)
        : NSFont.systemFont(ofSize: 12, weight: .medium)
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .paragraphStyle: style,
    ]
    let attributed = NSAttributedString(string: text, attributes: attrs)
    let rect = attributed.boundingRect(
        with: CGSize(width: maxW, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let width = min(maxW, ceil(rect.width) + (tagLineOnly ? 2 : 0))
    let height = max(1, ceil(rect.height))
    return CGSize(width: width, height: height)
}

private struct ChipLayout: Equatable {
    var chipSize: CGSize
    var contentSize: CGSize
    var needsVerticalScroll: Bool
}

private func sportCutWatermarkComputeChipLayout(snapshot: WatermarkRichSnapshot, maxTextW: CGFloat, maxTextH: CGFloat) -> ChipLayout {
    let text = snapshot.plainTextForLayout
    let contentSize = sportCutWatermarkTextContentSize(
        text: text,
        maxLineWidth: maxTextW,
        tagLineOnly: snapshot.isTagLineOnly || snapshot.isTagPlusTimeOnlyPlain
    )
    let needsScroll = contentSize.height > maxTextH + 0.5
    let chipW: CGFloat
    let chipH: CGFloat
    if needsScroll {
        chipW = maxTextW + 24
        chipH = maxTextH + 16
    } else {
        chipW = contentSize.width + 24
        chipH = contentSize.height + 16
    }
    return ChipLayout(
        chipSize: CGSize(width: max(1, chipW), height: max(1, chipH)),
        contentSize: contentSize,
        needsVerticalScroll: needsScroll
    )
}

/// Rich watermark content (tag / time events / labels / comment) for styling + plain copy for measuring.
private struct WatermarkRichSnapshot: Equatable {
    struct LabelGroupChunk: Equatable {
        let groupName: String
        let labelsJoined: String
    }

    let tagLine: String
    let timeEventsLine: String?
    /// Single-line label groups row represented as styled chunks.
    let labelGroups: [LabelGroupChunk]
    let comment: String?

    var plainTextForLayout: String {
        var lines: [String] = []
        if !tagLine.isEmpty {
            if let t = timeEventsLine, !t.isEmpty {
                lines.append("\(tagLine) • \(t)")
            } else {
                lines.append(tagLine)
            }
        } else if let t = timeEventsLine, !t.isEmpty {
            lines.append(t)
        }
        if !labelGroups.isEmpty {
            lines.append(
                labelGroups
                    .map { "\($0.groupName): \($0.labelsJoined)" }
                    .joined(separator: " • ")
            )
        }
        let head = lines.joined(separator: "\n")
        if let c = comment, !c.isEmpty {
            return head.isEmpty ? c : head + "\n\n" + c
        }
        return head
    }

    /// Single-line tag, no time events / labels / comment — layout width must match 13 pt semibold tag text.
    var isTagLineOnly: Bool {
        guard !tagLine.isEmpty else { return false }
        if let t = timeEventsLine, !t.isEmpty { return false }
        if !labelGroups.isEmpty { return false }
        if let c = comment, !c.isEmpty { return false }
        return true
    }

    /// Tag + time events on one line, nothing else — measure with tag-line typography so width matches UI.
    var isTagPlusTimeOnlyPlain: Bool {
        guard !tagLine.isEmpty,
              let t = timeEventsLine, !t.isEmpty,
              labelGroups.isEmpty,
              comment == nil else { return false }
        return true
    }
}

private func sportCutWatermarkBuildSnapshot(playerManager: SportCutPlayerManager) -> WatermarkRichSnapshot? {
    let sessions = SportCutSessionManager.shared.sessions
    var tagLine = ""
    var timeEventsLine: String?
    var labelGroups: [WatermarkRichSnapshot.LabelGroupChunk] = []
    var comment: String?
    var playlistIndexPrefix: Int?
    var currentSession: SportCutSession?
    var currentEvent: SportCutEvent?
    var currentSource: SportCutSource?

    if playerManager.showEventDataWatermark, let event = playerManager.currentEvent,
       let sessionID = playerManager.sessionID,
       let session = sessions.first(where: { $0.id == sessionID }),
       let source = session.sources.first(where: { $0.id == event.sourceID }) {
        currentSession = session
        currentEvent = event
        currentSource = source
        tagLine = event.tagName.uppercased()
        let timeNames = event.eventIDs.compactMap { id in source.timeEvents.first { $0.id == id }?.name }
        if !timeNames.isEmpty {
            timeEventsLine = timeNames.joined(separator: ", ")
        }
        let stampLabels = event.labelIDs.compactMap { source.findLabel(byID: $0) }
        if !stampLabels.isEmpty {
            var grouped: [(groupName: String, labels: [Label])] = []
            for label in stampLabels {
                let fallbackGroup = String(^String.Titles.labels)
                let groupName = source.labelGroups
                    .first(where: { $0.lables.contains(label.id) })?
                    .name ?? fallbackGroup
                if let idx = grouped.firstIndex(where: { $0.groupName == groupName }) {
                    grouped[idx].labels.append(label)
                } else {
                    grouped.append((groupName: groupName, labels: [label]))
                }
            }
            labelGroups = grouped
                .sorted { $0.groupName < $1.groupName }
                .compactMap { item in
                    let joined = item.labels.map(\.name).joined(separator: ", ")
                    guard !joined.isEmpty else { return nil }
                    return WatermarkRichSnapshot.LabelGroupChunk(groupName: item.groupName, labelsJoined: joined)
                }
        }
    }

    if playerManager.showCommentsWatermark,
       let event = playerManager.currentEvent,
       let sessionID = playerManager.sessionID,
       let session = sessions.first(where: { $0.id == sessionID }) {
        if currentSession == nil { currentSession = session }
        if currentEvent == nil { currentEvent = event }

        // 1) Preferred source in playlist mode: per-playlist comments.
        if let playlistID = playerManager.currentPlaylistID,
           let playlist = session.playlistGroups.flatMap(\.playlists).first(where: { $0.id == playlistID }) {
            if let idx = playlist.events.firstIndex(where: { $0.hiddenKey == event.hiddenKey }) {
                playlistIndexPrefix = idx + 1
            }
            let raw = playlist.eventComments[event.hiddenKey] ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                comment = trimmed
            }
        }

        // 2) Fallback in markup mode: original stamp comment from timeline.
        if comment == nil {
            let source = currentSource ?? session.sources.first(where: { $0.id == event.sourceID })
            if let source,
               let stamp = source.timelines.flatMap(\.stamps).first(where: { $0.id == event.stampID }) {
                let raw = stamp.comment ?? ""
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    comment = trimmed
                }
            }
        }
    }

    if !tagLine.isEmpty, let playlistIndexPrefix {
        tagLine = "\(playlistIndexPrefix). \(tagLine)"
    }

    let hasHead = !tagLine.isEmpty || timeEventsLine != nil || !labelGroups.isEmpty
    let hasComment = comment != nil
    guard hasHead || hasComment else { return nil }
    return WatermarkRichSnapshot(
        tagLine: tagLine,
        timeEventsLine: timeEventsLine,
        labelGroups: labelGroups,
        comment: comment
    )
}

private func sportCutWatermarkLayoutIdentity(eventHiddenKey: String, snapshot: WatermarkRichSnapshot) -> String {
    eventHiddenKey + "\u{1E}" + snapshot.plainTextForLayout
}

private struct WatermarkChrome: View, Equatable {
    let snapshot: WatermarkRichSnapshot
    let maxTextWidth: CGFloat
    let maxTextHeight: CGFloat
    let contentSize: CGSize
    let needsVerticalScroll: Bool

    static func == (lhs: WatermarkChrome, rhs: WatermarkChrome) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.maxTextWidth == rhs.maxTextWidth
            && lhs.maxTextHeight == rhs.maxTextHeight
            && lhs.contentSize == rhs.contentSize
            && lhs.needsVerticalScroll == rhs.needsVerticalScroll
    }

    private var tagAndTimeFirstLine: Text {
        let tag = Text(snapshot.tagLine)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.green)
        guard let time = snapshot.timeEventsLine, !time.isEmpty else {
            return tag
        }
        return tag
            + Text(" • ")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)
            + Text(time)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.orange)
    }

    @ViewBuilder
    private var eventBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !snapshot.tagLine.isEmpty {
                if snapshot.isTagLineOnly {
                    Text(snapshot.tagLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    tagAndTimeFirstLine
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: maxTextWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let time = snapshot.timeEventsLine, !time.isEmpty {
                Text(time)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
            }
            if !snapshot.labelGroups.isEmpty {
                labelGroupsText
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: maxTextWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var labelGroupsText: Text {
        var result = Text("")
        for (index, chunk) in snapshot.labelGroups.enumerated() {
            result = result
                + Text("\(chunk.groupName):")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                + Text(" \(chunk.labelsJoined)")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white)
            if index < snapshot.labelGroups.count - 1 {
                result = result
                    + Text(" • ")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white)
            }
        }
        return result
    }

    @ViewBuilder
    private var commentBlock: some View {
        if let comment = snapshot.comment, !comment.isEmpty {
            Text(comment)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: maxTextWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        let textBlock: some View = Group {
            if needsVerticalScroll {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        eventBlock
                        commentBlock
                    }
                    .frame(maxWidth: maxTextWidth, alignment: .leading)
                }
                .frame(width: maxTextWidth, height: maxTextHeight)
                .sportCutWatermarkScrollDisabledIfAvailable()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    eventBlock
                    commentBlock
                }
                .frame(width: contentSize.width, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
            }
        }

        let label = textBlock
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

        Group {
            if #available(macOS 26.0, *) {
                label
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: sportCutWatermarkCornerRadius, style: .continuous))
            } else {
                label
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: sportCutWatermarkCornerRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: sportCutWatermarkCornerRadius, style: .continuous)
                                .fill(Color.black.opacity(0.22))
                        }
                    }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: sportCutWatermarkCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Draggable tile (fresh @State per `.id` when clip / text changes)

private struct SportCutWatermarkDraggableTile: View {
    @ObservedObject var playerManager: SportCutPlayerManager
    let snapshot: WatermarkRichSnapshot
    let container: CGSize

    @State private var chipLayout: ChipLayout
    @State private var liveDragTranslation: CGSize = .zero
    @State private var isDraggingWatermark = false
    @State private var chipSizeWhileDragging: CGSize = .zero

    init(playerManager: SportCutPlayerManager, snapshot: WatermarkRichSnapshot, container: CGSize) {
        self.playerManager = playerManager
        self.snapshot = snapshot
        self.container = container
        let W = container.width
        let H = container.height
        let maxTextW = max(1, W * sportCutWatermarkMaxSizeFraction - 24)
        let maxTextH = max(1, H * sportCutWatermarkMaxSizeFraction - 16)
        _chipLayout = State(
            initialValue: sportCutWatermarkComputeChipLayout(snapshot: snapshot, maxTextW: maxTextW, maxTextH: maxTextH)
        )
    }

    var body: some View {
        let W = container.width
        let H = container.height
        let maxOverlayW = W * sportCutWatermarkMaxSizeFraction
        let maxOverlayH = H * sportCutWatermarkMaxSizeFraction
        let maxTextW = max(1, maxOverlayW - 24)
        let maxTextH = max(1, maxOverlayH - 16)

        let chipW = (isDraggingWatermark && chipSizeWhileDragging.width > 0.5)
            ? chipSizeWhileDragging.width
            : chipLayout.chipSize.width
        let chipH = (isDraggingWatermark && chipSizeWhileDragging.height > 0.5)
            ? chipSizeWhileDragging.height
            : chipLayout.chipSize.height
        let w = max(chipW, 1)
        let h = max(chipH, 1)
        let bottomInset = SportCutPlayerManager.watermarkBottomInset
        let anchorX = W * SportCutPlayerManager.watermarkAnchorFraction
        let base = playerManager.watermarkDragOffset
        let drag = liveDragTranslation

        let rawX = anchorX + base.width + drag.width
        let rawYTop = H - bottomInset - h + base.height + drag.height + SportCutPlayerManager.watermarkAnchorVerticalShift
        let x = min(max(rawX, 0), max(0, W - w))
        let yTop = min(max(rawYTop, 0), max(0, H - h))

        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())

            WatermarkChrome(
                snapshot: snapshot,
                maxTextWidth: maxTextW,
                maxTextHeight: maxTextH,
                contentSize: chipLayout.contentSize,
                needsVerticalScroll: chipLayout.needsVerticalScroll
            )
            .equatable()
            .contentShape(Rectangle())
            .transaction { $0.animation = nil }
            .offset(x: x, y: yTop)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDraggingWatermark {
                            isDraggingWatermark = true
                            chipSizeWhileDragging = CGSize(width: w, height: h)
                        }
                        liveDragTranslation = value.translation
                    }
                    .onEnded { value in
                        let wm = CGSize(width: w, height: h)
                        liveDragTranslation = .zero
                        isDraggingWatermark = false
                        chipSizeWhileDragging = .zero
                        playerManager.commitWatermarkDrag(
                            delta: value.translation,
                            container: container,
                            watermark: wm
                        )
                    }
            )
        }
        .transaction { $0.animation = nil }
        .onAppear {
            let next = sportCutWatermarkComputeChipLayout(snapshot: snapshot, maxTextW: maxTextW, maxTextH: maxTextH)
            chipLayout = next
            playerManager.syncWatermarkOffsetWithinVideoBounds(container: container, watermark: next.chipSize)
        }
        .onChange(of: container) { newContainer in
            guard !isDraggingWatermark else { return }
            let nW = newContainer.width
            let nH = newContainer.height
            let nMaxTextW = max(1, nW * sportCutWatermarkMaxSizeFraction - 24)
            let nMaxTextH = max(1, nH * sportCutWatermarkMaxSizeFraction - 16)
            let next = sportCutWatermarkComputeChipLayout(snapshot: snapshot, maxTextW: nMaxTextW, maxTextH: nMaxTextH)
            chipLayout = next
            playerManager.syncWatermarkOffsetWithinVideoBounds(container: newContainer, watermark: next.chipSize)
        }
    }
}

/// Draggable watermark: text hugs intrinsic size; background matches text + padding.
struct SportCutWatermarkOverlay: View {
    @ObservedObject var playerManager: SportCutPlayerManager

    private var snapshot: WatermarkRichSnapshot? {
        sportCutWatermarkBuildSnapshot(playerManager: playerManager)
    }

    var body: some View {
        Group {
            if let snapshot {
                GeometryReader { geo in
                    SportCutWatermarkDraggableTile(
                        playerManager: playerManager,
                        snapshot: snapshot,
                        container: geo.size
                    )
                    .id(sportCutWatermarkLayoutIdentity(
                        eventHiddenKey: playerManager.currentEvent?.hiddenKey ?? "_",
                        snapshot: snapshot
                    ))
                }
                .clipped()
            }
        }
    }
}
