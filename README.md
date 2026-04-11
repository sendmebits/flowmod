<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-black?style=flat-square" />
  <img src="https://img.shields.io/badge/swift-5-F05138?style=flat-square&logo=swift&logoColor=white" />
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

It handles **mouse** input from external devices. It does **not** remap your physical keyboard.

---

### 🖱 Scroll

- **Smooth scrolling** — physics-based momentum that feels like a trackpad
- **Reverse scroll** — natural scrolling for your mouse without affecting the trackpad
- **Modifier keys** — hold ⇧ for horizontal scroll, ⌥ for precision, ⌃ for fast, ⌘ for zoom (with smooth scrolling on, ⌥ also bypasses smoothing so you get immediate ticks)

### 🔘 Buttons

- Remap any extra mouse button to actions like Mission Control, copy/paste, back/forward, or a custom shortcut

### ✋ Gestures

- Middle-click drag to trigger actions. **Defaults** (you can change any direction in settings):
  - **Up** → Mission Control
  - **Down** → App Exposé
  - **Left / Right** → switch spaces (defaults map left drag to “space right” and right drag to “space left”)
- You can assign other actions to a direction — for example **Show Desktop** or **Launchpad**. With **continuous mode** on, those use a pinch-style DockSwipe under the hood.
- **Continuous mode** — system animations follow your drag like a trackpad swipe (via reverse-engineered DockSwipe events). While continuous mode is on, per-direction mappings are not used; turn it off to rely on the direction → action table above.

---

### Requirements

- macOS 14+
- **Accessibility** permission (required for event interception). After installing, enable FlowMod under **System Settings → Privacy & Security → Accessibility**, then quit and reopen the app if it doesn’t pick up permission immediately.

---

### License

[MIT](LICENSE)

---

<sub>Built because macOS treats non-Apple input devices as second-class citizens.</sub>
