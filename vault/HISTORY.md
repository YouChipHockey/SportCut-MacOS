# История задач (changelog)

Сквозной журнал выполненных задач. **Новые записи — сверху.** Одна запись на задачу.
Формат: дата · заголовок · что просили · что сделано · как правилось (файлы/подход).

Пишется по правилу из `CLAUDE.md` после каждой выполненной задачи.

---

## 2026-08-12 — Дубли id коллекций разводятся автоматически (корень проблемы)
- **Задача:** убрать саму причину дублей, а не лечить последствия. Приоритет текущей коллекции в
  `findTagById` (запись ниже) — это защита по месту; здесь коллекции перестают делить id вообще.
- **Как решили (по согласованию):** ловим при ИМПОРТЕ, пользователя не спрашиваем — если
  пересечение найдено, молча перевыдаём id. Плюс дублирование коллекции. Экспорт не трогаем: он
  пишет файл и не знает, куда его импортируют, а сверять там не с чем.
- **Новое:** `CollectionIdRegenerator` (Modules/VideoPlayer/Managers).
  - `occupiedIds()` — все id сущностей установленных коллекций (пользовательских И стандартных:
    стандартные тоже попадают в общий пул).
  - `collides(...)` — есть ли пересечение.
  - `regenerate(...)` — копия коллекции со свежими id и перевязкой ВСЕХ ссылок: `TagGroup.tags`,
    `LabelGroupData.lables`, `Tag.lablesGroup`, **ключи `Tag.labelHotkeys` (это id лейблов)**,
    `Tag.mapFieldId`/`mapFieldIds`, а также раскладка — `TagFreeLayoutItem.elementId` по kind и
    `KeyBinding.sourceId/targetId` (id самой связки тоже новый). Элементы и связки, чей id не
    отобразился, выкидываются. `Tag.primaryID` НЕ трогаем — это сквозной идентификатор смысла
    тега между копиями, по нему сшивается разметка разных проектов.
- **Точки применения:**
  - `CollectionImportManager.importCollection` — проверка + молчаливая регенерация (лог `♻️`).
  - `CollectionsBookmarksManager.duplicateCollection` — регенерация всегда (копия по определению
    делит id с оригиналом). Папка копируется целиком, поэтому `tagLayout.json` в ней
    перезаписывается перевязанной раскладкой.
  - `CustomCollectionManager.startFromTemplate` — переведён на тот же регенератор вместо своей
    копии той же логики (у шаблона раскладки нет → `layout: nil`).
- **Файлы:** `CollectionIdRegenerator.swift` (новый), `CollectionExportModels.swift`,
  `CollectionsBookmarksManager.swift`, `CustomCollectionManager.swift`.
- **Не сделано:** разовая починка УЖЕ существующих дублей — по решению пользователя не нужна.

## 2026-08-11 — Источник тега при добавлении на таймлайн + пересборка глобальных пулов
- **Симптом:** поменял настройки тега (время до/после, интервальность), сохранил — редактор и
  экспорт показывают новые значения, а на таймлайн метка встаёт по старым. **Подтверждено на
  живых данных пользователя** (случай с дублем коллекции), фикс проверен.
- **Прим.:** первый разобранный кейс оказался ошибкой пользователя — там `tags.json`,
  UserDefaults-блоб `collection_<id>` и лог загрузки давали новое значение, а дублей id не было.
  Настоящий дефект нашёлся при разборе кода и подтвердился уже на другой коллекции — с дублем.
- **Что было не так:** добавление тега не брало его по id из ВЫБРАННОЙ коллекции, а доверяло
  тому, что пришло:
  - режим связок — читал из `tagLibrary.allTags`, ГЛОБАЛЬНОГО пула, склеенного из всех коллекций
    (`handleCanvasButtonTap`, `onAddTag`, `onStartIntervalTag`);
  - сгруппированный режим — использовал пришедший объект `Tag` как есть. По хоткею это СНИМОК из
    `HotKeyManager.registeredHotkeys` (там хранится сам `Tag`, а не id), сделанный на момент
    регистрации; по клику — объект из списка. Изначально я счёл этот путь безопасным — **неверно**:
    объект может оказаться копией из другой коллекции с тем же id.

  Пул ненадёжен по двум причинам:
  1. **Асинхронность.** Пересобирается в `loadAllUserCollections()` на фоновой очереди.
  2. **Дедупликация по id.** `Dictionary(grouping: mergedTags, by: { $0.id })
     .values.compactMap { $0.first }` сохраняет порядок внутри группы, а `mergedTags` строится по
     порядку коллекций из `CollectionsBookmarks.json` — побеждает копия из ПЕРВОЙ коллекции с этим
     id. Дубли id заводятся штатно и встречаются у пользователей: `duplicateCollection` копирует
     теги как есть, импорт сохраняет id из файла — новый генерируется только у самой коллекции,
     поэтому повторный импорт того же файла даёт полный комплект дублей. В такой ситуации
     правки во второй коллекции на таймлайн не попадут никогда.
- **Главное, что я сначала упустил:** имя/цвет тега на таймлайне берутся НЕ из штампа, а
  перерезолвятся при каждой отрисовке через `TagLibraryManager.findTagById(stamp.idTag)` —
  а он читал только `allTags`. Поэтому переименованный в дубле тег ставился правильно, но
  показывался старым именем из соседней коллекции, и правки в путях ДОБАВЛЕНИЯ ничего не меняли.
  Воспроизведение пользователя: коллекции `тест2` и `тест2 (1)` (один файл импортирован дважды),
  тег переименован во второй — на таймлайн попадало имя из первой.
- **Фикс:**
  - `TagLibraryManager`: единое правило поиска по id — сначала ВЫБРАННАЯ коллекция
    (`tags`/`labels`/`tagGroups`/`labelGroups`), потом пул. Переписаны `findTagById`,
    `findLabelById`, `findTagGroupForTag`, `findLabelsForTag`. Это накрывает всех потребителей
    разом: отрисовку штампов (`FullControlView`, `VideoPlayerView`, `ViewerTableView`,
    `ViewerTimelineView`, `MomentViewerView`), `TimelineDataManager`, экспортёры.
  - Прямые обращения `allTags.first(where: id ==)` в обход правила переведены на `findTagById`:
    `ClipAutoSaveManager`, `OrganizerView`, `ExportHelper` (3 места).
  - `TagLibraryView.resolveTag(id:)` теперь делегирует в `findTagById` (правило в одном месте) и
    применён во ВСЕХ путях добавления: связки (`handleCanvasButtonTap`, `onAddTag`,
    `onStartIntervalTag`), хоткей (обработчик `.showLabelSheet` — до ветвления по режимам) и клик
    в сгруппированном режиме (`handleTagButtonTap`, резолв на входе).
  - `TagLibraryManager.handleCollectionDataChanged`: ветка с `changedName` делала `return` до
    пересборки пулов — добавлен вызов. Общий `reloadAllCollectionsIfIdle()` вместо инлайн-guard;
    если изменение пришло во время пересборки, оно больше не теряется (`needsAnotherReload` →
    повторный прогон по завершении).
  - `WindowsManager.openCustomCollectionsWindow`: убран наблюдатель `.collectionDataChanged`,
    который вешался на КАЖДОЕ открытие редактора и никогда не снимался (наблюдатели копились,
    пулы пересобирались N раз на одно сохранение). Пересборку теперь делает сам TagLibraryManager.
- **Файлы:** `TagLibraryView.swift`, `TagLibraryManager.swift`, `WindowsManager.swift`.
- **Урок:** `allTags`/`allLabels`/`allTimeEvents` — это МЕЖколлекционный кэш с дедупликацией по id
  и асинхронной пересборкой. Для действий над текущей коллекцией читать из `tags`/`labels`;
  глобальный пул — только для «чужих» id.

## 2026-08-11 — Вернул запоминание раскладки окон разметки и блокировку окон (регресс)
- **Симптом:** окна разметки перестали открываться в том положении, в котором их оставили, и
  тумблер «Заблокировать окна» ни на что не влияет — всегда дефолтная раскладка.
- **Причина:** это добивка того же регресса, что описан в записи от 2026-08-10 («Восстановление
  openSettingsWindow / showMultiFieldMapSelection»): `git checkout -- WindowsManager.swift` снёс
  незакоммиченные правки. Тогда восстановили два метода, но не заметили, что вместе с ними
  пропала вся проводка раскладки. Сам `MarkupWindowLayoutStore` и тумблер в `VideoPlayerView`
  (~l.167) уцелели — просто `WindowsManager` про стор больше не знал: оба пути открытия
  (`openLiveWindows` и открытие проекта) безусловно ставили дефолтные фреймы, `track()` не
  вызывался нигде, `stopTracking()` тоже.
- **Фикс:** общий `applyMarkupWindowsLayout()` в `WindowsManager` — сохранённая раскладка
  (слепок блокировки, если включена, иначе последняя позиция) → иначе дефолт; оба пути открытия
  теперь зовут его вместо дублированного дефолта. `track()` вызывается ПОСЛЕ `setFrame`
  (иначе в стор попадёт дефолтный размер контроллера, т.к. `track` сразу запоминает кадр),
  `stopTracking()` — первым делом в `closeAll()` (до снятия делегатов и закрытия окон, чтобы
  `flush()` успел записать последнюю позицию) и защитно в начале `applyMarkupWindowsLayout()`
  от накопления наблюдателей.
- **Файлы:** `WindowsManager.swift`.
- **Урок:** `WindowsManager` — файл с историей потери незакоммиченных правок. После любого
  `git checkout` по нему проверять не только явно упомянутые методы, но и проводку фич,
  чьи менеджеры лежат в других файлах (тут: стор жив, вызовы вырезаны).

## 2026-08-11 — Экспорт из режима просмотра игнорировал ресайз клипов
- **Симптом:** после изменения границ тега в плейлисте (режим просмотра) плеер и плейлист
  показывают новую длительность, а экспорт всё равно пишет исходный вариант тега — ровно такой,
  как он лежит в проекте разметки.
- **Причина:** `SportCutExportSheet.resolvedEvent` = `session.timelineResolvedEvent(for:)`, а тот
  пересобирает событие из текущей разметки (`SportCutEvent.from(stamp:line:source:)`). Ресайз
  клипа в просмотре хранится ОТДЕЛЬНО — в `playlist.eventStartOverrides` /
  `eventDurationOverrides` (ключ `hiddenKey` = `sourceID|stampID`). Плеер их накладывает
  (`SportCutPlayerManager`, ~l.795 и ~l.1055), а экспорт — нет: во всех трёх ветках (клипы, фильм,
  фильм-на-плейлист) он брал `event.startTime` / `event.duration` напрямую.
- **Фикс:** `resolvedEvent` получил параметр `playlist` и накладывает оверрайды поверх
  разрешённого события в том же порядке, что плеер (оверрайд важнее, иначе — свежее значение из
  разметки); слайды не трогаются. Так как `startTime`/`duration` у `SportCutEvent` — `let`,
  добавлен `withClipRange(start:duration:)`. Обновлены все 3 места вызова; дальше по коду
  (timeRange, рисунки, вотермарка, инструкции) значения уже консистентны, т.к. едут в самом event.
- **Файлы:** `SportCutExportSheet.swift`, `SportCutModels.swift`.

## 2026-08-11 — Объединение проектов: экспорт падал с AVFoundation -11838
- **Симптом:** склейка проектов обрывается ошибкой «Операция остановлена
  [AVFoundationErrorDomain -11838] → Не удалось завершить операцию (OSStatus -16976)», хотя видео
  и разметка нормальные. -11838 = `AVErrorOperationNotSupported`. Формат текста — из
  `detailedExportError`, т.е. источник именно `ProjectMergeManager`.
- **Ключевая деталь от пользователя:** падало на .mov, записанном НАШЕЙ ЖЕ лайв-записью
  (`LiveStreamManager` → `AVAssetWriter`). У таких файлов при `enableAudio == false`
  аудиодорожки нет вообще, а `startSession(atSourceTime:)` + пауза/резюм дают дорожки, чьи
  `timeRange` не обязаны начинаться с нуля и совпадать с `asset.duration`.
