import SwiftUI

/// Settings for mouse button remapping
struct MouseButtonsView: View {
    @Bindable var settings: Settings
    @State private var showingCustomShortcutForButton: UUID?
    @State private var showingButtonRecorder = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Mouse Button Mappings")
                        .font(.headline)
                
                    Spacer()
                
                    Button {
                        showingButtonRecorder = true
                    } label: {
                        Label("Add Button", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            
                Text("Configure what each mouse button does")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            
                GroupBox {
                    if settings.customMouseButtonMappings.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "computermouse")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            
                            Text("No mouse button mappings")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            Text("Click \"Add Button\" to configure extra mouse buttons")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(settings.customMouseButtonMappings) { mapping in
                                buttonRow(for: mapping)
                            
                                if mapping.id != settings.customMouseButtonMappings.last?.id {
                                    Divider()
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $showingCustomShortcutForButton) { mappingId in
            KeyRecorderSheet(title: "Record Shortcut") { combo in
                if let combo = combo,
                   let index = settings.customMouseButtonMappings.firstIndex(where: { $0.id == mappingId }) {
                    settings.customMouseButtonMappings[index].action = .customShortcut(combo)
                }
                showingCustomShortcutForButton = nil
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
    
    private func buttonRow(for mapping: CustomMouseButtonMapping) -> some View {
        HStack {
            Image(systemName: mapping.icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            Text(mapping.displayName)
                .frame(minWidth: 150, alignment: .leading)
            
            Spacer()
            
            actionPicker(for: mapping)
            
            Button {
                deleteMapping(mapping)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func actionPicker(for mapping: CustomMouseButtonMapping) -> some View {
        Menu {
            ForEach(MouseAction.allCases) { action in
                Button {
                    updateAction(for: mapping, to: action)
                } label: {
                    Label(action.displayName, systemImage: action.icon)
                }
            }
            
            Divider()
            
            Button {
                showingCustomShortcutForButton = mapping.id
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
    
    private func updateAction(for mapping: CustomMouseButtonMapping, to action: MouseAction) {
        if let index = settings.customMouseButtonMappings.firstIndex(where: { $0.id == mapping.id }) {
            settings.customMouseButtonMappings[index].action = action
        }
    }
    
    private func deleteMapping(_ mapping: CustomMouseButtonMapping) {
        settings.customMouseButtonMappings.removeAll { $0.id == mapping.id }
    }
}

#Preview {
    MouseButtonsView(settings: Settings.shared)
        .padding()
        .frame(width: 460, height: 400)
}
