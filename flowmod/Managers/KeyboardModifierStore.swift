import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

/// Option/Command pairs stored in the same ByHost preference System Settings uses
/// for Keyboard Shortcuts → Modifier Keys.
///
/// The preference key is `com.apple.keyboard.modifiermapping.<vendorID>-<productID>-0`.
/// Values are HID usages on the keyboard page (`0x700000000` combined with the key usage).
enum KeyboardModifierMapping {
    static let sourceKey = "HIDKeyboardModifierMappingSrc"
    static let destinationKey = "HIDKeyboardModifierMappingDst"
    static let pairsKey = "HIDKeyboardModifierMappingPairs"

    static let leftOption: Int64 = 0x7000000E2
    static let leftCommand: Int64 = 0x7000000E3
    static let rightOption: Int64 = 0x7000000E6
    static let rightCommand: Int64 = 0x7000000E7

    struct Pair: Equatable {
        var source: Int64
        var destination: Int64
    }

    static let optionCommandSources: Set<Int64> = [
        leftOption, leftCommand, rightOption, rightCommand
    ]

    static let swapPairs: [Pair] = [
        Pair(source: leftOption, destination: leftCommand),
        Pair(source: leftCommand, destination: leftOption),
        Pair(source: rightOption, destination: rightCommand),
        Pair(source: rightCommand, destination: rightOption),
    ]

    static func preferenceKey(vendorID: Int, productID: Int) -> String {
        "com.apple.keyboard.modifiermapping.\(vendorID)-\(productID)-0"
    }

    /// True when both sides of Option and Command are swapped. Other pairs,
    /// such as Caps Lock, do not affect the result.
    static func isOptionCommandSwapped(_ pairs: [Pair]) -> Bool {
        let bySource = Dictionary(pairs.map { ($0.source, $0.destination) }, uniquingKeysWith: { _, new in new })
        return swapPairs.allSatisfy { bySource[$0.source] == $0.destination }
    }

    /// Turn the Option/Command swap on or off without disturbing other modifier pairs.
    /// Turning it off drops Option and Command sources; it does not restore an
    /// earlier custom destination such as Option → Control.
    static func applying(swap enabled: Bool, to pairs: [Pair]) -> [Pair] {
        let kept = pairs.filter { !optionCommandSources.contains($0.source) }
        guard enabled else { return kept }
        return kept + swapPairs
    }
}

/// Reads and writes the system modifier-key preference, and pushes the same
/// pairs onto the live keyboard service so the change applies immediately.
enum KeyboardModifierStore {
    struct StoredMapping {
        var pairs: [KeyboardModifierMapping.Pair]
        /// False when the preference key is absent (Modifier Keys shows defaults).
        var exists: Bool
    }

    static func read(vendorID: Int, productID: Int) -> StoredMapping {
        let key = KeyboardModifierMapping.preferenceKey(vendorID: vendorID, productID: productID) as CFString
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        guard let value = CFPreferencesCopyValue(
            key,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) else {
            return StoredMapping(pairs: [], exists: false)
        }
        return StoredMapping(pairs: pairs(from: value), exists: true)
    }

    /// Writes `pairs`, or removes the key when the array is empty so Modifier Keys
    /// shows Restore Defaults.
    static func write(pairs: [KeyboardModifierMapping.Pair], vendorID: Int, productID: Int) {
        let key = KeyboardModifierMapping.preferenceKey(vendorID: vendorID, productID: productID) as CFString
        let value: CFPropertyList? = pairs.isEmpty ? nil : propertyList(for: pairs)
        CFPreferencesSetValue(
            key,
            value,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    /// Pushes `pairs` to every keyboard service with this vendor and product.
    /// Returns false when the mapping could not be applied to a live service.
    static func applyLive(pairs: [KeyboardModifierMapping.Pair], vendorID: Int, productID: Int) -> Bool {
        guard let client = IOHIDEventSystemClientCreateWithType(
            kCFAllocatorDefault,
            kIOHIDEventSystemClientTypeMonitor,
            nil
        )?.takeRetainedValue() else {
            return false
        }

        guard let services = IOHIDEventSystemClientCopyServices(client) else {
            return false
        }

        let property = propertyList(for: pairs)
        var matched = 0
        var applied = 0
        for index in 0..<CFArrayGetCount(services) {
            guard let pointer = CFArrayGetValueAtIndex(services, index) else { continue }
            let service = Unmanaged<IOHIDServiceClient>.fromOpaque(pointer).takeUnretainedValue()
            guard IOHIDServiceClientConformsTo(
                service,
                UInt32(kHIDPage_GenericDesktop),
                UInt32(kHIDUsage_GD_Keyboard)
            ) != 0 else { continue }
            guard serviceInteger(service, kIOHIDVendorIDKey) == vendorID,
                  serviceInteger(service, kIOHIDProductIDKey) == productID else { continue }
            matched += 1
            if IOHIDServiceClientSetProperty(service, KeyboardModifierMapping.pairsKey as CFString, property) {
                applied += 1
            }
        }
        return matched > 0 && applied == matched
    }

    private static func propertyList(for pairs: [KeyboardModifierMapping.Pair]) -> CFArray {
        let entries: [[String: NSNumber]] = pairs.map { pair in
            [
                KeyboardModifierMapping.sourceKey: NSNumber(value: pair.source),
                KeyboardModifierMapping.destinationKey: NSNumber(value: pair.destination),
            ]
        }
        return entries as CFArray
    }

    private static func pairs(from value: Any) -> [KeyboardModifierMapping.Pair] {
        let entries = value as? [Any] ?? []
        return entries.compactMap { entry in
            guard let dictionary = entry as? [String: Any],
                  let source = integerValue(dictionary[KeyboardModifierMapping.sourceKey]),
                  let destination = integerValue(dictionary[KeyboardModifierMapping.destinationKey]) else {
                return nil
            }
            return KeyboardModifierMapping.Pair(source: source, destination: destination)
        }
    }

    private static func integerValue(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber:
            return number.int64Value
        case let number as Int64:
            return number
        case let number as Int:
            return Int64(number)
        default:
            return nil
        }
    }

    private static func serviceInteger(_ service: IOHIDServiceClient, _ key: String) -> Int? {
        guard let value = IOHIDServiceClientCopyProperty(service, key as CFString) else { return nil }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let number = value as? Int {
            return number
        }
        return nil
    }
}

/// Monitor clients can set `HIDKeyboardModifierMappingPairs`. The simple client cannot.
private let kIOHIDEventSystemClientTypeMonitor: Int32 = 1

@_silgen_name("IOHIDEventSystemClientCreateWithType")
private func IOHIDEventSystemClientCreateWithType(
    _ allocator: CFAllocator?,
    _ type: Int32,
    _ attributes: CFDictionary?
) -> Unmanaged<IOHIDEventSystemClient>?