- Закрыты три известные причины именно этого кода ошибки:
  1. **Пустая аудиодорожка в композиции.** Трек добавлялся всегда, а вставка звука шла на
     `[0, asset.duration]`. Для лайв-записи без звука вставлять нечего, а при склейке двух таких
     записей в композиции оставался аудиотрек без единого сэмпла — писателю нечего в него
     положить → -11838. Теперь: вставка идёт ПЕРЕСЕЧЕНИЕМ с реальным `track.timeRange`
     (и позиция сдвигается на `range.start`, чтобы не разъезжался звук внутри клипа), а если
     звук не вставился нигде — трек удаляется (`composition.removeTrack`). То же пересечение
     применено к видео: раньше `insertTimeRange` на длину ассета бросал, если дорожка короче.
  2. **Пресет, несовместимый с ассетом.** `AVAssetExportPresetHighestQuality` подходит не всегда.
     Добавлен `makeExportSession(for:)` — спрашивает `exportPresets(compatibleWith:)` и берёт
     лучший из реально совместимых (Passthrough намеренно не в списке: он несовместим с
     `videoComposition`).
  3. **Тип файла вне `supportedFileTypes`.** `outputFileType` выставлялся по расширению без
     проверки. Теперь запрошенный тип валидируется, иначе уход в `.mov` с правкой расширения;
     `finalURL` проброшен и в `assembleProject`, и в очистку при отмене/ошибке.
- **Побочно:** `offsets.append` стоял ПОСЛЕ `guard duration > 0`, поэтому источник нулевой
  длительности ломал индексацию `offsets[index]` и сдвигал разметку всех последующих проектов.
  Перенесён до guard.
- **Файлы:** `ProjectMergeManager.swift`.

## 2026-08-11 — Меню коллекций: свежесозданная коллекция не открывалась по клику
- **Симптом:** после создания коллекции карточка в меню коллекций на главном экране не
  реагирует на нажатие. Начинает открываться только «после того, как откроешь её в библиотеке
  тегов» (на деле — просто спустя время).
- **Причина:** `CollectionsMenuView.openCollectionEditor` шёл через
  `CollectionsBookmarksManager.collectionBookmark(for:)`, а тот собирает security-scoped
  bookmark'и ИЗ ФАЙЛОВ коллекции и возвращает nil, если нет
  `tagGroups/tags/labelGroups/labels.json`. Но `InMemoryStorageManager.saveCollection()` кладёт
  коллекцию в UserDefaults сразу, а на диск сбрасывает отложенно (`scheduleSaveToDisk`, таймер
  30 с, либо `applicationWillTerminate`). Проверил на живых данных: в папке только что созданной
  коллекции лежал ровно один файл — `tagLayout.json`. Итог: `guard let ... else { return }` —
  и клик молча ничего не делал, пока таймер не допишет файлы.
- **Фикс:** редактору сами bookmark-данные не нужны — `CustomCollectionManager(withBookmark:)`
  грузит коллекцию по имени через `InMemoryStorageManager` (UserDefaults → файлы). Поэтому
  добавлен фолбэк на `CollectionBookmark` с пустыми `Data` (ровно так его собирает и
  `TagLibraryView.loadUserCollections()`).
- **Файлы:** `CollectionsMenuView.swift`.

## 2026-08-11 — Связки не работают в только что созданной коллекции (до перезапуска приложения)
- **Симптом:** создаёшь коллекцию со связками клавиш, выбираешь её — холст рисуется корректно
  (все кнопки на местах), теги по клику ставятся, хоткеи работают, а **связки не срабатывают
  вообще**. Лечилось только так: выбрать коллекцию → закрыть приложение → открыть проект с ней
  уже предвыбранной; после этого работает всегда.
- **Диагностика:** данные на диске корректны — проверил `Collections/<id>/tagLayout.json` свежей
  коллекции против `tags.json`/UserDefaults-блоба `collection_<id>`: items и bindings на месте,
  осиротевших связок нет. Значит проблема чисто рантаймовая — у `KeyBindingRuntimeManager`
  массив `bindings` оставался **пустым**.
- **Причина:** `bindings` заполнялись ТОЛЬКО императивным `configure(layout:)` из двух
  жизненных хуков вьюх — `TagLibraryView.reloadKeyBindingRuntimeLayout()` (через
  `applyCollectionDisplayMode`) и `FreeTagsCanvasView.loadLayoutIfNeeded()` (`onAppear` /
  `onChange(currentCollectionId)`, читающий НЕнаблюдаемые синглтоны). Если ни один из них не
  срабатывал в нужном порядке (коллекция создана и подхвачена в уже смонтированном канвасе),
  `configure` не звался вовсе. Всё остальное при этом работает независимо от связок: холст
  рисуется из своего `@State layout`, тег ставится через `tagLibrary.allTags`, хоткеи — через
  `HotKeyManager`. Поэтому симптом выглядел как «работает всё, кроме связок». При перезапуске
  `TagLibraryManager.init` → `applyDefaultCollection()` расставляет коллекцию ДО появления вьюх,
  и `configure` проходит гарантированно — отсюда «после перезахода работает всегда».
  Вторая, сопутствующая проблема: `reset()` чистит только состояние подсветки, но НЕ `bindings`,
  поэтому связки прошлой коллекции протекали в следующую (движок — синглтон).
- **Фикс — конфигурация стала самовосстанавливающейся, а не зависящей от порядка хуков:**
  - `KeyBindingRuntimeManager`: добавлен `private(set) var configuredCollectionId`;
    `configure(layout:collectionId:)` его проставляет; новый `clearConfiguration()` (чистит
    `bindings`/`items`/`runtimeVisibility` — в отличие от `reset()`); новый
    `ensureConfiguredForCurrentCollection(playFields:)` — **ленивая** загрузка раскладки текущей
    коллекции (резолвит `TagLibraryManager.currentCollectionType` → `CollectionsBookmarksManager`
    → `TagFreeLayoutStorage`), идемпотентная по `configuredCollectionId` (иначе `configure`
    сбрасывал бы подсветку посреди цепочки).
  - `TagLibraryView`: новый `prepareRuntimeForTap()` = `wireRuntimeCallbacks()` +
    `ensureConfiguredForCurrentCollection` — зовётся вместо `wireRuntimeCallbacks()` во всех трёх
    обработчиках (`handleCanvasButtonTap`, `handleCanvasLabelTap`, `handleCanvasMapTap`), так что
    связки гарантированно загружены к первому нажатию. Все `keyBindingRuntime.reset()` при смене
    коллекции заменены на `clearConfiguration()`.
- **Вторая причина (всплыла после первого фикса: «связки с ИНТЕРВАЛЬНЫМИ не работают»):**
  `wireRuntimeCallbacks()` подключал колбэки ОДИН раз за запуск (`guard onAddTag == nil else
  { return }`) и захватывал `[self]` — структуру вьюхи с её `@State`-боксами. После
  `refreshID = UUID()` (перезагрузка коллекций, `.collectionsLoadingFinished`) вьюха
  перемонтируется с новой идентичностью, и колбэки продолжают писать в осиротевшие боксы прошлого
  экземпляра: `startIntervalRecording` кладёт запись в мёртвый `activeIntervalTags`, а
  `isKeyBindingsCanvasMode` читает там `.grouped` и отваливается по guard. Прямое нажатие по тому
  же интервальному тегу идёт из ЖИВОЙ вьюхи и работает — отсюда «ломаются только связки с
  интервальными». Фикс: убрал one-shot guard, колбэки перевязываются на каждом нажатии
  (8 замыканий на тап — пренебрежимо), всегда на актуальный экземпляр.
- **Диагностика:** добавлен `KeyBindingLog` (флаг `KeyBindingLog.isEnabled`, префикс `🔗 KB:`) —
  логирует configure/clear/ensure, вход в `handleButtonTap`, применение каждой связки, activation /
  deactivation / intervalInversion с проверкой «подключён ли колбэк», и старт/стоп интервала с
  причиной отказа. **Временное — снять, когда баг подтверждён закрытым.**
- **Файлы:** `KeyBindingRuntimeManager.swift`, `TagLibraryView.swift`, `FreeTagsCanvasView.swift`.
- **Прим.:** SourceKit на `KeyBindingRuntimeManager.swift` сыплет ложными «Cannot find type
  `KeyBinding`/`TagFreeLayout`/`PlayField` in scope» — типы того же модуля, использовались там и
  раньше; верить `xcodebuild`.

## 2026-08-11 — FullControl: стебли меток рисунков на всю высоту + голова в баре (регресс от sticky-header)
- **Причина:** при выносе шапки таймлайнов в закреплённый оверлей я целиком переместил
  `ScreenshotMarkersView` (голова-карандаш + стебель) в `PinnedTimelineRulerView`, а тот
  `.frame(height: band+30).clipped()`. Итог: стебель (высотой `totalHeight` = все дорожки) обрезался
  по шапке (синяя полоска только в верхней зоне), а голова с `.offset(y:-headLift)` уезжала выше
  фрейма (не видна, но клики проходили).
- **Фикс:** разнёс голову и стебель. В `ScreenshotMarkersView` добавил `enum RenderPart {full,
  headsOnly, stemsOnly}` + `part`; в `screenshotMarker` стебель под `part != .headsOnly`, голова под
  `part != .stemsOnly`.
  - Шапка (`PinnedTimelineRulerView`): `part: .headsOnly`, `headLift: 0` — головы кликабельны и всегда
    видны в баре (переживают вертикальный скролл). zIndex 3.
  - Скролл (`timelineZStackContent`): добавил `part: .stemsOnly`, `.padding(.top, markerHeadBand)`,
    `.allowsHitTesting(false)` — стебли на всю высоту дорожек, как плейхед.
  - Выравнивание x: голова центрируется на времени за счёт `-7` в rawX (её контейнер ~14pt), а
    стебель — отдельный View шириной 2pt, поэтому в `.stemsOnly` добавил `+7` к offset.x (половина
    «шарика»), иначе полоска шла на пол-головы левее.
- **Файлы:** `FullControlView.swift` (ScreenshotMarkersView + timelineZStackContent),
  `PinnedTimelineRulerView.swift`.
- **Прим.:** также поправлен баг №2 из записи ниже (рендер библиотеки связок) — верное решение
  через remount `.id(freeCanvasCollectionKey)`, а не `onChange(tags)`; подробности в той записи.

## 2026-08-10 — Связки клавиш: камера редактора, рендер библиотеки, хват плейхеда в шапке
Три несвязанные правки из фидбэка.

- **1. Камера в редакторе раскладки прыгала при перемещении тега** (`TagFreeLayoutEditorView`).
  Причина: во время drag охват холста заморожен (`frozenContentRect`), но на `onEnded` разморозка
  пересчитывала `contentRect()`; если элемент вынесли левее/выше прежних границ, `origin`
  (`virtual.minX/minY`) смещался и весь холст «прыгал» — выглядело как перескок камеры к тегу.
  Фикс: на завершении drag/resize/rotate компенсируем `panOffset` на смещение origin
  (`compensatePanForContentShift`) — визуально ничего не дёргается. Камерой следуем (плавно,
  0.3s) ТОЛЬКО если перемещённый элемент оказался полностью за вьюпортом
  (`panToRevealIfOffscreen`). Вынес общий `originForContent`; `centerCameraOnItem` переиспользует его.
  Правил все 4 `onEnded`: одиночный move, `selection-move`, resize, rotate.

