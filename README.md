<p align="center">
  <img src="flowmod/Assets.xcassets/AppIcon.appiconset/FlowMod_icon_512.png" width="128" height="128" alt="FlowMod app icon">
</p>

<h1 align="center">FlowMod</h1>

<p align="center">
  A lightweight macOS menu bar app that makes non-Apple mice feel right at home.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square" alt="Requires macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-5-F05138?style=flat-square&amp;logo=swift&amp;logoColor=white" alt="Built with Swift 5">
  <img src="https://img.shields.io/badge/UI-SwiftUI-007AFF?style=flat-square" alt="Built with SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License"></a>
</p>

<p align="center">
  <a href="https://github.com/sendmebits/flowmod/releases/latest"><img src="https://img.shields.io/github/v/release/sendmebits/flowmod?style=for-the-badge&amp;logo=apple&amp;logoColor=white&amp;label=Download&amp;color=2ea043" alt="Download the latest FlowMod release"></a>
</p>

<p align="center">
  <strong>Free and open source.</strong> No paywalls. No ads. No tracking.
</p>

---

**FlowMod** adds the mouse features macOS leaves out: smooth scrolling, independent scroll direction, button remapping, and trackpad-style gestures. Settings can apply to every mouse or be customized per device—without changing how your trackpad behaves.

## Features

### Native-feeling scrolling

- **Smooth scrolling** — physics-based momentum that feels like a trackpad
- **Independent scroll direction** — use natural scrolling on a mouse without changing your trackpad
- **Scroll modifiers** — hold a key while scrolling to change its behavior:

| Hold | Action |
| :--- | :--- |
| ⇧ Shift | Horizontal scroll |
| ⌥ Option | Precision (also bypasses smoothing for immediate ticks) |
| ⌃ Control | Fast scroll |
| ⌘ Command | Zoom |

### More useful buttons

Map extra mouse buttons to Mission Control, copy and paste, back and forward, or any custom keyboard shortcut.

### Trackpad-style gestures

Hold the middle mouse button and drag to trigger an action. Each direction is configurable in Settings.

| Drag | Default action |
| :--- | :--- |
| **Up** | Mission Control |
| **Down** | App Exposé |
| **Left** | Space right |
| **Right** | Space left |

Horizontal drags follow trackpad swipe direction, so the content moves with your gesture.

- **Continuous gestures off** — assign any supported action to each direction, including Show Desktop or Launchpad.
- **Continuous gestures on** — system animations follow your drag like a three-finger trackpad swipe. Mission Control, App Exposé, and Spaces use fixed mappings while this option is enabled.

> [!NOTE]
> Continuous gestures use reverse-engineered DockSwipe events.

### A profile for every mouse

Turn on **Separate Settings Per Mouse** in the General tab to give each mouse its own scrolling, button, and gesture settings—handy for work and home mice or devices with different button layouts.

Each new profile starts with your defaults. Uncustomized mice continue to follow those defaults, and two connected mice can use different settings at the same time.

## Install

FlowMod requires **macOS 14 Sonoma or later**.

1. Download `flowmod.zip` from the [latest release](https://github.com/sendmebits/flowmod/releases/latest).
2. Unzip it and move **FlowMod** to your Applications folder.
3. Open FlowMod and grant access under **System Settings → Privacy & Security → Accessibility**.
4. If the permission is not recognized immediately, quit and reopen FlowMod.

> [!IMPORTANT]
> Accessibility permission lets FlowMod intercept mouse events and perform the actions you assign. FlowMod does not remap physical keyboard input.

## License

FlowMod is available under the [MIT License](LICENSE).

---

<p align="center"><em>Built because macOS treats non-Apple input devices as second-class citizens.</em></p>
