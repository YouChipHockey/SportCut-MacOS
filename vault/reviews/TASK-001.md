---
task: TASK-001
reviewer: reviewer
date: 2026-08-02
verdict: changes-requested   # approved | changes-requested | blocked
---

# Ревью TASK-001 — Фиксы автосохранения клипов + баннер + merged-экспорт

## Что ревьюил
Задача [[../tasks/in-progress/TASK-001-clip-autosave-folder-fixes]].
Файлы TASK-001 (из общего диффа ветки `localization`, где много постороннего in-flight кода):
- NEW `Modules/VideoPlayer/Managers/ClipAutoSaveManager.swift` (untracked)
- NEW `Modules/VideoPlayer/Managers/ClipSaveToastPresenter.swift` (untracked)
- `Modules/VideoPlayer/Managers/TimelineDataManager.swift` (хук автосейва в `addStampToSelectedLine`)
- `Modules/VideoPlayer/Managers/HotKeyManager.swift` (Cmd+S / Opt+Cmd+S)
- `Modules/VideoPlayer/Managers/WindowsManager.swift` (`promptFolderForNewSessionIfNeeded`)
- `Common/Extensions/LocalizedStrings.swift` + `Resourses/{ru,en,es,fr,uz,zh-Hans,zh-Hant}`

