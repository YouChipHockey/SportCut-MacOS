---
id: TASK-007
title: Производительность FullControlView / таймлайнов в разметке
status: in-progress
assignee: developer
created: 2026-08-13
updated: 2026-08-13
tags: [performance, VideoPlayer, FullControlView, timeline]
---

# TASK-007 — Разгрузка редактора разметки (FullControlView + таймлайны)

## Постановка

При появлении большого количества таймлайнов в окне FullControl («разметка») вся программа
начинает ужасно тупить. Уже на ~20 таймлайнах пользоваться почти невозможно. Нужен
глубокий разбор причин + план оптимизации и разгрузки.

## Диагноз: одна корневая причина + семь усилителей

### Корень: 30 Гц `currentTime` × веерное `@ObservedObject` на синглтонах

`VideoPlayerManager.startTimeObserver()`
([VideoPlayerManager.swift:383](Youchip-Stat/Modules/VideoPlayer/Managers/VideoPlayerManager.swift:383))
пишет `@Published currentTime` **30 раз в секунду** на главном потоке.

`@ObservedObject` подписывается на `objectWillChange` **всего объекта**, а не на конкретное
свойство. Поэтому каждый тик currentTime инвалидирует `body` у всех, кто держит
`VideoPlayerManager.shared` через `@ObservedObject` — даже если этот body currentTime вообще
не читает:

| Подписчик | Файл |
|---|---|
| `FullControlView` (весь body: 3513 строк логики, все строки таймлайнов) | FullControlView.swift:17 |
| `TimelineLineView` — **каждая** из N строк, отдельной подпиской | TimelineLineView.swift:15 |
| `ScreenshotMarkersView` — 2 экземпляра (стебли + головы) | FullControlView.swift:3010 |
| `TagLibraryView` (2712 строк) | TagLibraryView.swift:19 |
| `VideoPlayerView`, `MirroredVideoWindow`, `ReviewVideoView` | соотв. файлы |
| `ViewerTimelineView` / `ViewerTableView` (если открыт просмотр) | Viewer/… |

То есть тупит **вся программа**, а не только окно FullControl: три окна разметки (+ зеркала
+ просмотр) полностью перестраивают свои деревья 30 раз в секунду. Это и объясняет
«тупит вообще всё, а не только таймлайны».

**Прошлая изоляция сломана.** В `timelineZStackContent` есть комментарий, что FullControlView
специально не читает `@Published` у `playheadDragController` — но строкой ниже он читает
`videoManager.currentTime`
([FullControlView.swift:828](Youchip-Stat/Modules/VideoPlayer/Views/FullControlView.swift:828)):

```swift
let timeOffsetToPixels = duration > 0 ? (videoManager.currentTime / duration) * gridWidth : 0
```

Плюс `.onChange(of: videoManager.currentTime)` на `timelineScrollView`
([FullControlView.swift:470](Youchip-Stat/Modules/VideoPlayer/Views/FullControlView.swift:470)).
Смысл выделения `TimelinePlayheadView` в отдельный View полностью потерян.

### Усилитель 1 — виртуализации строк нет

Материализуются **все** строки таймлайнов, а не только видимые:

- [FullControlView.swift:596](Youchip-Stat/Modules/VideoPlayer/Views/FullControlView.swift:596) — `ForEach(timelineData.lines)` в `timelineNameRows()`, обычный `VStack`
- [FullControlView.swift:788](Youchip-Stat/Modules/VideoPlayer/Views/FullControlView.swift:788) — `ForEach(timelineData.lines)` в `timelineZStackContent`, обычный `VStack`
- `grep visibleLineRange|LazyVStack|TimelineVOffsetKey` → 0 совпадений

> **Важно про историю.** Раньше такая оптимизация проектировалась (описание сохранилось в
> памяти `project_fullcontrolview_perf`), но `git log --all -S "visibleLineRange"` не находит
> её ни в одном коммите ни на одной ветке — включая ветку `optimization`. То есть это **не
> регресс**: код никогда не был закоммичен и его нельзя восстановить через `git show`. Правку
> придётся писать заново, но описанный в памяти подход можно использовать как готовый чертёж.

### Усилитель 2 — `@StateObject exportHelper` подписывает весь body

[FullControlView.swift:22](Youchip-Stat/Modules/VideoPlayer/Views/FullControlView.swift:22)
`@StateObject var exportHelper = ExportHelper()`, а `exportHelper.progress` читается прямо в
body ([FullControlView.swift:2008](Youchip-Stat/Modules/VideoPlayer/Views/FullControlView.swift:2008)).
Каждый тик прогресса при экспорте пересчитывает весь body со всеми строками — ровно тот
механизм, который на больших проектах приводил к hang'у и убийству по watchdog.

Аналогичное исправление (`@State` + изолированный `@ObservedObject`-оверлей) применялось
раньше **в другом файле** (`show export progress in viewer mode`); в `FullControlView` здесь
`@StateObject` стоит с самого коммита `83d2b76` и не менялся.

### Усилитель 3 — `fileExists` в теле View, 30 раз в секунду

`ScreenshotMarkersView.body`
([FullControlView.swift:3048](Youchip-Stat/Modules/VideoPlayer/Views/FullControlView.swift:3048)):

```swift
ForEach(screenshotsManager.screenshots, id: \.screenshotName) { screenshot in
    if screenshotFileExists(for: screenshot) { screenshotMarker(for: screenshot) }
}
```

