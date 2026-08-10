---
id: TASK-001
title: Фиксы автосохранения клипов в папку + баннер уведомлений + merged-экспорт по Opt+Cmd+S
status: in-progress    # backlog | in-progress | review | done
assignee: developer
created: 2026-08-02
updated: 2026-08-02
tags: [VideoPlayer, ClipAutoSave, hotkeys, export, feedback]
---

# TASK-001 — Фиксы автосохранения клипов в папку

## Постановка (со слов пользователя)
Фидбек по уже реализованной фиче «сохранение тегов/клипов сразу в заданную папку на компе»:

1. **Не сохраняет клип в выбранную папку** — как во время записи, так и после завершения.
   Комбинация срабатывает, на экране появляется оповещение «тег сохранён», но файла в папке нет.
2. **Не предлагает выбрать папку при новой записи.**
3. **Баннер уведомления о сохранённом теге переделать**: показывать в правом нижнем углу
   экрана (вне зависимости от расположения окон) и делать самоисчезающим — без кнопки «ОК».
   Критично, когда аналитик быстро работает в лайве.
4. **Opt+Cmd+S** — сохранение выделенных клипов в виде склеенного (merged) фильма сразу на комп.
   (К фидбеку было приложено видео, но оно НЕ подгрузилось — детали ожидаемого поведения
   неизвестны, см. «Открытые вопросы».)

## Затронутые модули / файлы
- [[../knowledge/modules/VideoPlayer]] — режим «Разметка», где живёт фича.
- `Youchip-Stat/Modules/VideoPlayer/Managers/ClipAutoSaveManager.swift` — весь менеджер
  автосохранения: папка (bookmark), `saveSelectedStampClip()`, экспорт `AVAssetExportSession`.
  - `:101` `saveSelectedStampClip()` — экспорт выбранного стампа.
  - `:194` `selectedStampAndName()` — **ключ к багу 1**: берёт стамп только из
    `TimelineDataManager.shared.selectedStampID`.
  - `:53` `pickFolder()`, `:38` `refreshFolderState()`, `:19` bookmarkKey (глобальный, не per-session).
- `Youchip-Stat/Modules/VideoPlayer/Managers/HotKeyManager.swift`
  - `:237-249` — обработчик Cmd+S (`keyCode == 1`, `.command`, `!.option`) →
    `ClipAutoSaveManager.shared.saveSelectedStampClip()`. Здесь же добавить ветку **Opt+Cmd+S**.
- `Youchip-Stat/Modules/VideoPlayer/Managers/TimelineDataManager.swift`
  - `:30` `lastAddedStampID` (private(set)) — id только что созданного стампа (НЕ selected).
  - `:283-337` `addStampToSelectedLine(...)` — на `:315`/`:336` пишет `lastAddedStampID`, но
    **не** `selectedStampID`. Отсюда рассинхрон: записанный тег не является «выбранным».
  - `:32` `stampsSelectedForSportCut: Set<UUID>` — уже существующий мультивыбор стампов,
    кандидат-источник «выделенных клипов» для п.4.
- `Youchip-Stat/Modules/VideoPlayer/Managers/VideoMarkupActivityBanner.swift`
  - `:97` `showInfoToast(_:)`, `:101` `showTransientToast(...)` (автоскрытие 2с уже есть).
  - `:131` `VideoMarkupActivityOverlay` — оверлей истории/REC, сейчас якорится в **верхнем
    левом** углу (`.topLeading`, `padding(.leading/.top)`), ширина/высота ограничены.
  - `:227` `VideoMarkupInlineStatusView` — инлайн-строка тоста.
  - **Баг 3**: нужно вынести уведомление в правый нижний угол экрана независимо от окон.