- **2. При переключении МЕЖДУ коллекциями связок в библиотеке не рисовались теги и карта**
  (только лейблы) — до перезахода / открытия редактора / переключения на стандартную и обратно.
  Ключ: баг ТОЛЬКО на keybinding→keybinding. При заходе из стандартной (.grouped) `FreeTagsCanvasView`
  вообще не смонтирован → появление коллекции связок монтирует его заново → onAppear грузит раскладку
  корректно. А между двумя .free-коллекциями канвас НЕ размонтируется, переиспользуется, и его
  `@State layout` остаётся от прежней коллекции. Лейблы берутся из ГЛОБАЛЬНОГО `tagLibrary.allLabels`
  (объединение всех коллекций, TagLibraryManager ~l.384) и потому рисуются даже со старой раскладкой,
  а теги (`tagLibrary.tags`) и карты (collection-specific) — нет. Перезагрузка по
  `onChange(currentCollectionId)` (читает необлюдаемые синглтоны) на этом переходе не срабатывала.
  Фикс: `.id(freeCanvasCollectionKey)` на `freeTagsSection` (ключ = имя пользовательской коллекции) —
  форсирует remount при смене коллекции, ровно как рабочий обходной путь «через стандартную и обратно».
  Плюс `TagLibraryView.loadUserCollection` чистит `cachedPlayFields = nil` в самом начале, иначе при
  switch в раскладку уходят карты ПРОШЛОЙ коллекции и `normalizeLayout` выкидывает карты новой (их id
  нет среди старых); пустой список → карты сохраняются, канвас догружает их сам
  (`loadSelfPlayFieldsIfNeeded`).
  (Первая попытка через `onChange(of: tags.map(\.id))` не помогла — суть в remount, а не в onChange.)

- **3. После закрепления шапки таймлайна плейхед нельзя было хватать в шапке**
  (`PinnedTimelineRulerView` перекрывала стебель из скролла; голова была `allowsHitTesting(false)`).
  Фикс: пробросил `playheadDragController` в `PinnedTimelineRulerView` и добавил прозрачную зону
  захвата (16pt) над плейхедом в шапке. Своя `DragGesture` в координатах шапки
  (`coordinateSpace "pinnedRuler"`), перевод `contentX = value.location.x + controller.currentScrollX`,
  кормит ТОТ ЖЕ `dragController` (begin/update/endDrag) — логика скраб-превью и pause/resume
  зеркалит `TimelinePlayheadView`. Курсор openHand на hover.
  Файлы: `PinnedTimelineRulerView.swift` (переписан), `FullControlView.swift` (проброс параметра).

## 2026-08-10 — Восстановление openSettingsWindow / showMultiFieldMapSelection в WindowsManager
- **Причина:** в ходе отката moment-viewer-правки был выполнен `git checkout -- WindowsManager.swift`,
  который снёс НЕзакоммиченные (жившие только в рабочей копии) методы `openSettingsWindow` и
  `showMultiFieldMapSelection`. В git-истории/стэше/dangling-блобах их нет — восстановить точь-в-точь
  через git нельзя.
- **Как восстановлено (реконструкция):** по `vault/HISTORY.md` (записи 2026-08-06 про экран настроек и
  мультикарту), незакоммиченным файлам `FieldMapMultiSelectionWindowController` (init
  `tag/items/onSave:[String:CGPoint]`), `SettingsView`, местам вызова (`TagLibraryView` x2,
  `AppDelegate`, `VideosView`) и существующим паттернам:
  - `showMultiFieldMapSelection(tag:items:lockWindows:onSave:)` — по образцу `showFieldMapSelection`
    (слот `fieldMapWindow`, `fieldMapLockedMainWindows`/`lockMainWindows`, закрытие через
    `fieldMapWindowDidClose`; фрейм окна задаёт сам контроллер).
  - `openSettingsWindow()` + приватное `settingsWindow: NSWindow?` — по образцу
    `openCollectionsMenuWindow` (переиспользуемое окно, `isReleasedWhenClosed=false`, delegate=self).
  Скан подтвердил: все внешние вызовы `WindowsManager.shared.*` снова резолвятся.
- **Остаточный риск:** чисто ВНУТРЕННИЕ незакоммиченные правки того же файла (изменённые тела методов
  без внешних вызовов) скан не ловит — если такие были, они утрачены. Точный оригинал мог остаться в
  открытом буфере Xcode. Урок: не делать `git checkout` по файлу с чужими незакоммиченными правками.
- **Файлы:** `Modules/VideoPlayer/Managers/WindowsManager.swift`.

## 2026-08-10 — HaishinKit 2.0.9 → 2.2.5 (фикс ошибки сборки под Xcode 26 / Swift 6.2)
- **Задача:** сборка падала на ошибке внутри пакета HaishinKit —
  `RTMPConnection.swift:437 Sending 'iterator' risks causing data races`. Причина: Xcode 26.1.1 /
  Swift 6.2.1 ужесточил проверку Sendable, а пакет был пришпилен на 2.0.9 (`upToNextMinorVersion` от
  2.0.0 → максимум 2.0.x), где `Task { await socket?.send(iterator) }` шлёт не-Sendable в актор.
- **Как правилось:** поднял HaishinKit до 2.2.5 (релиз «Fix compilation error»). В pbxproj требование
  пакета → `upToNextMajorVersion` от `2.2.5`; в обоих `Package.resolved` (workspace + xcodeproj)
  HaishinKit rev `dc880cb540b8feeb98f64e8b7dcfaaf320b6b2bd` / 2.2.5, транзитивный Logboard 2.5.0 → 2.6.0.
  В 2.2.5 проблемный `doOutput`/`send(iterator)` убран целиком.
- **Совместимость / правки кода под новый API (LiveStreamManager.swift):**
  - Протокол `MediaMixerOutput` (реализуют `LiveFrameCaptureOutput` и `LiveStreamRecorder`) идентичен в
    2.0.9 и 2.2.5 — conformance не тронут.
  - `MediaMixer(useManualCapture: true)` → `MediaMixer(captureSessionMode: .single)` (в 2.2 инициализатор
    сменился; камере нужен реальный AVCaptureSession `.single`, `.manual` = NullCaptureSession/ReplayKit).
  - `setFrameRate(_)` стал `throws`: `await newMixer.setFrameRate(x)` → `try await newMixer.setFrameRate(x)`
    (2 места). `MediaMixer` — `public final actor`, поэтому все `await` на его методах валидны (actor-hop),
    остальной API (`attachVideo/Audio`, `setVideoMixerSettings`, `videoMixerSettings`,
    `addOutput/removeOutput`, `startRunning/stopRunning`, `MTHKView(frame:)`/`videoGravity`) без изменений.
  - RTMP-публикацию app не использует (локальная запись через MediaMixerOutput), так что изменения RTMP-API
    не задевают.
- **Файлы:** `Youchip-Stat.xcodeproj/project.pbxproj`, оба `Package.resolved`,
  `Modules/VideoPlayer/Managers/LiveStreamManager.swift`.

## 2026-08-08 — Зум видео в пересмотре/окне тега/просмотре + плейхед не мешает Cmd+клику
- **Плейхед (Cmd+ЛКМ выбор тегов):** `TimelinePlayheadView` рисовал полосу 16pt на всю высоту с
  drag-жестом → стебель перехватывал клики по тегам при зажатом Cmd для мультивыбора.
  Фикс: визуал плейхеда сделал `allowsHitTesting(false)`; зона захвата зависит от Cmd — БЕЗ Cmd
  плейхед тянется по всей высоте (как раньше), при зажатом Cmd зона сжимается до верхней «ручки»-
  треугольника (`grabHitHeight = 22`), и стебель пропускает клики к тегам. Состояние Cmd отслеживаю
  монитором `NSEvent .flagsChanged` (`isCommandHeld` → `frame(maxHeight:)`).
- **Зум видео:** ввёл переиспользуемый `ZoomableVideoPlayerView<Native>` (Modules/VideoPlayer/Views)
  — на 1.0× показывает «родной» плеер (нативные контролы через @ViewBuilder), при зуме — голый
  `CustomVideoPlayer` (слой-трансформ) + пан; кнопки зума (−/%/+/сброс) и жесты (пинч/драг) оверлеем.
  Подключил в: окно пересмотра лайва (`ReviewVideoView`), окно тега по двойному клику
  (`MomentViewerView` — и лайв, и обычная разметка), плеер режима просмотра
  (`SportCutVideoPlayerView` → обёртка вокруг `SportCutMinimalPlayerView`). `ViewerVideoView` не
  трогал (там drawing-оверлеи с координатами — зум бы их рассинхронил).

## 2026-08-08 — Лимиты бесплатного использования: дозапись видео + отдельные лимиты режима просмотра
- **Задача:** при неактивной лицензии/после пробного периода (3 видео) нельзя было ограничить
  дозапись видео и добавление файлов (в т.ч. в просмотре) — бесконечное использование. Требовалось:
  дозапись видео = −1 лимит; режим просмотра — ОТДЕЛЬНЫЕ 3 лимита (создание сессии = −1); при 0
  лимитах нельзя ни создавать сессии, ни добавлять источники; лимиты просмотра показать в главном
  меню и в списке просмотра. Активная лицензия = без лимитов.
- **Как сделано:**
  - Новый синглтон `LicenseLimitsManager` (Modules/License) — единый источник: `isLicenseActive`
    (из UserDefaults `auth_deadline` + `AppConfig.isDebug`), лимиты разметки (`added_videos_count`,
    max 3) и просмотра (`added_viewing_sessions_count`, max 3), методы `canAddMarkupVideo` /
    `consumeMarkupVideoIfNeeded`, `canCreateViewingSession` / `canModifyViewing` /
    `consumeViewingSessionIfNeeded`. Счётчики `@Published`.
  - Разметка: `VideosViewModel` переведён на менеджер. Закрыт лут-хол дозаписи: `appendToVideo`
    теперь гейтится `canAddMoreVideos`, а старт дозаписи (`liveSourceConfigured` append-ветка)
    списывает −1. (Импорт/merge/новый лайв уже списывали.)
  - Просмотр: `SportCutSessionManager.createSession` списывает −1 (оба пути создания —
    `SportCutCreateSessionView` и `WindowsManager.showSportCutNewSessionFromMarkup` — гейтятся
    `canCreateViewingSession` с алертом). Добавление источников в существующую сессию
    (`SportCutAddSourceSheet`) гейтится `canModifyViewing`. Инициальные источники в потоке создания
    не гейтятся (входят в оплаченное создание).
  - UI: бейдж лицензии в главном меню (`VideosView.licenseBadge`) показывает лимиты разметки И
    просмотра (2 строки); `SportCutListView` показывает лимит просмотра в шапке. `VideosViewModel`
    подписан на `$addedViewingSessionsCount`/`$addedVideosCount` для авто-обновления бейджа.
  - Новые ключи локализации `viewingSessionsLimit`, `viewingLimitReachedTitle`,
    `viewingLimitReachedMessage` (7 языков); для OK-кнопок использован существующий `alertsOkTitle`.

## 2026-08-08 — Редактор коллекции связок: две мелочи (клик по всей кнопке-вкладке + удаление свёрнутой связки)
- **Задача 1:** вкладки навигации (Лейблы/Теги/События/Карты) в `CollectionNavigationPanel` реагировали
  на клик только по тексту/иконке. **Фикс:** добавил `.contentShape(Rectangle())` на лейбл кнопки —
  теперь кликается вся зона (прозрачный фон невыбранной вкладки иначе не ловил тап). `CollectionNavigationPanel.swift`.
- **Задача 2:** чтобы удалить связку, её приходилось раскрывать. **Фикс:** в `KeyBindingSettingsPanel`
  в шапку СВЁРНУТОЙ строки связки (`collapsible && !isExpanded`) добавил кнопку-корзину `deleteBinding` —
  можно удалять не раскрывая (в раскрытом виде удаление остаётся в деталке). `KeyBindingSettingsPanel.swift`.

## 2026-08-08 — Лайв: чёрный экран при дабл-клике тега сразу после отметки + кнопка «Обновить»
- **Задача (продолжение прошлого фикса):** чёрный экран остался, когда тег отмечают и СРАЗУ делают
  дабл-клик (или пауза → дабл-клик) — буфер обновляется раз в 5 сек, поэтому свежих кадров нет.
  Нужно: дабл-клик форсит обновление буфера (100% показ), а т.к. «время после» тега может быть ещё
  не дозаписано — показывать плашку «не дозаписано» + кнопку «Обновить» прямо в окне момента.
