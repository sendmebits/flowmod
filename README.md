<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-black?style=flat-square" />
  <img src="https://img.shields.io/badge/swift-6-F05138?style=flat-square&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-007AFF?style=flat-square" />
</p>

# FlowMod

A macOS menu bar app that makes external mice actually feel good on a Mac.

<p align="center">
  <a href="https://github.com/sendmebits/flowmod/releases/latest/download/flowmod.zip">
    <img src="https://img.shields.io/badge/Download-FlowMod%20(latest)-2ea043?style=for-the-badge&logo=apple&logoColor=white" alt="Download FlowMod" />
  </a>
</p>

FlowMod intercepts input events at a low level (CGEvent taps + IOKit HID) to add features that macOS doesn't provide for non-Apple mouse peripherals — smooth scrolling, natural scroll direction per-device, button remapping, and trackpad-style gestures from a mouse.

---

### 🖱 Scroll

- **Smooth scrolling** — physics-based momentum that feels like a trackpad
- **Reverse scroll** — natural scrolling for your mouse without affecting the trackpad
- **Modifier keys** — hold ⇧ for horizontal scroll, ⌥ for precision, ⌃ for fast, ⌘ for zoom

### 🔘 Buttons

- Remap any extra mouse button to actions like Mission Control, copy/paste, back/forward, or a custom shortcut

### ✋ Gestures

- Middle-click drag in any direction to trigger macOS gestures:
  - **Up** → Mission Control
  - **Down** → App Exposé
  - **Left/Right** → Switch Spaces
  - **Pinch in/out** → Show Desktop / Launchpad
- **Continuous mode** — gestures follow your drag like a real trackpad swipe (via reverse-engineered DockSwipe events)

### ⌨️ Shortcuts

- Mouse buttons and gestures can trigger standard shortcuts like copy/paste, back/forward, and fullscreen
- Record a custom shortcut and attach it to a mouse button or gesture

### ⚙️ General

- Launch at login
- Auto-update support

---

### Requirements

- macOS 14+
- Accessibility permission (required for event interception)

---

<sub>Built because macOS treats non-Apple input devices as second-class citizens.</sub>
