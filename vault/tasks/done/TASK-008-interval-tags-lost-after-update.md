# TASK-008 — Интервальные теги становятся обычными после обновления

Статус: **research, без правок кода** (2026-08-14)

## Симптом
После обновления приложения теги, отмеченные как интервальные, ведут себя и выглядят как обычные.

## Механика потери флага

`Tag.isInterval: Bool?` (VideoPlayerModels.swift:27), везде читается как `isInterval ?? false`.
Codable синтезированный → для nil ключ **не пишется** (`encodeIfPresent`). Отсюда цепочка:

> старые данные без ключа → декодируется nil → UI считает тег обычным → при следующей
> записи ключ не пишется → флаг потерян **на диске навсегда**.

Достаточно один раз прочитать коллекцию из устаревшего источника, чтобы флаг исчез необратимо.

## Где «правда» о коллекции (главный риск)

`InMemoryStorageManager` (Common/Managers):
- `loadCollection(id:)` — сперва блоб `collection_<id>` из **UserDefaults**, файлы только фолбэк.
- `saveCollectionsToDisk()` — перезаписывает **все** папки `Collections/<id>/*.json` из этих блобов
  и **удаляет** папки коллекций, для которых нет ключа в UserDefaults.
- Читатели: `TagLibraryManager.loadAllUserCollections` (:428), `CollectionIdRegenerator` (:42),
  `GroupDuplicationService` (:35), `CollectionsBookmarksManager` (:537).

Значит: любое изменение **файлов** мимо UserDefaults (restore из бэкапа, ручная подмена,
перенос с другой машины, запись старой сборкой) оставляет блоб устаревшим, и ближайший
`saveToDiskImmediate()` откатывает файлы к блобу.

Подтверждение на машине пользователя: все 5 `tags.json` имеют **одинаковый mtime**
`2026-08-14 12:42:26` — то есть сплошная перезапись всех коллекций реально происходит.

## Мина в DataSyncManager (запускается на каждом старте)

`AppSetupManager.setup()` → `DataSyncManager.synchronizeOnAppLaunch()`:
1. `hasBackupDataDifferences()` = `UserDefaultsBackup.plist.mtime > lastSyncDate`,
   где `lastSyncDate` = `UserDefaults["DataSync_LastSyncDate"] ?? .distantPast`.
   **На машине пользователя ключа `DataSync_LastSyncDate` НЕТ** → условие всегда истинно,
   как только появится `UserDefaultsBackup.plist`.
2. → `restoreFromBackup()` → `restoreCollections()`: **удаляет весь `Documents/.../Collections`**
   и копирует папку из бэкапа. Сравнения «что новее по содержимому» нет.
3. Бэкап на машине пользователя:
   `…/YouChip-Stat-Backup/YouChip-Stat/Collections` — **пустая папка от 16 февраля**
   (и `UserDefaultsBackup.plist` отсутствует, поэтому пока не срабатывает).

Т.е. при появлении бэкап-плиста с отсутствующим `lastSyncDate` коллекции заменяются
устаревшим (в пределе — пустым) снимком. Это ровно паттерн «после обновления всё откатилось».

## Что видно в данных пользователя

| Коллекция | тегов | isInterval=true |
|---|---|---|
| СМЕНЫ | 16 | 16 |
| Сезон 26 27 | 62 | 35 |
| Сезон 26 27 (1) | 58 | **11** |
| тест2 / тест2 (1) | 12 / 12 | 0 / 0 |

24 тега с **одинаковым `primaryID`** имеют `true` в «Сезон 26 27» и `false` в копии «(1)».
id полностью разведены (коллизий между коллекциями — 0), т.е. копия прошла через
`CollectionIdRegenerator`. Сам регенератор `isInterval` копирует честно (:155) —
значит **источник копии уже был устаревшим** (старый экспорт / старый блоб).

## Дополнительно

- Базовые (bundled) коллекции: `isInterval` нет **ни в одной** из 14 `tags(*).json` —
  любой тег, пересобранный из стандартной коллекции, интервальным быть не может.
- Синтетические теги в просмотре (`SportCutSessionManager.augmentedLibrary`) ставят
  `isInterval: true` — на разметку не влияет, но расхождение стоит помнить.

## Как подтвердить причину на конкретной машине (без правок)

1. `defaults read com.YouChip.YouChipSportCut DataSync_LastSyncDate` — есть ли ключ.
2. Есть ли `…/YouChip-Stat-Backup/UserDefaultsBackup.plist` и его дата.
3. Сравнить `collection_<id>` из UserDefaults с `Collections/<id>/tags.json` по числу
   `isInterval=true` — расхождение = блоб устарел (или наоборот).
4. Логи старта: `🔄 DataSync`, `⚠️ Differences found, restoring newer data from backup`.

## Сделано (2026-08-14, данные пользователя не трогали)

`DataSyncManager`:
- `hasBackupDataDifferences()` — отсутствие `DataSync_LastSyncDate` больше не означает
  «бэкап новее»: ставим отметку и возвращаем false.
- `restoreCollections/​restoreTimelines/​restorePlayFields` → общий `restoreMissingItems(from:to:label:)`:
  пустой бэкап пропускаем, живую папку не удаляем, копируем **только отсутствующие** элементы.
- `restoreCollectionsBackup()` — живой `CollectionsBookmarks.json` не заменяем.
- `restoreUserDefaults()` — `videosData`/`collectionsBookmarks` пишем только если ключа нет.

`InMemoryStorageManager`:
- `loadCollection(id:)` — сперва файлы, блоб `collection_<id>` только фолбэк (кэш).
- `saveCollection(_:)` — файл пишется сразу, а не по 30-секундному таймеру.
- `saveCollectionsToDisk()` — папку удаляем, только если коллекции нет ни в кэше, ни в
  `CollectionsBookmarks`; файлы пишем только там, где их ещё нет (файл авторитетнее кэша).
- `loadCollectionFromFile` — кэш обновляем, только если он разошёлся с файлами.

## Осталось (по желанию)

- `Tag.isInterval` всё ещё `Bool?`, и при nil ключ не пишется. Сделать не-Optional нельзя
  «в лоб» (синтезированный `init(from:)` бросит на старых JSON без ключа) — нужен ручной
  `Codable` со всеми ключами. Ценность после фиксов выше — в основном косметическая:
  источник устаревших данных устранён.

## Связи
[[../../knowledge/modules/Collections]] · [[../../knowledge/architecture]]
