//
//  minputApp.swift
//  minput
//
//  Created by Chris Greco on 2026-01-31.
//

import SwiftUI
import AppKit

@main
struct minputApp: App {
    @State private var settings = Settings.shared
    @State private var deviceManager = DeviceManager.shared
    @State private var permissionManager = PermissionManager.shared
    @State private var inputInterceptor = InputInterceptor.shared
    
    @State private var showOnboarding = false
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
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
            Image(systemName: "computermouse.fill")
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
}

// MARK: - Menu Bar Content View

struct MenuBarContent: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    var permissionManager: PermissionManager
    var inputInterceptor: InputInterceptor
    
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        // Status section
        VStack(alignment: .leading, spacing: 4) {
            if inputInterceptor.isRunning {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Inactive", systemImage: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        
        Divider()
        
        // Quick toggles
        Toggle("Reverse Scroll", isOn: $settings.reverseScrollEnabled)
        
        Divider()
        
        // Settings
        Button("Settings...") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        
        Divider()
        
        // Start/Stop
        if inputInterceptor.isRunning {
            Button("Pause minput") {
                inputInterceptor.stop()
            }
        } else {
            Button("Start minput") {
                startInterceptor()
            }
        }
        
        Divider()
        
        Button("Quit minput") {
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
