![FlowMod](assets/flowmod_banner.png)

<div align="center">

# FlowMod

A lightweight macOS app that makes non-Apple mice feel right at home.

![Requires macOS 14 or later](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square)
![Built with Swift 5](https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white)
![Built with SwiftUI](https://img.shields.io/badge/UI-SwiftUI-007AFF?style=flat-square)
[![MIT License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

[![Download the latest FlowMod release](https://img.shields.io/github/v/release/sendmebits/flowmod?style=for-the-badge&logo=apple&logoColor=white&label=Download&color=2ea043)](https://github.com/sendmebits/flowmod/releases/latest)

**Free and open source.** No paywalls. No ads. No tracking.

</div>

---

**FlowMod** adds the mouse features macOS leaves out: smooth scrolling, independent scroll direction, button remapping, and trackpad-style gestures. Settings can apply to every mouse or be customized per device—without changing how your trackpad behaves.

## Features

### Native-feeling scrolling

- **Smooth scrolling** — physics-based momentum that feels like a trackpad
- **Independent scroll direction** — use natural scrolling on a mouse without changing your trackpad
- **Scroll modifiers** — hold a key while scrolling to change its behavior:

<table>
  <thead>
    <tr>
      <th align="left">Hold</th>
      <th align="left">Action</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>⇧ Shift</td>
      <td>Horizontal scroll</td>
    </tr>
  </tbody>
  <tbody>
    <tr>
      <td>⌥ Option</td>
      <td>Precision (also bypasses smoothing for immediate ticks)</td>
    </tr>
  </tbody>
  <tbody>
    <tr>
      <td>⌃ Control</td>
      <td>Fast scroll</td>
    </tr>
  </tbody>
  <tbody>
    <tr>
      <td>⌘ Command</td>
      <td>Zoom</td>
    </tr>
  </tbody>
</table>

### More useful buttons

Map extra mouse buttons to Mission Control, copy and paste, back and forward, or any custom keyboard shortcut.

### Trackpad-style gestures

Hold the middle mouse button and drag to trigger an action. Each direction is configurable in Settings.

<table>
  <thead>
    <tr>
      <th align="left">Drag</th>
      <th align="left">Default action</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>Up</strong></td>
      <td>Mission Control</td>
    </tr>
  </tbody>
  <tbody>
    <tr>
      <td><strong>Down</strong></td>
      <td>App Exposé</td>
    </tr>
  </tbody>
  <tbody>
    <tr>
      <td><strong>Left</strong></td>
      <td>Space right</td>
    </tr>
  </tbody>
  <tbody>
    <tr>
      <td><strong>Right</strong></td>
      <td>Space left</td>
    </tr>
  </tbody>
</table>

Horizontal drags follow trackpad swipe direction, so the content moves with your gesture.

- **Continuous gestures off** — assign any supported action to each direction, including Show Desktop or Launchpad.
- **Continuous gestures on** — system animations follow your drag like a three-finger trackpad swipe. Mission Control, App Exposé, and Spaces use fixed mappings while this option is enabled.

### A profile for every mouse

Turn on **Separate Settings Per Mouse** in the General tab to give each mouse its own scrolling, button, and gesture settings—handy for work and home mice or devices with different button layouts.

Each new profile starts with your defaults. Uncustomized mice continue to follow those defaults, and two connected mice can use different settings at the same time.

## Install

FlowMod requires **macOS 14 Sonoma or later**.

1. Download `flowmod.zip` from the [latest release](https://github.com/sendmebits/flowmod/releases/latest).
2. Unzip it and move **FlowMod.app** to your Applications folder.
3. Open FlowMod and grant access under **System Settings → Privacy & Security → Accessibility**.
4. If the permission is not recognized immediately, quit and reopen FlowMod.

## License

FlowMod is available under the [MIT License](LICENSE).

---

*Built because macOS treats non-Apple input devices as second-class citizens.*
