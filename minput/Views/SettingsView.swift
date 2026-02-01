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
            
            // Tab content - using Group to avoid layout recursion
            Group {
                switch selectedTab {
                case 0:
                    ScrollSettingsView(settings: settings, deviceManager: deviceManager)
                case 1:
                    MouseButtonsView(settings: settings)
                case 2:
                    MiddleDragGesturesView(settings: settings)
                case 3:
                    KeyboardMappingsView(settings: settings)
                case 4:
                    ExcludedAppsView(settings: settings)
                case 5:
                    GeneralSettingsView(settings: settings, deviceManager: deviceManager)
                default:
                    ScrollSettingsView(settings: settings, deviceManager: deviceManager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            
            Divider()
            
            // Custom tab bar at bottom
            HStack(spacing: 0) {
                tabButton(index: 0, icon: "scroll", label: "Scroll")
                tabButton(index: 1, icon: "computermouse", label: "Buttons")
                tabButton(index: 2, icon: "hand.draw", label: "Gestures")
                tabButton(index: 3, icon: "keyboard", label: "Keyboard")
                tabButton(index: 4, icon: "xmark.app", label: "Excluded")
                tabButton(index: 5, icon: "gear", label: "General")
            }
            .padding(.vertical, 8)
        }
        .frame(width: 500, height: 480)
        .background(.regularMaterial)
    }
    
    private func tabButton(index: Int, icon: String, label: String) -> some View {
        Button {
            selectedTab = index
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(selectedTab == index ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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
