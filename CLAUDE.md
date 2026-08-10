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

**Verify a change compiles from the CLI** (use this after edits — do not rely on
SourceKit diagnostics, they are often spurious):

```bash
xcodebuild -workspace Youchip-Stat.xcworkspace -scheme Youchip-Stat -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet
```

Success = `** BUILD SUCCEEDED **`; read failures by grepping the output for `error:`.

> **Do NOT run the build yourself** — it is slow and token-heavy. The user builds and
> reports back whether it's OK. Write code carefully to compile; rely on the user's report
> (and treat SourceKit diagnostics as often-spurious, per the note above).

**Key build requirements:**
- macOS 12.0+ deployment target
- Xcode 13+
- OpenCV dylibs are embedded from `/OpenCv/` directory — these are pre-built and shouldn't be modified
- Code signing required for the embedded dylibs

## Knowledge Base (vault/)

Work **inline** — a single session, no subagent team (spawning agents is slow and
token-heavy for this project). Instead the repo carries a rich, file-based knowledge
base (an Obsidian vault) so one session can act fast with minimal re-exploration:
**read the relevant vault notes before non-trivial work, and keep them up to date.**

**Vault** — `vault/` (open as an Obsidian vault). See `vault/README.md`.
- `vault/knowledge/architecture.md` — the codebase map: entry point, patterns, the
  singletons/managers index, persistence, inter-module communication. Read this first.
- `vault/knowledge/modules/` — one note per module (key files, its managers, gotchas).
- `vault/knowledge/conventions/` — code style, localization.
- `vault/decisions/` — ADRs (why non-obvious decisions were made).
- `vault/tasks/` — lightweight task history (`backlog/` → `in-progress/` → `done/`).

**Loop:** read the module note + `architecture.md` → implement → build (`xcodebuild`,
above) → record any lasting, non-obvious lesson back into `vault/knowledge/`.

**History log (rule):** After finishing any task, **prepend** an entry to
`vault/HISTORY.md` (newest on top) with: date, task title, what was requested, what was
done, and how it was fixed (files/approach). One concise entry per task — this is the
running project history.

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
