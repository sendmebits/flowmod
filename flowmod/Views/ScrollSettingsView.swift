import SwiftUI

/// Settings for scroll direction, smoothing, and modifier-key behaviors
struct ScrollSettingsView: View {
    @Bindable var profile: ProfileSettings
    var preview: CustomizeProfileBanner? = nil
    
    var body: some View {
        Form {
            if let preview {
                preview
            }

            Group {
                Section {
                    Toggle("Reverse Scroll Direction", isOn: $profile.reverseScrollEnabled)

                    Picker("Smooth Scrolling", selection: $profile.smoothScrolling) {
                        ForEach(SmoothScrolling.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle(isOn: $profile.preciseScrolling) {
                        Text("Precise Scrolling")
                        Text("Slower scrolling for finer control")
                    }
                } header: {
                    Text("Scrolling")
                } footer: {
                    Text("Apple trackpads and Magic Mouse aren't affected.")
                }

                Section {
                    modifierToggle("Horizontal Scrolling", key: "⇧ Shift", isOn: $profile.shiftHorizontalScroll)
                    modifierToggle("Precision Scrolling", key: "⌥ Option", isOn: $profile.optionPrecisionScroll)
                    modifierToggle("Fast Scrolling", key: "⌃ Control", isOn: $profile.controlFastScroll)
                    modifierToggle("Zoom", key: "⌘ Command", isOn: $profile.commandZoomScroll)
                } header: {
                    Text("Modifier Keys")
                } footer: {
                    Text("Hold the key while scrolling.")
                }
            }
            .disabled(preview != nil)
        }
        .formStyle(.grouped)
    }

    private func modifierToggle(_ title: String, key: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
            Text(key)
        }
        .accessibilityHint("Hold \(key.dropFirst(2)) while scrolling")
    }
}

#Preview {
    ScrollSettingsView(profile: Settings.shared.defaultProfile)
        .frame(width: 560, height: 520)
}
