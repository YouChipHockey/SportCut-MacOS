# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a macOS SwiftUI app managed with CocoaPods. Always open the **workspace**, not the project file.

```bash
# Install dependencies (first time or after Podfile changes)
pod install

# Open in Xcode
open Youchip-Stat.xcworkspace
```

Build and run from Xcode (Cmd+B / Cmd+R). There are no automated tests.

**Key build requirements:**
- macOS 12.0+ deployment target
- Xcode 13+
- OpenCV dylibs are embedded from `/OpenCv/` directory — these are pre-built and shouldn't be modified
- Code signing required for the embedded dylibs

## Architecture

**Pattern:** MVVM + Combine, with Redux-style action/state separation.

**Entry point:** `Youchip_StatApp.swift` — initializes Firebase, checks auth/license via `AuthManager`, then renders `ContentView`.

**Two main tabs:**
- **Markup tab** → `VideosView` (video library, annotation/tagging)
- **Viewing tab** → `SportCutListView` (clip playlist and analysis)

### Module Overview

| Module | Purpose |
|--------|---------|
| `Videos/` | Video library management, import/export |
| `VideoPlayer/` | Main markup editor, multi-window coordination (largest: ~97 files) |
| `SportCut/` | Clip extraction and playlist management |
| `Telestration/` | Drawing tools (arrows, zones, polygons) overlaid on video |
| `ImagesEditor/` | Screenshot/image editing |
| `License/` | License key validation, Firebase-backed auth |

### State Management Pattern

All ViewModels follow this pattern:
```swift
@Published var state = SomeState()                          // Observable state
let action = PassthroughSubject<SomeActions, Never>()       // Input actions

// Actions handled in handleAction(_ action: SomeActions)
// which mutates state, triggering SwiftUI re-renders
```

### Multi-Window Architecture

`WindowsManager.shared` is the central coordinator for 12+ distinct window types (VideoPlayer, FullControl, TagLibrary, Analytics, MirroredVideo variants, SportCut, ReviewVideo, etc.). Secondary windows use `NSWindowController` subclasses. All window lifecycle goes through `WindowsManager`.

### Key Singletons

- `WindowsManager.shared` — multi-window coordination
- `TimelineDataManager.shared` — timeline stamp state
- `VideoFilesManager.shared` — file operations
- `AuthManager` — passed as `@EnvironmentObject` from root

### Inter-Module Communication

- **Combine/PassthroughSubject** for ViewModel action routing
- **NotificationCenter** for menu commands and cross-window events (see `NSNotification + Convenience.swift` for typed notification extensions)
- **Environment objects** passed down the SwiftUI tree

### Persistence

| Storage | Used For |
|---------|---------|
| `~/Documents/YouChip-Stat/` | Project data, collections, play fields |
| `~/Library/Application Support/YouChip-Stat-Backup/` | Automatic backup |
| UserDefaults | Preferences, license info |
| Keychain | Sensitive credentials (`KeychainHelper.swift`) |
| Security-scoped bookmarks | Persistent file access across launches |

### Localization

String keys use a custom extension pattern: `^String.Titles.someKey`. Localizations are in `Resourses/` (intentional misspelling) covering: ru_RU, en, es, fr, uz, zh-Hans.

## Key Files

- `Youchip_StatApp.swift` — app entry, Firebase init, auth gate
- `Modules/VideoPlayer/Managers/WindowsManager.swift` — all secondary window management
- `Modules/VideoPlayer/ViewModel/VideoPlayerViewModel.swift` — main editor state
- `Common/Files/Helpers/VideoFilesManager.swift` — central file operations
- `Common/Managers/DataSyncManager.swift` — Documents ↔ Application Support sync
- `Modules/License/Managers/AuthManager.swift` — license validation
