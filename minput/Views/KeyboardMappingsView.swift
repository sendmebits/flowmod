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
            
            Text("Remap Windows keyboard keys to Mac equivalents")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if settings.keyboardMappings.isEmpty {
                emptyState
            } else {
                GroupBox {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Source Key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("Target Action")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // Spacer for delete button
                            Color.clear.frame(width: 30)
                        }
                        .padding(.bottom, 8)
                        
                        Divider()
                        
                        // Mappings list
                        ForEach(settings.keyboardMappings) { mapping in
                            mappingRow(for: mapping)
                            
                            if mapping.id != settings.keyboardMappings.last?.id {
                                Divider()
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
    
    private var emptyState: some View {
        GroupBox {
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
        }
    }
    
    private func mappingRow(for mapping: KeyboardMapping) -> some View {
        HStack {
            // Source key picker
            sourceKeyPicker(for: mapping)
            
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            
            // Target action picker
            targetActionPicker(for: mapping)
            
            // Delete button
            Button {
                deleteMapping(mapping)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .frame(width: 30)
        }
        .padding(.vertical, 8)
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
            sourceKey: .home,
            targetAction: .lineStart
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
