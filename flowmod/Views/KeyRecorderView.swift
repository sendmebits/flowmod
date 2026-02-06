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
