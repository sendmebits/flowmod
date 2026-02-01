import SwiftUI

/// Main settings view with a clean tabbed interface
struct SettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    var permissionManager: PermissionManager
    
    @State private var showMousePopover = false
    @State private var showKeyboardPopover = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Permission warning if needed
            if !permissionManager.hasAccessibilityPermission {
                permissionWarning
            }
            
            // Tab content using native TabView
            TabView {
                ScrollSettingsView(settings: settings, deviceManager: deviceManager)
                    .tabItem {
                        Label("Scroll", systemImage: "scroll")
                    }
                
                MouseButtonsView(settings: settings)
                    .tabItem {
                        Label("Buttons", systemImage: "computermouse")
                    }
                
                MiddleDragGesturesView(settings: settings)
                    .tabItem {
                        Label("Gestures", systemImage: "hand.draw")
                    }
                
                KeyboardMappingsView(settings: settings)
                    .tabItem {
                        Label("Keyboard", systemImage: "keyboard")
                    }
                
                ExcludedAppsView(settings: settings)
                    .tabItem {
                        Label("Excluded", systemImage: "xmark.app")
                    }
                
                GeneralSettingsView(settings: settings, deviceManager: deviceManager)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
            }
            .padding()
        }
        .frame(width: 500, height: 440)
        .background(.regularMaterial)
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "computermouse.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            
            Text("minput")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            // Connection status indicators
            HStack(spacing: 12) {
                connectionIndicator(
                    connected: deviceManager.externalMouseConnected,
                    icon: "computermouse",
                    label: "Mouse",
                    devices: deviceManager.connectedDevices.filter { $0.isMouse && !$0.isAppleDevice },
                    showPopover: $showMousePopover
                )
                
                connectionIndicator(
                    connected: deviceManager.externalKeyboardConnected,
                    icon: "keyboard",
                    label: "Keyboard",
                    devices: deviceManager.connectedDevices.filter { $0.isKeyboard && !$0.isAppleDevice },
                    showPopover: $showKeyboardPopover
                )
            }
        }
        .padding()
    }
    
    private func connectionIndicator(connected: Bool, icon: String, label: String, devices: [DeviceManager.HIDDevice], showPopover: Binding<Bool>) -> some View {
        // Deduplicate device names
        let uniqueDeviceNames = Array(Set(devices.map { $0.displayName })).sorted()
        
        let deviceList: String = {
            if uniqueDeviceNames.isEmpty {
                return "No external \(label.lowercased()) detected"
            }
            return uniqueDeviceNames.joined(separator: "\n")
        }()
        
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Circle()
                .fill(connected ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 6, height: 6)
        }
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