`screenshotFileExists` → `FileManager.default.fileExists(atPath:)` — **синхронный stat-syscall
на главном потоке, на каждый скриншот, на каждый пересчёт body**. View подписан на
`videoManager` → 30 пересчётов/сек × 2 экземпляра × K скриншотов. При 50 рисунках это
**3000 stat/сек** на main. Плюс тот же body пересчитывается на каждый кадр горизонтального
скролла (через `liveScrollX`).

### Усилитель 4 — `.contextMenu` на каждом штампе с тяжёлым содержимым

`stampView` навешивает `.contextMenu { menuForTag(stamp:) }` на **каждый** штамп
([TimelineLineView.swift:308](Youchip-Stat/Modules/VideoPlayer/Views/TimelineLineView.swift:308)).
Содержимое строится вместе с body и внутри делает:

- `ScreenshotsMetadataManager.shared.screenshots.contains { … }` — O(K) на штамп
  ([TimelineLineView.swift:599](Youchip-Stat/Modules/VideoPlayer/Views/TimelineLineView.swift:599))
- на каждый лейбл: `tagLibrary.allLabelGroups.first(where: { $0.lables.contains(…) })` — O(G×L)
- `SportCutSessionManager.shared.sessions.isEmpty`

При 20 таймлайнах × 30 штампов = 600 меню × ~15 узлов = ~9000 View-узлов, пересобираемых 30 раз
в секунду. Также каждый штамп несёт `.onDrag`, `.position`, `.coordinateSpace(name:)`, два
`onTapGesture` и `DragGesture`.

### Усилитель 5 — квадратичная и линейная работа в рендере строки

В `stampView` на **каждый** штамп на **каждый** рендер:

- `getOverlapCount` — O(index) → суммарно **O(S²)** на строку
  ([TimelineLineView.swift:63](Youchip-Stat/Modules/VideoPlayer/Views/TimelineLineView.swift:63))
- `timelineData.lines.firstIndex(where:)` — O(L) на штамп
  ([TimelineLineView.swift:158](Youchip-Stat/Modules/VideoPlayer/Views/TimelineLineView.swift:158))
- `stamp.color` → `Color(hex:)` — `trimmingCharacters` + `Scanner` **на каждое обращение**
  ([Color.swift:12](Youchip-Stat/Common/Extensions/Color.swift:12)), а обращений 3 на штамп
  (два в градиенте + тень)
- `Array(line.stamps.enumerated())` — новая аллокация массива на рендер
- `videoManager.timelineDuration` → `player?.currentItem?.duration.seconds`, обращение в
  AVFoundation, на каждую строку ([TimelineLineView.swift:84](Youchip-Stat/Modules/VideoPlayer/Views/TimelineLineView.swift:84))

### Усилитель 6 — `GeometryReader` и `.sheet` на каждый элемент

- `GeometryReader` в корне `TimelineLineView.body` (лишний layout-проход на строку)
- `GeometryReader` внутри `StampLabelsOverlayView` — **на каждый штамп**
- **Два `.sheet(item:)` на каждую строку** (`commentEditingStamp`, `sessionPickerStamp`)
  ([TimelineLineView.swift:126](Youchip-Stat/Modules/VideoPlayer/Views/TimelineLineView.swift:126)) →
  при 20 строках это 40 presentation-хостов
- `StampLabelsOverlayView` держит свой `@ObservedObject tagLibrary` — то есть **каждый штамп**
  подписан ещё и на `TagLibraryManager`
- В `updateDisplayedLabels` — `String.size(withSystemFontOfSize:)`, реальное измерение текста,
  на каждый лейбл каждого штампа

### Усилитель 7 — дубли и «жирные» слои

- `TimelineTimestampsHeaderView` рендерится **дважды**: в скролле
  ([FullControlView.swift:774](Youchip-Stat/Modules/VideoPlayer/Views/FullControlView.swift:774))
  и в закреплённой шапке (PinnedTimelineRulerView.swift:48). Первая версия при этом полностью
  скрыта под закреплённой шапкой — 240 `Text` + 240 `String(format:)` вхолостую, 30 раз/сек.
- `TimeGridView` — `Canvas` шириной `gridWidth` и высотой `30 × (lines.count + 1)`. Лимит на
  число линий (550) есть, лимита на **размер слоя** нет. При максимальном зуме
  `maxScale = duration/10` — для матча 90 мин это 540× → `gridWidth ≈ 650 000 pt`. Слой такой
  ширины — прямой удар в CoreAnimation render-server и в память.
- `TimelineScrollControllerAttacher.updateNSView` делает `DispatchQueue.main.async` с проходом
  по иерархии NSView **на каждый апдейт** → 30 обходов/сек
  ([TimelineAutoScrollHelper.swift:289](Youchip-Stat/Modules/VideoPlayer/Views/TimelineAutoScrollHelper.swift:289)).
- В review-режиме `reviewCurrentTime` и `currentTime` присваиваются подряд
  ([VideoPlayerManager.swift:284](Youchip-Stat/Modules/VideoPlayer/Managers/VideoPlayerManager.swift:284)) →
  **два** `objectWillChange` на тик вместо одного.

### Отдельно: залипания при *изменении* разметки (не при воспроизведении)

`TimelineDataManager.updateTimelines()`
([TimelineDataManager.swift:464](Youchip-Stat/Modules/VideoPlayer/Managers/TimelineDataManager.swift:464))
на каждую мутацию делает `JSONEncoder().encode(lines)` + `UserDefaults.set(data:)`
**синхронно на главном потоке**
([InMemoryStorageManager.swift:38](Youchip-Stat/Common/Managers/InMemoryStorageManager.swift:38)).
Вызывается из ~12 мест: добавление тега, ресайз, перенос штампа, правка лейблов, комментарий,
удаление, сортировка. При 20 таймлайнах это многомегабайтный энкод на каждое действие — «залипло
на пол-секунды при постановке тега».

