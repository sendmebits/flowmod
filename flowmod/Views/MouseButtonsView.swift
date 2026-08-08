import SwiftUI

/// Identifiable wrapper for `sheet(item:)` (avoids retroactive `UUID: Identifiable` on Foundation types).
private struct CustomShortcutSheetItem: Identifiable {
    let id: UUID
}

/// Settings for mouse button remapping
struct MouseButtonsView: View {
    @Bindable var profile: ProfileSettings
    @State private var customShortcutSheetItem: CustomShortcutSheetItem?
    @State private var showingButtonRecorder = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    SettingsSectionHeader(title: "Mouse Buttons")
                    Spacer()

                    if !profile.customMouseButtonMappings.isEmpty {
                        Button {
                            showingButtonRecorder = true
                        } label: {
                            Label("Add Button…", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                GroupBox {
                    if profile.customMouseButtonMappings.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "computermouse")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            
                            Text("No mouse button mappings")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            Text("Configure extra mouse buttons with custom actions or shortcuts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button {
                                showingButtonRecorder = true
                            } label: {
                                Label("Add Button…", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(profile.customMouseButtonMappings) { mapping in
                                buttonRow(for: mapping)
                            
                                if mapping.id != profile.customMouseButtonMappings.last?.id {
                                    SettingsRowDivider()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $customShortcutSheetItem) { item in
            KeyRecorderSheet(title: "Record Shortcut") { combo in
                if let combo = combo,
                   let index = profile.customMouseButtonMappings.firstIndex(where: { $0.id == item.id }) {
                    profile.customMouseButtonMappings[index].action = .customShortcut(combo)
                }
                customShortcutSheetItem = nil
            }
        }
        .sheet(isPresented: $showingButtonRecorder) {
            MouseButtonRecorderSheet(
                title: "Record Mouse Button",
                existingButtonNumbers: profile.customMappedButtonNumbers
            ) { result in
                showingButtonRecorder = false
                if case .success(let buttonNumber) = result {
                    let newMapping = CustomMouseButtonMapping(
                        buttonNumber: buttonNumber,
                        // Middle button defaults to a working middle-click;
                        // side buttons default to Back, a common remap.
                        action: buttonNumber == 2 ? .middleClick : .back
                    )
                    profile.customMouseButtonMappings.append(newMapping)
                }
            }
        }
    }
    
    private func buttonRow(for mapping: CustomMouseButtonMapping) -> some View {
        HStack {
            Image(systemName: mapping.icon)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            Text(mapping.displayName)
                .font(.subheadline)
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
            .help("Remove \(mapping.displayName) mapping")
            .accessibilityLabel("Remove \(mapping.displayName) mapping")
            .accessibilityHint("Deletes this mouse button mapping")
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
                customShortcutSheetItem = CustomShortcutSheetItem(id: mapping.id)
            } label: {
                Label("Custom Shortcut…", systemImage: "keyboard")
            }
        } label: {
            HStack {
                Image(systemName: mapping.action.icon)
                Text(mapping.action.displayName)
                    .lineLimit(1)
            }
        }
        .fixedSize()
    }
    
    private func updateAction(for mapping: CustomMouseButtonMapping, to action: MouseAction) {
        if let index = profile.customMouseButtonMappings.firstIndex(where: { $0.id == mapping.id }) {
            profile.customMouseButtonMappings[index].action = action
        }
    }
    
    private func deleteMapping(_ mapping: CustomMouseButtonMapping) {
        profile.customMouseButtonMappings.removeAll { $0.id == mapping.id }
    }
}

#Preview {
    MouseButtonsView(profile: Settings.shared.defaultProfile)
        .padding()
        .frame(width: 460, height: 400)
}