- **Как правилось:**
  1. `LiveStreamManager.finalizeCurrentSegment` больше НЕ бейлится, если в этот момент идёт
     периодический review-refresh (`isReviewRefreshInProgress`) — ЖДЁТ его завершения (ретраи по 0.1с,
     до 40 раз) и затем финализирует. Раньше при совпадении с 5-сек рефрешем композиция строилась из
     устаревших сегментов → чёрный экран.
  2. `MomentViewerSession`: хранит `requestedDuration` (полную длину тега), в `configure` считает
     `safeDuration` от неё (а не от ранее обрезанной `displayDuration`) и ставит `isTruncated`, если
     буфер не покрывает всю длину (лайв). Добавлены `allowsRefresh` + `assetProvider` (форс-финализация
     через `assetForMomentViewer`) и метод `refresh()` — подменяет `sourceAsset` на свежий и
     пересобирает клип. `sourceAsset`/`sourceAssetDuration` стали `var`.
  3. `MomentViewerView`: оверлей-плашка сверху видео с текстом + кнопкой «Обновить» (спиннер при
     `isRefreshing`), когда `session.isTruncated`.
  4. Проброс `allowsRefresh`/`assetProvider` через `MomentViewerWindowController` и
     `WindowsManager.openMomentViewer` (только лайв). Новые ключи локализации
     `momentClipNotFullyRecorded`, `momentRefreshClip` (7 языков).

## 2026-08-08 — Импорт XML (Sportscode/WyScout/Dartfish): фантомная группа лейблов «Лейблы» в фильтре
- **Симптом:** при импорте видео из XML своих групп лейблов нет, но в фильтрах режима просмотра
  показывается группа «Лейблы» (см. скрин — «Label groups → Labels»).
- **Первопричина:** `SportCutSessionManager.augmentedLibrary` реконструирует библиотеку для источника
  из штампов. Если у лейбла `lableGroupId` непустой, но соответствующей группы нет в загруженной
  коллекции (`TagLibraryManager.allLabelGroups` — у импортированных видео коллекции нет), создавалась
  fallback-группа с ИМЕНЕМ `^String.Titles.sportCutLabels` («Лейблы»). Фильтр
  (`SportCutFilterSheet.hasResolvedName`) отсеивает группы без «настоящего» имени (пусто или имя==id),
  но выдуманное «Лейблы» проходит этот фильтр → фантомная группа видна.
- **Как правилось:** синтетическую группу теперь именуем её `id` (а не «Лейблы») —
  `hasResolvedName(id, id)` = false → фильтр её скрывает; сами лейблы остаются фильтруемыми в
  отдельной секции «Лейблы» (строятся из штампов напрямую). Чтобы id не «протёк» в подписи, добавил
  `LabelGroupData.labelGroupDisplayName` (= «Лейблы», если имя не резолвится) и применил в
  таблице (`SportCutTableView`), экспорте (`SportCutExportSheet`) и вотермарке
  (`SportCutWatermarkOverlay`). Файлы: `SportCutSessionManager.swift`, `VideoPlayerModels.swift`
  (extension), `SportCutTableView.swift`, `SportCutExportSheet.swift`, `SportCutWatermarkOverlay.swift`.

## 2026-08-08 — Редактор связок: кнопка «удалить все связки кнопки» в деталке
- **Задача:** в правой деталке кнопки (при выделении кнопки, когда показаны её связки) добавить
  кнопку удаления сразу ВСЕХ связок этой кнопки.
- **Как сделано:** в `KeyBindingSettingsPanel.focusedButtonPanel` в шапку (рядом с крестиком) добавил
  красную корзину, видимую только когда есть связки (`!(outgoing.isEmpty && incoming.isEmpty)`).
  `deleteAllBindings(forButtonKey:)` = `layout.bindings.removeAll { sourceButtonKey == key ||
  targetButtonKey == key }` (исходящие + входящие) + сброс `expandedBindingIds`. Новый ключ
  локализации `keyBindingsDeleteAllForButton` (7 языков). `KeyBindingSettingsPanel.swift`.

## 2026-08-08 — Таймлайны разметки (FullControlView): закреплённая сверху шапка (линейка + бар кнопок)
- **Задача:** при вертикальном скролле должны ехать только дорожки; верх сетки (линейка с
  треугольником плейхеда) и бар-кнопки в той же полосе — статичны сверху.
- **Как сделано (подход «оверлей», тело почти не трогали → мин. риск регрессий плейхеда/зума/автоскролла):**
  - `TimelineScrollController`: добавил `@Published liveScrollX` (наблюдатель `boundsDidChange` на
    clip-view) — непрерывное горизонтальное смещение для синхронизации закреплённой линейки.
  - `PinnedTimelineRulerView` (новый, изолированный — чтобы 60 Гц ре-рендеры не тянули FullControlView):
    линейка `TimelineTimestampsHeaderView` + треугольник-индикатор плейхеда + «головы» меток
    рисунков (`ScreenshotMarkersView`), всё смещено на `-liveScrollX`, клип по высоте шапки, tap-to-seek.
  - `FullControlView.pinnedTimelineHeaderOverlay`: `.overlay(alignment:.top)` на вертикальном ScrollView
    (обе ветки macOS): слева бар-кнопки `timelineTableCornerControls()` (единственный экземпляр —
    из скроллящегося тела убран), справа `PinnedTimelineRulerView`; непрозрачный фон перекрывает
    уехавшую полосу.
  - Из тела убрал: бар-кнопки из header-row и `ScreenshotMarkersView` из `timelineZStackContent`
    (перенесены в шапку — иначе оверлей перекрыл бы кликабельные «головы» меток). Линейка в теле
    осталась (безвредный дубль под оверлеем). Плейхед тянут за стебель ниже шапки.
  - **Компромисс:** стебли меток рисунков поверх дорожек больше не рисуются (только «головы»
    закреплены сверху). Требует визуальной проверки выравнивания (band=22 + линейка 30, offset
    `-liveScrollX`, ширина `geo-200`).
  - **Фикс скролла до конца при уменьшении окна (давний баг):** симптом — «уменьшил окно на Δ →
    не долистывает ровно на Δ», т.е. диапазон скролла был привязан к стартовому размеру.
    Причина: высота контента правой колонки зависела от вьюпорта — (1) правая колонка
    оборачивалась `GeometryReader` внутри вертикального ScrollView (обёртка отдаёт высоту вьюпорта),
    (2) горизонтальный `ScrollView` правой колонки «жадный» по вертикали (тянется на весь вьюпорт,
    режет контент). Фикс: обёртку `GeometryReader` заменил на измерение только ШИРИНЫ фоновым
    reader (`timelineRightColumnWidth`), а горизонтальному ScrollView добавил
    `.fixedSize(horizontal:false, vertical:true)` — теперь колонка берёт РЕАЛЬНУЮ высоту контента,
    диапазон вертикального скролла корректен при любом размере окна. `timelineScrollView(geo:)` →
    `timelineScrollView(width:)`.
  - **Эти правки не помогли** (баг оказался глубже) → добавлен КОСТЫЛЬ по просьбе: запоминаю
    стартовую высоту окна (`standardWindowHeight` из body-`GeometryReader`), при уменьшении окна
    добавляю снизу списка `.padding(.bottom, max(0, standardWindowHeight - currentWindowHeight))` —
    столько пустоты, насколько окно меньше стартового, чтобы всегда долистывалось до конца.

## 2026-08-08 — Окно выбора точки на нескольких картах: сетка (2 в столбце) во всю высоту экрана
- **Задача:** окно мультивыбора карт открывалось маленьким и карты приходилось листать. Нужно:
  плитка по 2 карты в столбце и окно сразу во всю высоту экрана (независимо от числа карт).
- **Как сделано:** `FieldMapMultiSelectionView` — вертикальный стек заменил на `LazyVGrid` с
  `columnCount = ceil(count/2)` (макс 2 карты в столбце). `ScrollView` оставил страховкой.
  `FieldMapMultiSelectionWindowController`: ширина под число колонок (`columns×cellWidth`, клампится
  до 95% ширины), а высота — `window.setFrame` на весь `visibleFrame` по высоте (во всю высоту
  экрана), по центру X. Файлы: `FieldMapMultiSelectionView.swift`,
  `FieldMapMultiSelectionWindowController.swift`. (Ранее было ceil(count/3) и размер под сетку.)

## 2026-08-08 — Слияние проектов: одноимённые дорожки теряли теги (дубликаты id штампов)
- **Симптом:** два видео с одинаковыми дорожками (теги на всех), при мердже выбрано «слить
  таймлайны» → на слитых дорожках перенеслись теги только с ОДНОГО видео, и они «уезжают» со своих
  мест относительно своего видео.
- **Первопричина:** если проекты имеют совпадающие id штампов (типично когда один проект дублирован
  из другого — «одинаковые таймлайны»), при слиянии в одну дорожку появляются штампы с ОДИНАКОВЫМ
  `id`. `TimelineLineView` рендерит `ForEach(..., id: \.element.id)` — дубликаты id SwiftUI схлопывает
  (виден один набор) и переиспользует вью → теги «уезжают». Смещение времени (offset) при этом было
  корректным — проблема именно в id.
- **Как правилось (`ProjectMergeManager.swift`):** в `mergedTimelines` каждый штамп пересобираю с
  НОВЫМ `UUID` (`id` у `TimelineStamp` — `let`, поэтому через init, хелпер `mergedStamp` = новый id +
  сдвиг времени, все поля сохраняются). Метод теперь возвращает ещё и per-source ремапы
  `oldStampID→newStampID`; `copyScreenshots`/`copyScreenshotMetadata` переносят
  `ScreenshotMetadata.relatedStampIds` на новые id (иначе рвались привязки скриншотов к тегам).
  Заменил старый `shift` на `mergedStamp`.

## 2026-08-08 — Плейлисты просмотра: клипы всегда играют (автосохранение во внутреннюю папку)
- **Задача:** клипы, уже добавленные в плейлисты режима просмотра, должны автоматически сохраняться
  и всегда воспроизводиться — даже если оригинал видео удалён совсем или проект убран из сессии
  просмотра. Раньше при удалении проекта из сессии клипы переставали играть.
- **Что уже было:** `SportCutClipCache` (экспорт обрезанных клипов + подхват при плейбеке) —
  но триггерился ВРУЧНУЮ (`makeOffline`), хранил в ЮЗЕРСКОЙ папке `Documents/YouChip-Stat/PlaylistClips`,
  без очистки; плейбек предпочитал кэш (cache-first).
- **Доработка:**
  1. **Внутренняя папка:** хранилище перенёс в `Application Support/YouChip-Stat-PlaylistClips/<sessionID>/`
     (не видно юзеру), добавил `clipsDirPath` без создания папки.
  2. **Автосохранение:** `SportCutClipCache.autoCacheIfNeeded(session:)` вызывается из
     `SportCutSessionManager.updateSession` (центральная точка всех правок) — экспортирует все ещё
     не закэшированные видимые клипы в фоне (гвард `inProgressSessions`, слайды/уже-кэш/удалённые
     источники пропускаются).
  3. **Очистка:** `deleteSession` → `removeAllClips(sessionID:)`; удаление плейлиста/группы/эпизода
     → `pruneOrphanedClips(for:)` из `updateSession` (сносит файлы, чьих hiddenKey больше нет ни в
     одном плейлисте). Удаление ИСТОЧНИКА из сессии НЕ чистит — клипы должны пережить это.
  4. **Плейбек source-first, cache-fallback** (важно!): раньше был cache-first — с авто-кэшем это
     сразу «замораживало» клип и ломало правки start/duration оверрайдов. Переделал оба пути
     (`loadSourceAndPlay`, `loadPlaylistAsSingleFilm`): пока оригинал доступен — играем из источника
     с оверрайдами; если источник удалён/убран из сессии — берём автономный клип из кэша (целиком).
  - **Грабли:** cache-first + авто-кэш = потеря редактируемости оверрайдов; решается source-first.
    Экспорт в файл (`SportCutExportSheet`) фолбэк на кэш пока НЕ добавлен (вне запроса — там про
    воспроизведение). Файлы: `SportCutClipCache.swift`, `SportCutSessionManager.swift`,
    `SportCutPlayerManager.swift`.

