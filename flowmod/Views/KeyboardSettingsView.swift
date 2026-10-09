import SwiftUI

/// Swap Option and Command on each connected external keyboard.
struct KeyboardSettingsView: View {
    var keyboardManager: KeyboardManager

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    ModifierKeysDiagram()

                    VStack(spacing: 4) {
                        Text("Mac Layout for Windows Keyboards")
                            .font(.headline)
                        Text("Swaps Option and Command so Command sits next to the space bar, the same as on a Mac keyboard.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                if keyboardManager.connectedKeyboards.isEmpty {
                    ContentUnavailableView(
                        "No External Keyboard",
                        systemImage: "keyboard",
                        description: Text("Connect a USB or Bluetooth keyboard to see it here.")
                    )
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(keyboardManager.connectedKeyboards) { keyboard in
                        Toggle(keyboardManager.displayName(for: keyboard), isOn: Binding(
                            get: { keyboardManager.isSwapped(keyboard) },
                            set: { keyboardManager.setSwapped($0, for: keyboard) }
                        ))
                    }
                }
            } header: {
                Text("External Keyboards")
            } footer: {
                if !keyboardManager.connectedKeyboards.isEmpty {
                    Text("Turn on for keyboards labeled Ctrl, Win, and Alt. Saved in System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys, so it keeps working when FlowMod is quit. Apple keyboards aren't listed.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            keyboardManager.refreshMappingState()
        }
    }
}

/// The modifier row of a Windows keyboard, with what Win and Alt do once swapped.
private struct ModifierKeysDiagram: View {
    private struct Key: Identifiable {
        let label: String
        var remap: String? = nil
        var width: CGFloat = 56
        var id: String { label }
    }

    private let keys = [
        Key(label: "ctrl"),
        Key(label: "win", remap: "⌥ Option"),
        Key(label: "alt", remap: "⌘ Command"),
        Key(label: "space", width: 160),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(keys) { key in
                VStack(spacing: 5) {
                    keycap(key)
                    // Captions may be wider than their key, so they overflow instead of widening it.
                    Text(key.remap ?? " ")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                        .fixedSize()
                }
                .frame(width: key.width)
            }
        }
        .accessibilityHidden(true)
    }

    private func keycap(_ key: Key) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let highlighted = key.remap != nil
        return Text(key.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(highlighted ? .primary : .secondary)
            .frame(width: key.width, height: 30)
            .background(.quaternary, in: shape)
            .overlay(
                shape.strokeBorder(
                    highlighted ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: 1
                )
            )
    }
}

#Preview {
    KeyboardSettingsView(keyboardManager: .shared)
        .frame(width: 560, height: 520)
}
