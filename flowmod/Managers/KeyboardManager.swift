import AppKit
import Foundation
import IOKit
import IOKit.hid
import Observation

/// Detects external keyboards and applies the Option/Command swap for each one.
///
/// Keyboards are identified the way System Settings identifies them: decimal
/// vendor ID and product ID. The built-in keyboard is omitted. On Apple silicon
/// that keyboard reports vendor 0 and product 0, and writing that preference key
/// would change the internal keyboard.
@MainActor
@Observable
class KeyboardManager {
    static let shared = KeyboardManager()

    private(set) var connectedKeyboards: [ExternalKeyboard] = []
    /// Vendor/product keys whose Option and Command keys are currently swapped.
    private(set) var swappedKeys: Set<String> = []

    struct ExternalKeyboard: Identifiable, Equatable {
        let vendorID: Int
        let productID: Int
        let vendorName: String
        let productName: String

        var id: String { "\(vendorID):\(productID)" }

        var displayName: String {
            if !productName.isEmpty {
                return productName
            }
            if !vendorName.isEmpty {
                return "\(vendorName) Keyboard"
            }
            return "Keyboard"
        }
    }

    @ObservationIgnored private var hidManager: IOHIDManager?
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var hasEnumerated = false
    private let appleVendorIDs: Set<Int> = [
        0x05AC, // Apple USB
        0x004C  // Apple Bluetooth
    ]

    private init() {
        setupHIDManager()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
                self?.refreshMappingState()
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }
        refreshTimer?.tolerance = 5.0
    }

    func isSwapped(_ keyboard: ExternalKeyboard) -> Bool {
        swappedKeys.contains(keyboard.id)
    }

    func setSwapped(_ enabled: Bool, for keyboard: ExternalKeyboard) {
        let current = KeyboardModifierStore.read(vendorID: keyboard.vendorID, productID: keyboard.productID)
        let updated = KeyboardModifierMapping.applying(swap: enabled, to: current.pairs)
        KeyboardModifierStore.write(pairs: updated, vendorID: keyboard.vendorID, productID: keyboard.productID)
        let applied = KeyboardModifierStore.applyLive(
            pairs: updated,
            vendorID: keyboard.vendorID,
            productID: keyboard.productID
        )
        if enabled {
            swappedKeys.insert(keyboard.id)
        } else {
            swappedKeys.remove(keyboard.id)
        }
        LogManager.shared.log(
            "\(keyboard.displayName): Option/Command swap \(enabled ? "on" : "off") (\(applied ? "applied" : "saved, reconnect may be required"))",
            category: "Keyboard"
        )
    }

    /// Re-read System Settings in case the user changed Modifier Keys there.
    func refreshMappingState() {
        var swapped = Set<String>()
        for keyboard in connectedKeyboards {
            let stored = KeyboardModifierStore.read(vendorID: keyboard.vendorID, productID: keyboard.productID)
            if KeyboardModifierMapping.isOptionCommandSwapped(stored.pairs) {
                swapped.insert(keyboard.id)
            }
        }
        swappedKeys = swapped
    }

    func displayName(for keyboard: ExternalKeyboard) -> String {
        let sameNameCount = connectedKeyboards.filter { $0.displayName == keyboard.displayName }.count
        guard sameNameCount > 1 else { return keyboard.displayName }
        if !keyboard.vendorName.isEmpty {
            return "\(keyboard.displayName) (\(keyboard.vendorName))"
        }
        return "\(keyboard.displayName) (\(keyboard.vendorID):\(keyboard.productID))"
    }

    private func setupHIDManager() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            print("Failed to create keyboard HID manager")
            return
        }

        let keyboardMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, keyboardMatch as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let matchCallback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let manager = Unmanaged<KeyboardManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in manager.refreshDevices() }
        }
        let removeCallback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let manager = Unmanaged<KeyboardManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in manager.refreshDevices() }
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, matchCallback, selfPtr)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, removeCallback, selfPtr)

        // Discovery does not require opening the HID devices. Opening them would
        // request Input Monitoring, which this mapping does not need.
        refreshDevices()
    }

    private func refreshDevices() {
        guard let manager = hidManager else { return }
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            updateKeyboards([])
            return
        }

        var byIdentity: [String: ExternalKeyboard] = [:]
        for device in deviceSet where HIDRegistry.isLive(device) {
            guard let keyboard = createKeyboard(from: device) else { continue }
            if let existing = byIdentity[keyboard.id] {
                byIdentity[keyboard.id] = preferred(existing, keyboard)
            } else {
                byIdentity[keyboard.id] = keyboard
            }
        }

        let keyboards = byIdentity.values.sorted { lhs, rhs in
            if lhs.displayName != rhs.displayName {
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            if lhs.vendorID != rhs.vendorID {
                return lhs.vendorID < rhs.vendorID
            }
            return lhs.productID < rhs.productID
        }
        updateKeyboards(keyboards)
    }

    private func updateKeyboards(_ keyboards: [ExternalKeyboard]) {
        let previous = hasEnumerated ? Set(connectedKeyboards.map(\.id)) : []
        let changed = keyboards != connectedKeyboards
        if changed || !hasEnumerated {
            connectedKeyboards = keyboards
            hasEnumerated = true
            for keyboard in keyboards where !previous.contains(keyboard.id) {
                reapplyStoredMapping(for: keyboard)
            }
            refreshMappingState()
            if changed {
                LogManager.shared.log(
                    "External keyboards: \(keyboards.map(\.displayName).joined(separator: ", "))",
                    category: "Keyboard"
                )
            }
        }
    }

    /// The driver usually loads the preference when a keyboard connects. Push
    /// the stored pairs as well so a keyboard attached while FlowMod is running
    /// picks up a swap that was saved earlier.
    private func reapplyStoredMapping(for keyboard: ExternalKeyboard) {
        let stored = KeyboardModifierStore.read(vendorID: keyboard.vendorID, productID: keyboard.productID)
        guard stored.exists else { return }
        KeyboardModifierStore.applyLive(
            pairs: stored.pairs,
            vendorID: keyboard.vendorID,
            productID: keyboard.productID
        )
    }

    private func preferred(_ existing: ExternalKeyboard, _ candidate: ExternalKeyboard) -> ExternalKeyboard {
        if existing.productName.isEmpty && !candidate.productName.isEmpty {
            return candidate
        }
        return existing
    }

    private func createKeyboard(from device: IOHIDDevice) -> ExternalKeyboard? {
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let vendorName = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? ""
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0

        guard usagePage == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Keyboard else { return nil }
        guard vendorID != 0 && productID != 0 else { return nil }
        guard !isBuiltIn(device) else { return nil }

        let isApple = appleVendorIDs.contains(vendorID)
            || productName.lowercased().contains("apple")
            || vendorName.lowercased().contains("apple")
        guard !isApple else { return nil }

        return ExternalKeyboard(
            vendorID: vendorID,
            productID: productID,
            vendorName: vendorName,
            productName: productName
        )
    }

    private func isBuiltIn(_ device: IOHIDDevice) -> Bool {
        let value = IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString)
        if let number = value as? Int { return number != 0 }
        if let flag = value as? Bool { return flag }
        return false
    }
}