Плюс любая мутация `lines` инвалидирует **все** строки (общий `objectWillChange`), даже если
изменился один штамп.

---

## Порядок работ (по соотношению «эффект / риск»)

Каждая фаза самостоятельна и проверяема. Останавливаться можно после любой.

### Фаза 0 — измерить, чтобы не оптимизировать наугад (0.5 дня)

- [ ] Xcode Instruments → **Time Profiler** + **SwiftUI** template, сценарий: проект на 20
      таймлайнах, воспроизведение 10 сек, затем горизонтальный скролл, затем постановка тега.
      Зафиксировать baseline: % main thread, число `body` вызовов, самые дорогие фреймы.
- [ ] Временный дебажный счётчик в `FullControlView.body`, `TimelineLineView.body`,
      `ScreenshotMarkersView.body` (`os_signpost` или `print` раз в секунду) — чтобы видеть
      реальное число пересчётов до/после. Убрать перед мержем.
- [ ] `Self._printChanges()` в `FullControlView.body` и `TimelineLineView.body` (только в
      `#if DEBUG`) — покажет, какое именно свойство инвалидирует.

**Критерий приёмки всей задачи:** на паузе — 0 пересчётов `TimelineLineView.body` в секунду;
при воспроизведении — 0 пересчётов body строк, движется только плейхед; постановка тега —
без визуального фриза.

### Фаза 1 — вывести плеер из 30 Гц-цикла перестроек (максимальный эффект, малый риск)

Это одна правка, которая снимает большую часть нагрузки во всех окнах сразу.

- [x] **1.1. Отдельный «часовой» объект для времени.** Ввести
      `final class PlaybackClock: ObservableObject { @Published var time: Double }` (синглтон).
      `VideoPlayerManager` продолжает знать `currentTime` как **обычное** (не `@Published`)
      свойство, а 30 Гц-тик пишет только в `PlaybackClock.shared.time`. Тогда
      `objectWillChange` `VideoPlayerManager` перестаёт срабатывать 30 раз/сек, и все
      «случайные» подписчики (`TagLibraryView`, `VideoPlayerView`, зеркала, строки таймлайна)
      выпадают из цикла автоматически.
      *Альтернатива, если правка синглтона слишком инвазивна:* оставить `currentTime`
      `@Published`, но у всех «случайных» подписчиков заменить `@ObservedObject` на
      неподписанную ссылку (`private let videoManager = VideoPlayerManager.shared`) + точечный
      `.onReceive(videoManager.$isPlaying)` там, где реакция реально нужна. Эффект тот же,
      но правок больше и легче что-то пропустить.
- [x] **1.2. Плейхед читает время сам.** `TimelinePlayheadView` и `PinnedTimelineRulerView`
      подписываются на `PlaybackClock` (`@ObservedObject`) и вычисляют X внутри себя.
      Убрать параметр `timeOffsetToPixels` и строку
      [FullControlView.swift:828](Youchip-Stat/Modules/VideoPlayer/Views/FullControlView.swift:828).
      *Сделано.* Плюс третий потребитель, который нашёлся при инвентаризации: цифровой таймкод
      в `VideoPlayerView` вынесен в `LivePlaybackTimeLabel`.
- [x] **1.3. Автоскролл — не через `onChange` на body.** Сделано через
      `.onReceive(PlaybackClock.shared.$time)`.
      **Это было обязательно, а не «желательно»:** `onChange(of:)` сравнивает значения при
      пересчёте body, а body FullControlView после 1.1 на тик плеера больше не пересчитывается —
      автоскролл с `onChange` просто перестал бы работать. Замыкание body не инвалидирует,
      внутри двигается только `NSScrollView`. Перенос подписки внутрь `TimelineScrollController`
      не понадобился.
- [x] **1.4. Одно уведомление на тик в review-режиме.** Решилось само: `reviewCurrentTime` тоже
      переведён в обычное свойство (реактивных потребителей у него нет — читается только
      императивно из `VideoPlayerViewModel`), поэтому на тик остаётся ровно одна публикация
      через `PlaybackClock`.
- [ ] **1.5. Снизить частоту, где не нужно 30 Гц.** Тик остаётся 30 Гц для плавности плейхеда,
      но остальные потребители (`liveStreamManager`, баннеры) — через `throttle(0.25)`.
      *Отложено:* после 1.1 у часов осталось три мелких подписчика, throttle сейчас ничего не
      экономит. Вернуться, если появятся новые.
- [ ] **1.6. Кэшировать `timelineDuration`.** Сделать его закэшированным значением, которое
      обновляется при загрузке item / в live-режиме, а не читает `AVPlayerItem.duration`
      на каждое обращение.
      *Сознательно отложено в фазу 3:* смысл был в том, что `timelineDuration` читался в каждой
      из N строк 30 раз в секунду. После 1.1 body строк на тик не пересчитывается, и выигрыш
      почти исчез, а кэш `AVPlayerItem.duration` — это риск получить 0/NaN до готовности item'а.
      В фазе 3.1 длительность станет параметром строки, и вопрос закроется сам.

**Ожидаемо:** на паузе перестройки прекращаются полностью; при воспроизведении перестраивается
только плейхед (один `offset`).

### Фаза 2 — вернуть и укрепить виртуализацию строк (большой эффект, средний риск)

