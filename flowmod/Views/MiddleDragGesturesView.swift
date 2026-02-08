import SwiftUI

/// Settings for middle-button drag gestures
struct MiddleDragGesturesView: View {
    @Bindable var settings: Settings
    @State private var showingCustomShortcut: DragDirection?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Middle Button Drag Gestures")
                    .font(.headline)
            
                Text("Hold middle mouse button and drag in a direction to trigger an action")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            
            // Continuous gesture mode — shown first
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "hand.draw")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Continuous Gestures")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Animation follows your drag like a trackpad swipe")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $settings.continuousGestures)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    if settings.continuousGestures {
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
            .opacity(settings.continuousGestures ? 0.5 : 1.0)
            .allowsHitTesting(!settings.continuousGestures)
            
            // Threshold slider
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Drag Sensitivity")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(settings.dragThreshold))px")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(value: $settings.dragThreshold, in: 20...100, step: 5)
                    
                    Text("Distance you need to drag before triggering the gesture")
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
                    settings.middleDragMappings[direction] = .customShortcut(combo)
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
            get: { settings.middleDragMappings[direction] ?? .none },
            set: { newValue in
                if case .customShortcut = newValue {
                    showingCustomShortcut = direction
                } else {
                    settings.middleDragMappings[direction] = newValue
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
                Label("Custom Shortcut...", systemImage: "keyboard")
            }
        } label: {
            HStack {
                let action = settings.middleDragMappings[direction] ?? .none
                Image(systemName: action.icon)
                Text(action.displayName)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary)
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
    }
}

#Preview {
    MiddleDragGesturesView(settings: Settings.shared)
        .padding()
        .frame(width: 460, height: 400)
}
