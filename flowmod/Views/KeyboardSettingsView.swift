import SwiftUI

/// Swap Option and Command on each connected external keyboard.
struct KeyboardSettingsView: View {
    var keyboardManager: KeyboardManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsSectionHeader(title: "External Keyboards")

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            if keyboardManager.connectedKeyboards.isEmpty {
                                Text("Connect a USB or Bluetooth keyboard to swap Option and Command.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(Array(keyboardManager.connectedKeyboards.enumerated()), id: \.element.id) { index, keyboard in
                                    if index > 0 {
                                        SettingsRowDivider()
                                    }

                                    SettingsControlRow(
                                        icon: "keyboard",
                                        title: keyboardManager.displayName(for: keyboard),
                                        description: "Swap Option and Command so this keyboard matches a Mac keyboard"
                                    ) {
                                        Toggle("Swap Option and Command", isOn: Binding(
                                            get: { keyboardManager.isSwapped(keyboard) },
                                            set: { keyboardManager.setSwapped($0, for: keyboard) }
                                        ))
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if !keyboardManager.connectedKeyboards.isEmpty {
                        Text("This choice also appears in System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            keyboardManager.refreshMappingState()
        }
    }
}

#Preview {
    KeyboardSettingsView(keyboardManager: .shared)
        .padding()
        .frame(width: 460, height: 400)
}
