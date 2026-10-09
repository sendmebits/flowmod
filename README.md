![FlowMod](assets/flowmod_banner.png)

<div align="center">

# FlowMod

A lightweight macOS menu bar app that makes non-Apple mice feel right at home.

![Requires macOS 14 or later](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square)
![Built with Swift 5](https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white)
![Built with SwiftUI](https://img.shields.io/badge/UI-SwiftUI-007AFF?style=flat-square)
[![MIT License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

[![Download the latest FlowMod release](https://img.shields.io/github/v/release/sendmebits/flowmod?style=for-the-badge&logo=apple&logoColor=white&label=Download&color=2ea043)](https://github.com/sendmebits/flowmod/releases/latest/download/FlowMod.dmg)

**Free and open source.** No paywalls. No ads. No tracking.

</div>

---

**FlowMod** adds the mouse features macOS leaves out: smooth scrolling, independent scroll direction, button remapping, and trackpad-style gestures. Use one set of settings for every mouse or customize each one. Your trackpad is never affected.

## Features

### Native-feeling scrolling

- **Smooth scrolling** — physics-based momentum that feels like a trackpad
- **Independent scroll direction** — natural scrolling on your mouse without changing your trackpad
- **Precise scrolling** — slower, finer control for small movements
- **Scroll modifiers** — hold a key while scrolling:

<div align="center">
<table align="center">
  <thead>
    <tr>
      <th align="left">Hold</th>
      <th align="left">Action</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="left">⇧ Shift</td>
      <td align="left">Horizontal scroll</td>
    </tr>
    <tr>
      <td align="left">⌥ Option</td>
      <td align="left">Precision scroll (immediate, unsmoothed ticks)</td>
    </tr>
    <tr>
      <td align="left">⌃ Control</td>
      <td align="left">Fast scroll</td>
    </tr>
    <tr>
      <td align="left">⌘ Command</td>
      <td align="left">Zoom</td>
    </tr>
  </tbody>
</table>
</div>

### More useful buttons

Map extra mouse buttons to Mission Control, App Exposé, Show Desktop, Launchpad, back and forward, copy, cut, paste, undo, redo, or any custom keyboard shortcut.

### Trackpad-style gestures

Hold the middle mouse button and drag:

<div align="center">
<table align="center">
  <thead>
    <tr>
      <th align="left">Drag</th>
      <th align="left">Default action</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="left"><strong>Up</strong></td>
      <td align="left">Mission Control</td>
    </tr>
    <tr>
      <td align="left"><strong>Down</strong></td>
      <td align="left">App Exposé</td>
    </tr>
    <tr>
      <td align="left"><strong>Left</strong></td>
      <td align="left">Space right</td>
    </tr>
    <tr>
      <td align="left"><strong>Right</strong></td>
      <td align="left">Space left</td>
    </tr>
  </tbody>
</table>
</div>

Left and right follow trackpad swipe direction, so content moves with your hand.

With **Continuous Gestures** on (the default), system animations follow your drag like a three-finger trackpad swipe. Turn it off to assign any action to each direction, including Show Desktop or Launchpad.

### Windows keyboards

Swap Option and Command on a USB or Bluetooth keyboard so those keys sit where they do on a Mac keyboard. FlowMod uses the same per-keyboard setting as **System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys**, so the swap stays in place even when FlowMod isn't running.

### A profile for every mouse

Turn on **Separate Settings for Each Mouse** in the General tab to give each mouse its own scroll, button, and gesture settings. New profiles start from your defaults, mice without a profile keep following them, and two connected mice can use different settings at the same time.

### Stays out of your way

- Lives in the menu bar with no Dock icon
- Optional launch at login
- Built-in updater checks for new releases and installs them in one click

## Install

FlowMod requires **macOS 14 Sonoma or later**.

1. Download [`FlowMod.dmg`](https://github.com/sendmebits/flowmod/releases/latest/download/FlowMod.dmg) from the latest release.
2. Open the disk image and drag **FlowMod** onto the Applications folder.
3. Open FlowMod. The setup assistant walks you through granting access under **System Settings → Privacy & Security → Accessibility**.
4. If the permission isn't recognized right away, use the **Relaunch** button or quit and reopen FlowMod.

If you open FlowMod from the disk image or Downloads instead, it offers to move itself into Applications first. Accessibility access is tied to the app's location, so this keeps the permission working.

## License

FlowMod is available under the [MIT License](LICENSE).

---

*Built because macOS treats non-Apple input devices as second-class citizens.*
