//
//  VideoControlPanelActions.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 19.01.2026.
//


import SwiftUI

struct VideoControlPanelActions {
    var seekBackward10: () -> Void
    var seekBackward5: () -> Void
    var togglePlayPause: () -> Void
    var seekForward5: () -> Void
    var seekForward10: () -> Void
    var changeSpeed: (Double) -> Void
}

struct VideoControlPanelView: View {
    let width: CGFloat
    let playbackSpeed: Double
    let forViewerMode: Bool
    let actions: VideoControlPanelActions

    private var isSmallScreen: Bool { width < 1700 }
    private let speeds: [Double] = [0.1, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 5.0]

    var body: some View {
        Group {
            if forViewerMode {
                content // без заголовка и без фона
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(^String.Titles.video)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    content
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isSmallScreen {
            VStack(spacing: 4) {
                buttonsRow
                HStack(spacing: 8) {
                    SpeedMenu(playbackSpeed: playbackSpeed, speeds: speeds, onSelect: actions.changeSpeed)
                    Spacer()
                }
            }
        } else {
            HStack(spacing: 8) {
                buttonsRow
                SpeedMenu(playbackSpeed: playbackSpeed, speeds: speeds, onSelect: actions.changeSpeed)
            }
        }
    }

    private var buttonsRow: some View {
        HStack(spacing: 8) {
            SeekButton(title: "10s", systemImage: "gobackward.10", color: .blue, action: actions.seekBackward10)
            SeekButton(title: "5s", systemImage: "gobackward.5", color: .cyan, action: actions.seekBackward5)
            PlayPauseButton(action: actions.togglePlayPause)
            SeekButton(title: "5s", systemImage: "goforward.5", color: .cyan, reversed: true, action: actions.seekForward5)
            SeekButton(title: "10s", systemImage: "goforward.10", color: .blue, reversed: true, action: actions.seekForward10)
        }
    }
}

// MARK: - Subviews

private struct SeekButton: View {
    let title: String
    let systemImage: String
    let color: Color
    var reversed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if reversed {
                    Text(title).font(.system(size: 10, weight: .medium))
                    Image(systemName: systemImage).font(.system(size: 12, weight: .medium))
                } else {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .medium))
                    Text(title).font(.system(size: 10, weight: .medium))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

private struct PlayPauseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "playpause")
                .font(.system(size: 14, weight: .medium))
                .padding(6)
                .background(Color.green.opacity(0.1))
                .foregroundColor(.green)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

private struct SpeedMenu: View {
    let playbackSpeed: Double
    let speeds: [Double]
    let onSelect: (Double) -> Void

    var body: some View {
        Menu {
            ForEach(speeds, id: \.self) { speed in
                Button(String(format: "%.2fx", speed)) {
                    onSelect(speed)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "speedometer").font(.system(size: 12, weight: .medium))
                Text("x\(String(format: "%.2f", playbackSpeed))").font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.1))
            .foregroundColor(.orange)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
