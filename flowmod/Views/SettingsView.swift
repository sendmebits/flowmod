import SwiftUI

/// Consistent title, description, icon, and trailing control layout for settings.
struct SettingsControlRow<Control: View>: View {
    let icon: String
    let title: String
    private let descriptionText: Text
    private let accessibilityDescription: String
    private let control: Control

    init(
        icon: String,
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) {
        self.icon = icon
        self.title = title
        self.descriptionText = Text(description)
        self.accessibilityDescription = description
        self.control = control()
    }

    init(
        icon: String,
        title: String,
        description: LocalizedStringKey,
        accessibilityDescription: String,
        @ViewBuilder control: () -> Control
    ) {
        self.icon = icon
        self.title = title
        self.descriptionText = Text(description)
        self.accessibilityDescription = accessibilityDescription
        self.control = control()
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                descriptionText
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityHidden(true)

            Spacer()

            control
                .accessibilityLabel(title)
                .accessibilityHint(accessibilityDescription)
        }
    }
}

/// Small, consistent label used above settings groups.
struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

/// Shared divider spacing for row-based settings groups.
struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 8)
    }
}

/// Main settings view with a clean tabbed interface
struct SettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    var permissionManager: PermissionManager
    var inputInterceptor: InputInterceptor

    private enum Tab: Hashable {
        case general, scroll, buttons, gestures
    }

    /// Which profile the window is editing. nil = default ("All Mice").
    @State private var selectedProfileKey: String? = nil
    @State private var showRemoveConfirmation = false
    @State private var selectedTab: Tab = .general

    private static let windowSize = CGSize(width: 500, height: 560)
    private static let scopeBarHeight: CGFloat = 38

    /// The mouse scope bar is only relevant on the per-mouse behavior tabs.
    private var showsScopeBar: Bool {
        settings.perMouseSettingsEnabled && selectedTab != .general
    }

    var body: some View {
        VStack(spacing: 0) {
            // Permission warning if needed
            if !permissionManager.hasAccessibilityPermission {
                permissionWarning
            } else if let startupError = inputInterceptor.startupError {
                interceptorWarning(startupError)
            }

            // Mouse scope bar — Finder-style filter under the toolbar,
            // shown only on the tabs it applies to
            if showsScopeBar {
                profileScopeBar
            }

            // Tab content using native TabView
            TabView(selection: $selectedTab) {
                GeneralSettingsView(settings: settings, deviceManager: deviceManager)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
                    .tag(Tab.general)

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

                gesturesTab
                .tabItem {
                    Label("Gestures", systemImage: "hand.draw")
                }
                .tag(Tab.gestures)
            }
            .padding()
        }
        // Keep a stable System Settings-style window; tab scroll views handle overflow.
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
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
            "Reset \(selectedDeviceName) to shared settings?",
            isPresented: $showRemoveConfirmation
        ) {
            Button("Reset to Shared Settings", role: .destructive) {
                if let key = selectedProfileKey {
                    settings.removeProfile(forKey: key)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This mouse will go back to following the settings it inherits for this model.")
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
                .padding(.trailing, 16)
                .help("Profile options")
                .accessibilityLabel("Profile options")
                .accessibilityHint("Reset \(selectedDeviceName) to the default settings")
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .frame(height: Self.scopeBarHeight)
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

                content(inheritedProfile)
                    .disabled(true)
                    .opacity(0.5)
            }
        }
    }

    /// Gestures include a global drag-distance control, so only the
    /// profile-specific controls become read-only in preview mode.
    @ViewBuilder
    private var gesturesTab: some View {
        if let profile = selectedProfile {
            MiddleDragGesturesView(profile: profile, settings: settings)
        } else {
            VStack(spacing: 10) {
                customizeBanner

                MiddleDragGesturesView(
                    profile: inheritedProfile,
                    settings: settings,
                    profileControlsDisabled: true
                )
            }
        }
    }

    private var customizeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "computermouse")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(selectedDeviceName) is following shared settings")
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
                OnboardingWindowController.shared.show()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
    }

    private func interceptorWarning(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("FlowMod couldn't start")
                    .font(.callout)
                    .fontWeight(.medium)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Accessibility Settings") {
                permissionManager.openAccessibilitySettings()
            }
            .controlSize(.small)

            Button("Try Again") {
                inputInterceptor.start(settings: settings, deviceManager: deviceManager)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
    }
}

#Preview {
    SettingsView(
        settings: Settings.shared,
        deviceManager: DeviceManager.shared,
        permissionManager: PermissionManager.shared,
        inputInterceptor: InputInterceptor.shared
    )
}