## 2026-08-08 — Режим просмотра: зум таймлайна разметки «в плейхед» (как в разметке плеера)
- **Задача:** ползунок зума таймлайна в режиме просмотра (SportCut) должен зумить туда, где плейхед,
  как в разметке.
- **Как сделано:** переиспользовал `TimelineScrollController` + `TimelineScrollControllerAttacher`
  (из `TimelineAutoScrollHelper.swift`, тот же таргет). В `SportCutTimelineView` привязал контроллер
  к горизонтальному `ScrollView` разметки через `.background(attacher)`, на `.onChange(of:
  timelineScale)` вызываю `handleMarkupZoomChanged(source:)` — логика 1:1 как `handleZoomChanged` в
  `FullControlView`: доля = `absoluteVideoTimelineTime(forSourceID:) / totalDuration` (если плейхед
  неизвестен — центр видимой области), удерживаем экранную позицию плейхеда (или центр, если он вне
  области), `newScrollX = ratio*newGridWidth - anchorX`, прыжок через `DispatchQueue.main.async`.
  Работает для ползунка и по завершении пинча (пинч меняет `timelineScale` только в `onEnded`).
  Плейлистовый таймлайн (`SportCutPlaylistsTimelinePane`) — отдельный компонент, при необходимости
  отдельная доработка. `SportCutTimelineView.swift`.

## 2026-08-08 — Тулбар окна разметки: кнопки переносятся на новую строку при сужении окна
- **Задача:** кнопки в навбаре окна видео (режим разметки) при узком окне не влезали в строку и
  ломали раскладку («распидорасивало»). Нужно, чтобы не влезающие переходили на следующую строку.
- **Как сделано:** ввёл `ToolbarFlowLayout: Layout` (flow-раскладка: строки + перенос не влезающих)
  — доступна с macOS 13, на 12 fallback на обычный `HStack` + `Spacer`. `customNormalToolbar`
  разбил на `toolbarControls` (общий набор кнопок без зума) + `zoomControls`; в flow-ветке они
  просто перечислены (каждый контрол — отдельный subview, `liveBroadcastControls` переносится целым
  блоком). `Layout` нативно работает с разнородными вью, поэтому моделировать кнопки как данные не
  пришлось. `VideoPlayerView.swift`.

## 2026-08-08 — Объединение проектов: выбор объединения одноимённых дорожек по каждому имени
- **Задача:** при склейке записанных видео, если есть таймлайны с одинаковым названием, предлагать
  пользователю выбрать — объединять их или нет.
- **Было:** один глобальный тумблер `mergesSameNamedLines` (всё или ничего; при выкл. ВСЕ дорожки
  получали префикс проекта, даже уникальные).
- **Стало:** `ProjectMergeOptions.mergedLineNames: Set<String>` — имена одноимённых дорожек,
  выбранных к объединению. В `ProjectMergeView` считаю дубли (`computeDuplicateLineNames` — имена,
  встречающиеся ≥2 раз среди выбранных проектов, кроме дорожки рисунков) и показываю секцию с
  чекбоксом на каждое имя (по умолчанию все отмечены) — ТОЛЬКО когда дубли есть, иначе секции нет.
  `mergedTimelines(sources:mergedLineNames:)`: рисунки всегда в одну по id; имя из набора →
  сливаем; иначе раздельно, причём одноимённые (в наборе дублей), которые НЕ сливаем, различаем
  префиксом «Проект — Имя», а уникальные дорожки всегда сохраняют исходное имя. Новый ключ
  локализации `mergeProjectsMergeLinesHint` во всех 7 языках. Файлы: `ProjectMergeManager.swift`,
  `ProjectMergeView.swift`. Грабли: static-func и computed-var не могут иметь одинаковое имя →
  хелпер назвал `computeDuplicateLineNames`.

## 2026-08-08 — Редактор коллекции связок: камера центрируется на только что созданном элементе
- **Задача:** при создании тега/лейбла/общего события в коллекции связок клавиш камера холста
  должна подъехать к новому элементу (чтобы он оказался по центру). Новые элементы кладутся ПОД
  существующими (`addTagToLayout`/`addLabelToLayout`/`addTimeEventToLayout` и `normalizeLayout`
  для новых тегов → `center.y = maxY + 80`), поэтому появляются за краем видимой области.
- **Как сделано:** в `TagFreeLayoutEditorContent` (холст) слежу за набором id элементов раскладки
  `.onChange(of: layout.items.map(\.id))`. `TagFreeLayoutItem.id` = `"kind:elementId"` (стабилен при
  нормализации — сохранённые элементы id не меняют, новый получает новый), поэтому одиночное
  добавление легко детектится диффом. На одиночное добавление плавно (0.25s) двигаю ТОЛЬКО панораму
  (`panOffset`), зум не трогаю: `panOffset = viewport/2 - (item.center - origin)*canvasZoom`, где
  `origin` считается как в `canvasArea` (contentRect + `infiniteMargin`). Массовые добавления
  (импорт/сброс/нормализация нескольких) пропускаю (`added.count == 1`). Автопанораму взвожу с
  задержкой 0.6s после `onAppear` (`autoCenterArmed`) + базовый `lastKnownItemIds` — чтобы стартовая
  загрузка/нормализация раскладки не дёргала камеру. Ловит все пути добавления (тег через normalize,
  лейбл/событие через nav-панель, карта через drop) в одном месте. `TagFreeLayoutEditorView.swift`.

## 2026-08-08 — Библиотека тегов: пропадает скролл на старых маках + кнопки зума (macOS < 18)
- **Задача:** в окне библиотеки тегов для обычных (grouped/стандартных) коллекций на старых маках
  пропадает скролл. Плюс: на macOS ниже 18 добавить кнопки зума (−/+), а не только ползунок, на
  этом экране.
- **Первопричина (скролл):** `groupedModeBody` использовал `LazyVStack` внутри `ScrollView`.
  Контент строится из flow-лэйаутов на `GeometryReader` (`TagFlowLayout` и т.п.); на старом macOS
  `LazyVStack` некорректно измеряет высоту такого контента → список не скроллится.
- **Как правилось (скролл):** вынес контент в `groupedModeContent` и на macOS < 14 рендерю его в
  обычном `VStack` (измеряется сразу, скроллится корректно), на 14+ оставил `LazyVStack` ради
  ленивости. `TagLibraryView.swift`.
- **Как правилось (кнопки):** в поповере `tagLibraryScaleControl` добавил кнопки −/+ вокруг
  слайдера под `if #unavailable(macOS 18.0)` (реальные версии прыгают 15 → 26, поэтому на 15 и
  ниже кнопки видны, на 26 — скрыты). Шаг `tagLibraryScaleStep = 0.25`, клампится в
  `tagLibraryScaleRange` (0.75...3.0), сохраняется через `saveScalePreference()`.

## 2026-08-08 — Фикс: зум окна видео в разметке (обычная: работает только первое нажатие; лайв: не зумит)
- **Задача:** в разметке кнопки +/− зума видео работают только на первое нажатие (дальше нет); в
  лайв-разметке зум не работает вообще (цифры растут, картинка не меняется).
- **Первопричина:** зум применялся через SwiftUI `.scaleEffect` на `CustomVideoPlayer`
  (`NSViewRepresentable` поверх `AVPlayerLayer`). Первое нажатие «срабатывало» лишь потому, что
  scale пересекал границу 1.0 и SwiftUI подменял `VideoPlayer` → `CustomVideoPlayer` (свежий
  AppKit-вью получает трансформ при вставке). Последующие изменения `.scaleEffect` на уже
  смонтированном вью не применялись — AppKit сбрасывает трансформ хост-слоя на следующем layout.
  В лайве же `liveStreamContent` рендерил `DirectCameraPreviewView()` вообще без `.scaleEffect` —
  зум-состояние никуда не применялось.
- **Как правилось:** зум/пан применяю напрямую как трансформ `CALayer` внутри репрезентаблов
  (`VideoPlayerView.swift`). Ввёл подклассы `NSView`: `ZoomablePlayerNSView` (хостит `AVPlayerLayer`)
  и `ZoomableCameraPreviewNSView` (хостит `AVCaptureVideoPreviewLayer`). Размер слоя и трансформ
  (`bounds`+`position`+`setAffineTransform(translate(offset)*scale)`, скейл вокруг центра, y инвертирую
  под SwiftUI-`.offset`) выставляю в `layout()`, а не только в `updateNSView`. Это ВАЖНО: первый
  `updateNSView` вызывается до того, как SwiftUI выдаст NSView реальные `bounds` (они `.zero`) —
  слой получал нулевой размер → чёрный экран до первого изменения зума. `layout()` вызывается
  AppKit на первом реальном лэйауте и на каждом ресайзе, поэтому картинка видна сразу на 1.0×.
  `updateNSView` теперь только прокидывает `scale`/`offset`/сессию (сеттеры → `needsLayout`).
  `CustomVideoPlayer`/`DirectCameraPreviewView` получили параметры `scale`/`offset`. Лайв-превью
  подключил к зуму в `liveStreamContent` (+ pinch/drag жесты); маленькое превью в боковой панели и
  mirror-окно остаются без зума (дефолт 1.0).
  - **Регрессия (пофикшена тем же подходом):** после первой версии (sizing в `updateNSView`) в
    лайве видео не появлялось до первого +/пинча, а в обычной разметке первый зум давал чёрный
    экран (потом ок) — та же причина с `.zero` bounds на первом `updateNSView`; перенос в `layout()`
    устранил оба случая.

## 2026-08-08 — Фикс: чёрный экран при просмотре тега (двойной клик) во время паузы трансляции
- **Задача:** при трансляции: отметить пару тегов (НЕ открывая их двойным кликом), поставить на
  паузу, затем открыть эти теги двойным кликом → чёрный экран, не проигрываются. Если открыть теги
  двойным кликом ДО паузы — во время паузы они открываются нормально.
- **Первопричина:** `assetForMomentViewer` (VideoPlayerManager) в live-режиме вызывает
  `LiveStreamManager.finalizeCurrentSegment`, затем собирает композицию только из `allSegmentURLs`
  (уже финализированные сегменты). А `finalizeCurrentSegment` имел guard `!isBroadcastPaused` —
  на паузе выходил сразу, НЕ финализируя текущий (открытый) сегмент. Кадры тегов, записанные
  непосредственно перед паузой, лежат в этом незавершённом сегменте → в композицию не попадают →
  чёрный экран. «Двойной клик до паузы» работал, потому что он (без паузы) финализировал текущий
  сегмент с кадрами тегов в `allSegmentURLs`.
- **Как правилось:** убрал `!isBroadcastPaused` из guard в `finalizeCurrentSegment`
  (`LiveStreamManager.swift`). Безопасно: `LiveStreamRecorder.stopRecording` финализирует writer в
  состоянии `.writing` (пауза лишь дропает входящие кадры), а `startNewSegmentRecorder` уже
  pause-aware — заново ставит новый рекордер на паузу, если `isBroadcastPaused`. Метод вызывается
  только из `assetForMomentViewer`, поэтому правка изолирована.

## 2026-08-07 — Фикс: после долгой работы Backspace не работает во ВСЕХ текстовых полях
- **Задача:** редко, после продолжительной работы, Backspace переставал работать сразу во всех
  полях (создание коллекции, теги, название плейлиста, комментарий к эпизоду) — до перезапуска.
  Одновременно не добавлялась картинка в слайд. Repro поймать не удалось.
- **Первопричина (Backspace):** глобальный `NSEvent.addLocalMonitorForEvents(.keyDown)` в
  `FullControlView` ловит клавиши ВСЕГО приложения и перехватывает Backspace (keyCode 51) как
  «удалить тег», пропуская событие в поле только если `FocusStateManager.isAnyTextFieldFocused`.
  Но многие поля (`AutoFocusTextField` в редакторе коллекций/плейлистах) этот флаг НЕ
  выставляют, а сам монитор мог накапливаться (пересоздавался в `setupKeyboardShortcuts` без
  снятия старого при повторном onAppear). Итог: утёкший/активный монитор съедал Backspace во
  всех окнах.