- [x] **2.1. Ручное окно видимости — СДЕЛАНО.** Реализация отличается от чертежа: обошлось без
      `PreferenceKey`. Смещение измеряет `timelineScrollOffsetTracker` — `GeometryReader` в
      `.background` контента, читающий `frame(in: .named("vTimelineScroll"))`; координатное
      пространство объявлено на вертикальном `ScrollView` в ОБЕИХ ветках (macOS 12/13).
      `visibleLineRange(count:)` (высота строки 30, вьюпорт ≈ `parentWindowHeight`, буфер 12)
      применяется к обеим колонкам, сверху/снизу — `Color.clear` точной высоты.
      Запись в `@State` дросселирована порогом «полстроки»: без него каждый кадр скролла
      инвалидировал бы body и виртуализация съела бы сама себя.
      **Проверено допущение:** вертикального `scrollTo` нет — более того, `proxy`, который
      `timelineContent` принимает от `ScrollViewReader`, не используется НИГДЕ (все `scrollTo`
      горизонтальные, через `timelineScrollController`). Значит окно безопасно.
      Если появится вертикальный `scrollTo` к строке — окно надо будет учесть и там.
- [ ] ~~Реализовать ручное окно видимости~~ по чертежу из памяти (в git его нет — писать
      `project_fullcontrolview_perf`): `TimelineVOffsetKey` (PreferenceKey) +
      `.coordinateSpace(name: "vTimelineScroll")` на вертикальном `ScrollView` (обе ветки
      macOS 12/13) + невидимый `GeometryReader`-трекер в `.background(timelineContent)` +
      `visibleLineRange(count:)` (rowHeight 30, viewport ≈ `parentWindowHeight`, буфер 12).
      Диапазон применяется **одинаково** к `timelineRows` и `timelineNameRows`, сверху/снизу —
      `Color.clear` фиксированной высоты, чтобы общая высота и выравнивание колонок сохранялись.
      Обязательно проверить: в коде нет вертикального `scrollTo` (только горизонтальный через
      `timelineScrollController`), иначе окно сломает прокрутку к строке.
      *Проверить в git-истории, в каком коммите правка потерялась* — возможно, её можно
      вернуть `git show`-ом, а не переписывать.
- [x] **2.2. `LazyVStack`** — **не нужен, пункт снят.** Смысл был в дополнение к 2.1, но окно
      видимости уже отдаёт наружу ~30 строк вместо 613; ленивый стек поверх этого не даёт ничего,
      а `VStack` предсказуемее по высоте (а высота здесь критична — на ней держится скролл).
      Исходная формулировка ниже.
- [ ] ~~`LazyVStack` вместо `VStack`~~ в обеих колонках (сам по себе правую колонку не
      виртуализует из-за вложенного горизонтального `ScrollView` — поэтому нужен и 2.1).
- [~] **2.3. Ограничение зума — ОТКЛОНЕНО пользователем (2026-08-13).** Зум нужен ровно такой,
      как сейчас; `maxScale = duration / 10` не трогаем. Не предлагать повторно.
- [ ] **2.3a. Тот же выигрыш без изменения зума: рисовать сетку по видимому окну.**
      Проблема остаётся: `TimeGridView` — это `Canvas` шириной во весь `gridWidth`, а на матче
      90 минут при максимальном зуме это ~650 000 pt слоя (удар в CoreAnimation и память).
      Число линий там уже ограничено (550), а размер слоя — нет.
      Решение, не затрагивающее поведение зума: рисовать сетку только по
      `timelineScrollController.documentVisibleRect` и сдвигать её за скроллом, вместо одного
      слоя на всю длину. Зум и координаты штампов при этом не меняются вообще.
- [x] **2.4. Дубль линейки убран — СДЕЛАНО.** Копия в скролле всегда полностью скрыта под
      закреплённой шапкой, то есть 240 `Text` строились вхолостую. Осталась распорка той же
      высоты (на ней выравнивание дорожек). Тап по линейке работает через закреплённую копию —
      у скрытой он всё равно был недостижим.
- [ ] ~~Убрать дубль линейки:~~ удалить `TimelineTimestampsHeaderView` из
      `timelineZStackContent` ([FullControlView.swift:774](Youchip-Stat/Modules/VideoPlayer/Views/FullControlView.swift:774)),
      оставив только закреплённую (в `PinnedTimelineRulerView`), с полосой-заглушкой той же
      высоты для выравнивания.
- [x] **2.5. `TimelineScrollControllerAttacher`** — привязываться один раз, а не обходить
      иерархию на каждый `updateNSView`. *Сделано:* ранний выход по `controller.scrollView == nil`.
      Отдельный флаг не понадобился — ссылка на скроллвью слабая, так что при пересоздании
      скроллвью она сама обнулится и привязка повторится.

### Фаза 3 — сделать строку и штамп дешёвыми (большой эффект, средний риск)

