# FlowMod – Agent Instructions

This file guides AI agents (Cursor, Copilot, etc.) working on the FlowMod codebase. 

---

## Project at a Glance

- **What it is:** macOS menu bar app that customizes external mouse and keyboard via low-level HID/CGEvent interception.
- **Stack:** Swift, SwiftUI, AppKit, IOKit, CGEvent.
- **Layout:** `flowmod/` is the main app target; Xcode project at `flowmod.xcodeproj/`.


---

## Conventions to Follow

- **Managers:** Singletons with `static let shared` and `@MainActor` where appropriate.
- **State:** Swift `@Observable` (not Combine) for reactive state.
- **Persistence:** UserDefaults; complex types via JSON (see `Settings.swift`).
- **UI:** SwiftUI; use `@Bindable` for settings; tabbed settings in `SettingsView`.
- **Thread safety:** Event tap runs on a background thread; use `onMain()` when reading `@MainActor` state (e.g. settings) from the tap callback.

---

## Key Paths

| Purpose              | Path |
|----------------------|------|
| App entry & menu bar | `flowmod/FlowModApp.swift` |
| Event tap & mapping  | `flowmod/Managers/InputInterceptor.swift` |
| HID device detection | `flowmod/Managers/DeviceManager.swift` |
| Settings model       | `flowmod/Models/Settings.swift` |
| Key/combo models     | `flowmod/Models/KeyCombo.swift`, `flowmod/Models/KeyboardMapping.swift` |
| Settings UI          | `flowmod/Views/SettingsView.swift` |

---

## Build & Test

From repo root:

```bash
xcodebuild -scheme flowmod -configuration Debug build
open build/Debug/flowmod.app
```

Requires macOS, Xcode, and Accessibility permission (app runs with sandbox disabled for input interception).

---

