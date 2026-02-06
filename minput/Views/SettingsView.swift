import SwiftUI

/// Main settings view with a clean tabbed interface
struct SettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    var permissionManager: PermissionManager
    
    var body: some View {
        VStack(spacing: 0) {
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