- `Youchip-Stat/Modules/VideoPlayer/Views/TagLibraryView.swift`
  - `:956`,`:1003` `notifyInstantTagAdded(...)`; `:1031`,`:1634` `completeIntervalRecording(...)`;
    `:1330`,`:1549`,`:1835` `startIntervalRecording(...)` — источник тоста «тег сохранён»,
    который пользователь принимает за подтверждение сохранения клипа.
  - `:943`,`:989`,`:1017`,`:1621` `addStampToSelectedLine(...)` — точки создания стампа;
    здесь потенциальная точка авто-сохранения клипа/авто-выбора стампа.
- `Youchip-Stat/Modules/VideoPlayer/Views/FullControlView.swift`
  - `:1649-1697` `clipAutoSaveButton` — единственный вход в `pickFolder()` (бейдж в тулбаре).
- `Youchip-Stat/Modules/VideoPlayer/Managers/WindowsManager.swift`
  - `:242`,`:286`,`:329`,`:823` — старт новой сессии разметки
    (`clearTagMarkupHistoryForNewVideoSession()`), удобные хуки для промпта выбора папки (баг 2).
- `Youchip-Stat/Modules/VideoPlayer/Helpers/ExportHelper.swift`
  - `:222` `exportFilm(segments:asset:type:...)` и `:299` `insertTimeRange(...)` — готовая логика
    склейки сегментов в одну композицию; переиспользовать для merged-экспорта (п.4).
- `Youchip-Stat/Common/Extensions/LocalizedStrings.swift` — ключи `clipAutoSave*`
  (`^String.Titles.clipAutoSave...`). Новые строки для промпта/merged добавлять сюда + во все
  локали `Resourses/` (ru_RU, en, es, fr, uz, zh-Hans), см. [[../knowledge/conventions/localization]].

## Гипотезы по багам

### Баг 1 — «оповещение есть, файла нет» (высокая уверенность)
`saveSelectedStampClip()` берёт стамп **только** из `TimelineDataManager.shared.selectedStampID`
(`ClipAutoSaveManager.swift:196`). Но при записи интервала/мгновенного тега созданный стамп
пишется в `lastAddedStampID` (`TimelineDataManager.swift:315/336`), а `selectedStampID` **не**
проставляется. Значит:
- «во время записи» — стампа ещё нет (записан только старт), экспортировать нечего;
- «после записи» — стамп есть как `lastAddedStampID`, но не выбран → `selectedStampAndName()`
  возвращает `nil` → показывается **модальный alert** «нет выбранного стампа» (а не сохранение),
  либо, если ранее вручную был выбран старый стамп, экспортируется **не тот** клип.

Тост «тег сохранён», который видит пользователь — это НЕ тост автосохранения клипа, а
маркап-тост из `completeIntervalRecording` / `notifyInstantTagAdded` (TagLibraryView), не
связанный с записью файла. Отсюда ложное ощущение «сохранилось».

Направление фикса (уточнить с продуктом): либо (а) Cmd+S/автосейв нацеливать на
`lastAddedStampID`, когда `selectedStampID == nil`; либо (б) авто-сохранять клип по завершении
записи интервала / добавлении мгновенного тега (в `completeIntervalRecording`/после
`addStampToSelectedLine`). Также проверить, что запись реально доходит до export и не падает
на security-scoped доступе (добавить временный лог статуса/ошибки сессии).

### Баг 2 — «не предлагает выбрать папку при новой записи» (высокая уверенность)
`pickFolder()` вызывается только из бейджа в `FullControlView` (`:1657/1664`). Bookmark
хранится глобально в UserDefaults (`clipAutoSaveFolderBookmark`) и никак не привязан к сессии.
На старте новой сессии/записи промпта нет — пользователь должен сам найти бейдж. Нужно на хуке
старта сессии разметки (`WindowsManager` рядом с `clearTagMarkupHistoryForNewVideoSession()`),
если папка не сконфигурирована, предложить выбрать её (или показать явный CTA). Уточнить у
продукта: промпт при КАЖДОЙ новой записи или только когда папка не задана.

## План (декомпозиция от tech-lead)

