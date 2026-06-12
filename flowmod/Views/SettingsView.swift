import SwiftUI

/// Main settings view with a clean tabbed interface
struct SettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    var permissionManager: PermissionManager

    /// Which profile the window is editing. nil = default ("All Mice").
    @State private var selectedProfileKey: String? = nil
    @State private var showRemoveConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Permission warning if needed
            if !permissionManager.hasAccessibilityPermission {
                permissionWarning
            }

            // Profile picker — only when per-mouse settings are enabled
            if settings.perMouseSettingsEnabled {
                profilePickerBar
            }

            // Tab content using native TabView
            TabView {
                behaviorTab { profile in
                    ScrollSettingsView(profile: profile)
                }
                .tabItem {
                    Label("Scroll", systemImage: "scroll")
                }

                behaviorTab { profile in
                    MouseButtonsView(profile: profile)
                }
                .tabItem {
                    Label("Buttons", systemImage: "computermouse")
                }

                behaviorTab { profile in
                    MiddleDragGesturesView(profile: profile, settings: settings)
                }
                .tabItem {
                    Label("Gestures", systemImage: "hand.draw")
                }

                GeneralSettingsView(settings: settings, deviceManager: deviceManager)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
            }
            .padding()
        }
        .frame(width: 500, height: settings.perMouseSettingsEnabled ? 482 : 440)
        .background(.regularMaterial)
        .onChange(of: settings.perMouseSettingsEnabled) { _, enabled in
            if !enabled { selectedProfileKey = nil }
        }
        .onChange(of: availableProfileKeys) { _, keys in
            // Selected mouse disappeared (disconnected with no profile, or
            // profile removed while disconnected) — fall back to defaults.
            if let key = selectedProfileKey, !keys.contains(key) {
                selectedProfileKey = nil
            }
        }
        .confirmationDialog(
            "Remove the custom settings for \(selectedDeviceName)?",
            isPresented: $showRemoveConfirmation
        ) {
            Button("Remove Customization", role: .destructive) {
                if let key = selectedProfileKey {
                    settings.removeProfile(forKey: key)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This mouse will go back to following the default settings.")
        }
    }

    // MARK: - Profile Selection

    /// Connected external mice, de-duplicated by profile key.
    private var connectedMice: [DeviceManager.HIDDevice] {
        var seen = Set<String>()
        return deviceManager.connectedDevices.filter { device in
            guard device.isMouse && !device.isAppleDevice else { return false }
            return seen.insert(device.deviceKey).inserted
        }
    }

    /// Saved profiles for mice that aren't currently connected.
    private var disconnectedProfileKeys: [String] {
        let connectedKeys = Set(connectedMice.map { $0.deviceKey })
        return settings.mouseProfiles.keys
            .filter { !connectedKeys.contains($0) }
            .sorted { profileName(forKey: $0) < profileName(forKey: $1) }
    }

    /// Every key currently offered by the picker.
    private var availableProfileKeys: Set<String> {
        Set(connectedMice.map { $0.deviceKey }).union(settings.mouseProfiles.keys)
    }

    /// The profile for the current selection, or nil when the selected mouse
    /// hasn't been customized yet.
    private var selectedProfile: ProfileSettings? {
        guard let key = selectedProfileKey else { return settings.defaultProfile }
        return settings.mouseProfiles[key]
    }

    private func profileName(forKey key: String) -> String {
        if let device = connectedMice.first(where: { $0.deviceKey == key }) {
            return device.displayName
        }
        let name = settings.mouseProfiles[key]?.displayName ?? ""
        return name.isEmpty ? "Mouse" : name
    }

    private var selectedDeviceName: String {
        guard let key = selectedProfileKey else { return "All Mice" }
        return profileName(forKey: key)
    }

    private var profilePickerBar: some View {
        HStack(spacing: 8) {
            Text("Configuring:")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("", selection: $selectedProfileKey) {
                Text("All Mice (Default)").tag(String?.none)

                ForEach(connectedMice, id: \.deviceKey) { device in
                    Text(pickerLabel(name: device.displayName, key: device.deviceKey))
                        .tag(Optional(device.deviceKey))
                }

                if !disconnectedProfileKeys.isEmpty {
                    Section("Not Connected") {
                        ForEach(disconnectedProfileKeys, id: \.self) { key in
                            Text(pickerLabel(name: profileName(forKey: key), key: key))
                                .tag(Optional(key))
                        }
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)

            Spacer()

            if selectedProfileKey != nil && selectedProfile != nil {
                Button("Reset to Default…") {
                    showRemoveConfirmation = true
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    /// Mark customized mice so the picker shows which mice have their own settings.
    private func pickerLabel(name: String, key: String) -> String {
        settings.mouseProfiles[key] != nil ? "\(name) ✓" : name
    }

    // MARK: - Tab Content Gating

    /// Show the editor bound to the right profile, or — when the selected
    /// mouse has no profile yet — a prompt to create one.
    @ViewBuilder
    private func behaviorTab<Content: View>(@ViewBuilder content: (ProfileSettings) -> Content) -> some View {
        if let profile = selectedProfile {
            content(profile)
        } else {
            customizePrompt
        }
    }

    private var customizePrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "computermouse")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("\(selectedDeviceName) uses the default settings")
                .font(.headline)

            Text("Give this mouse its own scroll, button, and gesture settings. It starts with a copy of your current defaults.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button("Customize This Mouse") {
                customizeSelectedMouse()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func customizeSelectedMouse() {
        guard let key = selectedProfileKey else { return }
        settings.createProfile(forKey: key, displayName: profileName(forKey: key))
    }

    // MARK: - Permission Warning

    private var permissionWarning: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text("Accessibility permission required")
                .font(.callout)

            Spacer()

            Button("Grant Access") {
                permissionManager.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
    }
}

#Preview {
    SettingsView(
        settings: Settings.shared,
        deviceManager: DeviceManager.shared,
        permissionManager: PermissionManager.shared
    )
}
