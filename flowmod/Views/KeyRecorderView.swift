import SwiftUI

/// Shared layout for the recorder sheets: title, recording area, trailing buttons.
private struct RecorderSheetChrome<Area: View, Buttons: View>: View {
    let title: String
    @ViewBuilder let area: Area
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.headline)

            area
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 8) {
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

/// Large symbol plus caption used in the recording area.
private struct RecorderStatus: View {
    let systemImage: String
    var tint: Color = .accentColor
    var pulses = false
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: pulses)

            Text(title)
                .font(detail == nil ? .callout : .headline)
                .foregroundStyle(detail == nil ? .secondary : .primary)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Recorded value shown large in the recording area.
private struct RecorderResult: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Label(caption, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 16)
    }
}

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
        RecorderSheetChrome(title: title) {
            if isRecording {
                RecorderStatus(systemImage: "keyboard", pulses: true, title: "Press a key combination…")
            } else if let combo = recordedCombo {
                RecorderResult(value: combo.displayName, caption: "Shortcut recorded")
            }
        } buttons: {
            if !isRecording {
                Button("Try Again") {
                    recordedCombo = nil
                    isRecording = true
                    startRecording()
                }
            }

            Button("Cancel") {
                cleanup()
                onComplete(nil)
            }
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                cleanup()
                onComplete(recordedCombo)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(recordedCombo == nil)
        }
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
        
        let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        recordedCombo = combo
        isRecording = false
        AccessibilityNotification.Announcement("Recorded \(combo.displayName)").post()
        
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
            
            let combo = KeyCombo(keyCode: primaryKeyCode, modifiers: modifiers)
            recordedCombo = combo
            isRecording = false
            AccessibilityNotification.Announcement("Recorded \(combo.displayName)").post()
            
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
    
    @State private var recordResult: MouseButtonRecordResult?
    @State private var isRecording = true
    @State private var mouseMonitor: Any?
    @State private var globalMouseMonitor: Any?
    @State private var interceptorBypassActive = false

    private var canAdd: Bool {
        if case .success = recordResult { return true }
        return false
    }
    
    var body: some View {
        RecorderSheetChrome(title: title) {
            if isRecording {
                RecorderStatus(systemImage: "computermouse", pulses: true, title: "Click a mouse button…")
            } else if let result = recordResult {
                switch result {
                case .success(let buttonNum):
                    RecorderResult(value: "Mouse Button \(buttonNum + 1)", caption: "Button recorded")
                case .alreadyMapped(let name):
                    RecorderStatus(
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .yellow,
                        title: "Already Mapped",
                        detail: "\(name) is already configured."
                    )
                case .primaryButton:
                    RecorderStatus(
                        systemImage: "xmark.circle.fill",
                        tint: .red,
                        title: "Can't Remap This Button",
                        detail: "Left and right click can't be remapped."
                    )
                }
            }
        } buttons: {
            if !isRecording {
                Button("Try Again") {
                    recordResult = nil
                    isRecording = true
                    startRecording()
                }
            }

            Button("Cancel") {
                cleanup()
                onComplete(nil)
            }
            .keyboardShortcut(.cancelAction)

            Button("Add") {
                cleanup()
                onComplete(recordResult)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canAdd)
        }
        .onAppear {
            startRecording()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func startRecording() {
        cleanup()

        if !interceptorBypassActive {
            InputInterceptor.shared.beginMouseButtonRecording()
            interceptorBypassActive = true
        }
        
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
        
        isRecording = false
        // Keep the interceptor bypass active until the sheet is dismissed so
        // the matching physical mouse-up also passes through. Ending bypass on
        // mouse-down can produce an orphan/synthetic up, especially for middle click.
        stopEventMonitors()
        
        // Check if it's a primary button (left/right click)
        if buttonNumber == 0 || buttonNumber == 1 {
            recordResult = .primaryButton
            AccessibilityNotification.Announcement("Primary mouse buttons cannot be remapped").post()
            return nil
        }
        
        // Check if it's already in custom mappings
        if existingButtonNumbers.contains(buttonNumber) {
            recordResult = .alreadyMapped("Mouse Button \(buttonNumber + 1)")
            AccessibilityNotification.Announcement("Mouse Button \(buttonNumber + 1) is already configured").post()
            return nil
        }
        
        recordResult = .success(buttonNumber)
        AccessibilityNotification.Announcement("Mouse Button \(buttonNumber + 1) recorded").post()
        return nil
    }
    
    private func cleanup() {
        stopEventMonitors()
        if interceptorBypassActive {
            InputInterceptor.shared.endMouseButtonRecording()
            interceptorBypassActive = false
        }
    }

    private func stopEventMonitors() {
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
