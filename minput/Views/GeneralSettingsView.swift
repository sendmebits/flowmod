import SwiftUI
import ServiceManagement

/// General app settings
struct GeneralSettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    
    @State private var launchAtLoginEnabled = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Launch at Login
            GroupBox {
                Toggle(isOn: $launchAtLoginEnabled) {
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
                    }
                }
                .toggleStyle(.switch)
                .padding(.vertical, 4)
                .onChange(of: launchAtLoginEnabled) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
            }
            
            // Connected Devices
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Connected Devices", systemImage: "cable.connector")
                        .font(.headline)
                    
                    if deviceManager.connectedDevices.isEmpty {
                        Text("No external devices detected")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(deviceManager.connectedDevices) { device in
                            HStack {
                                Image(systemName: device.isMouse ? "computermouse" : "keyboard")
                                    .foregroundStyle(device.isAppleDevice ? Color.secondary : Color.accentColor)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.displayName)
                                        .font(.callout)
                                    
                                    Text(device.isAppleDevice ? "Apple Device (ignored)" : "External Device")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if !device.isAppleDevice {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            
            // Quit button
            HStack {
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

#Preview {
    GeneralSettingsView(settings: Settings.shared, deviceManager: DeviceManager.shared)
        .padding()
        .frame(width: 460, height: 400)
}
