import SwiftUI

/// Settings for mouse button remapping
struct MouseButtonsView: View {
    @Bindable var settings: Settings
    @State private var showingCustomShortcut: MouseButton?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mouse Button Mappings")
                .font(.headline)
            
            Text("Configure what each mouse button does")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            GroupBox {
                VStack(spacing: 0) {
                    ForEach(MouseButton.allCases) { button in
                        buttonRow(for: button)
                        
                        if button != MouseButton.allCases.last {
                            Divider()
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            Spacer()
        }
        .sheet(item: $showingCustomShortcut) { button in
            KeyRecorderSheet(title: "Record Shortcut for \(button.rawValue)") { combo in
                if let combo = combo {
                    settings.mouseButtonMappings[button] = .customShortcut(combo)
                }
                showingCustomShortcut = nil
            }
        }
    }
    
    private func buttonRow(for button: MouseButton) -> some View {
        HStack {
            Image(systemName: button.icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            Text(button.rawValue)
                .frame(minWidth: 150, alignment: .leading)
            
            Spacer()
            
            actionPicker(for: button)
        }
    }
    
    private func actionPicker(for button: MouseButton) -> some View {
        let binding = Binding<MouseAction>(
            get: { settings.mouseButtonMappings[button] ?? .none },
            set: { newValue in
                if case .customShortcut = newValue {
                    showingCustomShortcut = button
                } else {
                    settings.mouseButtonMappings[button] = newValue
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
                showingCustomShortcut = button
            } label: {
                Label("Custom Shortcut...", systemImage: "keyboard")
            }
        } label: {
            HStack {
                let action = settings.mouseButtonMappings[button] ?? .none
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
    MouseButtonsView(settings: Settings.shared)
        .padding()
        .frame(width: 460, height: 350)
}
