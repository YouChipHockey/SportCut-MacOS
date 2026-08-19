//
//  PlaybackClock.swift
//  Youchip-Stat
//
//  Часы воспроизведения — единственный `@Published`-источник текущего времени плеера.
//

import Combine
import Foundation

/// Единственный `ObservableObject`, публикующий текущее время воспроизведения.
///
/// **Зачем отдельный объект.** `VideoPlayerManager` — синглтон, на который через
/// `@ObservedObject` подписаны почти все экраны разметки: `FullControlView`, `TagLibraryView`
/// (2700 строк), `VideoPlayerView`, зеркальные окна, окно просмотра. `@ObservedObject`
/// подписывается на `objectWillChange` **всего объекта**, а не на конкретное свойство —
/// поэтому пока `currentTime` был `@Published`, тик плеера (30 Гц) перестраивал `body` у всех
/// этих экранов целиком, включая те, что время вообще не читают. На 20+ таймлайнах это
/// выжирало главный поток и «тупила вся программа», а не только окно разметки.
///
/// **Как пользоваться теперь.**
/// - Нужно *прочитать* время в момент действия (поставить тег, посчитать границы) —
///   читай `VideoPlayerManager.shared.currentTime` как раньше, это обычное свойство.
/// - Нужно *реагировать* на изменение времени (двигать плейхед, показывать таймкод) —
///   подписывайся здесь.
///
/// Подписчиков должно быть мало и они должны быть **мелкими**: плейхед, линейка, таймкод.
/// Никогда не подписывай на эти часы вью со списком таймлайнов — вернётся ровно та проблема,
/// от которой уходили (см. `vault/tasks/…/TASK-007`).
final class PlaybackClock: ObservableObject {

    static let shared = PlaybackClock()

    /// Текущее время воспроизведения, сек. Пишется только из `VideoPlayerManager`.
    @Published private(set) var time: Double = 0

    private init() {}

    /// Записывает новое значение. Одинаковое значение повторно не публикуется — иначе на паузе
    /// и во время seek'ов идут лишние перерисовки плейхеда.
    func update(_ newTime: Double) {
        let sanitized = newTime.isFinite ? newTime : 0
        guard time != sanitized else { return }
        time = sanitized
    }
}

/// Часы ПЕРЕСМОТРА в лайве: публикуют позицию review-плеера. Отдельно от `PlaybackClock`
/// (тот в лайве держит позицию ЖИВОЙ записи), чтобы на таймлайне жили ДВА плейхеда: основной
/// (лайв) и бирюзовый (пересмотр). Подписчик один — бирюзовый плейхед; правило то же, что у
/// `PlaybackClock`: подписывать сюда список таймлайнов нельзя.
final class ReviewPlaybackClock: ObservableObject {

    static let shared = ReviewPlaybackClock()

    /// Текущая позиция пересмотра, сек. Пишется из `VideoPlayerManager` (review time observer).
    @Published private(set) var time: Double = 0

    private init() {}

    func update(_ newTime: Double) {
        let sanitized = newTime.isFinite ? newTime : 0
        guard time != sanitized else { return }
        time = sanitized
    }
}
