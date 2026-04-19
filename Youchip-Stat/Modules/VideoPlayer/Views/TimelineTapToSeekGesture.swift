//
//  TimelineTapToSeekGesture.swift
//  Youchip-Stat
//

import SwiftUI

extension View {

    /// Interprets a short press with almost no movement as a tap at `startLocation.x`
    /// and maps it to a time along the horizontal timeline of width `gridWidth`.
    ///
    /// `DragGesture(minimumDistance: 0)` is used because `onTapGesture` does not
    /// provide tap coordinates on older macOS targets.
    func timelineTapToSeek(
        gridWidth: CGFloat,
        duration: Double,
        onShortPress: (() -> Void)? = nil,
        seek: @escaping (Double) -> Void
    ) -> some View {
        gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    let dist = hypot(value.translation.width, value.translation.height)
                    guard dist < 5 else { return }
                    onShortPress?()
                    guard duration > 0, gridWidth > 0 else { return }
                    let time = (value.startLocation.x / gridWidth) * duration
                    seek(max(0, min(time, duration)))
                }
        )
    }
}
