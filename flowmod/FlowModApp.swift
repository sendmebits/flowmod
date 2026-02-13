//
//  FlowModApp.swift
//  FlowMod
//
//  Created by Chris Greco on 2026-01-31.
//

import SwiftUI
import AppKit

@main
struct FlowModApp: App {
    @State private var settings = Settings.shared
    @State private var deviceManager = DeviceManager.shared
    @State private var permissionManager = PermissionManager.shared
    @State private var inputInterceptor = InputInterceptor.shared
    @State private var updateManager = UpdateManager.shared
    
    var body: some Scene {
        // Menu bar item
        MenuBarExtra {
            MenuBarContent(
                settings: settings,
                deviceManager: deviceManager,
                permissionManager: permissionManager,
                inputInterceptor: inputInterceptor
            )
        } label: {
            let isActive = permissionManager.hasAccessibilityPermission
                && inputInterceptor.isRunning
                && (settings.mouseEnabled || settings.keyboardEnabled)
            Image(nsImage: Self.menuBarImage(active: isActive, updateAvailable: updateManager.updateAvailable))
        }
        .menuBarExtraStyle(.menu)
        
        // Settings scene - provides proper macOS settings window styling
        SwiftUI.Settings {
            SettingsView(
                settings: settings,
                deviceManager: deviceManager,
                permissionManager: permissionManager
            )
            .onAppear {
                // Make settings window float on top and bring to front
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    for window in NSApp.windows {
                        if window.title == "Settings" || window.identifier?.rawValue.contains("Settings") == true {
                            window.level = .floating
                            window.orderFrontRegardless()
                        }
                    }
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    init() {
        // Start the input interceptor on launch if we have permission
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in
                if PermissionManager.shared.hasAccessibilityPermission {
                    InputInterceptor.shared.start(
                        settings: Settings.shared,
                        deviceManager: DeviceManager.shared
                    )
                }
                // Check for updates on launch (respects auto-check setting and 24h interval)
                UpdateManager.shared.checkIfNeeded()
            }
        }
    }

    // MARK: - Menu Bar Icon Builder

    /// Creates a template NSImage for the menu bar icon.
    /// When inactive, draws a diagonal slash across the mouse symbol.
    /// When an update is available, draws a small upward-arrow badge.
    static func menuBarImage(active: Bool, updateAvailable: Bool = false) -> NSImage {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let base = NSImage(systemSymbolName: "computermouse.fill",
                                 accessibilityDescription: "FlowMod")?
                .withSymbolConfiguration(symbolConfig) else {
            return NSImage()
        }

        // If active with no update, return a plain template image
        if active && !updateAvailable {
            let img = base.copy() as! NSImage
            img.isTemplate = true
            return img
        }

        let size = base.size
        let result = NSImage(size: size, flipped: false) { rect in
            NSColor.labelColor.set()
            base.draw(in: rect)

            if !active {
                // Diagonal slash in red — high contrast, reads as "stopped/disabled"
                let slash = NSBezierPath()
                let inset: CGFloat = 1.5
                slash.move(to: NSPoint(x: rect.maxX - inset, y: rect.maxY - inset))
                slash.line(to: NSPoint(x: rect.minX + inset, y: rect.minY + inset))
                slash.lineWidth = 2.0
                slash.lineCapStyle = .round
                NSColor.systemRed.setStroke()
                slash.stroke()
            }

            if updateAvailable {
                // Draw a small green circle with an upward arrow in the bottom-right corner
                let badgeSize: CGFloat = 8.0
                let badgeX = rect.maxX - badgeSize + 1.0
                let badgeY = rect.minY - 1.0
                let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeSize, height: badgeSize)

                // Green circle background
                NSColor.systemGreen.setFill()
                let circle = NSBezierPath(ovalIn: badgeRect)
                circle.fill()

                // White upward arrow inside the badge
                let arrowCenterX = badgeRect.midX
                let arrowCenterY = badgeRect.midY
                let arrowHalfHeight: CGFloat = 2.5
                let arrowHalfWidth: CGFloat = 1.8

                let arrow = NSBezierPath()
                // Arrow tip (top center)
                arrow.move(to: NSPoint(x: arrowCenterX, y: arrowCenterY + arrowHalfHeight))
                // Left wing
                arrow.line(to: NSPoint(x: arrowCenterX - arrowHalfWidth, y: arrowCenterY))
                // Left side of shaft
                arrow.line(to: NSPoint(x: arrowCenterX - 0.6, y: arrowCenterY))
                // Shaft bottom left
                arrow.line(to: NSPoint(x: arrowCenterX - 0.6, y: arrowCenterY - arrowHalfHeight))
                // Shaft bottom right
                arrow.line(to: NSPoint(x: arrowCenterX + 0.6, y: arrowCenterY - arrowHalfHeight))
                // Right side of shaft
                arrow.line(to: NSPoint(x: arrowCenterX + 0.6, y: arrowCenterY))
                // Right wing
                arrow.line(to: NSPoint(x: arrowCenterX + arrowHalfWidth, y: arrowCenterY))
                arrow.close()

                NSColor.white.setFill()
                arrow.fill()
            }

            return true
        }
        result.isTemplate = false  // Use our explicit colors, not system tint
        return result
    }
}

// MARK: - Menu Bar Content View

struct MenuBarContent: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    var permissionManager: PermissionManager
    var inputInterceptor: InputInterceptor

    var body: some View {
        Toggle("Mouse", isOn: $settings.mouseEnabled)
        Toggle("Keyboard", isOn: $settings.keyboardEnabled)

        Divider()

        SettingsLink {
            Text("Settings...")
        }

        Divider()

        if inputInterceptor.isRunning {
            Button("Disable") {
                inputInterceptor.stop()
            }
        } else {
            Button("Enable") {
                startInterceptor()
            }
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func startInterceptor() {
        guard permissionManager.hasAccessibilityPermission else {
            permissionManager.requestPermission()
            return
        }

        Task { @MainActor in
            inputInterceptor.start(settings: settings, deviceManager: deviceManager)
        }
    }
}
