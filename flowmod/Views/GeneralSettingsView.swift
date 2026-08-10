import SwiftUI
import ServiceManagement

/// General app settings
struct GeneralSettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    var updateManager = UpdateManager.shared
    
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?
    @State private var showAdvanced = false
    @State private var showDevicePopover = false
    
    /// Get the app version from Bundle info
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // App header with icon, name, version, and device indicators
                headerView
                
                Divider()
                
                // Launch at Login
                VStack(alignment: .leading, spacing: 6) {
                    SettingsSectionHeader(title: "Startup")

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsControlRow(
                                icon: "power",
                                title: "Launch at Login",
                                description: "Start FlowMod automatically when you log in"
                            ) {
                                Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                                        guard #available(macOS 13.0, *) else { return }
                                        guard newValue != launchAtLoginServiceEnabled else { return }
                                        setLaunchAtLogin(newValue)
                                    }
                            }

                            if let error = launchAtLoginError {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.caption)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Per-mouse settings
                VStack(alignment: .leading, spacing: 6) {
                    SettingsSectionHeader(title: "Mouse Profiles")

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsControlRow(
                                icon: "computermouse",
                                title: "Separate Settings Per Mouse",
                                description: "Give each mouse its own scroll, button, and gesture settings"
                            ) {
                                Toggle("Separate Settings Per Mouse", isOn: $settings.perMouseSettingsEnabled)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }

                            if settings.perMouseSettingsEnabled {
                                Text("Choose a mouse at the top of the Scroll, Buttons, and Gestures tabs to customize it.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Updates
                updatesSection

                // Bottom buttons
                HStack {
                    Button {
                        showAdvanced = true
                    } label: {
                        Label("Advanced…", systemImage: "gearshape.2")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            checkLaunchAtLoginStatus()
        }
        .sheet(isPresented: $showAdvanced) {
            AdvancedSettingsSheet(settings: settings)
        }
        .onChange(of: updateManager.isChecking) { _, isChecking in
            if isChecking {
                AccessibilityNotification.Announcement("Checking for updates").post()
            }
        }
        .onChange(of: updateManager.isDownloading) { _, isDownloading in
            if isDownloading {
                AccessibilityNotification.Announcement("Downloading update").post()
            }
        }
        .onChange(of: updateManager.upToDateMessage) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .onChange(of: updateManager.updateAvailable) { _, isAvailable in
            if isAvailable, let version = updateManager.latestVersion {
                AccessibilityNotification.Announcement("FlowMod version \(version) is available").post()
            }
        }
        .onChange(of: updateManager.errorMessage) { _, error in
            if let error {
                AccessibilityNotification.Announcement("Update error: \(error)").post()
            }
        }
    }
    
    private func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            launchAtLoginEnabled = launchAtLoginServiceEnabled
        }
    }

    private var launchAtLoginServiceEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }

        return false
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                settings.launchAtLogin = enabled
                launchAtLoginEnabled = launchAtLoginServiceEnabled
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = "Couldn't \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
                // Revert UI state
                launchAtLoginEnabled = !enabled
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionHeader(title: "Updates")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsControlRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Automatic Updates",
                        description: "Checks once per day for new releases on [GitHub](https://github.com/sendmebits/flowmod)",
                        accessibilityDescription: "Checks once per day for new releases on GitHub"
                    ) {
                        Toggle("Check for Updates Automatically", isOn: Binding(
                            get: { updateManager.autoCheckForUpdates },
                            set: { updateManager.autoCheckForUpdates = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }

                    SettingsRowDivider()

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await updateManager.checkForUpdates()
                            }
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(updateManager.isChecking || updateManager.isDownloading)

                        if updateManager.isChecking {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let message = updateManager.upToDateMessage {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    // Update available banner
                    if updateManager.updateAvailable, let version = updateManager.latestVersion {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(.green)

                            Text("Version \(version) is available")
                                .font(.callout)
                                .fontWeight(.medium)

                            Spacer()

                            if updateManager.downloadURL != nil {
                                Button {
                                    Task {
                                        await updateManager.downloadAndInstall()
                                    }
                                } label: {
                                    Label("Download & Install", systemImage: "arrow.down.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(updateManager.isDownloading)
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.green.opacity(0.08))
                        )
                    }

                    // Download progress
                    if updateManager.isDownloading {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: updateManager.downloadProgress)
                                .accessibilityLabel("Downloading update")
                                .accessibilityValue("\(Int(updateManager.downloadProgress * 100)) percent")
                            Text("Downloading update… \(Int(updateManager.downloadProgress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }

                    // Error message
                    if let error = updateManager.errorMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 14) {
            // App identity — centered
            VStack(spacing: 4) {
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                
                Text("FlowMod")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(appVersionString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            // Device connection pill — centered
            devicePill(
                connected: deviceManager.externalMouseConnected,
                icon: "computermouse",
                label: mousePillLabel,
                devices: externalMice
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var externalMice: [DeviceManager.HIDDevice] {
        var seen = Set<String>()
        return deviceManager.connectedDevices.filter {
            $0.isMouse && !$0.isAppleDevice && seen.insert($0.deviceKey).inserted
        }
    }

    /// Pill label: the device name when one mouse is connected, a count when
    /// several are, or "Mouse" when none is detected.
    private var mousePillLabel: String {
        switch externalMice.count {
        case 0: return "Mouse"
        case 1: return externalMice[0].displayName
        default: return "\(externalMice.count) Mice"
        }
    }
    
    private func devicePill(connected: Bool, icon: String, label: String, devices: [DeviceManager.HIDDevice]) -> some View {
        let duplicateNames = Dictionary(grouping: devices, by: \.displayName)
        let uniqueDeviceNames = devices.map { device in
            guard (duplicateNames[device.displayName]?.count ?? 0) > 1,
                  let qualifier = device.profileQualifier else {
                return device.displayName
            }
            return "\(device.displayName) (\(qualifier))"
        }.sorted()
        let deviceList = uniqueDeviceNames.isEmpty
            ? "No external \(label.lowercased()) detected"
            : uniqueDeviceNames.joined(separator: "\n")

        return Button {
            showDevicePopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                Circle()
                    .fill(connected ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(connected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
        )
        .foregroundStyle(connected ? .primary : .secondary)
        .accessibilityLabel(connected ? "\(label), connected" : "\(label), not connected")
        .accessibilityHint("Shows connected mouse details")
        .popover(isPresented: $showDevicePopover, arrowEdge: .bottom) {
            Text(deviceList)
                .font(.caption)
                .multilineTextAlignment(.leading)
                .padding(8)
                .fixedSize()
        }
    }
}

/// Advanced settings sheet
struct AdvancedSettingsSheet: View {
    @Bindable var settings: Settings
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Advanced Settings")
                .font(.headline)

            // Debug Logging
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsControlRow(
                        icon: "ladybug",
                        title: "Debug Logging",
                        description: "Captures detailed logs for troubleshooting. May impact performance."
                    ) {
                        Toggle("Enable Debug Logging", isOn: $settings.debugLogging)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    HStack {
                        Button {
                            LogManager.shared.copyLogsToClipboard()
                            showCopiedConfirmation = true
                            AccessibilityNotification.Announcement("Logs copied").post()
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                showCopiedConfirmation = false
                            }
                        } label: {
                            Label("Copy Logs", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if showCopiedConfirmation {
                            Label("Copied", systemImage: "checkmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(LogManager.shared.entryCount) entries")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            LogManager.shared.clearLogs()
                        } label: {
                            Text("Clear")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }

            // Device Detection Override
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsControlRow(
                        icon: "cable.connector",
                        title: "Device Detection",
                        description: "Assume an external mouse is connected if Bluetooth detection is unreliable"
                    ) {
                        Toggle("Assume external mouse is connected", isOn: $settings.assumeExternalMouse)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }

            // Setup troubleshooting
            GroupBox {
                SettingsControlRow(
                    icon: "checklist",
                    title: "Setup Assistant",
                    description: "Review Accessibility access and verify that FlowMod can start"
                ) {
                    Button("Run Setup Again…") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            OnboardingWindowController.shared.show()
                        }
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 8)
            }

            // Bottom-right action, standard macOS sheet layout
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    GeneralSettingsView(settings: Settings.shared, deviceManager: DeviceManager.shared)
        .padding()
        .frame(width: 460, height: 400)
}
