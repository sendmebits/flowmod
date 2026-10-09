import SwiftUI

/// Settings for middle-button drag gestures
struct MiddleDragGesturesView: View {
    @Bindable var profile: ProfileSettings
    /// Global settings (drag threshold is shared across all mice)
    @Bindable var settings: Settings
    /// When set, profile controls are read-only; the shared drag distance stays editable.
    var preview: CustomizeProfileBanner? = nil
    @State private var showingCustomShortcut: DragDirection?

    private var profileControlsDisabled: Bool { preview != nil }
    
    var body: some View {
        Form {
            if let preview {
                preview
            }

            Section {
                Toggle("Continuous Gestures", isOn: $profile.continuousGestures)
            } header: {
                Text("Middle-Button Drag")
            } footer: {
                Text("Follows your drag like a trackpad swipe: up for Mission Control, down for App Exposé, left and right to switch Spaces.")
            }
            .disabled(profileControlsDisabled)

            Section {
                ForEach(DragDirection.allCases) { direction in
                    LabeledContent {
                        actionPicker(for: direction)
                    } label: {
                        Label(direction.rawValue, systemImage: direction.icon)
                    }
                }
            } header: {
                Text("Drag Actions")
            } footer: {
                if profile.continuousGestures {
                    Text("Not used while Continuous Gestures is on.")
                }
            }
            .disabled(profile.continuousGestures || profileControlsDisabled)

            Section {
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: $settings.dragThreshold, in: 10...100, step: 5) {
                            Text("Drag Distance")
                        }
                        .labelsHidden()
                        .accessibilityValue("\(Int(settings.dragThreshold)) pixels")

                        Text("\(Int(settings.dragThreshold)) px")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: 260)
                } label: {
                    Text("Drag Distance")
                }
            } footer: {
                Text("How far to drag before a gesture starts. Applies to all mice.")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $showingCustomShortcut) { direction in
            KeyRecorderSheet(title: "Record Shortcut for \(direction.rawValue)") { combo in
                if let combo = combo {
                    profile.middleDragMappings[direction] = .customShortcut(combo)
                }
                showingCustomShortcut = nil
            }
        }
    }
    
    private func actionPicker(for direction: DragDirection) -> some View {
        let binding = Binding<MouseAction>(
            get: { profile.middleDragMappings[direction] ?? .none },
            set: { newValue in
                if case .customShortcut = newValue {
                    showingCustomShortcut = direction
                } else {
                    profile.middleDragMappings[direction] = newValue
                }
            }
        )
        let currentAction = binding.wrappedValue
        
        return Menu {
            ForEach(MouseAction.allCases) { action in
                Button {
                    binding.wrappedValue = action
                } label: {
                    Label(action.displayName, systemImage: action.icon)
                }
            }
            
            Divider()
            
            Button {
                showingCustomShortcut = direction
            } label: {
                Label("Custom Shortcut…", systemImage: "keyboard")
            }
        } label: {
            Label(currentAction.displayName, systemImage: currentAction.icon)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityLabel("Action for \(direction.rawValue)")
        .accessibilityValue(currentAction.displayName)
    }
}

#Preview {
    MiddleDragGesturesView(profile: Settings.shared.defaultProfile, settings: Settings.shared)
        .frame(width: 560, height: 520)
}
