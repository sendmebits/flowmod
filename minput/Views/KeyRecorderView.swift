import SwiftUI
import Carbon.HIToolbox

/// A sheet for recording a keyboard shortcut
struct KeyRecorderSheet: View {
    let title: String
    let onComplete: (KeyCombo?) -> Void
    
    @State private var recordedCombo: KeyCombo?
    @State private var isRecording = true
    @State private var keyDownMonitor: Any?
    @State private var flagsChangedMonitor: Any?
    
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
        // Clean up any existing monitors first
        cleanup()
        
        // Use both local and global monitors to capture all key events
        // Local monitor for regular app events
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            return handleKeyEvent(event)
        }
        
        // Also add a global monitor to catch events that might be intercepted
        // Note: This requires accessibility permissions which the app already has
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            // We don't record modifier-only keys, but we need to track them
            // Just pass through - the actual recording happens on keyDown
            return event
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let keyCode = UInt16(event.keyCode)
        
        // Ignore escape without modifiers (used for cancel)
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
        
        // Stop monitoring after successful recording
        cleanup()
        
        return nil  // Consume the event
    }
    
    private func cleanup() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
    }
}

#Preview {
    KeyRecorderSheet(title: "Record Shortcut") { combo in
        print("Recorded: \(combo?.displayName ?? "nil")")
    }
}