## Сборка
- [x] `xcodebuild … build CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED** (exit 0).
      SourceKit-диагностики (`^`, `Titles`, `WindowsManager not in scope`) — ложные, как и ожидалось.
- [x] `plutil -lint` по всем 7 `.strings` → OK.

## Замечания
| # | Файл:строка | Severity | Что не так | Предложение |
|---|-------------|----------|------------|-------------|
| 1 | `ClipAutoSaveManager.swift:169-187` (`exportClip.fail`) + `TimelineDataManager.swift:349-352` | med | Автосейв триггерится на КАЖДЫЙ добавленный штамп и при неудаче показывает **красный error-тост**. Сценарий: тег с `defaultTimeBefore==0 && defaultTimeAfter==0` (юзер может так настроить, поля редактируемые) → `end == start` → `guard end>start` падает → тост «Некорректный диапазон клипа» на каждый такой инстант-тег в лайве. Автоматическое действие не должно шуметь ошибками. | Для авто-пути (`autoSaveStampIfConfigured`) молча пропускать нулевой/битый диапазон и «нет видео»; error-тосты показывать только для явного Cmd+S. Проще: в `drainPendingQueue` отсекать `end<=start` до `exportClip`. |
| 2 | `TimelineDataManager.swift:986-1001,1014-1029` → `ClipAutoSaveManager.makeFileName:410-418` | med | Мульти-карта создаёт N штампов с одинаковым `tagName` и одинаковым `timeStart` → `makeFileName` даёт **одинаковое имя файла** → N экспортов последовательно перезаписывают друг друга (`removeItem` + запись), остаётся 1 файл, N-1 экспорт впустую. Клипы к тому же идентичны (в экспорт не идут карты/оверлеи). | Дедуплицировать автосейв по диапазону времени (один клип на (start,end)); либо не автосейвить мульти-карту дубликатами. Если оставлять — добавить в имя uid, чтобы не терять файлы. |
| 3 | `ClipAutoSaveManager.swift:114-130` (`saveSelectedStampClip`) | low-med | Cmd+S не проверяет `isSaving` и идёт мимо очереди `pendingStampIDs`. При активном авто-экспорте запускается параллельный экспорт, перетирается `exportSession`, а по завершении первого `isSaving=false` даёт `drainPendingQueue` стартовать ещё один поверх текущего → наложение экспортов в лайве. | Пропускать Cmd+S тоже через очередь (append selected/last id) или `guard !isSaving`. |
| 4 | `ClipAutoSaveManager.swift:242-375` (`saveMergedSelectedClips`) + `HotKeyManager.swift:237-249` | med | Источник Opt+Cmd+S = `stampsSelectedForSportCut` выбран по **догадке** — это открытый вопрос/блокер самой задачи (видео фидбека не подгрузилось; могло иметься в виду клипы плейлиста SportCut). Функция рабочая, но спека не подтверждена. | Не мержить п.4 в релиз до ответа продукта. Код можно оставить за фиче-флагом/уточнить. Отметить в задаче как «ожидает подтверждения». |
| 5 | `WindowsManager.swift:243,286,330,824` (`promptFolderForNewSessionIfNeeded`) | low | План (п.2) требовал «не спрашивать повторно в рамках сессии, если юзер отклонил» (флаг сессии). Флага нет: при отказе от NSOpenPanel следующая новая сессия снова покажет модалку. Внутри одной сессии не повторяется, но между открытиями видео — да. Может раздражать тех, кто не пользуется автосейвом. | Добавить `sessionDeclinedFolderPrompt` флаг или спрашивать один раз за запуск приложения. |
| 6 | `ClipAutoSaveManager.swift:134-158` (очередь) | low | `pendingStampIDs`/`isSaving` мутируются без синхронизации — корректно только при вызове строго с main. Сейчас все вызовы с main (UI/`addStampToSelectedLine`), но контракт нигде не зафиксирован. | Добавить `assert(Thread.isMainThread)` или коммент-инвариант, чтобы будущий фоновый вызов не словил гонку. |

## Что проверено и ОК
- **Баг 1 (корень):** `selectedStampAndName()` → `selectedStampID` → fallback `lastAddedStampID` (`:380-389`) — верно. Инстант/интервал/мульти-карта все ставят `lastAddedStampID` и вызывают автосейв. Интервал автосейвится в точке завершения (`addStampToSelectedLine` вызывается из `proceedWithTagAdditionInterval:1621` с уже известным finish), спурий-сейвов «во время записи» нет.
- **«Сохранено» только при `.completed` И существующем файле** (`:216`, `:357`) — да; иначе error-тост + `print(status/error)`, ошибки не глотаются.
- **Security-scoped доступ** сбалансирован: `resolveFolderURL` открывает, `exportClip`/`refreshFolderState`/fail-пути закрывают ровно один раз (`didStopFolderAccess` guard). Утечек scope не нашёл.
- **Screen-space тост** (`ClipSaveToastPresenter`): borderless `.nonactivatingPanel`, `.statusBar`, `ignoresMouseEvents=true`, правый нижний угол `visibleFrame`, экран = `keyWindow?.screen ?? NSScreen.main` (норм для мультимонитора). Панель переиспользуется (не течёт), `hideTask` корректно отменяется перед новым показом, автоскрытие 2.5с. Модалок нет. `show(_:)` потокобезопасен.
- **Merged-экспорт:** сборка `AVMutableComposition` (видео+аудио), сортировка по времени, `insertTimeRange` последовательно, `preferredTransform` перенесён, `guard !isSaving`, info-тост прогресса, ошибки не глотаются.
- **Локализация:** все 14 использованных `clipAutoSave*`-ключей есть в enum и во ВСЕХ 7 локалях, первая буква заглавная, `%@` присутствует в обоих format-ключах во всех языках, дублей среди новых ключей нет, `plutil` чистый. `zh-Hant` реально подключён (pbxproj `knownRegions` + resources build phase), не мёртвый груз.

## Соответствие конвенциям
- [[../knowledge/conventions/code-style]] — да. Синглтоны через `.shared`, стиль/комментарии в духе проекта, новый `.swift` подхватился без правки pbxproj.
- [[../knowledge/conventions/localization]] — да (см. выше).

## Объём / посторонние изменения
Дифф ветки огромен и содержит много кода НЕ из TASK-001 (переработка merge-timelines в `TimelineDataManager`, `MarkupWindowLayoutStore`/lock-окна и `showMultiFieldMapSelection` в `WindowsManager`, ключи MergeProjects/HeatMap/ClubLogo/ImageEditor/KeyBindings в `.strings` и т.д.) — это накопленный in-flight код других задач ветки, не мусор данного developer'а. В рамках TASK-001 лишнего рефакторинга нет.

## Вердикт
**changes-requested.** Ядро бага 1 починено корректно, сборка и локализация чистые, тост и security-scoped сделаны аккуратно. Но до мержа нужно закрыть:
1. **(med) #1** — заглушить error-тосты авто-сейва (шум на нулевых/битых диапазонах); ошибки только для явного Cmd+S.
2. **(med) #4** — п.4 (Opt+Cmd+S) построен на неподтверждённом источнике `stampsSelectedForSportCut` — это блокер самой задачи; не отдавать в релиз без ответа продукта.
3. **(med) #2** — коллизия имён файлов при мульти-карте (теряются экспорты / впустую работа).
4. **(low-med) #3** — Cmd+S мимо очереди даёт наложение экспортов.
5. **(low) #5,#6** — флаг «не спрашивать папку повторно» и фиксация main-thread-инварианта очереди.
</content>
</invoke>
