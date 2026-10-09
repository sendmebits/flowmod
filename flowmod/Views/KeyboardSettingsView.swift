import SwiftUI

/// Swap Option and Command on each connected external keyboard.
struct KeyboardSettingsView: View {
    var keyboardManager: KeyboardManager

    var body: some View {
        Form {
            Section {
                if keyboardManager.connectedKeyboards.isEmpty {
                    ContentUnavailableView(
                        "No External Keyboard",
                        systemImage: "keyboard",
                        description: Text("Connect a USB or Bluetooth keyboard to swap Option and Command.")
                    )
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(keyboardManager.connectedKeyboards) { keyboard in
                        Toggle(isOn: Binding(
                            get: { keyboardManager.isSwapped(keyboard) },
                            set: { keyboardManager.setSwapped($0, for: keyboard) }
                        )) {
                            Text(keyboardManager.displayName(for: keyboard))
                            Text("Swap Option and Command")
                        }
                    }
                }
            } header: {
                Text("External Keyboards")
            } footer: {
                if !keyboardManager.connectedKeyboards.isEmpty {
                    Text("Also shown in System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            keyboardManager.refreshMappingState()
        }
    }
}

#Preview {
    KeyboardSettingsView(keyboardManager: .shared)
        .frame(width: 560, height: 520)
}
