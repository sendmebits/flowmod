import SwiftUI

/// Main settings view with a clean tabbed interface
struct SettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    var permissionManager: PermissionManager

    private enum Tab: Hashable {
        case scroll, buttons, gestures, general
    }

    /// Which profile the window is editing. nil = default ("All Mice").
    @State private var selectedProfileKey: String? = nil
    @State private var showRemoveConfirmation = false
    @State private var selectedTab: Tab = .scroll

    /// The mouse scope bar is only relevant on the per-mouse behavior tabs.
    private var showsScopeBar: Bool {
        settings.perMouseSettingsEnabled && selectedTab != .general
    }

    var body: some View {
        VStack(spacing: 0) {
            // Permission warning if needed
            if !permissionManager.hasAccessibilityPermission {
                permissionWarning
            }

            // Mouse scope bar — Finder-style filter under the toolbar,
            // shown only on the tabs it applies to
            if showsScopeBar {
                profileScopeBar
            }

            // Tab content using native TabView
            TabView(selection: $selectedTab) {
                behaviorTab { profile in
                    ScrollSettingsView(profile: profile)
                }
                .tabItem {
                    Label("Scroll", systemImage: "scroll")
                }
                .tag(Tab.scroll)

                behaviorTab { profile in
                    MouseButtonsView(profile: profile)
                }
                .tabItem {
                    Label("Buttons", systemImage: "computermouse")
                }
                .tag(Tab.buttons)

                behaviorTab { profile in
                    MiddleDragGesturesView(profile: profile, settings: settings)
                }
                .tabItem {
                    Label("Gestures", systemImage: "hand.draw")
                }
                .tag(Tab.gestures)

                GeneralSettingsView(settings: settings, deviceManager: deviceManager)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
                    .tag(Tab.general)
            }
            .padding()
        }
        .frame(width: 500, height: showsScopeBar ? 478 : 440)
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

    /// One selectable mouse in the scope bar (connected mice first, then
    /// saved profiles for disconnected mice).
    private struct ScopeEntry: Identifiable {
        let key: String
        let name: String
        let connected: Bool
        var id: String { key }
    }

    private var scopeEntries: [ScopeEntry] {
        let connected = connectedMice.map {
            ScopeEntry(key: $0.deviceKey, name: $0.displayName, connected: true)
        }
        let disconnected = disconnectedProfileKeys.map {
            ScopeEntry(key: $0, name: profileName(forKey: $0), connected: false)
        }
        return connected + disconnected
    }

    /// Finder-style scope bar: a centered segmented control selecting which
    /// mouse is being configured, with a trailing reset menu for customized
    /// mice. Falls back to a dropdown when there are too many mice for
    /// segments to stay readable.
    private var profileScopeBar: some View {
        HStack {
            Spacer(minLength: 40)
            scopePicker
            Spacer(minLength: 40)
        }
        .overlay(alignment: .trailing) {
            if selectedProfileKey != nil && selectedProfile != nil {
                Menu {
                    Button("Reset \(selectedDeviceName) to Default…", role: .destructive) {
                        showRemoveConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.trailing, 14)
                .help("Profile options")
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var scopePicker: some View {
        let entries = scopeEntries
        if entries.count <= 3 {
            Picker("", selection: $selectedProfileKey) {
                Text("All Mice").tag(String?.none)
                ForEach(entries) { entry in
                    Text(entry.name).tag(Optional(entry.key))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        } else {
            // Too many mice for segments — compact centered dropdown
            Picker("", selection: $selectedProfileKey) {
                Text("All Mice").tag(String?.none)
                ForEach(entries.filter { $0.connected }) { entry in
                    Text(entry.name).tag(Optional(entry.key))
                }
                if entries.contains(where: { !$0.connected }) {
                    Section("Not Connected") {
                        ForEach(entries.filter { !$0.connected }) { entry in
                            Text(entry.name).tag(Optional(entry.key))
                        }
                    }
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: - Tab Content Gating

    /// Show the editor bound to the right profile. When the selected mouse
    /// has no profile yet, show the default settings it currently follows —
    /// dimmed and read-only — under a banner offering to customize. The
    /// preview doubles as documentation: those values are exactly what the
    /// new profile starts with.
    @ViewBuilder
    private func behaviorTab<Content: View>(@ViewBuilder content: (ProfileSettings) -> Content) -> some View {
        if let profile = selectedProfile {
            content(profile)
        } else {
            VStack(spacing: 10) {
                customizeBanner

                content(settings.defaultProfile)
                    .disabled(true)
                    .opacity(0.5)
            }
        }
    }

    private var customizeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "computermouse")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(selectedDeviceName) is following the default settings")
                    .font(.callout)
                    .fontWeight(.medium)
                Text("Customize to give it its own settings, starting from a copy of these.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Customize") {
                customizeSelectedMouse()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.08))
        )
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
                permissionManager.requestPermission()
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
