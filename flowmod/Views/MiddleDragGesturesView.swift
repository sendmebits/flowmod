import SwiftUI

/// Settings for middle-button drag gestures
struct MiddleDragGesturesView: View {
    @Bindable var profile: ProfileSettings
    /// Global settings (drag threshold is shared across all mice)
    @Bindable var settings: Settings
    var profileControlsDisabled = false
    @State private var showingCustomShortcut: DragDirection?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Continuous gesture mode — shown first
                VStack(alignment: .leading, spacing: 6) {
                    SettingsSectionHeader(title: "Gesture Mode")

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsControlRow(
                                icon: "hand.draw",
                                title: "Continuous Gestures",
                                description: "Animation follows your drag like a trackpad swipe"
                            ) {
                                Toggle("Continuous Gestures", isOn: $profile.continuousGestures)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }

                            if profile.continuousGestures {
                                Text("Mimics three-finger trackpad swipes: up opens Mission Control, down opens App Exposé, and left or right switches Spaces. Direction settings below are not used in this mode.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .opacity(profileControlsDisabled ? 0.5 : 1.0)
                .disabled(profileControlsDisabled)

                // Direction mappings
                VStack(alignment: .leading, spacing: 6) {
                    SettingsSectionHeader(title: "Direction Actions")

                    GroupBox {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(DragDirection.allCases) { direction in
                                directionRow(for: direction)

                                if direction != DragDirection.allCases.last {
                                    SettingsRowDivider()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .opacity(profile.continuousGestures || profileControlsDisabled ? 0.5 : 1.0)
                .disabled(profile.continuousGestures || profileControlsDisabled)

                // Threshold slider
                VStack(alignment: .leading, spacing: 6) {
                    SettingsSectionHeader(title: "Gesture Threshold")

                    GroupBox {
                        HStack(alignment: .top) {
                            Image(systemName: "arrow.left.and.right")
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Drag Distance")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(Int(settings.dragThreshold))px")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Slider(value: $settings.dragThreshold, in: 10...100, step: 5) {
                                    Text("Drag Distance")
                                }
                                .labelsHidden()

                                Text("How far to drag before a gesture triggers. Shorter distances start gestures sooner. Applies to all mice.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $showingCustomShortcut) { direction in
            KeyRecorderSheet(title: "Record Shortcut for Drag \(direction.rawValue)") { combo in
                if let combo = combo {
                    profile.middleDragMappings[direction] = .customShortcut(combo)
                }
                showingCustomShortcut = nil
            }
        }
    }
    
    private func directionRow(for direction: DragDirection) -> some View {
        HStack {
            Image(systemName: direction.icon)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            Text(direction.rawValue)
                .font(.subheadline)
                .frame(minWidth: 100, alignment: .leading)
            
            Spacer()
            
            actionPicker(for: direction)
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
            HStack {
                let action = profile.middleDragMappings[direction] ?? .none
                Image(systemName: action.icon)
                Text(action.displayName)
                    .lineLimit(1)
            }
        }
        .fixedSize()
    }
}

#Preview {
    MiddleDragGesturesView(profile: Settings.shared.defaultProfile, settings: Settings.shared)
        .padding()
        .frame(width: 460, height: 400)
}
