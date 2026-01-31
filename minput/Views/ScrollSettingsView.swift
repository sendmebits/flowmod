import SwiftUI

/// Settings for scroll reversal
struct ScrollSettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Main toggle
            GroupBox {
                Toggle(isOn: $settings.reverseScrollEnabled) {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reverse Scroll Direction")
                                .font(.headline)
                            Text("For external mice only (excludes Apple devices)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .padding(.vertical, 4)
            }
            
            // Status info
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("External Mouse Status", systemImage: "info.circle")
                        .font(.headline)
                    
                    if deviceManager.externalMouseConnected {
                        let mice = deviceManager.connectedDevices.filter { $0.isMouse && !$0.isAppleDevice }
                        ForEach(mice) { mouse in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(mouse.displayName)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                        
                        if settings.reverseScrollEnabled {
                            Label("Scroll reversal is active", systemImage: "arrow.triangle.2.circlepath")
                                .font(.callout)
                                .foregroundStyle(.green)
                        }
                    } else {
                        HStack {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                            Text("No external mouse detected")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            
            // Help text
            Text("Apple trackpads and Magic Mouse will continue to scroll naturally. Only external/Windows mice will have their scroll direction reversed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
}

#Preview {
    ScrollSettingsView(settings: Settings.shared, deviceManager: DeviceManager.shared)
        .padding()
        .frame(width: 460, height: 350)
}