- [x] **3.1 + 3.2 + 5.4 — СДЕЛАНО одним заходом** (это оказалось одной правкой, а не тремя).
      `TimelineLineView` больше не подписчик: `videoManager`/`timelineData`/`tagLibrary` —
      обычные `private let` без `@ObservedObject`, к ним только императивные обращения из
      обработчиков. Всё, что влияет на картинку, приходит параметрами: `totalDuration`,
      `lineIndex`, `linesCount`, `selectedStampID`, `bulkSelectedStampIDs`.
      - `Equatable` + **`.equatable()` на вызове** — без второго конформанс бесполезен: SwiftUI
        сам по себе `==` у View не использует, только через `EquatableView`.
      - Колбэки в `==` намеренно не участвуют: они пересоздаются на каждый рендер родителя, и с
        ними равенство всегда было бы `false`.
      - `bulkSelectedStampIDs` — только id из ЭТОЙ строки. Передавать весь
        `stampsSelectedForSportCut` нельзя: ⌘-выбор в одной строке менял бы параметр у всех и
        ломал пропуск перерисовки.
      - Отдельный `StampLayout` (как планировалось в 3.2) не понадобился: хватило вынести
        перекрытия в `overlapCounts()` — один проход на строку вместо O(S²) на каждый рендер,
        плюс убрать `lines.firstIndex(where:)` на каждый штамп и `Array(enumerated())`.
      - 5.4 достигнута без счётчика ревизий: `TimelineLine: Equatable` уже сравнивает штампы,
        а перерисовку теперь пропускает `EquatableView`.
      - **Две ошибки, которые я по ходу внёс и откатил:** менял идентичность в `ForEach` со
        `line.id` на индекс (и у штампов — со `stamp.id` на индекс). При переупорядочивании или
        удалении из середины SwiftUI переиспользовал бы `@State` не того элемента — активный
        ресайз штампа, подсветку drop-таргета. Идентичность возвращена по id: индекс строки
        передаётся рядом через `WindowedLine`, перекрытия штампов — словарём по `stamp.id`.
- [ ] ~~Убрать подписки из `TimelineLineView`.~~ `videoManager` и `timelineData` —
      обычные `let`-ссылки, не `@ObservedObject`. Всё, что нужно строке, приходит параметрами:
      `line`, `duration`, `gridWidth`, `isSelected`, `selectedStampID`, набор
      `stampsSelectedForSportCut` для этой строки, `lineIndex`, `linesCount`.
      Сделать `TimelineLineView: Equatable` по этим значениям (и обернуть в `EquatableView`
      либо опираться на автоматическое сравнение POD-полей) — тогда строка не перерисовывается,
      пока её данные не изменились.
- [ ] **3.2. Предпосчитанная модель строки.** Ввести `struct StampLayout` (id, x, width,
      height, цвет как `Color`, `overlapCount`, флаги selected/bulk) и считать её один раз на
      строку в `TimelineDataManager`/лёгком view-model'е, кэшируя по
      `(line.id, stamps-версия, gridWidth)`. Это убирает из рендера: `getOverlapCount` (O(S²)
      → один линейный проход по отсортированным по началу штампам), `firstIndex(where:)`,
      `Array(enumerated())`.
- [x] **3.3. Кэш цветов.** *Сделано:* `ColorHexCache` в `Common/Extensions/Color.swift`, и
      `TimelineStamp.color` ходит через него. Править сами рендер-пути не понадобилось: все они
      читают цвет через `stamp.color`, так что выигрыш получили и `TimelineLineView`, и
      `StampLabelsOverlayView`, и вьюхи просмотра — одной точкой.
- [~] **3.4. Сделана только дешёвая половина.** Убран перебор всех скриншотов, который шёл на
      КАЖДЫЙ штамп внутри меню: `ScreenshotsMetadataManager.hasScreenshot(named:relatedTo:)`
      по индексу `id штампа → имена скриншотов` (перестраивается в `didSet` у `screenshots`,
      поэтому покрывает все пути мутации). Сам перевод меню «на требование» НЕ делан: это
      изменение UX правого клика, и после виртуализации меню строятся только для ~30 видимых
      строк, так что срочность упала. Формулировка исходного пункта: Не строить `menuForTag` для каждого штампа.
      Варианты: (а) `.contextMenu` только на выбранном штампе, остальным — правый клик через
      `NSEvent`/жест, который сначала выделяет штамп; (б) вынести меню в `NSViewRepresentable`
      с `NSMenu`, собираемым в `menu(for:)` в момент клика. Внутри меню заменить
      `screenshots.contains {…}` и `allLabelGroups.first(where:)` на предпосчитанные словари
      (`[UUID: Set<String>]`, `[String: String]` label→group) в `TagLibraryManager`.
- [x] **3.5. `.sheet` убраны из строки — СДЕЛАНО.** Оба листа поднялись в `FullControlView`,
      строка теперь дёргает колбэки `onEditComment` / `onPickSession`. Контекст (линия + штамп)
      носит `StampInLine: Identifiable` с `id` штампа. Было по 2 хоста на строку, стало 2 на окно.
- [ ] ~~Убрать `.sheet` из строки.~~ Оба листа (`commentEditingStamp`, `sessionPickerStamp`)
      поднять в `FullControlView` — один экземпляр на окно, состояние через колбэки строки.
- [~] **3.6. Сделан кэш измерения текста, `GeometryReader` оставлен.** `String.size(withSystemFontOfSize:)`
      теперь с кэшем (`TextSizeCache`) — реальная разметка текста шла на каждый лейбл каждого
      штампа и заново на каждый зум. А `GeometryReader` убирать НЕ стал: он задаёт фактическую
      ширину с учётом `.padding(.horizontal, 4)` вокруг вьюхи, и замена на `maxWidth` сдвинула бы
      чипы на 4pt с риском обрезки — плохой обмен. Исходная формулировка: убрать `GeometryReader` (ширина уже известна как
      `maxWidth`), убрать `@ObservedObject tagLibrary` (лейблы приходят готовыми из
      `StampLayout`), а измерение текста (`size(withSystemFontOfSize:)`) кэшировать в
      `[String: CGFloat]`.
- [x] **3.7. Корневой `GeometryReader` в строке убран — СДЕЛАНО.** Его `geometry` не
      использовался ни разу (проверено грепом), а это лишний проход лейаута на каждую строку.
- [ ] ~~Убрать корневой `GeometryReader`~~ из `TimelineLineView.body` (высота/ширина
      известны: `lineHeight`, `widthMax`).
