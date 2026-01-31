import Foundation

/// A single keyboard key remapping
struct KeyboardMapping: Codable, Identifiable, Equatable {
    var id = UUID()
    var sourceKey: SourceKey
    var customSourceKeyCode: UInt16?  // Used when sourceKey == .custom
    var targetAction: KeyboardAction
    
    var sourceDisplayName: String {
        if sourceKey == .custom, let keyCode = customSourceKeyCode {
            return KeyCombo(keyCode: keyCode, modifiers: 0).displayName
        }
        return sourceKey.rawValue
    }
    
    var effectiveKeyCode: UInt16? {
        if sourceKey == .custom {
            return customSourceKeyCode
        }
        return sourceKey.keyCode
    }
}

/// An app excluded from keyboard remapping
struct ExcludedApp: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleIdentifier: String
    var appName: String
    var iconData: Data?  // Cached app icon
}
