import Foundation
import CoreGraphics
import Carbon.HIToolbox
import AppKit

/// Wrapper for macOS private CGS Symbolic Hotkeys API
/// These APIs allow triggering system-level actions like Mission Control, Spaces switching, etc.

// MARK: - Private CGS API Declarations

/// CGS Modifier flags (matches CGSModifierFlags from CGSHotKeys.h)
struct CGSModifierFlags: OptionSet {
    let rawValue: UInt32
    
    static let alphaShift = CGSModifierFlags(rawValue: 1 << 16)  // Caps Lock
    static let shift = CGSModifierFlags(rawValue: 1 << 17)
    static let control = CGSModifierFlags(rawValue: 1 << 18)
    static let alternate = CGSModifierFlags(rawValue: 1 << 19)  // Option
    static let command = CGSModifierFlags(rawValue: 1 << 20)
    static let numericPad = CGSModifierFlags(rawValue: 1 << 21)
    static let help = CGSModifierFlags(rawValue: 1 << 22)
    static let function = CGSModifierFlags(rawValue: 1 << 23)
}

/// CGS Symbolic Hot Key enum (matches CGSSymbolicHotKey from CGSHotKeys.h)
typealias CGSSymbolicHotKey = UInt32

/// Returns whether the symbolic hot key is enabled
@_silgen_name("CGSIsSymbolicHotKeyEnabled")
func CGSIsSymbolicHotKeyEnabled(_ hotKey: CGSSymbolicHotKey) -> Bool

/// Sets whether the symbolic hot key is enabled
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
func CGSSetSymbolicHotKeyEnabled(_ hotKey: CGSSymbolicHotKey, _ isEnabled: Bool) -> CGError

/// Gets the configured key values for a symbolic hot key
@_silgen_name("CGSGetSymbolicHotKeyValue")
func CGSGetSymbolicHotKeyValue(
    _ hotKey: CGSSymbolicHotKey,
    _ outKeyEquivalent: UnsafeMutablePointer<UniChar>,
    _ outVirtualKeyCode: UnsafeMutablePointer<UniChar>,
    _ outModifiers: UnsafeMutablePointer<UInt32>
) -> CGError

// MARK: - Symbolic Hotkeys

/// Enum representing macOS system-level symbolic hotkeys
/// Values correspond to the symbolic hotkey IDs used by the CGS API
enum SymbolicHotKey: UInt32 {
    // Dock/Exposé
    case exposeAllWindows = 32          // Mission Control
    case exposeAllWindowsSlow = 34
    case applicationWindows = 33         // App Exposé
    case applicationWindowsSlow = 35
    case exposeDesktop = 36             // Show Desktop
    case exposeDesktopSlow = 37
    
    // Spaces
    case spaces = 75
    case spacesSlow = 76
    case moveLeftASpace = 79            // Move left a space
    case moveLeftASpaceSlow = 80
    case moveRightASpace = 81           // Move right a space
    case moveRightASpaceSlow = 82
    case spaceDown = 83
    case spaceDownSlow = 84
    case spaceUp = 85
    case spaceUpSlow = 86
    
    // Other
    case launchpad = 160
    case showNotificationCenter = 163
    case spotlightSearch = 64
    case lookUpWordInDictionary = 70
}

/// Marker for synthetic events to avoid re-processing by InputInterceptor
private let syntheticEventMarker: Int64 = 0x4D494E505554  // "MINPUT" in hex

/// Utility struct for posting symbolic hotkey events
struct SymbolicHotkeys {
    
    /// Post a symbolic hotkey event to trigger a system action
    /// - Parameter hotkey: The symbolic hotkey to trigger
    static func post(_ hotkey: SymbolicHotKey) {
        do {
            try postSymbolicHotKey(hotkey)
        } catch {
            print("[SymbolicHotkeys] Failed to post hotkey \(hotkey): \(error)")
            // Fallback to dedicated key for some actions
            fallbackPost(hotkey)
        }
    }
    
    /// Post a symbolic hotkey by getting its configured key combination and posting that
    private static func postSymbolicHotKey(_ hotkey: SymbolicHotKey) throws {
        let hotkeyValue = CGSSymbolicHotKey(hotkey.rawValue)
        
        var keyEquivalent: UniChar = 0
        var virtualKeyCode: UniChar = 0
        var modifiers: UInt32 = 0
        
        // Get the user's configured keyboard shortcut for this symbolic hotkey
        let error = CGSGetSymbolicHotKeyValue(
            hotkeyValue,
            &keyEquivalent,
            &virtualKeyCode,
            &modifiers
        )
        
        guard error == .success else {
            throw NSError(domain: "CGSError", code: Int(error.rawValue), userInfo: [
                NSLocalizedDescriptionKey: "CGSGetSymbolicHotKeyValue failed with error \(error.rawValue)"
            ])
        }
        
        // Check if the hotkey is enabled, temporarily enable it if not
        let hotkeyEnabled = CGSIsSymbolicHotKeyEnabled(hotkeyValue)
        if !hotkeyEnabled {
            _ = CGSSetSymbolicHotKeyEnabled(hotkeyValue, true)
        }
        
        defer {
            if !hotkeyEnabled {
                // Wait a bit for events to be processed before disabling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    _ = CGSSetSymbolicHotKeyEnabled(hotkeyValue, false)
                }
            }
        }
        
        // Convert CGS modifiers to CGEventFlags
        let flags = convertModifiersToEventFlags(CGSModifierFlags(rawValue: modifiers))
        
        // Post the key down and up events
        let keyCode = UInt16(virtualKeyCode)
        
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        keyDown.flags = flags
        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)!
        keyUp.flags = flags
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        
        print("[SymbolicHotkeys] Posted hotkey \(hotkey) with keyCode=\(keyCode), modifiers=\(modifiers)")
    }
    
    /// Convert CGSModifierFlags to CGEventFlags
    private static func convertModifiersToEventFlags(_ modifiers: CGSModifierFlags) -> CGEventFlags {
        var flags = CGEventFlags()
        
        if modifiers.contains(.command) {
            flags.insert(.maskCommand)
        }
        if modifiers.contains(.shift) {
            flags.insert(.maskShift)
        }
        if modifiers.contains(.alternate) {
            flags.insert(.maskAlternate)
        }
        if modifiers.contains(.control) {
            flags.insert(.maskControl)
        }
        if modifiers.contains(.function) {
            flags.insert(.maskSecondaryFn)
        }
        
        return flags
    }
    
    /// Fallback method using dedicated key codes
    private static func fallbackPost(_ hotkey: SymbolicHotKey) {
        switch hotkey {
        case .exposeAllWindows:
            // Mission Control - dedicated key 0xA0
            postDedicatedKey(0xA0)
            
        case .applicationWindows:
            // App Exposé - dedicated key 0xA1
            postDedicatedKey(0xA1)
            
        case .exposeDesktop:
            // Show Desktop - F11
            postKeyEventWithModifiers(keyCode: UInt16(kVK_F11), modifiers: .maskSecondaryFn)
            
        case .launchpad:
            // Launchpad - dedicated key 0x83
            postDedicatedKey(0x83)
            
        default:
            print("[SymbolicHotkeys] No fallback for hotkey \(hotkey)")
        }
    }
    
    /// Post a key event with modifier flags using CGEvent
    private static func postKeyEventWithModifiers(keyCode: UInt16, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
            return
        }
        keyDown.flags = modifiers
        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        keyDown.post(tap: .cghidEventTap)
        
        usleep(50000)
        
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyUp.flags = modifiers
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        keyUp.post(tap: .cghidEventTap)
    }
    
    /// Post a dedicated system key
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