- **Что сделано:**
  - `FullControlView`: пропускаем событие в поле по РЕАЛЬНОМУ фокусу — новый
    `static isEditingTextInFocusedField()` (проверяет `NSApp.keyWindow?.firstResponder`:
    NSTextField / NSTextView.isFieldEditor). Теперь Backspace проходит в любом текстовом поле
    независимо от залипшего флага. Плюс монитор ставится идемпотентно (снимаем старый перед новым).
  - Утечки мониторов: `ViewerTableView` (.flagsChanged монитор вообще не снимался — теперь
    хранится в @State, идемпотентен, снимается в onDisappear); `StampCommentEditSheet` и
    `SportCutPlaylistsView` (Return-мониторы) — сделаны идемпотентными.
- **Картинка в слайд:** первопричину без repro не локализовал (вероятно застрявшая модальная
  сессия панели выбора файла или залипший флаг). Просил при повторении заметить контекст.
- **Как правилось:** `FullControlView.swift`, `ViewerTableView.swift`, `StampCommentEditSheet.swift`,
  `SportCutPlaylistsView.swift`. **Собирать — пользователь.**

## 2026-08-07 — Фикс: нумерация в «фильме по рисункам» — все клипы №1
- **Задача:** при экспорте рисунков (drawings) в виде фильма номер эпизода у всех клипов = 1.
- **Причина:** `NSAttributedString.attributedStringForTagInfo` при `playlistIndex == nil`
  считает ordinal как позицию штампа среди штампов ТОГО ЖЕ тега. У рисунков
  `Tag.syntheticDrawingTag.id = stamp.idTag` (уникален для каждого рисунка) → «штамп того же
  типа» всегда один → `firstIndex == 0` → ordinal = 1 у всех.
- **Что сделано:** в `ExportHelper.exportFilm` для типа `.drawingsTimeline` передаём
  последовательный `playlistIndex` (счётчик `episodeOrdinal` по порядку добавляемых сегментов,
  в обоих местах создания `OverlayItem` — с рисунками-скриншотами и без). Для остальных типов
  экспорта поведение не изменилось (`playlistIndex: nil` → прежняя нумерация по тегу).
- **Как правилось:** `ExportHelper.swift`. **Собирать — пользователь.**

## 2026-08-07 — ОТКАТ оптимизаций зависания FullControlView (по просьбе)
- **Задача:** оптимизации окна таймлайнов не помогли (всё равно виснет), пользователь попросил
  откатить всё по этой задаче — вернёмся позже.
- **Что сделано:** вручную (git нельзя — рабочее дерево содержит незакоммиченные правки из
  прошлых работ) откатил в `FullControlView.swift`: `exportHelper` обратно на `@StateObject`,
  inline-оверлей прогресса, убрал `ExportProgressOverlay`/`TimelineVOffsetKey`, ручную
  виртуализацию (`visibleLineRange`/`timelineRows`/трекер/coordinateSpace/@State), `LazyVStack`
  → обычный `VStack`, вернул прямые `ForEach(timelineData.lines)`. В `TimelineLineView.swift`
  откатил вынос `currentLineIndex` (снова считается в `stampView`), СОХРАНив более раннюю
  правку про мультипозиции (перенос штампа копирует `mapPositions`).
- **Итог:** окно таймлайнов — в состоянии до задачи оптимизации. Вернёмся по свежему профилю.

## 2026-08-07 — FullControlView: ручная виртуализация строк (открытие/скролл больших проектов)
- **Задача:** окно таймлайнов виснет даже на мощном ПК при большом числе таймлайнов/тегов,
  на слабом — зависает и вылетает. Причина (см. прошлую запись): все строки со штампами
  материализуются сразу; `LazyVStack` не виртуализирует правый столбец из-за вложенного
  горизонтального ScrollView.
- **Что сделано:** ручное «оконное» отсечение (безопасно — вертикального `scrollTo` в коде нет).
  - Трекинг вертикального смещения: `PreferenceKey TimelineVOffsetKey` + `coordinateSpace`
    на вертикальном `ScrollView` (обе ветки macOS12/13) + невидимый `timelineScrollOffsetTracker`
    (GeometryReader) в фоне `timelineContent`. `updateTimelineVerticalOffset` пишет @State
    троттлингом (раз в ~полстроки).
  - `visibleLineRange(count:)` считает видимый диапазон строк (высота строки 30, вьюпорт ≈
    `parentWindowHeight`, буфер 12 строк).
  - Оба списка вынесены в `timelineRows(...)` (дорожки) и `timelineNameRows()` (имена):
    рендерят `ForEach(timelineData.lines[range])` + распорки `Color.clear` фикс-высоты
    сверху/снизу (общая высота и выравнивание колонок сохраняются). Общий диапазон = обе
    колонки прокручиваются синхронно.
  - Итог: при 686 таймлайнах рендерится ~30–40 строк вместо всех.
  - Доп. (после жалобы, что всё равно виснет): в `TimelineLineView.stampView` индекс строки
    (`timelineData.lines.firstIndex`) вызывался ДЛЯ КАЖДОГО штампа → O(таймлайнов × штампов)
    на проход рендера (для 686 таймлайнов — квадратично, вешало). Теперь `currentLineIndex`
    считается один раз в body строки и передаётся в `stampView` параметром.
- **Как правилось:** `FullControlView.swift`, `TimelineLineView.swift`. **Собирать — пользователь.**
- **Замечание:** приложенный spindump снят ДО этих правок (стек — SwiftUI layout, 0.99s/1.03s
  main). Нужен свежий замер после пересборки, если тормоза останутся, — тогда точечно
  дожать (гориз. виртуализация штампов внутри строки / изоляция скролла от body / GeometryReader per row).

## 2026-08-07 — Inline-создание групп/событий в редакторе коллекций СО СВЯЗКАМИ КЛАВИШ
- **Задача:** в редакторе keybindings-коллекций добавление группы тегов / группы лейблов /
  общего события шло через модальное окно (sheet), где Enter не работал. Нужно — inline-ввод
  прямо в левом столбце, как при создании лейбла (`addInlineLabel`). (Ранее по ошибке правил
  не тот экран — `CreateCustomCollectionsView`; правильный экран — левая панель
  `CollectionNavigationPanel`, встроенная в `KeyBindingsCollectionEditorView`.)
- **Что сделано:** в `CollectionNavigationPanel` кнопки «+» теперь создают элемент СРАЗУ с
  пустым именем и открывают inline `AutoFocusTextField` в списке (Enter сохраняет), точно как
  `addInlineLabel`: `addInlineTagGroup`/`addInlineLabelGroup`/`addInlineTimeEvent` +
  состояния `editingGroupID`/`editingEventID`. Заголовок группы (`groupSelectableLabel`) и
  строка события (`timeEventRow`) показывают поле при редактировании (двойной клик по имени
  или карандаш — тоже inline). Три модальных `.sheet` (createTagGroup/createLabelGroup/
  addTimeEvent) убраны из `contentWithSheets`.
- **Как правилось:** `CollectionNavigationPanel.swift`. **Собирать — пользователь.**
- **Доп. правки (тот же экран):** (1) новые группы тегов/лейблов и события добавляются ВВЕРХУ
  списка — в `CustomCollectionManager` `createTagGroup`/`createLabelGroup`/`createTimeEvent`
  сменил `append` на `insert(at: 0)` (влияет и на обычный редактор — поведение универсальное).
  (2) Добавил кнопку удаления группы (корзина) в заголовок группы тегов и лейблов
  (`groupSelectableLabel` + `onDelete`) с подтверждением-алертом (`tagGroupPendingDelete`/
  `labelGroupPendingDelete`, методы `deleteTagGroup`/`deleteLabelGroup` уже были) — раньше
  удалить группу в связках клавиш было нельзя.

## 2026-08-07 — Оптимизация FullControlView: зависание при экспорте больших проектов
- **Задача:** экспорт огромной разметки (686 таймлайнов) на слабом маке крашил приложение.
  По логу (spindump `hang`, стек — рекурсия SwiftUI-layout + CoreAnimation, НЕ AVFoundation)
  — зависание main-потока при отрисовке FullControlView. Оптимизировать под любой размер.
- **Причина №1 (главная, краш при экспорте):** `@StateObject var exportHelper` подписывал
  ВЕСЬ FullControlView на `exportHelper.objectWillChange`, поэтому КАЖДЫЙ тик `progress`
  во время экспорта пересчитывал body со всеми 686 строками таймлайнов → hang → watchdog.
- **Причина №2 (тяжесть в принципе):** строки таймлайнов и столбец имён рендерились через
  обычный `VStack + ForEach` (не Lazy) — все 686 строк материализовались сразу.
- **Что сделано (пакеты A+B, экспорт-оверлеи НЕ трогали по решению пользователя):**
  - A: `@StateObject exportHelper` → `@State private var exportHelper` (стабильный экземпляр
    БЕЗ подписки на Combine). Прогресс вынесен в отдельный `ExportProgressOverlay`
    (`@ObservedObject` живёт только там) — тики `progress` перерисовывают лишь маленький
    оверлей, а не список. Это и убирает краш при экспорте.
  - B: два `VStack` со строками (дорожки + столбец имён) → `LazyVStack` — ленивый рендер.
- **Замечание:** левый столбец имён виртуализируется надёжно (LazyVStack прямо в vertical
  ScrollView). Правый столбец строк — внутри вложенного horizontal ScrollView, поэтому
  LazyVStack там может не виртуализировать; если после сборки правый столбец всё ещё тяжёлый,
  следующий шаг — ручное «оконное» отсечение видимого диапазона строк (с тестами, т.к.
  затрагивает scrollTo/плейхед).
- **Как правилось:** `FullControlView.swift` (`exportHelper` → @State, `ExportProgressOverlay`,
  два `LazyVStack`). **Собирать — пользователь.**

## 2026-08-06 — Прогресс-баннер экспорта по хоткеям + Enter в диалогах групп
- **Задача:** (1) при экспорте клипа/фильма по Cmd+S / Opt+Cmd+S показывать снизу баннер с
  прогресс-баром на время подготовки, после завершения — тот же тост успеха/ошибки; (2) в
  редакторе коллекций при добавлении группы тегов / группы лейблов / общего события по Enter
  сохранять и закрывать окно (а не только по кнопке Add).
- **Что сделано:**
  - `ClipSaveToastPresenter` — добавлен режим прогресса: `showProgress(text:progress:)`
    (обновляется на месте через `ProgressToastModel: ObservableObject`, без пересоздания
    панели) и `dismissProgress()`. Новый `ClipSaveProgressToastView` (спиннер + линейный
    прогресс-бар). Позиционирование панели вынесено в `positionPanel`.
  - `ClipAutoSaveManager` — `startProgressBanner(text:session:)` (Timer 0.15с опрашивает
    `session.progress`) + `stopProgressBanner()`. В `exportClip` (Cmd+S, только явный —
    `!silentErrors`) и `performMergedExport` (Opt+Cmd+S) баннер стартует перед
    `exportAsynchronously`; в completion — `stopProgressBanner()`, затем success/error-тост
    (при отмене — `dismissProgress()`). Ключи `ClipAutoSaveInProgress` /
    `ClipAutoSaveMergedInProgress` уже были во всех языках.
  - `CreateCustomCollectionsView` — добавление группы тегов / группы лейблов / общего события.
    В модальных `.sheet` Enter не срабатывал НИКАК (ни SwiftUI `.onSubmit`, ни `doCommandBy`,
    ни `target/action` — NSTextField просто выделял текст). Решение по просьбе: убрал модальные
    окна, сделал **inline-добавление прямо в списке слева** — как inline-переименование (там
    `AutoFocusTextField` давно работает). Кнопки `addTagGroupButton`/`addLabelGroupButton`/
    `addTimeEventButton` при нажатии показывают inline `AutoFocusTextField` (флаги
    `isAddingTagGroup`/`isAddingLabelGroup`/`isAddingTimeEvent`); Enter создаёт элемент +
    сохраняет + скрывает поле. Sheet-функции и `EnterSubmitTextField` остались в коде, но не
    вызываются.