### Пункт 1 — фактическое сохранение клипа
- [ ] Определить целевой стамп надёжно: fallback на `lastAddedStampID`, когда
      `selectedStampID == nil`, в `ClipAutoSaveManager.selectedStampAndName()`
      (`ClipAutoSaveManager.swift:194`). Согласовать с продуктом поведение «во время записи».
- [ ] Добавить временную диагностику (лог `session.status` / `session.error`, наличие файла
      по `outputURL`), воспроизвести и подтвердить реальную причину незаписи.
- [ ] Убедиться, что security-scoped доступ к папке держится до конца экспорта (сейчас держится,
      `:111-117`) и что запись .mov в выбранную папку реально проходит.
- [ ] Развести тосты: тост автосохранения клипа («клип сохранён в …») должен визуально
      отличаться от маркап-тоста «тег сохранён», чтобы не путать пользователя.

### Пункт 2 — предложить выбрать папку при новой записи
- [ ] На хуке старта новой сессии разметки (`WindowsManager.swift:242/286/329/823`) при
      `!ClipAutoSaveManager.shared.isFolderConfigured` предложить `pickFolder()` или показать
      заметный CTA. Не блокировать работу, если пользователь отказался.
- [ ] Не спрашивать повторно в рамках той же сессии, если пользователь отклонил (флаг сессии).

### Пункт 3 — баннер в правый нижний угол + автоскрытие
- [ ] Переместить уведомление «тег сохранён»/«клип сохранён» в правый нижний угол экрана
      (screen-space, независимо от расположения окон разметки). Рассмотреть отдельное
      borderless NSPanel поверх экрана (по аналогии с оверлеями), т.к. текущий
      `VideoMarkupActivityOverlay` живёт внутри окна и якорится в верхнем левом углу.
- [ ] Убедиться в самоисчезновении без «ОК» (в `showTransientToast` таймер 2с уже есть,
      `VideoMarkupActivityBanner.swift:114`) и что нигде для этих уведомлений не используется
      модальный `NSAlert`.
- [ ] Не перехватывать клики (`allowsHitTesting(false)`), чтобы не мешать лайв-разметке.

### Пункт 4 — Opt+Cmd+S: merged-экспорт выделенных клипов
- [ ] Добавить в `HotKeyManager.swift` (рядом с `:237-249`) ветку Opt+Cmd+S
      (`keyCode == 1`, `.command` + `.option`) → новый метод сохранения merged-фильма.
- [ ] Источник «выделенных клипов» — согласовать: вероятно `stampsSelectedForSportCut`
      (`TimelineDataManager.swift:32`). Собрать сегменты и склеить через переиспользование
      логики `ExportHelper.exportFilm(...)` (`ExportHelper.swift:222`).
- [ ] Сохранить результат в папку автосохранения (или спросить папку) одним файлом .mov/.mp4.
- [ ] Показать прогресс/итог через баннер (см. п.3), ошибки не глотать.
- [ ] ⚠️ Заблокировано открытым вопросом: точное ожидаемое поведение из невыгруженного видео.

### Общие
- [ ] Новые строки локализованы во всех локалях `Resourses/` (см. localization-конвенцию).
- [ ] Сборка проходит (`BUILD SUCCEEDED`).
- [ ] Ревью пройдено ([[../reviews/…]]).

## Что делегировать / что проверить
- **developer**: пункты 1→2→3→4 (в этом порядке; п.4 стартовать после ответа на открытый вопрос).
- **reviewer**: корректность выбора стампа (selected vs lastAdded), удержание security-scoped
  доступа, отсутствие модальных alert'ов для лайв-уведомлений, покрытие локализации.
- **tester**: сборка + ручной чек-лист:
  1) записать интервал/мгновенный тег → Cmd+S → файл реально появился в папке;
  2) старт новой записи без заданной папки → предложен выбор папки;
  3) уведомление — правый нижний угол, само исчезает, без «ОК», не блокирует клики;
  4) Opt+Cmd+S на нескольких выделенных клипах → один склеенный файл на диске.

