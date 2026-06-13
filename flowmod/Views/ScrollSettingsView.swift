import SwiftUI

/// Settings for scroll reversal
struct ScrollSettingsView: View {
    @Bindable var profile: ProfileSettings
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Scroll Settings Section
                GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    // Reverse scroll
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reverse Scroll Direction")
                                .font(.subheadline)
                            Text("Doesn't affect Apple trackpads or Magic Mouse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("Reverse Scroll Direction", isOn: $profile.reverseScrollEnabled)
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
                        
                        Picker("Smooth Scrolling", selection: $profile.smoothScrolling) {
                            ForEach(SmoothScrolling.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
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
                        
                        Toggle("Shift + Scroll = Horizontal", isOn: $profile.shiftHorizontalScroll)
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
                        
                        Toggle("Option + Scroll = Precision", isOn: $profile.optionPrecisionScroll)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    Divider()
                    
                    // Control for fast scroll
                    HStack {
                        Image(systemName: "hare")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Control + Scroll = Fast")
                                .font(.subheadline)
                            Text("Hold Control to scroll faster")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("Control + Scroll = Fast", isOn: $profile.controlFastScroll)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    Divider()
                    
                    // Command for zoom
                    HStack {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Command + Scroll = Zoom")
                                .font(.subheadline)
                            Text("Hold Command to zoom in and out")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("Command + Scroll = Zoom", isOn: $profile.commandZoomScroll)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    ScrollSettingsView(profile: Settings.shared.defaultProfile)
        .padding()
        .frame(width: 460, height: 400)
}
