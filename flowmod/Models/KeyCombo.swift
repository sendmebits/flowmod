import Foundation
import Carbon.HIToolbox

/// Represents a keyboard shortcut combination (key + modifiers)
struct KeyCombo: Codable, Equatable, Hashable {
    let keyCode: UInt16
    let modifiers: UInt64 // CGEventFlags raw value
    
    var displayName: String {
        var parts: [String] = []
        
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        
        parts.append(keyCodeToString(keyCode))
        
        return parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let specialKeys: [UInt16: String] = [
            0x24: "↩", // Return
            0x30: "⇥", // Tab
            0x31: "Space",
            0x33: "⌫", // Delete
            0x35: "⎋", // Escape
            0x37: "⌘",
            0x38: "⇧",
            0x39: "⇪", // Caps Lock
            0x3A: "⌥",
            0x3B: "⌃",
            0x7E: "↑",
            0x7D: "↓",
            0x7B: "←",
            0x7C: "→",
            0x73: "Home",
            0x77: "End",
            0x74: "Page Up",
            0x79: "Page Down",
            0x75: "Delete ⌦",
            0x72: "Insert",
            0x69: "Print Screen",
            0x6E: "Context Menu",
            0x60: "F5",
            0x61: "F6",
            0x62: "F7",
            0x63: "F3",
            0x64: "F8",
            0x65: "F9",
            0x67: "F11",
            0x6D: "F10",
            0x6F: "F12",
            0x76: "F4",
            0x78: "F2",
            0x7A: "F1",
            0x6A: "F16",
            0x40: "F17",
            0x4F: "F18",
            0x50: "F19",
        ]
        
        if let special = specialKeys[keyCode] {
            return special
        }
        
        // Try to get character from key code
        if let char = characterForKeyCode(keyCode) {
            return char.uppercased()
        }
        
        return "Key \(keyCode)"
    }
    
    private func characterForKeyCode(_ keyCode: UInt16) -> String? {
        return KeyCombo.cachedCharacterForKeyCode(keyCode)
    }
    
    /// Cached keyboard layout lookup to avoid repeated TISCopyCurrentKeyboardInputSource calls
    private static var cachedKeyboardLayout: UnsafePointer<UCKeyboardLayout>?
    private static var cachedLayoutInputSourceID: String?
    
    private static func cachedCharacterForKeyCode(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let sourceID = Unmanaged.passUnretained(source).toOpaque().debugDescription
        
        // Refresh cached layout if input source changed
        if sourceID != cachedLayoutInputSourceID {
            guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                return nil
            }
            let dataRef = unsafeBitCast(layoutData, to: CFData.self)
            cachedKeyboardLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)
            cachedLayoutInputSourceID = sourceID
        }
        
        guard let keyboardLayout = cachedKeyboardLayout else { return nil }
        
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        
        let error = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )
        
        if error == noErr && length > 0 {
            return String(utf16CodeUnits: chars, count: length)
        }
        
        return nil
    }
}

/// Common source keys for generic keyboards
enum SourceKey: String, CaseIterable, Codable, Identifiable {
    case none = "None"
    case home = "Home"
    case end = "End"
    case insert = "Insert"
    case deleteForward = "Delete ⌦"
    case pageUp = "Page Up"
    case pageDown = "Page Down"
    case printScreen = "Print Screen"
    case custom = "Record Key..."
    
    var id: String { rawValue }
    
    var keyCode: UInt16? {
        switch self {
        case .none: return nil
        case .home: return 0x73
        case .end: return 0x77
        case .insert: return 0x72
        case .deleteForward: return 0x75
        case .pageUp: return 0x74
        case .pageDown: return 0x79
        case .printScreen: return 0x69
        case .custom: return nil
        }
    }
}
