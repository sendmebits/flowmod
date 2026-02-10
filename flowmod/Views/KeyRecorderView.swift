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
    @State private var pendingModifierKeyCode: UInt16?
    @State private var peakModifierFlags: NSEvent.ModifierFlags = []
    
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
            // Pause all keyboard remapping so existing mappings don't
            // interfere with recording (important when swapping keys)
            InputInterceptor.shared.recordingPassthrough = true
            startRecording()
        }
        .onDisappear {
            cleanup()
            // Resume normal keyboard remapping
            InputInterceptor.shared.recordingPassthrough = false
        }
    }
    
    private func startRecording() {
        // Clean up any existing monitors first
        cleanup()
        
        // Reset modifier tracking state
        pendingModifierKeyCode = nil
        peakModifierFlags = []
        
        // Local monitor for regular key events
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            return handleKeyEvent(event)
        }
        
        // Monitor for modifier key presses (Control, Option, Shift, Command)
        // Modifier keys generate .flagsChanged events, not .keyDown events.
        // We record modifier-only presses when all modifiers are released
        // without any regular key being pressed in between.
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            return handleFlagsChanged(event)
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // A regular key was pressed, cancel any pending modifier-only recording
        pendingModifierKeyCode = nil
        peakModifierFlags = []
        
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
    
    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        
        let currentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = UInt16(event.keyCode)
        let keyModifierFlag = modifierFlagForKeyCode(keyCode)
        
        if currentFlags.contains(keyModifierFlag) {
            // This modifier key was just pressed — track it
            pendingModifierKeyCode = keyCode
            peakModifierFlags = peakModifierFlags.union(currentFlags)
        }
        
        // When all modifiers are released, record the modifier-only combo
        if currentFlags.isEmpty, let primaryKeyCode = pendingModifierKeyCode {
            // Build modifier flags from the peak state, excluding the primary key's own flag
            var modifiers: UInt64 = 0
            let otherFlags = peakModifierFlags.subtracting(modifierFlagForKeyCode(primaryKeyCode))
            
            if otherFlags.contains(.control) { modifiers |= CGEventFlags.maskControl.rawValue }
            if otherFlags.contains(.option) { modifiers |= CGEventFlags.maskAlternate.rawValue }
            if otherFlags.contains(.shift) { modifiers |= CGEventFlags.maskShift.rawValue }
            if otherFlags.contains(.command) { modifiers |= CGEventFlags.maskCommand.rawValue }
            
            recordedCombo = KeyCombo(keyCode: primaryKeyCode, modifiers: modifiers)
            isRecording = false
            
            // Reset state and stop monitoring
            pendingModifierKeyCode = nil
            peakModifierFlags = []
            cleanup()
            
            return nil  // Consume the event
        }
        
        return event
    }
    
    /// Maps a modifier key code to its corresponding NSEvent.ModifierFlags
    private func modifierFlagForKeyCode(_ keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch keyCode {
        case 0x37, 0x36: return .command    // Left/Right Command
        case 0x38, 0x3C: return .shift      // Left/Right Shift
        case 0x3A, 0x3D: return .option     // Left/Right Option
        case 0x3B, 0x3E: return .control    // Left/Right Control
        default: return []
        }
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

// MARK: - Mouse Button Recorder

/// Result of recording a mouse button
enum MouseButtonRecordResult: Equatable {
    case success(Int64)           // Successfully recorded button number
    case alreadyMapped(String)    // Button already has a mapping
    case primaryButton            // Can't map primary buttons
}

/// A sheet for recording a mouse button press
struct MouseButtonRecorderSheet: View {
    let title: String
    let existingButtonNumbers: Set<Int64>  // Button numbers that already have mappings
    let onComplete: (MouseButtonRecordResult?) -> Void
    
    @State private var recordedButton: Int64?
    @State private var recordResult: MouseButtonRecordResult?
    @State private var isRecording = true
    @State private var mouseMonitor: Any?
    @State private var globalMouseMonitor: Any?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text(title)
                .font(.headline)
            
            // Recording area
            VStack(spacing: 12) {
                if isRecording {
                    VStack(spacing: 8) {
                        Image(systemName: "computermouse")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.pulse)
                        
                        Text("Click a mouse button...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if let result = recordResult {
                    switch result {
                    case .success(let buttonNum):
                        VStack(spacing: 8) {
                            Text("Mouse Button \(buttonNum + 1)")
                                .font(.system(size: 32, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                            
                            Text("Button recorded")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    case .alreadyMapped(let name):
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.yellow)
                            
                            Text("Already Mapped")
                                .font(.headline)
                            
                            Text("\(name) is already configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .primaryButton:
                        VStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.red)
                            
                            Text("Cannot Map")
                                .font(.headline)
                            
                            Text("Primary mouse buttons cannot be remapped")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: 280, height: 120)
            .background(.quaternary)
            .cornerRadius(12)
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    cleanup()
                    onComplete(nil)
                }
                .buttonStyle(.bordered)
                
                if !isRecording {
                    Button("Try Again") {
                        recordedButton = nil
                        recordResult = nil
                        isRecording = true
                        startRecording()
                    }
                    .buttonStyle(.bordered)
                }
                
                if case .success = recordResult {
                    Button("Add") {
                        cleanup()
                        onComplete(recordResult)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 350)
        .onAppear {
            startRecording()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func startRecording() {
        cleanup()
        
        // Monitor for mouse button clicks (other mouse buttons)
        // Local monitor for events in the app
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .leftMouseDown, .rightMouseDown]) { event in
            return handleMouseEvent(event)
        }
        
        // Global monitor for events outside the app (needed because sheet might not capture all local events)
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { event in
            Task { @MainActor in
                _ = handleMouseEvent(event)
            }
        }
    }
    
    private func handleMouseEvent(_ event: NSEvent) -> NSEvent? {
        let buttonNumber = Int64(event.buttonNumber)
        
        recordedButton = buttonNumber
        isRecording = false
        cleanup()
        
        // Check if it's a primary button (left/right click)
        if MouseButton.isPrimaryButton(buttonNumber) {
            recordResult = .primaryButton
            return nil
        }
        
        // Check if it's already in custom mappings
        if existingButtonNumbers.contains(buttonNumber) {
            recordResult = .alreadyMapped("Mouse Button \(buttonNumber + 1)")
            return nil
        }
        
        recordResult = .success(buttonNumber)
        return nil
    }
    
    private func cleanup() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }
}

#Preview {
    KeyRecorderSheet(title: "Record Shortcut") { combo in
        print("Recorded: \(combo?.displayName ?? "nil")")
    }
}
