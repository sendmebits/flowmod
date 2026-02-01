import SwiftUI

/// Settings for keyboard key remapping
struct KeyboardMappingsView: View {
    @Bindable var settings: Settings
    @State private var showingSourceRecorder: UUID?
    @State private var showingTargetRecorder: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Keyboard Mappings")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    addMapping()
                } label: {
                    Label("Add Mapping", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Text("Remap Windows keyboard keys to macOS equivalents")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            GroupBox {
                if settings.keyboardMappings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        
                        Text("No keyboard mappings")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Text("Click \"Add Mapping\" to remap Windows keyboard keys")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(settings.keyboardMappings) { mapping in
                            mappingRow(for: mapping)
                            
                            if mapping.id != settings.keyboardMappings.last?.id {
                                Divider()
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Spacer()
        }
        .sheet(item: $showingSourceRecorder) { id in
            KeyRecorderSheet(title: "Press a Key to Map") { combo in
                if let combo = combo, let index = settings.keyboardMappings.firstIndex(where: { $0.id == id }) {
                    settings.keyboardMappings[index].sourceKey = .custom
                    settings.keyboardMappings[index].customSourceKeyCode = combo.keyCode
                }
                showingSourceRecorder = nil
            }
        }
        .sheet(item: $showingTargetRecorder) { id in
            KeyRecorderSheet(title: "Record Target Shortcut") { combo in
                if let combo = combo, let index = settings.keyboardMappings.firstIndex(where: { $0.id == id }) {
                    settings.keyboardMappings[index].targetAction = .customShortcut(combo)
                }
                showingTargetRecorder = nil
            }
        }
    }
    

    
    private func mappingRow(for mapping: KeyboardMapping) -> some View {
        HStack {
            // Icon for the source key
            Image(systemName: "command.square")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            // Source key picker (styled as text, clickable)
            sourceKeyPicker(for: mapping)
                .frame(minWidth: 100, alignment: .leading)
            
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
            
            Spacer()
            
            // Target action picker
            targetActionPicker(for: mapping)
            
            // Delete button
            Button {
                deleteMapping(mapping)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func sourceKeyPicker(for mapping: KeyboardMapping) -> some View {
        Menu {
            ForEach(SourceKey.allCases.filter { $0 != .custom }) { key in
                Button {
                    updateSourceKey(for: mapping, to: key)
                } label: {
                    Text(key.rawValue)
                }
            }
            
            Divider()
            
            Button {
                showingSourceRecorder = mapping.id
            } label: {
                Label("Record Key...", systemImage: "keyboard")
            }
        } label: {
            HStack {
                Text(mapping.sourceDisplayName)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary)
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
    }
    
    private func targetActionPicker(for mapping: KeyboardMapping) -> some View {
        Menu {
            ForEach(KeyboardAction.allCases) { action in
                Button {
                    updateTargetAction(for: mapping, to: action)
                } label: {
                    Label(action.displayName, systemImage: action.icon)
                }
            }
            
            Divider()
            
            Button {
                showingTargetRecorder = mapping.id
            } label: {
                Label("Custom Shortcut...", systemImage: "keyboard")
            }
        } label: {
            HStack {
                Image(systemName: mapping.targetAction.icon)
                Text(mapping.targetAction.displayName)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary)
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
    }
    
    private func addMapping() {
        let newMapping = KeyboardMapping(
            sourceKey: .none,
            targetAction: .none
        )
        settings.keyboardMappings.append(newMapping)
    }
    
    private func deleteMapping(_ mapping: KeyboardMapping) {
        settings.keyboardMappings.removeAll { $0.id == mapping.id }
    }
    
    private func updateSourceKey(for mapping: KeyboardMapping, to key: SourceKey) {
        if let index = settings.keyboardMappings.firstIndex(where: { $0.id == mapping.id }) {
            settings.keyboardMappings[index].sourceKey = key
            settings.keyboardMappings[index].customSourceKeyCode = nil
        }
    }
    
    private func updateTargetAction(for mapping: KeyboardMapping, to action: KeyboardAction) {
        if let index = settings.keyboardMappings.firstIndex(where: { $0.id == mapping.id }) {
            settings.keyboardMappings[index].targetAction = action
        }
    }
}

// MARK: - UUID extension for sheet presentation
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

#Preview {
    KeyboardMappingsView(settings: Settings.shared)
        .padding()
        .frame(width: 460, height: 400)
}
