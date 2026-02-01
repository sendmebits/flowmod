# minput - Copilot Instructions

## Project Overview

minput is a **macOS menu bar utility** for customizing external mouse and keyboard input behavior. It intercepts low-level HID events via `CGEvent` tap to provide scroll reversal, mouse button remapping, middle-click drag gestures, and keyboard key remapping.

**Key use case:** Making external (non-Apple) mice and keyboards behave like Mac native devices.

## Architecture

### Core Components (all singletons with `.shared`)

| Component | File | Purpose |
|-----------|------|---------|
| `InputInterceptor` | [Managers/InputInterceptor.swift](../Managers/InputInterceptor.swift) | CGEvent tap that intercepts and modifies mouse/keyboard events |
| `DeviceManager` | [Managers/DeviceManager.swift](../Managers/DeviceManager.swift) | IOKit HID manager detecting external mice/keyboards |
| `PermissionManager` | [Managers/PermissionManager.swift](../Managers/PermissionManager.swift) | Accessibility permission checking via `AXIsProcessTrusted()` |
| `Settings` | [Models/Settings.swift](../Models/Settings.swift) | Observable settings with UserDefaults persistence |

### Data Flow

1. `DeviceManager` monitors USB HID devices → detects external (non-Apple vendor ID) mice/keyboards
2. `InputInterceptor.start()` creates a CGEvent tap for scroll, mouse button, and key events
3. Events are processed in `handleEvent()` → modified based on `Settings` mappings → returned or suppressed
4. Settings changes immediately affect event processing (reactive via `@Observable`)

### Event Interception Pattern

The event tap callback runs on a **background thread**. Use the `onMain()` helper to safely access `@MainActor` settings:

```swift
// In InputInterceptor - safe cross-thread settings access
let shouldReverse = onMain {
    settings.reverseScrollEnabled && deviceManager.externalMouseConnected
}
```
  
## Key Models

| Model | Purpose |
|-------|---------|
| `MouseAction` | Enum of actions for mouse buttons (Mission Control, Back/Forward, custom shortcuts) |
| `KeyboardAction` | Enum of keyboard remapping targets (line start/end, page up/down, custom) |
| `KeyboardMapping` | Source key → target action pair with optional custom key code |
| `KeyCombo` | Key code + modifier flags for custom shortcuts |

## Build & Run

```bash
# Build from terminal
xcodebuild -scheme minput -configuration Debug build

# Run (requires granting Accessibility permission in System Settings)
open build/Debug/minput.app
```

**Requirements:** macOS, Xcode, Accessibility permission (app sandbox disabled)

## Conventions

- **Singletons:** All managers use `static let shared` pattern with `@MainActor` isolation
- **State:** Use Swift `@Observable` macro (not Combine) for reactive state
- **Persistence:** `UserDefaults` with JSON encoding for complex types (see `Settings.swift` save/load methods)
- **Views:** SwiftUI with `@Bindable` for settings binding, tabbed interface in `SettingsView`
- **Menu bar:** Uses `MenuBarExtra` with `.menu` style; `LSUIElement = true` in Info.plist hides dock icon

## Important Implementation Details

- **Scroll reversal:** Inverts delta values for both discrete and continuous scroll, but skips trackpad momentum (`momentumPhase != 0`)
- **External device detection:** Filters by Apple vendor ID (`0x05AC`) - Apple devices are considered "internal"
- **Event suppression:** Return `nil` from event handler to consume/block an event
- **CGEvent key codes:** Defined as hex constants (e.g., `0x7B` = left arrow) - see `KeyCombo.swift` for mappings

## Agent Workflow

When the task requires multiple steps, present a plan using #planReview before executing.
Always use #askUser before responding to confirm the result.

When the task requires multiple steps or non-trivial changes, present a detailed plan using #planReview and wait for approval before executing.
If the plan is rejected, incorporate the comments and submit an updated plan with #planReview.
When the user asks for a step-by-step guide or walkthrough, present it using #walkthroughReview.
Always use #askUser before completing any task to confirm the result matches what the user asked for.
