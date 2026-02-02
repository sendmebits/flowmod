import SwiftUI
import ServiceManagement

/// General app settings
struct GeneralSettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    
    @State private var launchAtLoginEnabled = false
    @State private var showAdvanced = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
                        Text("Start minput automatically when you log in")
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
            
            // About
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "computermouse.fill")
                            .font(.title)
                            .foregroundStyle(Color.accentColor)
                        
                        VStack(alignment: .leading) {
                            Text("minput")
                                .font(.headline)
                            Text("Version 1.0.0")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    Text("A lightweight input remapper for external mice and keyboards on macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            // Bottom buttons
            HStack {
                Button {
                    showAdvanced = true
                } label: {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Quit minput") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
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