- [x] **3.8. Главное здесь — СДЕЛАНО, и оно оказалось хуже, чем я оценил в плане.**
      `chronologicalOrdinalAmongSameTag` зовётся из `mouseMoved`, то есть до 10 раз в секунду
      пока мышь идёт по таймлайну, и каждый раз делал `flatMap` + `filter` + `sorted` по ВСЕМ
      ~7000 штампам. Переписан на подсчёт «сколько соседей раньше меня»: тот же результат,
      O(n) без аллокаций и сортировки. Порядок сравнения сохранён (время начала, при равенстве —
      строка uuid), поведение при отсутствии штампа в списке тоже (возврат 1).
      Глубокое `Equatable`-сравнение `lines` в самом трекере не тронуто. Исходно: `lines: [TimelineLine]` в `Equatable`-сравнении даёт
      глубокое сравнение всех штампов на каждый апдейт. Передавать вместо массива компактный
      снимок (или версию-счётчик) и хранить lookup-структуру внутри `TrackingView`.
      `chronologicalOrdinalAmongSameTag` в `mouseMoved` — O(всех штампов) с сортировкой на
      каждое движение мыши; предпосчитать ординалы.

### Фаза 4 — рисунки/скриншоты (средний эффект, малый риск)

- [x] **4.1. Никакого `fileExists` в body.** *Сделано:* `ScreenshotsMetadataManager`
      держит `existingImageBaseNames: Set<String>`, вьюха зовёт `hasImageFile(for:)`.
      Отдельного обхода папки не появилось: набор строится из того же листинга, которым уже
      читались метаданные. Обновляется при `loadScreenshots` (её зовут и после сохранения нового
      рисунка), `removeScreenshot`, `clearScreenshots`. Мёртвый `screenshotFileExists` удалён.
- [x] **4.2. Отвязать `ScreenshotMarkersView` от `videoManager`.** *Сделано.* А `timelineData` и
      `tagLibrary` **оставлены наблюдаемыми осознанно** — вопреки исходной формулировке пункта:
      они читаются в контенте контекстного меню (`getAvailableStampsForScreenshot`) и поповера
      со связанными тегами, то есть это тоже `body`. Снять их — значит получить устаревшее меню.
- [x] **4.3. СДЕЛАНО.** Лист «привязанные теги» поднят в `FullControlView`; `ScreenshotMarkersView`
      отдаёт наружу колбэк `onEditRelatedTags`, который прокидывает `PinnedTimelineRulerView`.
      Было по хосту листа на каждый из двух экземпляров вьюхи меток.
      Заодно убран костыль «переоткрыть лист через двойной `asyncAfter`, чтобы обновились
      данные»: `.sheet(item:)` строит содержимое в момент установки item'а, то есть уже по
      свежим данным. `ScreenshotMetadata` не `Identifiable`, поэтому обёрнут в
      `ScreenshotEditTarget`.
- [ ] ~~Один `.sheet` на окно~~, а не внутри `ScreenshotMarkersView` (который создаётся
      в двух местах). Убрать «переоткрытие листа» через двойной `asyncAfter` — это костыль,
      который лечится передачей актуальных данных в лист.

### Фаза 5 — экспорт и запись на диск (средний эффект, малый риск)

- [x] **5.1. `@State private var exportHelper`** вместо `@StateObject`, а `progress` читается
      только внутри маленького `ExportProgressOverlay(@ObservedObject …)`. *Сделано*, с
      комментарием-предупреждением «не меняй обратно» прямо у объявления.
- [x] **5.2 + 5.3 — СДЕЛАНО** (в `InMemoryStorageManager`, одной правкой — они об одном и том же
      пути записи). `saveTimelines` больше ничего не кодирует: кладёт снимок в
      `pendingTimelines` и планирует отложенный сброс (0.4 с) на своей очереди `timelineIOQueue`.
      Кодирование + запись — на фоне, серия быстрых правок даёт одну запись.
      - `DispatchWorkItem` с отменой, а не `Timer`: `saveTimelines` могут позвать не с главного
        потока, и тогда `Timer` молча не сработал бы (привязался бы не к тому раннлупу).
      - Файл теперь пишется ВСЕГДА и сразу (мы уже на фоне), UserDefaults остаётся только
        читающим кэшем и только пока блоб влезает под лимит CFPreferences. Прежний путь
        «UserDefaults → таймер 30 с → обход всех ключей → файлы» для разметки больше не нужен.
      - **Инвариант против потери данных:** `loadTimelines` СНАЧАЛА смотрит в `pendingTimelines`.
        Проверено, что этого достаточно: все чтения разметки в проекте идут через
        `VideoFilesManager.loadTimelines` → сюда (экспорт, бэкап, склейка проектов, открытие
        соседнего видео). Прямых чтений папки `Timelines` в обход менеджера нет, кроме
        `DataSyncManager` (копирование папки для бэкапа) и `TimelineMigrationManager` (старт).
      - Принудительные сбросы: `flushTimelinesNow()` зовётся из `applicationWillTerminate` и из
        `saveToDiskImmediate()` (до проверки `pendingSave` — у отложенной разметки своя очередь).
      - `deleteTimelines` снимает отложенную запись, иначе она воскресила бы удалённое.
- [ ] ~~`updateTimelines()` — не на главном потоке и с коалесингом.~~ Дебаунс ~0.3–0.5 с +
      `JSONEncoder().encode` на `DispatchQueue.global(qos: .utility)`. На выходе из окна /
      `applicationWillTerminate` — принудительный сброс. Сейчас энкод многомегабайтного массива
      идёт синхронно на main из ~12 точек мутации.
