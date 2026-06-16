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
    @State private var devicePopoverTask: Task<Void, Never>?

    private let devicePopoverDelay: Duration = .milliseconds(250)
    
    /// Get the app version from Bundle info
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // App header with icon, name, version, and device indicators
                headerView
                
                Divider()
                
                // Launch at Login
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "power")
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Launch at Login")
                                    .font(.subheadline)
                                Text("Start FlowMod automatically when you log in")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .onChange(of: launchAtLoginEnabled) { _, newValue in
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
                }
                .padding(.vertical, 4)

                // Per-mouse settings
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "computermouse")
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Separate Settings Per Mouse")
                                    .font(.subheadline)
                                Text("Give each mouse its own scroll, button, and gesture settings")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

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
                }
                .padding(.vertical, 4)

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
        .onDisappear {
            cancelDevicePopover()
        }
    }
    
    private func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
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
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = "Couldn't \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
                // Revert UI state
                launchAtLoginEnabled = !enabled
            }
        }
    }

    private func handleDevicePillHover(_ isHovering: Bool) {
        devicePopoverTask?.cancel()

        guard isHovering else {
            showDevicePopover = false
            return
        }

        devicePopoverTask = Task { @MainActor in
            try? await Task.sleep(for: devicePopoverDelay)
            guard !Task.isCancelled else { return }
            showDevicePopover = true
        }
    }

    private func cancelDevicePopover() {
        devicePopoverTask?.cancel()
        devicePopoverTask = nil
        showDevicePopover = false
    }
    
    private var updatesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Updates")
                            .font(.subheadline)
                        Text("Checks once per day for new releases on GitHub")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("Check for Updates Automatically", isOn: Binding(
                        get: { updateManager.autoCheckForUpdates },
                        set: { updateManager.autoCheckForUpdates = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                
                Divider()
                
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
                        Text("Downloading update… \(Int(updateManager.downloadProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
            
            // Device connection pills — centered
            HStack(spacing: 10) {
                devicePill(
                    connected: deviceManager.externalMouseConnected,
                    icon: "computermouse",
                    label: mousePillLabel,
                    devices: externalMice
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var externalMice: [DeviceManager.HIDDevice] {
        deviceManager.connectedDevices.filter { $0.isMouse && !$0.isAppleDevice }
    }

    /// Pill label: the device name when one mouse is connected, a count when
    /// several are, or "Mouse" when none is detected.
    private var mousePillLabel: String {
        let names = Array(Set(externalMice.map { $0.displayName })).sorted()
        switch names.count {
        case 0: return "Mouse"
        case 1: return names[0]
        default: return "\(names.count) Mice"
        }
    }
    
    private func devicePill(connected: Bool, icon: String, label: String, devices: [DeviceManager.HIDDevice]) -> some View {
        let uniqueDeviceNames = Array(Set(devices.map { $0.displayName })).sorted()
        let deviceList = uniqueDeviceNames.isEmpty
            ? "No external \(label.lowercased()) detected"
            : uniqueDeviceNames.joined(separator: "\n")

        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
            Circle()
                .fill(connected ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(connected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
        )
        .foregroundStyle(connected ? .primary : .secondary)
        .onHover(perform: handleDevicePillHover)
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
                    Label("Debug Logging", systemImage: "ladybug")
                        .font(.headline)

                    Toggle("Enable Debug Logging", isOn: $settings.debugLogging)
                        .font(.callout)

                    Text("Captures detailed logs for troubleshooting. May impact performance.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            LogManager.shared.copyLogsToClipboard()
                            showCopiedConfirmation = true
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
                .padding(.vertical, 4)
            }

            // Device Detection Override
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Device Detection", systemImage: "cable.connector")
                        .font(.headline)

                    Toggle("Assume external mouse is connected", isOn: $settings.assumeExternalMouse)
                        .font(.callout)

                    Text("Enable this if your Bluetooth mouse isn't being detected automatically.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Spacer()

            // Bottom-right action, standard macOS sheet layout
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 400, height: 320)
    }
}

#Preview {
    GeneralSettingsView(settings: Settings.shared, deviceManager: DeviceManager.shared)
        .padding()
        .frame(width: 460, height: 400)
}
