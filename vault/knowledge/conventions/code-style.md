# Стиль кода и паттерны проекта

## Общее
- macOS SwiftUI, **MVVM + Combine**, Redux-style разделение action/state.
- Пиши код в стиле окружающих файлов: та же плотность комментариев, именование, идиомы.
- Deployment target: macOS 12.0+. Xcode 13+. Зависимости — CocoaPods (открывать
  `.xcworkspace`, не `.xcodeproj`).

## Паттерн ViewModel (обязательный)
```swift
@Published var state = SomeState()                      // наблюдаемое состояние
let action = PassthroughSubject<SomeActions, Never>()   // входные действия
// действия обрабатываются в handleAction(_:), который мутирует state
```

## Коммуникация между модулями
- **Combine / PassthroughSubject** — роутинг действий ViewModel.
- **NotificationCenter** — меню-команды и кросс-оконные события; типизированные
  нотификации см. `NSNotification + Convenience.swift`.
- **@EnvironmentObject** — вниз по дереву SwiftUI (напр. `AuthManager`).

## Ключевые синглтоны
`WindowsManager.shared`, `TimelineDataManager.shared`, `VideoFilesManager.shared`, `AuthManager`.

## Xcode synced folders (важно)
- Новый `.swift`-файл подхватывается автоматически — **править `.pbxproj` не нужно**.
- Диагностика SourceKit часто ложная — доверяй `xcodebuild`, а не «красноте» в редакторе.

## OpenCV
- Dylib в `/OpenCv/` предсобраны — не менять. Требуется code signing встроенных dylib.

## Связи
[[localization]] · [[../modules/_index]]