- [x] **5.3.** См. 5.2 — сделано там же. ~~Не гонять данные через `UserDefaults`.~~ `userDefaults.set(data:)` для
      многомегабайтного блоба — дорого и уже требует ручной защиты от лимита 4 МБ
      ([InMemoryStorageManager.swift:41](Youchip-Stat/Common/Managers/InMemoryStorageManager.swift:41)).
      Писать таймлайны сразу в файл (атомарно), UserDefaults оставить только под мелкие ключи.
- [ ] **5.4. Гранулярные апдейты вместо `lines` целиком.** Рассмотреть версионный счётчик на
      строку (`TimelineLine.revision`), чтобы правка одного штампа не заставляла SwiftUI
      считать изменёнными все строки.

### Фаза 6 — прочее окружение редактора (малый эффект, малый риск)

- [ ] **6.1. `TagLibraryView`** (2712 строк): после фазы 1 она выпадет из 30 Гц-цикла, но
      стоит проверить профайлером её собственную стоимость body и разбить на под-View с
      `Equatable` там, где она перестраивается на любое изменение `TagLibraryManager`.
- [x] **6.2. Индексы в `TagLibraryManager`.** *Сделано частично, осознанно.* Словари по id
      собираются в `didSet` соответствующих `@Published`-массивов (пересборка редкая — только
      смена/перезагрузка коллекции). `uniquingKeysWith: { first, _ in first }` обязателен:
      дубли id между коллекциями штатны, а `uniqueKeysWithValues` уронил бы приложение — и
      «первый побеждает» точно повторяет семантику `first(where:)`, которую индексы заменяют.
      - Переведены: `findTagById`, `findLabelById`; добавлен `findTimeEventById` и применён в
        трёх горячих местах (`StampLabelsOverlayView`, `TimelineLineView.menuForTag`,
        `TimelineMouseTracker`) — там замена побайтово эквивалентна.
      - `findGroupForLabel` добавлен, но **нигде не подключён**: инлайн-поиски группы в отрисовке
        ищут только по пулу `allLabelGroups` (без приоритета выбранной коллекции) и имеют второй
        фолбэк по `lableGroupId`. Перевод их на общее правило — изменение поведения в том самом
        месте, где только что чинили дубли id, поэтому отложено в 3.4 и требует решения.
      - `findTagGroupForTag` и `findLabelsForTag` не тронуты: они возвращают выборки/`filter`,
        индекс по id там не применяется напрямую, а в горячем пути их нет.
- [x] **6.3. `secondsToTimeString` — СДЕЛАНО.** Ручная сборка вместо `String(format:)`
      (NSString-форматирование). Вывод побайтово тот же. Исходно: использует `String(format:)` (NSString-форматирование) —
      480 вызовов на тик из двух линеек. После 2.4 останется 240; при желании заменить на
      ручную сборку строки.
- [x] **6.4. Проверено — трогать не нужно.** Таймер 0.5 с создаётся в `Coordinator`, то есть
      один на каждый ЖИВОЙ `FocusAwareTextField`, а не один на приложение. Но все 14 его
      использований — в листах и редакторах коллекций (`AddLineSheet`, `EditTimelineNameSheet`,
      редактор связок и т.п.), в таймлайне разметки его нет вообще. К тормозам на большой
      разметке отношения не имеет. (Смежный смелл — `static var nsView` один на все экземпляры —
      к производительности не относится, но если полезут баги с фокусом, смотреть сюда.)

---

## Сводка ожидаемого эффекта

| Фаза | Что уходит | Ожидание |
|---|---|---|
| 1 | 30 Гц-перестройка ~7 деревьев View во всех окнах | основной выигрыш; на паузе UI полностью «замолкает» |
| 2 | материализация всех N строк + гигантские слои | линейная зависимость от числа таймлайнов исчезает |
| 3 | O(S²) + 600 контекстных меню + 40 sheet на окно | плавный скролл и выделение при 100+ таймлайнов |
| 4 | тысячи `stat()` в секунду на main | пропадают микрофризы при скролле |
| 5 | синхронный JSON-энкод на main при каждой правке | пропадает залипание при постановке тега |
| 6 | линейные поиски и лишнее форматирование | «полировка» |

## Риски и что легко сломать

- **Фаза 1** меняет способ доставки времени. Проверить: плейхед, автоскролл при
  воспроизведении, скраб плейхеда (обе точки — в скролле и в закреплённой шапке), live-режим,
  review-режим, зеркальные окна, окно просмотра.
- **Фаза 2.1** (окно видимости) — самая аккуратная часть: рассинхрон левой и правой колонок
  ловится глазами сразу. Обязательно один и тот же `range` для обеих. При «мигании» пустотой
  на быстром скролле — увеличивать буфер (был 12).
- **Фаза 2.3** — отклонена: зум остаётся как есть (решение пользователя, 2026-08-13). Вместо
  неё 2.3a — сетка по видимому окну, поведение зума не меняется.
- **Фаза 3.4** (контекстное меню) — меняет UX правого клика; нужно сохранить все текущие пункты.
- **Фаза 5.2/5.3** — трогает персистентность. Обязательно проверить: сохранение при закрытии
  окна, при выходе из приложения, при переключении видео, отсутствие потери разметки после
  краша (сброс по дебаунсу + на `willTerminate`).
- Сборка после каждой фазы: `xcodebuild -workspace Youchip-Stat.xcworkspace -scheme Youchip-Stat
  -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet` (запускает пользователь).

## Затронутые модули / файлы

