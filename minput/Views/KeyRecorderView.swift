import SwiftUI
import Carbon.HIToolbox

/// A sheet for recording a keyboard shortcut
struct KeyRecorderSheet: View {
    let title: String
    let onComplete: (KeyCombo?) -> Void
    
    @State private var recordedCombo: KeyCombo?
    @State private var isRecording = true
    @State private var eventMonitor: Any?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text(title)
                .font(.headline)
            
            // Recording area
            VStack(spacing: 12) {
                if isRecording {
                    VStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.pulse)
                        
                        Text("Press a key combination...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if let combo = recordedCombo {
                    VStack(spacing: 8) {
                        Text(combo.displayName)
                            .font(.system(size: 32, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("Key recorded")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .frame(width: 250, height: 100)
            .background(.quaternary)
            .cornerRadius(12)
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    cleanup()
                    onComplete(nil)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                
                if !isRecording {
                    Button("Try Again") {
                        recordedCombo = nil
                        isRecording = true
                        startRecording()
                    }
                    .buttonStyle(.bordered)
                }
                
                Button("Save") {
                    cleanup()
                    onComplete(recordedCombo)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(recordedCombo == nil)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onAppear {
            startRecording()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func startRecording() {
        // Use local event monitor to capture key presses
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let keyCode = UInt16(event.keyCode)
            
            // Ignore escape (used for cancel)
            if keyCode == 0x35 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                return event
            }
            
            // Ignore return/enter without modifiers (used for save)
            if (keyCode == 0x24 || keyCode == 0x4C) && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                return event
            }
            
            // Build modifier flags
            var modifiers: UInt64 = 0
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            if flags.contains(.control) {
                modifiers |= CGEventFlags.maskControl.rawValue
            }
            if flags.contains(.option) {
                modifiers |= CGEventFlags.maskAlternate.rawValue
            }
            if flags.contains(.shift) {
                modifiers |= CGEventFlags.maskShift.rawValue
            }
            if flags.contains(.command) {
                modifiers |= CGEventFlags.maskCommand.rawValue
            }
            
            recordedCombo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
            isRecording = false
            
            return nil  // Consume the event
        }
    }
    
    private func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

/// A button that shows a key recorder inline
struct KeyRecorderButton: View {
    let currentCombo: KeyCombo?
    let onRecord: () -> Void
    
    var body: some View {
        Button {
            onRecord()
        } label: {
            HStack {
                if let combo = currentCombo {
                    Text(combo.displayName)
                } else {
                    Text("Record...")
                        .foregroundStyle(.secondary)
                }
                
                Image(systemName: "record.circle")
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    KeyRecorderSheet(title: "Record Shortcut") { combo in
        print("Recorded: \(combo?.displayName ?? "nil")")
    }
}
