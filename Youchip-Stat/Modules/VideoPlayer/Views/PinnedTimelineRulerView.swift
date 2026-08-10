//
//  PinnedTimelineRulerView.swift
//  Youchip-Stat
//
//  Закреплённая сверху линейка времени с «головой»-треугольником плейхеда. Синхронно едет за
//  таймлайнами по горизонтали (через `TimelineScrollController.liveScrollX`). Вынесена в отдельный
//  View, чтобы частые ре-рендеры (скролл + плейхед) не тянули за собой перерисовку FullControlView.
//

import SwiftUI

struct PinnedTimelineRulerView: View {

    @ObservedObject var controller: TimelineScrollController
    @ObservedObject var videoManager: VideoPlayerManager
    let duration: Double
    let gridWidth: CGFloat
    let interval: Double
    let viewportWidth: CGFloat
    /// Верхняя полоса (под «головы» меток рисунков) — линейка идёт под ней.
    let band: CGFloat
    /// Высота таймлайнов (для позиционирования меток рисунков; стебли обрезаются по шапке).
    let markersTotalHeight: CGFloat

    var body: some View {
        let offsetX = -controller.liveScrollX
        let playheadX = duration > 0 ? (videoManager.currentTime / duration) * gridWidth : 0

        ZStack(alignment: .topLeading) {
            TimelineTimestampsHeaderView(duration: duration, interval: interval, width: gridWidth)
                .frame(width: gridWidth, height: 30, alignment: .leading)
                .timelineTapToSeek(gridWidth: gridWidth, duration: duration) { time in
                    videoManager.seek(to: time)
                }
                .offset(x: offsetX, y: band)

            // «Голова» плейхеда (треугольник) — только индикатор; тянут плейхед за стебель ниже.
            PlayheadStemWithGrabHead(stemWidth: 2, headBaseWidth: 12, compact: false)
                .frame(width: 16, height: band + 30)
                .offset(x: playheadX + offsetX - 7, y: 0)
                .allowsHitTesting(false)

            // «Головы» меток рисунков (кликабельны — возврат к рисунку) закреплены в шапке.
            ScreenshotMarkersView(
                duration: duration,
                gridWidth: gridWidth,
                totalHeight: markersTotalHeight,
                headLift: band
            )
            .frame(width: gridWidth, alignment: .topLeading)
            .offset(x: offsetX)
            .zIndex(2)
        }
        .frame(width: viewportWidth, height: band + 30, alignment: .topLeading)
        .clipped()
    }
}