- **Как правилось:** `ClipSaveToastPresenter.swift`, `ClipAutoSaveManager.swift`,
  `CreateCustomCollectionsView.swift`. **Собирать — пользователь.**

---

## 2026-08-06 — Правки: вотермарка Cmd+S = текстовый оверлей, лишняя шестерёнка, вход в настройки
- **Задача:** (1) убрать дублирующую шестерёнку из верхней панели; (2) настройка для Cmd+S /
  Opt+Cmd+S — это НЕ логотип клуба, а обычная текстовая вотермарка (название тега, лейблы,
  номер эпизода, комментарий), которая в окне экспорта — флаг; для хоткеев окна нет → флаг
  в настройках; (3) вход в настройки — из меню-шестерёнки в VideosView вместо «Club logo».
- **Что сделано:**
  - Убрал `settingsButton` (шестерёнку) из верхней панели `ContentView`. Вход в настройки:
    пункт главного меню «Настройки…» (⌘,) + меню-шестерёнка в `VideosView` (бывший «Club logo»
    → «Настройки…», открывает `openSettingsWindow`; старый sheet с ClubLogo убран).
  - `AppSettingsStore.exportClipsWithWatermark` теперь = ТЕКСТОВАЯ вотермарка. В
    `ClipAutoSaveManager` для Cmd+S (одиночный/каждый из мультивыбора) и Opt+Cmd+S (склейка)
    при включённой настройке накладывается `ExportHelper.videoCompositionWithTextOverlay`
    (переиспользую логику окна экспорта) с `ExportWatermarkOptions.default` (лого клуба тут
    не включаем). Новые приватные хелперы `overlayItem(for:…)` и `makeWatermarkedClipComposition`.
    Одиночный клип теперь при вотермарке экспортируется как композиция-отрезок (иначе — быстрый
    путь asset+timeRange).
  - Убрал неиспользуемую `ClubLogoWatermarkManager.makeWatermarkVideoComposition` (лого-композиция).
  - Обновил тексты тогла `SettingsExportWatermark`/`Hint` во всех 7 языках (теперь про текстовую вотермарку).
- **Как правилось:** `Youchip_StatApp.swift`, `Modules/Videos/Views/VideosView.swift`,
  `ClipAutoSaveManager.swift`, `ClubLogoWatermarkManager.swift`, `SettingsView.swift`,
  `Resourses/*/Localizable.strings`. **Собирать — пользователь.**

## 2026-08-06 — Экран настроек + мультиклип Cmd+S + вотермарка на быстром сохранении
- **Задача:** (1) при мультивыборе штампов в разметке Cmd+S должен сохранять КАЖДЫЙ
  выбранный клип отдельным видео в папку; (2) доп-опция в настройках «сохранять с
  вотермаркой» — если включена, лого клуба накладывается и на Cmd+S, и на Opt+Cmd+S
  (текущая логика вотермарки); (3) нормальный экран настроек, открываемый из ГЛАВНОГО
  меню (⌘,) + шестерёнка, куда перенесены логотип клуба и этот тогл (и будущие настройки).
- **Что сделано:**
  - Мультиклип: `ClipAutoSaveManager.saveSelectedStampClip()` — если выбрано >1 штампа
    (`stampsSelectedForSportCut`), каждый ставится в очередь `pendingExports` отдельным
    файлом (та же последовательная очередь `drainPendingQueue`). Один — как раньше.
    (Opt+Cmd+S по-прежнему склеивает в один фильм.)
  - Вотермарка: новый `AppSettingsStore.exportClipsWithWatermark` (UserDefaults). В
    `exportClip` и `performMergedExport` при включённом флаге ставится
    `session.videoComposition = ClubLogoWatermarkManager.makeWatermarkVideoComposition(for:)`
    — новый переиспользуемый билдер композиции с CALayer-лого (по образцу ExportHelper).
  - Экран настроек: новый `SettingsView` (язык, тема, тогл вотермарки, встроенный редактор
    логотипа клуба). Открытие: `WindowsManager.openSettingsWindow()`; пункт главного меню
    «Настройки…» (⌘,) в `AppSetupManager.setupMenu` (target=nil → responder chain →
    `AppDelegate.openSettings`); плюс кнопка-шестерёнка в верхней панели `ContentView`.
- **Как правилось:** новый `Common/Managers/AppSettingsStore.swift` (+pbxproj);
  `ClubLogoWatermarkManager.swift` (+`makeWatermarkVideoComposition`, import AVFoundation);
  `ClipAutoSaveManager.swift`; новый `Modules/VideoPlayer/Views/SettingsView.swift`;
  `WindowsManager.swift` (+`openSettingsWindow`); `AppDelegate.swift` (+`openSettings`);
  `AppSetupManager.swift` (пункт меню); `Youchip_StatApp.swift` (шестерёнка); 5 ключей
  Settings* во все 7 `.strings`. **Собирать — пользователь.**

## 2026-08-06 — Одна метка со всеми позициями для мультикарты (модель + миграция)
- **Задача:** тег, привязанный к нескольким картам, при простановке точек создавал ОТДЕЛЬНЫЙ
  штамп на каждую карту. Нужно: один штамп со всеми позициями (по точке на карту). Поменять
  корневую модель позиции в штампе на массив, мигрировать старые данные и корректно читать
  в визуализации.
- **Что сделано:**
  - Модель `TimelineStamp`: одиночные `position: CGPoint?` + `mapFieldId: String?` заменены
    на `mapPositions: [StampMapPosition]` (новый тип: `{mapFieldId: String?, position}`).
    `position`/`mapFieldId` оставлены как computed (первая точка) для обратной совместимости
    чтения. Добавлены `position(forFieldId:)`, `setPosition(_:forFieldId:)`, `setPrimaryPosition`.
  - Codable: пишем `mapPositions` + зеркалим первую точку в старые ключи (`position`/`mapFieldId`),
    чтобы файлы читались и старыми версиями. Декод: есть `mapPositions` → берём его; иначе
    миграция из старой одиночной точки.
  - Создание: `addStampToSelectedLine` получил параметр `mapPositions:`; в `TagLibraryView`
    `proceedWithTagAdditionMulti`/`…IntervalMulti` теперь строят ОДИН штамп со всеми точками
    (helper `mapPositions(fields:normalizedByField:)`), а не цикл по картам.
  - Обновление точки: `updateStampPosition` и config-view пишут через `setPosition`/`setPrimaryPosition`.
  - Визуализация: `FieldMapVisualizationView` считает позицию для каждой карты через
    `position(of:on:)` (учёт legacy-точки без карты → первая карта); `HeatMapView` теперь
    принимает `points: [CGPoint]` (позиции именно этой карты). `FieldMapVisualizationPicker`
    считает штамп визуализируемым, если ЛЮБАЯ его точка попадает в карту коллекции.
  - Защита от потери позиций при копировании штампа: `copyStamp`, перенос между таймлайнами
    (`TimelineLineView`), и orphaned-timeline round-trip в `DataSyncManager` (вложенный
    `TimelineStamp` тоже получил `mapPositions` + миграцию).
- **Как правилось:** `TimelineStamp.swift`, `TimelineDataManager.swift`, `TagLibraryView.swift`,
  `FieldMapVisualizationView.swift`, `HeatMapView.swift`, `FieldMapVisualizationPicker.swift`,
  `FieldMapConfigurationView.swift`, `TimelineLineView.swift`, `DataSyncManager.swift`.
  **Собирать — пользователь.**

## 2026-08-06 — Фикс: коллекция связок клавиш не прогружалась / улетала в угол
- **Задача:** в окне библиотеки тегов при входе в разметку коллекция «Связки клавиш»
  (свободная раскладка) (1) не прогружалась с первого раза — помогал только заход на
  стандартную коллекцию или в редактор; (2) уходила «в угол», хотя должна прижиматься
  левым верхним тегом к левому верхнему углу окна.
- **Причина (обе — один корень):** в `FreeTagsCanvasView` зум-к-курсору висел на
  `onChange(of: scale)`, а `scale = baseFit * userScale`. При первом открытии геометрия
  окна «доезжает» до реального размера уже ПОСЛЕ `onAppear` → меняется `baseFit` → меняется
  `scale` → срабатывает pivot-математика зума и `panOffset` уводит контент в угол/за экран
  (выглядит как «не прогрузилось»). При заходе на стандартную/в редактор и обратно геометрия
  уже стабильна (плюс `refreshID`-ребилд по `collectionsLoadingFinished`), поэтому «чинилось».
  Дисплей-режим тут ни при чём: `loadLayoutIfExists` не возвращает nil из-за меток, так что
  `tagDisplayMode` корректно становился `.free` и на первом заходе.
- **Что сделано:** зум-к-курсору теперь реагирует ТОЛЬКО на пользовательский зум —
  `onChange(of: userScale)` (пинч/слайдер), а ресайз окна (изменение `baseFit`) больше не
  двигает `panOffset`. Контент остаётся прижат к левому верхнему углу. `lastScale`→`lastUserScale`.
- **Как правилось:** `Youchip-Stat/Modules/VideoPlayer/Views/FreeTagsCanvasView.swift`
  (`@State lastUserScale`, `onChange(of: userScale)`, `onAppear`/`onChange(layoutKey)` →
  `lastUserScale = userScale`). **Собирать — пользователь.**

## 2026-08-06 — Ревью локализации + базовые коллекции для всех языков
- **Задача:** (1) сверить локализационные файлы с английским, чтобы ключи совпадали
  везде; (2) в BaseCollections сделать по 2 коллекции для остальных языков (было только
  ru/en) и обновить names.json; (3) при смене языка стандартные коллекции тоже переключать.
- **Что сделано:**
  1. Нашёл расхождение: en/ru имели 1260 ключей, es/fr/uz/zh-Hans/zh-Hant — по 1222
     (не хватало 38 ключей: `CollectionsMenu*`, `CollectionType*`, блок скачивания видео
     по URL, `KeyBindings*TimeEvents*`). Добавил переводы во все 5. Плюс баг регистра:
     ключ `players` (строчный) во всех файлах кроме ru — оператор `^` ищет `Players`
     (с заглавной), поэтому в en/es/fr/uz/zh лукап падал в фолбэк. Исправил на `Players`.
     Итог: все 7 языков ровно по 1260 ключей, `plutil -lint` OK.
  2. Сгенерировал 10 новых папок коллекций (Football/Hockey × es/fr/uz/zh-Hans/zh-Hant),
     скопировав структуру английских (id/цвета/ссылки групп сохранены, переведены только
     `name`, глоссарий ~148 терминов). Схема names.json переведена на v2: `items` с
     раздельными `folder` (уникальный ресурс, напр. `Football_fr`) и `name` (отображаемое).
     Это нужно из-за коллизий имён папок (fr «Football» == en, zh-Hans/zh-Hant == 足球/冰球).
  3. `getAppCollectionLanguage()` теперь берёт `LanguageManager.shared.effectiveLanguage`
     (учёт рантайм-выбора языка), фолбэк на en. Добавил наблюдателя `.appLanguageChanged`
     в `TagLibraryManager`: пересобирает `standardCollections` под новый язык и, если была
     выбрана стандартная коллекция, переключает на тот же вид спорта по индексу.
- **Как правилось:** `Resourses/*/Localizable.strings` (+38 ключей ×5, фикс `Players` ×6);
  `BaseCollections/` (+10 папок, `names.json` v2); `VideoPlayerModels.swift`
  (`LanguageCollectionItem` + `LanguageCollection.items/resolvedItems`);
  `TagLibraryManager.swift` (`loadBaseCollections`/`loadCollections(_:)` по folder+name,
  `getAppCollectionLanguage` через LanguageManager, `handleAppLanguageChanged`).
  Генератор: `scratchpad/gen_collections.py`. **Собирать — пользователь.**

## 2026-08-06 — Переключение языка интерфейса в приложении (без перезапуска)
- **Задача:** сделать смену языка прямо в настройках приложения. Стартовый язык —
  автоопределение по системе (как раньше), но пользователь может выбрать язык в приложении,
  и оно перелокализуется без перезахода. Языки — из уже добавленных.
