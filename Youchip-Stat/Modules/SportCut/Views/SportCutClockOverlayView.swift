//
//  SportCutClockOverlayView.swift
//  Youchip-Stat
//
//  Счётчики поверх кадра в режиме ПРОСМОТРА: и на одиночном клипе, и на клипах плейлиста.
//
//  Показывать нечего «живого» — счётчиков здесь никто не крутит; на кадр идут записи разметки
//  (`StampClockInfo`), пересечённые текущей позицией. Всё считает `SportCutPlayerManager`
//  (`currentClockOverlayItems`), рисует общая канва `ClockOverlayCanvas` — та же, что в разметке,
//  поэтому счётчик так же таскается и меняет размер, а позиция общая с разметкой.
//

import SwiftUI

struct SportCutClockOverlayView: View {

    @ObservedObject var playerManager: SportCutPlayerManager
    /// Правки в сессии (ресайз клипа/штампа пересчитывает показания записи) должны отражаться
    /// на кадре сразу — отсюда подписка на менеджер сессий.
    @ObservedObject private var sessionManager = SportCutSessionManager.shared

    var body: some View {
        // `currentTime` у менеджера тикает 10 Гц — этого хватает, чтобы счётчик шёл на кадре.
        ClockOverlayCanvas(items: playerManager.currentClockOverlayItems())
    }
}
