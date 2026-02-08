import Foundation

/// A single keyboard key remapping
struct KeyboardMapping: Codable, Identifiable, Equatable {
    var id = UUID()
    var sourceKey: SourceKey
    var customSourceKeyCode: UInt16?  // Used when sourceKey == .custom
    var customSourceModifiers: UInt64?  // Modifiers for custom source key (CGEventFlags raw value)
    var targetAction: KeyboardAction
    
    var sourceDisplayName: String {
        if sourceKey == .custom, let keyCode = customSourceKeyCode {
            let modifiers = customSourceModifiers ?? 0
            return KeyCombo(keyCode: keyCode, modifiers: modifiers).displayName
        }
        return sourceKey.rawValue
    }
    
    var effectiveKeyCode: UInt16? {
        if sourceKey == .custom {
            return customSourceKeyCode
        }
        return sourceKey.keyCode
    }
    
    var effectiveModifiers: UInt64 {
        if sourceKey == .custom {
            return customSourceModifiers ?? 0
        }
        // Built-in source keys have no modifiers
        return 0
    }
    
}

/// An app excluded from keyboard remapping
struct ExcludedApp: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleIdentifier: String
    var appName: String
    var iconData: Data?  // Cached app icon
}