- **Что сделано:** новый `LanguageManager` (singleton, ObservableObject) + подмена
  `Bundle.main` на `LocalizedBundle` (objc swizzle через `object_setClass` +
  associated object), чтобы `NSLocalizedString`/оператор `^` читали строки из выбранной
  `.lproj`. Выбор хранится в UserDefaults (`appLanguageOverride`); нет ключа = система.
  Мгновенная перелокализация — через `@Published refreshToken` и `.id(...)` на корневом
  `ContentView` (полная пересборка дерева SwiftUI). Меню-глобус в верхней панели рядом с
  темой оформления: «Как в системе» + 7 языков (ru/en/es/fr/uz/zh-Hans/zh-Hant) с
  native-названиями. `setupAtLaunch()` вызывается первым в `AppSetupManager.setup()`.
  Также постится `.appLanguageChanged` и выставляется `AppleLanguages` для консистентности
  форматтеров после рестарта. **Собирать — пользователь.**
- **Как правилось:** новый `Common/Managers/LanguageManager.swift` (enum `AppLanguage`,
  `Bundle.setLanguage`, `LanguageManager`); `AppSetupManager.setup` — вызов
  `setupAtLaunch()`; `Youchip_StatApp` — `@StateObject languageManager`,
  `.environmentObject` + `.id(refreshToken)` на `ContentView`, новый `languageMenu`;
  новые ключи `LanguageTitle`/`LanguageAuto` в enum `Titles` и во всех 7 `.strings`.

## 2026-08-03 — Вернуть авто-экспорт клипов под флагом рядом с папкой
- **Задача:** вернуть авто-экспорт клипа на каждый тег, но управлять им флагом рядом с
  названием папки автосейва.
- **Что сделано:** флаг `isAutoExportEnabled` (по умолчанию OFF, хранится в UserDefaults);
  авто-экспорт на добавление тега работает ТОЛЬКО при включённом флаге. В окне таймлайнов
  рядом с кнопкой папки — чекбокс «Авто-экспорт клипов». В лайве авто-путь по-прежнему
  пропускается (рестарт рекордера на каждый тег недопустим); в лайве — по Cmd+S/Opt+Cmd+S.
  **Собирать — пользователь.**
- **Как правилось:** `ClipAutoSaveManager` — `@Published isAutoExportEnabled` +
  `setAutoExportEnabled` + `autoSaveStampIfConfigured` (guard по флагу и `!isLive`);
  `TimelineDataManager.addStampToSelectedLine` — вернул вызов + `addedStampID`;
  `FullControlView` — новый `clipAutoExportToggle` рядом с `clipAutoSaveButton`;
  локализация `clipAutoExportBadge` в 7 языках (plutil OK).

## 2026-08-03 — Убрать авто-экспорт клипа при добавлении тега (лишнее)
- **Задача:** при завершении записи интервального тега НЕ нужно сохранять его как видео —
  просто закончить запись и добавить стамп на таймлайн. Пользователь этого не просил.
- **Что сделано:** авто-сохранение клипа на каждое добавление тега убрано полностью. В папку
  теперь только по явному Cmd+S (один) / Opt+Cmd+S (склейка). **Собирать — пользователь.**
- **Как правилось:** удалён вызов `ClipAutoSaveManager.autoSaveStampIfConfigured` из
  `TimelineDataManager.addStampToSelectedLine` (+ вычищена ставшая мёртвой переменная
  `addedStampID`); удалён сам метод `autoSaveStampIfConfigured` в `ClipAutoSaveManager`.
  Явные пути (`saveSelectedStampClip`/`saveMergedSelectedClips`, в т.ч. лайв через
  `prepareFullCompositionForExport`) не тронуты.

## 2026-08-03 — TASK-003 (часть): Enter сохраняет в sheet'ах редактора коллекций
- **Задача:** в редакторе коллекций Enter не сохраняет при вводе названия — общие события,
  создание групп тегов и групп лейблов. Enter должен применять, Esc — выходить.
- **Что сделано (эта итерация):** Enter (onSubmit) теперь сохраняет в трёх sheet-ах создания:
  общие события (`addTimeEventSheet`), группа тегов (`addTagGroupSheet`), группа лейблов
  (`addLabelGroupSheet`). В Cancel группы тегов добавлен Esc (не было). **Собирать — пользователь.**
- **Как правилось:** причина — `FocusAwareTextField` при фокусе перехватывает Return в свой
  `.onSubmit` (был nil), поэтому `.keyboardShortcut(.defaultAction)` на кнопке «Добавить» не
  срабатывал. Передал полю `onSubmit:` с тем же действием, что у кнопки (+`guard` на пустое имя).
  Файл `CreateCustomCollectionsView.swift`.
- **Осталось (не сделано):** Enter в sheet-ах РЕДАКТИРОВАНИЯ (события/лейбл/тег) и в
  `addLabelSheet`/имя тега; «общие события сделать инлайн в правом меню как лейблы» — это
  UI-редизайн (sheet → инлайн), нужен образец инлайн-ввода лейблов и подтверждение.

## 2026-08-03 — Сохранение клипов в папку в ЛАЙВЕ («текущее видео недоступно»)
- **Задача:** при сохранении тегов в папку в лайв-разметке (и один Cmd+S, и склейка
  Opt+Cmd+S) писало «текущее видео недоступно» — и при записи, и на паузе.
- **Что сделано:** в лайве источник берётся из записи, а не из плеера. `getCurrentVideoURL()`
  в лайве nil (плеер показывает поток, не файл) — отсюда ошибка. Теперь через
  `LiveStreamManager.prepareFullCompositionForExport` берётся вся запись (база+сегменты+
  текущий фрагмент) как `AVAsset`, тайминги штампов ложатся на неё напрямую. Работает и при
  записи, и на паузе (`isLive` на паузе остаётся true, рекордер не обнуляется). **Собирать
  будет пользователь.**
- **Как правилось:** `ClipAutoSaveManager` — новый `resolveExportAsset` (лайв→полная
  композиция, иначе→файл плеера, асинхронно); `exportClip` и merged-путь (`performMergedExport`)
  принимают готовый `AVAsset`; `drainPendingQueue` резервирует `isSaving` на время async-
  получения источника. В лайве авто-сейв на каждый тег отключён (`autoSaveStampIfConfigured`
  guard `!isLive`) — иначе рестарт рекордера на каждый тег; в лайве сохранение только по
  явному Cmd+S / Opt+Cmd+S.
- **Проверить:** склейка/одиночный в лайве при записи И на паузе; не сбивается ли состояние
  паузы после экспорта (метод финализирует и перезапускает рекордер).

## 2026-08-03 — TASK-005: кнопка папки автосейва показывает имя папки (центр-сокращение)
- **Задача:** дать возможность выбрать/сменить папку автосейва во время разметки; кнопка с
  индикатором в окне таймлайнов. Уточнение: показывать имя папки, при длине >15 — сокращать
  по центру («пап…ка»), сохраняя последние 2 символа.
- **Что сделано:** кнопка `clipAutoSaveButton` в окне таймлайнов (FullControlView) уже
  существовала (меню выбрать/сменить/сбросить + `pickFolder()`), но при выбранной папке
  показывала только галочку. Теперь показывает имя папки с центр-сокращением. BUILD зелёный.
- **Как правилось:** `FullControlView` — новый computed `truncatedFolderName`
  (`prefix(12) + "…" + suffix(2)` при длине >15); в label кнопки галочка заменена на
  `Text(truncatedFolderName)`. Механику выбора/смены папки трогать не пришлось — она из TASK-001.
- **Замечание:** ряд `inlineControlsBar` начинается с `VideoControlPanelView(width: 1800)` —
  на узком окне кнопка может уезжать вправо за край. Если будет не видно — вынести левее (TASK-006).

## 2026-08-03 — TASK-002: библиотека тегов — crop пустого места + левый верхний угол
- **Задача:** в библиотеке тегов у коллекций связок клавиш вокруг объектов оставалось лишнее
  пустое место (в канве-редакторе оно нужно, в библиотеке — нет); коллекция должна показываться
  строго по краям объектов и всегда открываться в левом верхнем углу.
- **Что сделано:** библиотечный рендер обрезается точно по bounding box объектов (убран отступ),
  коллекция открывается/переключается в левом верхнем углу вместо центрирования. Канва-редактор
  не тронут. BUILD зелёный.
- **Как правилось:** `FreeTagsCanvasView.contentRect(of:)` — `padding: 24 → 0`; начальный
  `panOffset` в `onAppear` и `onChange(layoutKey)` изменён с центрирования
  `(viewport - canvas)/2` на `.zero` (левый верхний угол).

## 2026-08-03 — Краш при старте записи интервального тега (регрессия TASK-001)
- **Задача:** приложение падало при включении записи интервального тега. В логе —
  `NSGenericException: window ... more Update Constraints in Window passes than there are views`
  на `NSPanel 153×50` (+ отдельные предупреждения CFPrefs о записи ≥4MB в UserDefaults).
- **Что сделано:** краш устранён. Причина — `ClipSaveToastPresenter` (тост из TASK-001):
  `NSHostingView` внутри `NSPanel` сам управлял размером окна через
  `updateWindowContentSizeExtrema`, осцилляция размера → бесконечный цикл updateConstraints.
  BUILD зелёный. Отдельно зафлажен баг >4MB в UserDefaults (потеря данных) — вынесен отдельно.
- **Как правилось:** `ClipSaveToastPresenter.present()` — `hosting.sizingOptions = []`
  (macOS 13+) + hosting кладётся в контейнер-`NSView`, а не в `contentView` панели напрямую
  (фикс для macOS 12) → hosting больше не управляет размером окна.

## 2026-08-03 — Разворот с ролевой команды на inline + база знаний
- **Задача:** роли (tech-lead/developer/reviewer/tester) оказались медленными и дорогими по
  токенам; сделать так, чтобы задачи выполнялись быстро и дёшево — хватит богатой базы знаний.
- **Что сделано:** удалена ролевая команда агентов (`.claude/agents/`); vault переориентирован
  из «памяти команды» в базу знаний, читаемую inline перед работой; база знаний наполнена
  (карта архитектуры, заметки по всем модулям, индекс синглтонов); заведён этот файл истории.
- **Как правилось:** `rm -rf .claude/agents`; переписаны `CLAUDE.md` (раздел «Knowledge Base»)
  и `vault/README.md`; добавлены `vault/knowledge/architecture.md` и заметки модулей.

## 2026-08-03 — TASK-001: автосохранение клипов в папку (фиксы по фидбеку)
- **Задача:** комбинация «сохранить тег в папку» показывала тост, но файл не сохранялся; не
  предлагала выбрать папку; тост в неудобном месте; нужен Opt+Cmd+S для склеенного фильма.
- **Что сделано:** клип реально сохраняется (во время и после записи); папка предлагается при
  старте записи + кнопка в тулбаре; тост вынесен в правый нижний угол экрана, самоисчезающий;
  Opt+Cmd+S склеивает выделенные клипы таймлайна в один фильм. Учтены замечания ревью:
  глушение некритичных ошибок на авто-пути, уникальные имена файлов (мульти-карта), единая
  очередь экспорта без гонок, флаг «не спрашивать папку повторно за сессию». BUILD SUCCEEDED.
- **Как правилось:** корень бага — автосейв целился в `selectedStampID`, а тег попадал в
  `lastAddedStampID` (`ClipAutoSaveManager.selectedStampAndName`); авто-триггер добавлен в
  `TimelineDataManager.addStampToSelectedLine`; новый `ClipSaveToastPresenter` (borderless
  NSPanel, правый нижний угол `visibleFrame`); Opt+Cmd+S в `HotKeyManager` →
  `saveMergedSelectedClips` через `stampsSelectedForSportCut` + `AVMutableComposition`.
  Локализация в 7 языках. Детали — [[tasks/in-progress/TASK-001-clip-autosave-folder-fixes]],
  ревью — [[reviews/TASK-001]]. _(Статус: код готов, ждёт ручной проверки пользователем.)_
