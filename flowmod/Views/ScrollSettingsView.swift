import SwiftUI

/// Settings for scroll reversal
struct ScrollSettingsView: View {
    @Bindable var settings: Settings
    var deviceManager: DeviceManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Scroll Settings Section
                GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scroll Settings")
                        .font(.headline)
                    
                    // Reverse scroll
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reverse Scroll Direction")
                                .font(.subheadline)
                            Text("For external mice only (excludes Apple devices)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $settings.reverseScrollEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    Divider()
                    
                    // Smooth scrolling
                    HStack {
                        Image(systemName: "water.waves")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smooth Scrolling")
                                .font(.subheadline)
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
                }
                .padding(.vertical, 4)
            }
            
            // Scroll Modifiers Section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scroll Modifiers")
                        .font(.headline)
                    
                    // Shift for horizontal scroll
                    HStack {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shift + Scroll = Horizontal")
                                .font(.subheadline)
                            Text("Hold Shift to scroll side-to-side")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $settings.shiftHorizontalScroll)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    Divider()
                    
                    // Option for precision scroll
                    HStack {
                        Image(systemName: "scope")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Option + Scroll = Precision")
                                .font(.subheadline)
                            Text("Hold Option for slower, more precise scrolling")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $settings.optionPrecisionScroll)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Help text
            Text("Apple trackpads and Magic Mouse will continue to scroll naturally. Only external/Windows mice will have their scroll direction reversed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    ScrollSettingsView(settings: Settings.shared, deviceManager: DeviceManager.shared)
        .padding()
        .frame(width: 460, height: 400)
}
