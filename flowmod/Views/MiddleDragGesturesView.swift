import SwiftUI

/// Settings for middle-button drag gestures
struct MiddleDragGesturesView: View {
    @Bindable var profile: ProfileSettings
    /// Global settings (drag threshold is shared across all mice)
    @Bindable var settings: Settings
    @State private var showingCustomShortcut: DragDirection?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Hold middle mouse button and drag in a direction to trigger an action")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            // Continuous gesture mode — shown first
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "hand.draw")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Continuous Gestures")
                                .font(.subheadline)
                            Text("Animation follows your drag like a trackpad swipe")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("Continuous Gestures", isOn: $profile.continuousGestures)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    if profile.continuousGestures {
                        Text("Works with Mission Control, App Exposé, Switch Spaces, Show Desktop, and Launchpad. Direction settings below are not used in this mode.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Direction mappings
            GroupBox {
                VStack(spacing: 0) {
                    ForEach(DragDirection.allCases) { direction in
                        directionRow(for: direction)
                        
                        if direction != DragDirection.allCases.last {
                            Divider()
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .opacity(profile.continuousGestures ? 0.5 : 1.0)
            .allowsHitTesting(!profile.continuousGestures)
            
            // Threshold slider
            GroupBox {
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

                    Text("How far to drag before a gesture triggers — shorter distances start gestures sooner. Applies to all mice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
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
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            Text(direction.rawValue)
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