## Открытые вопросы
- **П.4 (блокер):** приложенное к фидбеку видео не подгрузилось — неизвестно точное ожидаемое
  поведение Opt+Cmd+S: что считается «выделенными клипами» (мультивыбор стампов таймлайна
  `stampsSelectedForSportCut`? клипы плейлиста SportCut?), формат/имя итогового файла, куда
  сохранять (та же папка автосейва или отдельный диалог), порядок склейки. Запросить у пользователя.
- **П.1:** во время записи (интервал ещё не закрыт) — что должен делать Cmd+S? Игнорировать,
  закрыть интервал и сохранить, или сохранить накопленный отрезок? Уточнить.
- **П.2:** предлагать выбор папки при КАЖДОЙ новой записи или только если папка не задана?
- **П.1 фикс:** нацеливать автосейв на `lastAddedStampID` (последний записанный) или всё же
  на явно выбранный стамп? Влияет на UX в лайве.

## Журнал работы
- 2026-08-02 (tech-lead): задача заведена, проведено исследование кодовой базы,
  сформулированы гипотезы по багам 1 и 2, декомпозирован план по 4 пунктам.
- 2026-08-03 (main/inline): применены правки по ревью `reviews/TASK-001.md` (без спавна агентов).
  Сборка зелёная (exit 0, нет `error:`).
  - **Замечание №1 (глушить ошибки на авто-пути):** и Cmd+S, и авто-сейв проведены через ОДНУ
    последовательную очередь `pendingExports: [PendingExport]` с флагом `silentErrors`. Авто-путь
    (`autoSaveStampIfConfigured`) → `silentErrors=true`: некритичные ошибки (нулевой диапазон
    инстант-тега и т.п.) больше не кидают красный тост, только `print`. Явный Cmd+S → `silentErrors=false`,
    ошибки видны. Успех-тост «клип сохранён» показывается в обоих случаях.
  - **Замечание №4 (гонка Cmd+S мимо очереди):** устранена тем же объединением очереди — Cmd+S теперь
    `pendingExports.append(...)` + `drainPendingQueue()`, параллельных экспортов нет.
  - **Замечание №3 (мульти-карта перезатирает файлы):** добавлен `uniqueOutputURL(in:fileName:)` —
    при занятом имени добавляет « (2)», « (3)»… Применён и к одиночному, и к merged-экспорту (убран
    `removeItem`-overwrite).
  - **Замечание №5 (повторный промпт папки):** флаг `didPromptFolderThisSession` в
    `promptFolderForNewSessionIfNeeded()` — если папку не задали/отменили, за сессию больше не спрашиваем.
  - **Замечание №2 (источник Opt+Cmd+S):** подтверждён пользователем — `stampsSelectedForSportCut`
    (мультивыбор таймлайна). Реализация developer верна, изменений не требует.
  - Мелочь: merged-экспорт в конце дёргает `drainPendingQueue()`, чтобы авто-сейвы, накопившиеся за
    время склейки, не застряли.