- [[../knowledge/modules/VideoPlayer]] — основной модуль
- `Youchip-Stat/Modules/VideoPlayer/Views/FullControlView.swift` (3513 стр.)
- `Youchip-Stat/Modules/VideoPlayer/Views/TimelineLineView.swift`
- `Youchip-Stat/Modules/VideoPlayer/Views/StampLabelsOverlayView.swift`
- `Youchip-Stat/Modules/VideoPlayer/Views/TimeGridView.swift`
- `Youchip-Stat/Modules/VideoPlayer/Views/TimelineTimestampsHeaderView.swift`
- `Youchip-Stat/Modules/VideoPlayer/Views/TimelinePlayheadView.swift`
- `Youchip-Stat/Modules/VideoPlayer/Views/PinnedTimelineRulerView.swift`
- `Youchip-Stat/Modules/VideoPlayer/Views/TimelineAutoScrollHelper.swift`
- `Youchip-Stat/Modules/VideoPlayer/Views/TagLibraryView.swift`
- `Youchip-Stat/Modules/VideoPlayer/Managers/VideoPlayerManager.swift`
- `Youchip-Stat/Modules/VideoPlayer/Managers/TimelineDataManager.swift`
- `Youchip-Stat/Modules/VideoPlayer/Managers/TagLibraryManager.swift`
- `Youchip-Stat/Modules/VideoPlayer/Managers/ScreenshotsMetadataManager.swift`
- `Youchip-Stat/Common/Managers/InMemoryStorageManager.swift`
- `Youchip-Stat/Common/Extensions/Color.swift`

## Журнал работы

- 2026-08-13 (developer): проведён ресерч, задача заведена и декомпозирована на 6 фаз.
- 2026-08-13 (developer): **фаза 1 написана, ждёт сборки и проверки руками.**
  - Инвентаризация перед правкой (это оказалось ключевым): из 172 упоминаний `currentTime` в
    проекте **реактивная зависимость всего одна** — `onChange` автоскролла. Остальные читают
    время императивно, в обработчиках (`TagLibraryView` — 18 мест, `VideoPlayerViewModel` — 2),
    и от перевода свойства в обычное не страдают. `$currentTime` / `$reviewCurrentTime` не
    используются нигде, так что молча «отвалиться» ничему не грозит.
  - Реально живых чтений в `body` было четыре: плейхед в скролле, линейка в шапке, таймкод в
    `VideoPlayerView` и `onChange` автоскролла. Все четыре переведены на `PlaybackClock`.
  - Файлы: `PlaybackClock.swift` (новый), `VideoPlayerManager.swift`, `TimelinePlayheadView.swift`,
    `PinnedTimelineRulerView.swift`, `FullControlView.swift`, `VideoPlayerView.swift`.
  - Побочно: удалён осиротевший `VideoPlayerView.formatDuration`.
  - 1.5 и 1.6 сознательно отложены — см. отметки в фазе 1, после 1.1 они потеряли смысл.
- 2026-08-13 (developer): **второй заход — «невидимые» правки** (не меняют вёрстку, поэтому
  безопасно делать до сборки первого захода): 2.5, 3.3, 4.1, 4.2, 5.1, 6.2. Всё ждёт сборки.
  - Файлы: `ScreenshotsMetadataManager.swift`, `TagLibraryManager.swift`, `Color.swift`,
    `TimelineStamp.swift`, `TimelineAutoScrollHelper.swift`, `FullControlView.swift`,
    `StampLabelsOverlayView.swift`, `TimelineLineView.swift`.
  - Побочно удалено мёртвое: `screenshotFileExists`.
  - **Ложная тревога, чтобы не повторять.** По ходу решил, что приватные хранимые свойства
    ломают memberwise-инициализатор (правило «init становится private, если хоть одно свойство
    private») и снял `private` у трёх вьюх. Проверил на существующем коде: у самого
    `TimelinePlayheadView` есть `private let hitWidth = 16` рядом с memberwise-инициализатором,
    который зовут из другого файла, и это собирается. Значит приватные свойства **со значением
    по умолчанию** в memberwise-инициализатор не попадают и доступность его не понижают;
    правило из книги — про свойства БЕЗ дефолта. `private` возвращён.
  - Что НЕ сделано намеренно (детали в отметках пунктов): 4.3, перевод инлайн-поисков группы
    лейбла на `findGroupForLabel` (меняет поведение → в 3.4).
- 2026-08-13 (developer): **сборка зелёная, пользователь подтвердил «стало лучше».**
  Закоммичено: `2313296`.
  **Но на реальном большом проекте (613 таймлайнов, ~7000 тегов) тормоза остались:**
  добавление тега залипает ~5 секунд, скролл дёргается. Разобрал причины:
  - счётчики тегов (`TagLibraryView.updateTagCounts` по `.stampCountsChanged`) — один линейный
    проход по 7000 штампов, НЕ виновник, проверено;
  - `ClipAutoSaveManager.autoSaveStampIfConfigured` — ранний выход, если авто-экспорт выключен,
    тоже не виновник;
  - остаются два: (а) полная перестройка 613 строк при любом изменении `lines` — у каждой строки
    свой `GeometryReader`, у каждого штампа контекстное меню, плюс по 2 `.sheet` на строку, то
    есть ~1226 presentation-хостов; (б) синхронный `JSONEncoder().encode(lines)` +
    `UserDefaults.set` многомегабайтного блоба на главном потоке при каждой мутации.
  Сделана 2.1 (окно видимости) — она бьёт по (а) и по обоим симптомам сразу. **Ждёт сборки.**
  Следующий шаг зависит от замера: если после виртуализации залипание при добавлении тега
  осталось заметным — виновата (б), то есть 5.2/5.3.

## Результат

_(заполняется по мере выполнения)_
