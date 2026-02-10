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
            Image(nsImage: Self.menuBarImage(active: isActive))
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
            }
        }
    }

    // MARK: - Menu Bar Icon Builder

    /// Creates a template NSImage for the menu bar icon.
    /// When inactive, draws a diagonal slash across the mouse symbol.
    static func menuBarImage(active: Bool) -> NSImage {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let base = NSImage(systemSymbolName: "computermouse.fill",
                                 accessibilityDescription: "FlowMod")?
                .withSymbolConfiguration(symbolConfig) else {
            return NSImage()
        }

        if active {
            let img = base.copy() as! NSImage
            img.isTemplate = true
            return img
        }

        // Draw the base icon in gray with a red diagonal slash overlay
        let size = base.size
        let result = NSImage(size: size, flipped: false) { rect in
            // Mouse icon uses labelColor — adapts to light/dark menu bar
            NSColor.labelColor.set()
            base.draw(in: rect)

            // Diagonal slash in red — high contrast, reads as "stopped/disabled"
            let path = NSBezierPath()
            let inset: CGFloat = 1.5
            path.move(to: NSPoint(x: rect.maxX - inset, y: rect.maxY - inset))
            path.line(to: NSPoint(x: rect.minX + inset, y: rect.minY + inset))
            path.lineWidth = 2.0
            path.lineCapStyle = .round
            NSColor.systemRed.setStroke()
            path.stroke()

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
