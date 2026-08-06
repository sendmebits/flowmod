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
                        SettingsControlRow(
                            icon: "arrow.up.arrow.down",
                            title: "Reverse Scroll Direction",
                            description: "Doesn't affect Apple trackpads or Magic Mouse"
                        ) {
                            Toggle("Reverse Scroll Direction", isOn: $profile.reverseScrollEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Divider()

                        SettingsControlRow(
                            icon: "water.waves",
                            title: "Smooth Scrolling",
                            description: "Adds smoothing to mouse wheel scrolling"
                        ) {
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

                        SettingsControlRow(
                            icon: "arrow.left.arrow.right",
                            title: "Shift + Scroll = Horizontal",
                            description: "Hold Shift to scroll side-to-side"
                        ) {
                            Toggle("Shift + Scroll = Horizontal", isOn: $profile.shiftHorizontalScroll)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Divider()

                        SettingsControlRow(
                            icon: "scope",
                            title: "Option + Scroll = Precision",
                            description: "Hold Option for slower, more precise scrolling"
                        ) {
                            Toggle("Option + Scroll = Precision", isOn: $profile.optionPrecisionScroll)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Divider()

                        SettingsControlRow(
                            icon: "hare",
                            title: "Control + Scroll = Fast",
                            description: "Hold Control to scroll faster"
                        ) {
                            Toggle("Control + Scroll = Fast", isOn: $profile.controlFastScroll)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Divider()

                        SettingsControlRow(
                            icon: "plus.magnifyingglass",
                            title: "Command + Scroll = Zoom",
                            description: "Hold Command to zoom in and out"
                        ) {
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
