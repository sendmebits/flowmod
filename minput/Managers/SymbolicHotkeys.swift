import Foundation
import CoreGraphics
import Carbon.HIToolbox
import AppKit

/// Wrapper for macOS private CGS Symbolic Hotkeys API
/// These APIs allow triggering system-level actions like Mission Control, Spaces switching, etc.

// MARK: - Private CGS API Declarations

/// CGS connection type
typealias CGSConnectionID = Int

/// Get the default connection to the window server
@_silgen_name("_CGSDefaultConnection")
func CGSDefaultConnection() -> CGSConnectionID

/// Private Dock API to trigger space switching
@_silgen_name("CoreDockSendNotification")
func CoreDockSendNotification(_ notification: CFString, _ unknown: UnsafeMutableRawPointer?) -> Int32

// MARK: - Symbolic Hotkeys

/// Enum representing macOS system-level symbolic hotkeys
/// Values correspond to the symbolic hotkey IDs used by the CGS API
enum SymbolicHotKey: Int32 {
    // Mission Control family
    case missionControl = 32                // F3 or Ctrl+Up - Mission Control
    case applicationWindows = 33            // Ctrl+Down - App Exposé (Application Windows)
    case showDesktop = 36                   // F11 - Show Desktop
    case moveLeftASpace = 79                // Ctrl+Left - Move left a space
    case moveRightASpace = 81               // Ctrl+Right - Move right a space
    
    // Launchpad & Dock
    case launchpad = 160                    // F4 - Launchpad
    case showNotificationCenter = 163       // Notification Center
    
    // Spotlight
    case spotlightSearch = 64               // Cmd+Space - Spotlight
    case finderSearch = 65                  // Cmd+Option+Space - Finder search
    
    // Screenshots
    case screenshotFullScreen = 28          // Cmd+Shift+3
    case screenshotSelection = 29           // Cmd+Shift+4
    case screenshotWindow = 30              // Cmd+Shift+4, then Space
    case screenshotTouch = 31               // Cmd+Shift+5
    
    // Display
    case decreaseDisplayBrightness = 53
    case increaseDisplayBrightness = 54
}

/// Marker for synthetic events to avoid re-processing by InputInterceptor
private let syntheticEventMarker: Int64 = 0x4D494E505554  // "MINPUT" in hex

/// Utility struct for posting symbolic hotkey events
struct SymbolicHotkeys {
    
    /// Post a symbolic hotkey event to trigger a system action
    /// - Parameter hotkey: The symbolic hotkey to trigger
    static func post(_ hotkey: SymbolicHotKey) {
        switch hotkey {
        case .moveLeftASpace:
            // Use NX system-defined event for space switching left
            postSpaceSwitchEvent(direction: .left)
            
        case .moveRightASpace:
            // Use NX system-defined event for space switching right
            postSpaceSwitchEvent(direction: .right)
            
        case .applicationWindows:
            // App Exposé - use dedicated key code 0xA1 (161)
            postDedicatedKey(0xA1)
            
        case .missionControl:
            // Mission Control - use dedicated key code 0xA0 (160)
            postDedicatedKey(0xA0)
            
        case .showDesktop:
            // F11 key with Fn modifier
            postKeyEventWithModifiers(keyCode: UInt16(kVK_F11), modifiers: .maskSecondaryFn)
            
        case .launchpad:
            // Use the dedicated Launchpad key (0x83 / 131)
            postDedicatedKey(0x83)
            
        default:
            print("[SymbolicHotkeys] Hotkey \(hotkey) not directly supported")
        }
    }
    
    private enum SpaceDirection {
        case left
        case right
    }
    
    /// Post a space switching event using CGEvent with NX special key data
    private static func postSpaceSwitchEvent(direction: SpaceDirection) {
        // Post an NX system-defined event that triggers space switching
        // This uses the same mechanism as the physical "Move to Left/Right Space" keys
        
        // Method: Use NSEvent to post a system-defined key event
        // The subtype indicates the special key type
        let nsEventSubtype: Int16 = 8  // NX_SUBTYPE_AUX_CONTROL_BUTTONS
        
        // Data1 format: (keyCode << 16) | (keyState << 8) | repeat
        // keyState: 0x0A = key down, 0x0B = key up
        let keyCode: Int32 = direction == .left ? 0xB4 : 0xB5
        
        // Key down
        let keyDownData: Int = Int((keyCode << 16) | (0x0A << 8))
        if let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: nsEventSubtype,
            data1: keyDownData,
            data2: -1
        ) {
            event.cgEvent?.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        
        usleep(50000)  // 50ms
        
        // Key up
        let keyUpData: Int = Int((keyCode << 16) | (0x0B << 8))
        if let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: nsEventSubtype,
            data1: keyUpData,
            data2: -1
        ) {
            event.cgEvent?.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
    
    /// Post a key event with modifier flags using CGEvent
    private static func postKeyEventWithModifiers(keyCode: UInt16, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Create and post key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
            print("[SymbolicHotkeys] Failed to create key down event")
            return
        }
        keyDown.flags = modifiers
        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        keyDown.post(tap: .cghidEventTap)
        
        usleep(50000)  // 50ms
        
        // Create and post key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            print("[SymbolicHotkeys] Failed to create key up event")
            return
        }
        keyUp.flags = modifiers
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        keyUp.post(tap: .cghidEventTap)
    }
    
    /// Post a dedicated system key (like Mission Control, Launchpad, App Exposé keys)
    private static func postDedicatedKey(_ keyCode: UInt16) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            keyDown.post(tap: .cghidEventTap)
        }
        
        usleep(50000)
        
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
