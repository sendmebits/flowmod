import SwiftUI

/// Tinted, full-width notice shown above the settings tabs when FlowMod
/// can't run (wrong install location, missing permission, startup error).
struct StatusBanner<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    private let actions: Actions

    init(
        icon: String,
        tint: Color,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            actions
                .controlSize(.small)
        }
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

/// First section of a behavior tab when the selected mouse is still following
/// All Mice settings. The rest of the tab shows those settings read-only.
struct CustomizeProfileBanner: View {
    let deviceName: String
    let onCustomize: () -> Void

    var body: some View {
        Section {
            LabeledContent {
                Button("Customize", action: onCustomize)
                    .buttonStyle(.borderedProminent)
            } label: {
                Text("\(deviceName) follows All Mice")
                Text("Customize to give it its own settings, starting from these.")
            }
        }
    }
}

/// Main settings view with a clean tabbed interface
struct SettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    var permissionManager: PermissionManager
    var inputInterceptor: InputInterceptor
    var keyboardManager: KeyboardManager

    private enum Tab: Hashable {
        case general, scroll, buttons, gestures, keyboard
    }

    /// Which profile the window is editing. nil = default ("All Mice").
    @State private var selectedProfileKey: String? = nil
    @State private var showRemoveConfirmation = false
    @State private var selectedTab: Tab = .general

    private static let windowSize = CGSize(width: 560, height: 580)

    /// The mouse scope bar is only relevant on the per-mouse behavior tabs.
    private var showsScopeBar: Bool {
        settings.perMouseSettingsEnabled && selectedTab != .general && selectedTab != .keyboard
    }

    var body: some View {
        VStack(spacing: 0) {
            if InstallLocation.needsRelocation {
                relocationWarning
            } else if !permissionManager.hasAccessibilityPermission && !inputInterceptor.isRunning {
                permissionWarning
            } else if let startupError = inputInterceptor.startupError {
                interceptorWarning(startupError)
            } else if !inputInterceptor.isRunning {
                disabledNotice
            }

            // Mouse scope bar — Finder-style filter under the toolbar,
            // shown only on the tabs it applies to
            if showsScopeBar {
                profileScopeBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            TabView(selection: $selectedTab) {
                GeneralSettingsView(settings: settings, deviceManager: deviceManager)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
                    .tag(Tab.general)

                behaviorTab { profile, preview in
                    ScrollSettingsView(profile: profile, preview: preview)
                }
                .tabItem {
                    Label("Scroll", systemImage: "scroll")
                }
                .tag(Tab.scroll)

                behaviorTab { profile, preview in
                    MouseButtonsView(profile: profile, preview: preview)
                }
                .tabItem {
                    Label("Buttons", systemImage: "computermouse")
                }
                .tag(Tab.buttons)

                behaviorTab { profile, preview in
                    MiddleDragGesturesView(profile: profile, settings: settings, preview: preview)
                }
                .tabItem {
                    Label("Gestures", systemImage: "hand.draw")
                }
                .tag(Tab.gestures)

                KeyboardSettingsView(keyboardManager: keyboardManager)
                    .tabItem {
                        Label("Keyboard", systemImage: "keyboard")
                    }
                    .tag(Tab.keyboard)
            }
        }
        // Keep a stable System Settings-style window; each tab's form scrolls on overflow.
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .animation(.default, value: showsScopeBar)
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
            "Reset \(selectedDeviceName) to All Mice?",
            isPresented: $showRemoveConfirmation
        ) {
            Button("Reset to All Mice", role: .destructive) {
                if let key = selectedProfileKey {
                    settings.removeProfile(forKey: key)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scroll, button, and gesture settings for this mouse will follow All Mice again.")
        }
    }

    // MARK: - Profile Selection

    /// Connected external mice, de-duplicated by profile key.
    private var connectedMice: [DeviceManager.HIDDevice] {
        var seen = Set<String>()
        return deviceManager.connectedDevices.filter { device in
            guard !device.isAppleDevice else { return false }
            return seen.insert(device.deviceKey).inserted
        }
    }

    /// Saved profiles for mice that aren't currently connected.
    private var disconnectedProfileKeys: [String] {
        let connectedKeys = Set(connectedMice.map { $0.deviceKey })
        let inheritedLegacyKeys = Set(connectedMice.compactMap { device in
            device.deviceKey == device.legacyDeviceKey ? nil : device.legacyDeviceKey
        })
        return settings.mouseProfiles.keys
            .filter { !connectedKeys.contains($0) && !inheritedLegacyKeys.contains($0) }
            .sorted { profileName(forKey: $0) < profileName(forKey: $1) }
    }

    /// Every key currently offered by the picker.
    private var availableProfileKeys: Set<String> {
        Set(connectedMice.map { $0.deviceKey }).union(disconnectedProfileKeys)
    }

    /// The profile for the current selection, or nil when the selected mouse
    /// hasn't been customized yet.
    private var selectedProfile: ProfileSettings? {
        guard let key = selectedProfileKey else { return settings.defaultProfile }
        return settings.mouseProfiles[key]
    }

    /// The settings an uncustomized selected mouse currently inherits. This may
    /// be a legacy vendor/product profile after upgrading, not always defaults.
    private var inheritedProfile: ProfileSettings {
        settings.profile(forKey: selectedProfileKey)
    }

    private func profileName(forKey key: String) -> String {
        if let device = connectedMice.first(where: { $0.deviceKey == key }) {
            return displayNameForScope(device)
        }
        let name = settings.mouseProfiles[key]?.displayName ?? ""
        return name.isEmpty ? "Mouse" : name
    }

    private func displayNameForScope(_ device: DeviceManager.HIDDevice) -> String {
        let sameNameCount = connectedMice.filter { $0.displayName == device.displayName }.count
        guard sameNameCount > 1, let qualifier = device.profileQualifier else {
            return device.displayName
        }
        return "\(device.displayName) (\(qualifier))"
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
            ScopeEntry(key: $0.deviceKey, name: displayNameForScope($0), connected: true)
        }
        let disconnected = disconnectedProfileKeys.map {
            ScopeEntry(key: $0, name: profileName(forKey: $0), connected: false)
        }
        return connected + disconnected
    }

    /// Finder-style scope bar: a centered popup selecting which mouse is
    /// being configured, with a trailing reset menu for customized mice.
    private var profileScopeBar: some View {
        HStack {
            Spacer(minLength: 40)
            scopePicker
            Spacer(minLength: 40)
        }
        .overlay(alignment: .trailing) {
            if selectedProfileKey != nil && selectedProfile != nil {
                Menu {
                    Button("Reset \(selectedDeviceName) to All Mice…", role: .destructive) {
                        showRemoveConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.trailing, 20)
                .help("Profile options")
                .accessibilityLabel("Profile options")
                .accessibilityHint("Reset \(selectedDeviceName) to All Mice")
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var scopePicker: some View {
        let entries = scopeEntries
        let connectedEntries = entries.filter { $0.connected }
        let disconnectedEntries = entries.filter { !$0.connected }

        Picker("Mouse", selection: $selectedProfileKey) {
            Text("All Mice").tag(String?.none)
            ForEach(connectedEntries) { entry in
                Text(entry.name).tag(Optional(entry.key))
            }
            if !disconnectedEntries.isEmpty {
                Section("Not Connected") {
                    ForEach(disconnectedEntries) { entry in
                        Text(entry.name).tag(Optional(entry.key))
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 360)
    }

    // MARK: - Tab Content Gating

    /// Show the editor bound to the right profile. When the selected mouse
    /// has no profile yet, show the settings it currently follows read-only
    /// under a banner offering to customize. The preview doubles as
    /// documentation: those values are exactly what the new profile starts with.
    @ViewBuilder
    private func behaviorTab<Content: View>(
        @ViewBuilder content: (ProfileSettings, CustomizeProfileBanner?) -> Content
    ) -> some View {
        if let profile = selectedProfile {
            content(profile, nil)
        } else {
            content(inheritedProfile, CustomizeProfileBanner(
                deviceName: selectedDeviceName,
                onCustomize: customizeSelectedMouse
            ))
        }
    }

    private func customizeSelectedMouse() {
        guard let key = selectedProfileKey else { return }
        settings.createProfile(forKey: key, displayName: profileName(forKey: key))
    }

    // MARK: - Status Banners

    private var relocationWarning: some View {
        StatusBanner(
            icon: "folder.fill",
            tint: .accentColor,
            title: "Move FlowMod to Applications",
            message: "FlowMod needs to be in your Applications folder to set up input access."
        ) {
            Button("Move to Applications") {
                InstallLocationWindowController.shared.show()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var permissionWarning: some View {
        StatusBanner(
            icon: "exclamationmark.triangle.fill",
            tint: .yellow,
            title: "Mouse access isn't active",
            message: "Turn on FlowMod in \(PermissionManager.permissionSettingsPath). If it's already on, relaunch."
        ) {
            Button("Relaunch") {
                permissionManager.relaunchApp()
            }

            Button("Grant Access") {
                OnboardingWindowController.shared.show()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func interceptorWarning(_ message: String) -> some View {
        StatusBanner(
            icon: "exclamationmark.triangle.fill",
            tint: .orange,
            title: "FlowMod couldn't start",
            message: message
        ) {
            Button("Relaunch") {
                permissionManager.relaunchApp()
            }

            Button("Try Again") {
                inputInterceptor.start(settings: settings, deviceManager: deviceManager)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var disabledNotice: some View {
        StatusBanner(
            icon: "pause.circle.fill",
            tint: .gray,
            title: "FlowMod is turned off",
            message: "Your mouse is using standard macOS behavior. Changes here apply when FlowMod is on."
        ) {
            Button("Turn On") {
                inputInterceptor.start(settings: settings, deviceManager: deviceManager)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    SettingsView(
        settings: Settings.shared,
        deviceManager: DeviceManager.shared,
        permissionManager: PermissionManager.shared,
        inputInterceptor: InputInterceptor.shared,
        keyboardManager: KeyboardManager.shared
    )
}
