import SwiftUI

/// Main settings view with a clean tabbed interface
struct SettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    var permissionManager: PermissionManager
    
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Permission warning if needed
            if !permissionManager.hasAccessibilityPermission {
                permissionWarning
            }
            
            // Tab content
            TabView(selection: $selectedTab) {
                ScrollSettingsView(settings: settings, deviceManager: deviceManager)
                    .tabItem {
                        Label("Scroll", systemImage: "scroll")
                    }
                    .tag(0)
                
                MouseButtonsView(settings: settings)
                    .tabItem {
                        Label("Buttons", systemImage: "computermouse")
                    }
                    .tag(1)
                
                MiddleDragGesturesView(settings: settings)
                    .tabItem {
                        Label("Gestures", systemImage: "hand.draw")
                    }
                    .tag(2)
                
                KeyboardMappingsView(settings: settings)
                    .tabItem {
                        Label("Keyboard", systemImage: "keyboard")
                    }
                    .tag(3)
                
                ExcludedAppsView(settings: settings)
                    .tabItem {
                        Label("Excluded", systemImage: "xmark.app")
                    }
                    .tag(4)
                
                GeneralSettingsView(settings: settings, deviceManager: deviceManager)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
                    .tag(5)
            }
            .padding()
        }
        .frame(width: 500, height: 480)
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
                    label: "Mouse"
                )
                
                connectionIndicator(
                    connected: deviceManager.externalKeyboardConnected,
                    icon: "keyboard",
                    label: "Keyboard"
                )
            }
        }
        .padding()
    }
    
    private func connectionIndicator(connected: Bool, icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Circle()
                .fill(connected ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 6, height: 6)
        }
        .foregroundStyle(connected ? .primary : .secondary)
        .help(connected ? "\(label) connected" : "No external \(label.lowercased())")
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