- 2026-08-02 (developer): реализованы все 4 пункта, BUILD SUCCEEDED.

  **Пункт 1 — реальное сохранение клипа.**
  - `ClipAutoSaveManager.selectedStampAndName()` теперь целится: явный `selectedStampID` →
    fallback `lastAddedStampID` (вынес общий `stampAndName(forID:)`). Cmd+S больше не мажет мимо.
  - Добавлен автотриггер сохранения: `TimelineDataManager.addStampToSelectedLine(...)` по факту
    добавления штампа (любой путь — instant/interval/multi-map, оба режима) вызывает
    `ClipAutoSaveManager.autoSaveStampIfConfigured(stampID:)`. Молча выходит, если папка не задана.
  - Экспорт идёт через последовательную очередь `pendingStampIDs` — быстрые подряд-теги в лайве
    не теряются (раньше `guard !isSaving` просто дропал второй).
  - Честная диагностика: «сохранено» показывается только при `.completed` И реально существующем
    файле (`FileManager.fileExists`). Иначе — тост-ошибка + `print(status/error)`. Убраны модальные
    `NSAlert` из лайв-потока (нет папки / нет штампа / ошибка → неблокирующий тост).
  - Тосты разведены: маркап-тост «тег добавлен» остаётся в окне (VideoMarkupInlineStatusView),
    «клип сохранён в папку» — новый screen-space тост (см. п.3).

  **Пункт 2 — выбор папки.** Оба варианта:
  - Новый `ClipAutoSaveManager.promptFolderForNewSessionIfNeeded()` вызывается на 4 хуках старта
    сессии разметки в `WindowsManager` (openVideo/openLiveVideo/…): если папка не задана — асинхронно
    показывает `pickFolder()` (не блокирует открытие окон). Если задана — тихо использует её.
  - Кнопка смены папки в тулбаре `FullControlView.clipAutoSaveButton` не тронута, работает как прежде.

  **Пункт 3 — screen-space тост.** Новый файл `ClipSaveToastPresenter.swift`: borderless
  `.nonactivatingPanel` в правом нижнем углу `visibleFrame` текущего экрана (key window screen →
  `NSScreen.main`), `ignoresMouseEvents = true`, level `.statusBar`, автоскрытие 2.5с, без кнопок.
  Стили success/error/info. Все уведомления об автосохранении/склейке идут через него.

  **Пункт 4 — Opt+Cmd+S.** В `HotKeyManager` добавлена ветка `keyCode==1 + .command + .option`
  (перед Cmd+S) → `ClipAutoSaveManager.saveMergedSelectedClips()`. Источник клипов —
  `TimelineDataManager.stampsSelectedForSportCut`, сортировка по времени, склейка в одну
  `AVMutableComposition` (видео+аудио, без оверлеев/скриншотов), экспорт `.mov` в папку автосейва
  (если папка не задана — `pickFolder()`). Пустой выбор → неблокирующий тост. Ошибки не глотаются.

  **Локализация:** новые ключи `clipAutoSaveNoSelectedClips`, `clipAutoSaveMergedInProgress`,
  `clipAutoSaveMergedSuccess`, `clipAutoSaveMergedPrefix` — в `LocalizedStrings.swift` + все 7 локалей
  (ru, en, es, fr, uz, zh-Hans, zh-Hant).

  **Изменённые/новые файлы:**
  - NEW `Youchip-Stat/Modules/VideoPlayer/Managers/ClipSaveToastPresenter.swift`
  - `Youchip-Stat/Modules/VideoPlayer/Managers/ClipAutoSaveManager.swift`
  - `Youchip-Stat/Modules/VideoPlayer/Managers/TimelineDataManager.swift`
  - `Youchip-Stat/Modules/VideoPlayer/Managers/HotKeyManager.swift`
  - `Youchip-Stat/Modules/VideoPlayer/Managers/WindowsManager.swift`
  - `Youchip-Stat/Common/Extensions/LocalizedStrings.swift`
  - `Youchip-Stat/Resourses/{ru,en,es,fr,uz,zh-Hans,zh-Hant}.lproj/Localizable.strings`

  **Спорное/на уточнение:**
  - П.4: источником «выделенных клипов» взят `stampsSelectedForSportCut` (⌘-клик мультивыбор
    штампов таймлайна), т.к. исходное видео фидбека не подгрузилось. Формат — один `.mov`
    «Подборка_N_timestamp». Порядок — по времени старта. Если имелись в виду клипы плейлиста
    SportCut — переделать источник.
  - П.1: в лайве merged/clip-export берёт `getCurrentVideoURL()` напрямую (как и было в Cmd+S),
    без live-снапшота композиции. Если нужно сохранять ещё не финализированный live-отрезок —
    отдельная задача.
  - П.2: сейчас промпт папки только когда она НЕ задана (не при каждой новой записи) — как решено.

## Результат
_(заполняется по завершении)_
