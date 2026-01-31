import SwiftUI

/// Settings for scroll reversal
struct ScrollSettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Main toggle
            GroupBox {
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
                    
                    Spacer()
                    
                    Toggle("", isOn: $settings.reverseScrollEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 4)
            }
            
            // Smooth Scrolling
            GroupBox {
                HStack {
                    Image(systemName: "water.waves")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smooth Scrolling")
                            .font(.headline)
                        Text("Adds smoothing to mouse wheel scrolling")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $settings.smoothScrolling) {
                        ForEach(SmoothScrolling.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
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
