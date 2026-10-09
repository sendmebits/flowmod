import SwiftUI

/// Identifiable wrapper for `sheet(item:)` (avoids retroactive `UUID: Identifiable` on Foundation types).
private struct CustomShortcutSheetItem: Identifiable {
    let id: UUID
}

/// Settings for mouse button remapping
struct MouseButtonsView: View {
    @Bindable var profile: ProfileSettings
    var preview: CustomizeProfileBanner? = nil
    @State private var customShortcutSheetItem: CustomShortcutSheetItem?
    @State private var showingButtonRecorder = false
    
    var body: some View {
        Form {
            if let preview {
                preview
            }

            Section {
                if profile.customMouseButtonMappings.isEmpty {
                    ContentUnavailableView {
                        Label("No Button Mappings", systemImage: "computermouse")
                    } description: {
                        Text("Assign actions or shortcuts to your mouse's extra buttons.")
                    } actions: {
                        Button("Add Button…") {
                            showingButtonRecorder = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(profile.customMouseButtonMappings) { mapping in
                        buttonRow(for: mapping)
                    }
                }
            } header: {
                Text("Mouse Buttons")
            } footer: {
                if !profile.customMouseButtonMappings.isEmpty {
                    HStack {
                        Spacer()
                        Button {
                            showingButtonRecorder = true
                        } label: {
                            Label("Add Button…", systemImage: "plus")
                        }
                    }
                }
            }
            .disabled(preview != nil)
        }
        .formStyle(.grouped)
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
        LabeledContent {
            HStack(spacing: 8) {
                actionPicker(for: mapping)

                Button {
                    deleteMapping(mapping)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove \(mapping.displayName) mapping")
                .accessibilityLabel("Remove \(mapping.displayName) mapping")
            }
        } label: {
            Label(mapping.displayName, systemImage: mapping.icon)
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
            Label(mapping.action.displayName, systemImage: mapping.action.icon)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityLabel("Action for \(mapping.displayName)")
        .accessibilityValue(mapping.action.displayName)
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
        .frame(width: 560, height: 520)
}
