import SwiftUI

/// Settings for mouse button remapping
struct MouseButtonsView: View {
    @Bindable var settings: Settings
    @State private var showingCustomShortcut: MouseButton?
    @State private var showingCustomShortcutForCustomButton: UUID?
    @State private var showingButtonRecorder = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Mouse Button Mappings")
                    .font(.headline)
                
                Spacer()
                
                Menu {
                    Button {
                        showingButtonRecorder = true
                    } label: {
                        Label("Record New Button...", systemImage: "record.circle")
                    }
                    
                    if !settings.removedBuiltInButtons.isEmpty {
                        Divider()
                        
                        ForEach(Array(settings.removedBuiltInButtons).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { button in
                            Button {
                                restoreBuiltInButton(button)
                            } label: {
                                Label("Restore \(button.rawValue)", systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
                } label: {
                    Label("Add Button", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            
            Text("Configure what each mouse button does")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            GroupBox {
                VStack(spacing: 0) {
                    // Built-in buttons (excluding removed ones)
                    let visibleBuiltInButtons = MouseButton.allCases.filter { !settings.removedBuiltInButtons.contains($0) }
                    ForEach(visibleBuiltInButtons) { button in
                        buttonRow(for: button)
                        
                        if button != visibleBuiltInButtons.last || !settings.customMouseButtonMappings.isEmpty {
                            Divider()
                                .padding(.vertical, 8)
                        }
                    }
                    
                    // Custom buttons
                    ForEach(settings.customMouseButtonMappings) { mapping in
                        customButtonRow(for: mapping)
                        
                        if mapping.id != settings.customMouseButtonMappings.last?.id {
                            Divider()
                                .padding(.vertical, 8)
                        }
                    }
                    
                    // Show empty state if nothing visible
                    if visibleBuiltInButtons.isEmpty && settings.customMouseButtonMappings.isEmpty {
                        Text("No mouse buttons configured")
                            .foregroundStyle(.secondary)
                            .padding()
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
        .sheet(item: $showingCustomShortcutForCustomButton) { mappingId in
            KeyRecorderSheet(title: "Record Shortcut") { combo in
                if let combo = combo,
                   let index = settings.customMouseButtonMappings.firstIndex(where: { $0.id == mappingId }) {
                    settings.customMouseButtonMappings[index].action = .customShortcut(combo)
                }
                showingCustomShortcutForCustomButton = nil
            }
        }
        .sheet(isPresented: $showingButtonRecorder) {
            MouseButtonRecorderSheet(
                title: "Record Mouse Button",
                existingButtonNumbers: settings.customMappedButtonNumbers
            ) { result in
                showingButtonRecorder = false
                if case .success(let buttonNumber) = result {
                    let newMapping = CustomMouseButtonMapping(
                        buttonNumber: buttonNumber,
                        action: .none
                    )
                    settings.customMouseButtonMappings.append(newMapping)
                }
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
            
            Button {
                deleteBuiltInButton(button)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func customButtonRow(for mapping: CustomMouseButtonMapping) -> some View {
        HStack {
            Image(systemName: mapping.icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            Text(mapping.displayName)
                .frame(minWidth: 150, alignment: .leading)
            
            Spacer()
            
            customActionPicker(for: mapping)
            
            Button {
                deleteCustomMapping(mapping)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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
    
    private func customActionPicker(for mapping: CustomMouseButtonMapping) -> some View {
        Menu {
            ForEach(MouseAction.allCases) { action in
                Button {
                    updateCustomAction(for: mapping, to: action)
                } label: {
                    Label(action.displayName, systemImage: action.icon)
                }
            }
            
            Divider()
            
            Button {
                showingCustomShortcutForCustomButton = mapping.id
            } label: {
                Label("Custom Shortcut...", systemImage: "keyboard")
            }
        } label: {
            HStack {
                Image(systemName: mapping.action.icon)
                Text(mapping.action.displayName)
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
    
    private func updateCustomAction(for mapping: CustomMouseButtonMapping, to action: MouseAction) {
        if let index = settings.customMouseButtonMappings.firstIndex(where: { $0.id == mapping.id }) {
            settings.customMouseButtonMappings[index].action = action
        }
    }
    
    private func deleteCustomMapping(_ mapping: CustomMouseButtonMapping) {
        settings.customMouseButtonMappings.removeAll { $0.id == mapping.id }
    }
    
    private func deleteBuiltInButton(_ button: MouseButton) {
        settings.removedBuiltInButtons.insert(button)
        settings.mouseButtonMappings.removeValue(forKey: button)
    }
    
    private func restoreBuiltInButton(_ button: MouseButton) {
        settings.removedBuiltInButtons.remove(button)
        // Restore default action
        switch button {
        case .back:
            settings.mouseButtonMappings[button] = .back
        case .forward:
            settings.mouseButtonMappings[button] = .forward
        case .middleClick:
            settings.mouseButtonMappings[button] = .middleClick
        }
    }
}

#Preview {
    MouseButtonsView(settings: Settings.shared)
        .padding()
        .frame(width: 460, height: 400)
}
