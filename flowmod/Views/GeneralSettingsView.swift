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
    
    /// Get the app version from Bundle info
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }
    
    var body: some View {
        Form {
            Section {
                appHeader
                connectedMiceRows
            }

            Section {
                Toggle(isOn: $launchAtLoginEnabled) {
                    Text("Launch at Login")
                    if let error = launchAtLoginError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                .onChange(of: launchAtLoginEnabled) { _, newValue in
                    guard newValue != launchAtLoginServiceEnabled else { return }
                    setLaunchAtLogin(newValue)
                }

                Toggle("Separate Settings for Each Mouse", isOn: $settings.perMouseSettingsEnabled)
            } header: {
                Text("Behavior")
            } footer: {
                Text(settings.perMouseSettingsEnabled
                     ? "Pick a mouse at the top of the Scroll, Buttons, and Gestures tabs."
                     : "Give each mouse its own scroll, button, and gesture settings.")
            }

            updatesSection

            advancedSection
        }
        .formStyle(.grouped)
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
        launchAtLoginEnabled = launchAtLoginServiceEnabled
    }

    private var launchAtLoginServiceEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
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

    // MARK: - Header

    private static let repositoryURL = URL(string: "https://github.com/sendmebits/flowmod")!

    private var appHeader: some View {
        VStack(spacing: 4) {
            Button {
                NSWorkspace.shared.open(Self.repositoryURL)
            } label: {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Open the FlowMod GitHub page")
            .accessibilityLabel("FlowMod on GitHub")
            .accessibilityHint("Opens the FlowMod GitHub page")

            Text("FlowMod")
                .font(.title2)
                .fontWeight(.semibold)

            Text(appVersionString)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var externalMice: [DeviceManager.HIDDevice] {
        var seen = Set<String>()
        return deviceManager.connectedDevices.filter {
            !$0.isAppleDevice && seen.insert($0.deviceKey).inserted
        }
    }

    private struct MouseEntry: Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }

    private var externalMouseEntries: [MouseEntry] {
        let duplicateNames = Dictionary(grouping: externalMice, by: \.displayName)
        return externalMice.map { device in
            guard (duplicateNames[device.displayName]?.count ?? 0) > 1,
                  let qualifier = device.profileQualifier else {
                return MouseEntry(key: device.deviceKey, name: device.displayName)
            }
            return MouseEntry(key: device.deviceKey, name: "\(device.displayName) (\(qualifier))")
        }.sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private var connectedMiceRows: some View {
        let entries = externalMouseEntries
        if entries.isEmpty {
            LabeledContent("Mouse") {
                connectionStatus(connected: deviceManager.externalMouseConnected)
            }
        } else {
            ForEach(entries) { entry in
                let enabled = settings.isMouseEnabled(forKey: entry.key)
                Toggle(isOn: Binding(
                    get: { settings.isMouseEnabled(forKey: entry.key) },
                    set: { settings.setMouseEnabled($0, forKey: entry.key) }
                )) {
                    Text(entry.name)
                    Text(enabled ? "Customized by FlowMod" : "Not modified")
                }
                .accessibilityHint("Turn off to leave this mouse unmodified by FlowMod")
            }
        }
    }

    private func connectionStatus(connected: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(connected ? "Connected" : "Not Connected")
        }
    }

    // MARK: - Updates

    /// Secondary line under "Check for Updates": progress, error, or result.
    private var updateStatusText: String? {
        if updateManager.isChecking { return "Checking…" }
        if let error = updateManager.errorMessage { return error }
        return updateManager.upToDateMessage
    }

    private var updatesSection: some View {
        Section {
            Toggle("Check for Updates Automatically", isOn: Binding(
                get: { updateManager.autoCheckForUpdates },
                set: { updateManager.autoCheckForUpdates = $0 }
            ))

            LabeledContent {
                HStack(spacing: 8) {
                    if updateManager.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Check Now") {
                        Task {
                            await updateManager.checkForUpdates()
                        }
                    }
                    .disabled(updateManager.isChecking || updateManager.isDownloading)
                }
            } label: {
                Text("Check for Updates")
                if let status = updateStatusText {
                    Text(status)
                }
            }

            if updateManager.updateAvailable, let version = updateManager.latestVersion {
                LabeledContent {
                    if updateManager.downloadURL != nil {
                        Button("Download & Install") {
                            Task {
                                await updateManager.downloadAndInstall()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updateManager.isDownloading)
                    }
                } label: {
                    Label {
                        Text("Version \(version) is available")
                    } icon: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            if updateManager.isDownloading {
                ProgressView(value: updateManager.downloadProgress) {
                    Text("Downloading update…")
                } currentValueLabel: {
                    Text("\(Int(updateManager.downloadProgress * 100))%")
                }
                .accessibilityValue("\(Int(updateManager.downloadProgress * 100)) percent")
            }
        } header: {
            Text("Updates")
        }
    }

    private var advancedSection: some View {
        Section {
            LabeledContent {
                Button("Advanced…") {
                    showAdvanced = true
                }
            } label: {
                Text("Troubleshooting")
                Text("Debug logging, mouse detection, and setup assistant")
            }
        }
    }
}

/// Advanced settings sheet
struct AdvancedSettingsSheet: View {
    @Bindable var settings: Settings
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Advanced")
                .font(.headline)
                .padding(.top, 20)

            Form {
                Section {
                    Toggle("Debug Logging", isOn: $settings.debugLogging)

                    LabeledContent {
                        HStack(spacing: 8) {
                            Button("Copy") {
                                LogManager.shared.copyLogsToClipboard()
                                showCopiedConfirmation = true
                                AccessibilityNotification.Announcement("Logs copied").post()
                                Task {
                                    try? await Task.sleep(for: .seconds(2))
                                    showCopiedConfirmation = false
                                }
                            }

                            Button("Clear") {
                                LogManager.shared.clearLogs()
                                showCopiedConfirmation = false
                                AccessibilityNotification.Announcement("Logs cleared").post()
                            }
                        }
                    } label: {
                        Text("Logs")
                        Text(showCopiedConfirmation ? "Copied to clipboard" : "\(LogManager.shared.entryCount) entries")
                    }
                } footer: {
                    Text("Debug logging may affect performance.")
                }

                Section {
                    Toggle("Assume an External Mouse Is Connected", isOn: $settings.assumeExternalMouse)
                } footer: {
                    Text("Use if Bluetooth detection is unreliable.")
                }

                Section {
                    LabeledContent {
                        Button("Run Again…") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                OnboardingWindowController.shared.show()
                            }
                        }
                    } label: {
                        Text("Setup Assistant")
                        Text("Review input access and check that FlowMod can start")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460, height: 400)
    }
}

#Preview {
    GeneralSettingsView(settings: Settings.shared, deviceManager: DeviceManager.shared)
        .frame(width: 560, height: 520)
}
