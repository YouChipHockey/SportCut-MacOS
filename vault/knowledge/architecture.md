# Карта архитектуры YouChip-Stat

macOS SwiftUI приложение для спортивного видео-анализа. CocoaPods (открывать
`.xcworkspace`). Паттерн: **MVVM + Combine**, Redux-style разделение action/state.
Deployment target macOS 12.0+, Xcode 13+. OpenCV dylib в `/OpenCv/` (предсобраны, не трогать).

## Точка входа
- `Youchip_StatApp.swift` — init Firebase, проверка auth/лицензии через `AuthManager`,
  затем `ContentView`.
- Две вкладки: **Разметка** → `VideosView` (библиотека, тегирование) ·
  **Просмотр** → `SportCutListView` (плейлист клипов, анализ).
- Термины (не путать): **SportCut = просмотр, VideoPlayer = разметка.**

## Паттерн ViewModel (обязательный)
```swift
@Published var state = SomeState()                      // наблюдаемое состояние
let action = PassthroughSubject<SomeActions, Never>()   // входные действия
// обрабатываются в handleAction(_:), который мутирует state → SwiftUI ре-рендер
```

## Мультиоконность
`WindowsManager.shared` — центральный координатор 12+ типов окон (VideoPlayer, FullControl,
TagLibrary, Analytics, MirroredVideo*, SportCut, ReviewVideo…). Вторичные окна —
подклассы `NSWindowController`. Весь жизненный цикл окон идёт через `WindowsManager`.

## Связь между модулями
- **Combine / PassthroughSubject** — роутинг действий ViewModel.
- **NotificationCenter** — меню-команды и кросс-оконные события; типизированные имена
  см. `NSNotification + Convenience.swift`.
- **@EnvironmentObject** — вниз по дереву SwiftUI (напр. `AuthManager`).

## Персистентность
| Хранилище | Для чего |
|-----------|----------|
| `~/Documents/YouChip-Stat/` | Данные проектов, коллекции, поля |
| `~/Library/Application Support/YouChip-Stat-Backup/` | Автобэкап |
| UserDefaults | Настройки, инфо о лицензии |
| Keychain | Секреты (`KeychainHelper`) |
| Security-scoped bookmarks | Постоянный доступ к файлам между запусками |
`DataSyncManager.shared` синхронизирует Documents ↔ Application Support.

## Индекс синглтонов / менеджеров (`static let shared`)

### Common
- `DataSyncManager` — Documents ↔ Application Support.
- `VideoFilesManager` (`Common/Files/Helpers/`) — центральные файловые операции.
- `FileOpenHelper`, `VideoThumbnailManager`, `VideosPreviewManager` — файлы/превью.
- `CollectionsBackupManager`, `CollectionsBookmarksManager` — коллекции: бэкап и bookmarks.
- `InMemoryStorageManager`, `TimelineMigrationManager`, `OrphanedTimelinesManager`,
  `KeychainHelper`.

### VideoPlayer (разметка) — `Modules/VideoPlayer/Managers/`
- `WindowsManager` — все вторичные окна.
- `TimelineDataManager` — состояние штампов таймлайна (`selectedStampID`, `lastAddedStampID`,
  `stampsSelectedForSportCut`, `lines`; `addStampToSelectedLine`).
- `VideoPlayerManager` — плеер/текущее видео (`getCurrentVideoURL()`).
- `TagLibraryManager` — теги/коллекции (`findTagById`).
- `HotKeyManager` — регистрация хоткеев (Cmd+S, Opt+Cmd+S и т.д.).
- `KeyBindingRuntimeManager` — рантайм привязок клавиш к тегам/лейблам.
- `FocusStateManager` — фокус ввода (глушит хоткеи в текстовых полях).
- `ClipAutoSaveManager` + `ClipSaveToastPresenter` — автосохранение клипа тега в папку +
  screen-space тост (см. [[modules/VideoPlayer]] и [[../tasks/in-progress/TASK-001-clip-autosave-folder-fixes]]).
- `ClubLogoWatermarkManager` — водяной знак клуба.
- `LiveStreamManager`, `CameraLogger` — лайв-запись.
- `MarkupWindowLayoutStore` — блокировка/восстановление раскладки окон разметки.
- `ScreenshotsMetadataManager` — метаданные скриншотов разметки.
- `PlayFieldImageCache`, `TagLibraryFreeLayoutFitStore` — кэш/лейаут.
- `CanvasButtonClipboard`, `CollectionGroupClipboard` — copy/paste в редакторах.
- `VideoMarkupActivityBanner` — in-window тост «тег добавлен» (НЕ путать с ClipSaveToastPresenter).

### SportCut (просмотр)
- `SportCutSessionManager` — сессия просмотра/плейлиста.

### Videos
- `ProjectExportManager`, `ProjectMergeManager` — экспорт/слияние проектов.
- `VideoDownloadManager`, `DownloadsFolderPermissionManager` — загрузки.

### ImageEditor / ImagesEditor
- `ImageEditorProjectsManager`, `ImageEditorWindowManager` — новый таб «Редактор».

## Ключевые грабли (screen-space vs window, координаты)
- SwiftUI `.position` ломает `.local`-координаты жестов.
- Кэшируй `NSImage(data:)` — иначе лаги при перетаскивании.
- Heatmap: рассинхрон field-grid vs screen-space координат (см. [[modules/VideoPlayer]]).

## Связи
[[modules/_index]] · [[conventions/code-style]] · [[conventions/localization]]
