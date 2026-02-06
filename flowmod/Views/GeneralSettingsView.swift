import SwiftUI
import ServiceManagement

/// General app settings
struct GeneralSettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    
    @State private var launchAtLoginEnabled = false
    @State private var showAdvanced = false
    @State private var showMousePopover = false
    @State private var showKeyboardPopover = false
    
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
                    HStack {
                        Image(systemName: "power")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32)
                    
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at Login")
                                .font(.headline)
                            Text("Start FlowMod automatically when you log in")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    
                        Spacer()
                    
                    Toggle("", isOn: $launchAtLoginEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: launchAtLoginEnabled) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }
                }
                .padding(.vertical, 4)
            }
            
            // Bottom buttons
            HStack {
                Button {
                    showAdvanced = true
                } label: {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Quit FlowMod") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            checkLaunchAtLoginStatus()
        }
        .sheet(isPresented: $showAdvanced) {
            AdvancedSettingsSheet(settings: settings)
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
            } catch {
                print("Failed to set launch at login: \(error)")
                // Revert UI state
                launchAtLoginEnabled = !enabled
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
            
            // Device connection pills — centered
            HStack(spacing: 10) {
                devicePill(
                    connected: deviceManager.externalMouseConnected,
                    icon: "computermouse",
                    label: "Mouse",
                    devices: deviceManager.connectedDevices.filter { $0.isMouse && !$0.isAppleDevice },
                    showPopover: $showMousePopover
                )
                
                devicePill(
                    connected: deviceManager.externalKeyboardConnected,
                    icon: "keyboard",
                    label: "Keyboard",
                    devices: deviceManager.connectedDevices.filter { $0.isKeyboard && !$0.isAppleDevice },
                    showPopover: $showKeyboardPopover
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func devicePill(connected: Bool, icon: String, label: String, devices: [DeviceManager.HIDDevice], showPopover: Binding<Bool>) -> some View {
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
        .onHover { isHovering in
            showPopover.wrappedValue = isHovering
        }
        .popover(isPresented: showPopover, arrowEdge: .bottom) {
            Text(deviceList)
                .font(.caption)
                .padding(8)
                .fixedSize()
        }
    }
}

/// Advanced settings sheet
struct AdvancedSettingsSheet: View {
    @Bindable var settings: Settings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Advanced Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            
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
                        } label: {
                            Label("Copy Logs", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Text("\(LogManager.shared.entryCount) entries")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
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
                    
                    Toggle("Assume external keyboard is connected", isOn: $settings.assumeExternalKeyboard)
                        .font(.callout)
                    
                    Text("Enable these if your Bluetooth mouse or keyboard isn't being detected automatically.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 400, height: 350)
    }
}

#Preview {
    GeneralSettingsView(settings: Settings.shared, deviceManager: DeviceManager.shared)
        .padding()
        .frame(width: 460, height: 400)
}
