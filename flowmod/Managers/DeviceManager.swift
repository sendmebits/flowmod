import Foundation
import IOKit
import IOKit.hid
import Observation

/// Manages detection of external HID pointer devices (mice)
@MainActor
@Observable
class DeviceManager {
    static let shared = DeviceManager()
    
    private(set) var externalMouseConnected = false
    private(set) var connectedDevices: [HIDDevice] = []
    
    private var hidManager: IOHIDManager?
    private let appleVendorIDs: Set<Int> = [
        0x05AC, // Apple USB
        0x004C  // Apple Bluetooth
    ]
    private var refreshTimer: Timer?

    /// Attribution state read from the event-tap thread (see `device(forEventSenderID:)`).
    /// Guarded by `attributionLock` rather than the main actor so the scroll/button
    /// hot path never has to hop to the main thread to attribute an event.
    @ObservationIgnored private let attributionLock = NSLock()

    /// Snapshot of `connectedDevices` for off-main attribution. Updated under
    /// `attributionLock` whenever `connectedDevices` changes.
    @ObservationIgnored nonisolated(unsafe) private var attributionDevices: [HIDDevice] = []

    /// Cache of CGEvent sender IDs (undocumented field 87) → matched device.
    /// A nil value means "resolved, no match" so we don't re-walk the registry per event.
    @ObservationIgnored nonisolated(unsafe) private var senderIDCache: [UInt64: HIDDevice?] = [:]
    
    struct HIDDevice: Identifiable, Equatable {
        let id: UUID = UUID()
        let vendorID: Int
        let productID: Int
        let vendorName: String
        let productName: String
        let physicalDeviceUniqueID: String
        let serialNumber: String
        let locationID: Int
        let isMouse: Bool
        let isAppleDevice: Bool
        /// IORegistryEntry ID for this device; used to match CGEvent source (undocumented field 87).
        let registryID: UInt64

        /// Legacy profile identity used by versions before physical-device IDs.
        var legacyDeviceKey: String {
            "\(vendorID):\(productID)"
        }

        /// The most stable physical identity the HID device exposes. Serial and
        /// physical unique IDs survive reconnection; location ID distinguishes
        /// otherwise-identical devices connected at different locations. The
        /// legacy key remains the fallback for hardware exposing none of them.
        var deviceKey: String {
            if !physicalDeviceUniqueID.isEmpty {
                return "\(legacyDeviceKey):physical:\(Self.encodeKeyComponent(physicalDeviceUniqueID))"
            }
            if !serialNumber.isEmpty {
                return "\(legacyDeviceKey):serial:\(Self.encodeKeyComponent(serialNumber))"
            }
            if locationID != 0 {
                return "\(legacyDeviceKey):location:\(locationID)"
            }
            return legacyDeviceKey
        }

        var profileQualifier: String? {
            if !physicalDeviceUniqueID.isEmpty {
                return "ID \(String(physicalDeviceUniqueID.suffix(6)))"
            }
            if !serialNumber.isEmpty {
                return "S/N \(String(serialNumber.suffix(6)))"
            }
            if locationID != 0 {
                return String(format: "Port %08X", locationID)
            }
            return nil
        }

        var displayName: String {
            if !productName.isEmpty {
                return productName
            }
            if !vendorName.isEmpty {
                return "\(vendorName) Device"
            }
            return "Unknown Device"
        }
        
        /// Content-based equality (ignores UUID so polling doesn't trigger redraws)
        static func == (lhs: HIDDevice, rhs: HIDDevice) -> Bool {
            lhs.vendorID == rhs.vendorID &&
            lhs.productID == rhs.productID &&
            lhs.vendorName == rhs.vendorName &&
            lhs.productName == rhs.productName &&
            lhs.physicalDeviceUniqueID == rhs.physicalDeviceUniqueID &&
            lhs.serialNumber == rhs.serialNumber &&
            lhs.locationID == rhs.locationID &&
            lhs.isMouse == rhs.isMouse &&
            lhs.isAppleDevice == rhs.isAppleDevice &&
            lhs.registryID == rhs.registryID
        }

        private static func encodeKeyComponent(_ value: String) -> String {
            Data(value.utf8).base64EncodedString()
        }
    }
    
    private init() {
        setupHIDManager()
        // Safety-net poll for devices that may not trigger callbacks (e.g. some Bluetooth)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }
        refreshTimer?.tolerance = 5.0
    }
    
    private func setupHIDManager() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = hidManager else {
            print("Failed to create HID Manager")
            return
        }
        
        // Match mice and pointer devices
        let mouseMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
        ]
        
        let pointerMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer
        ]
        
        let matchingArray = [mouseMatch, pointerMatch] as CFArray
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingArray)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        
        let matchCallback: IOHIDDeviceCallback = { context, result, sender, device in
            guard let context = context else { return }
            let dm = Unmanaged<DeviceManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in dm.refreshDevices() }
        }
        let removeCallback: IOHIDDeviceCallback = { context, result, sender, device in
            guard let context = context else { return }
            let dm = Unmanaged<DeviceManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in dm.refreshDevices() }
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, matchCallback, selfPtr)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, removeCallback, selfPtr)

        // Device discovery and metadata access do not require opening the HID
        // devices. Opening them would unnecessarily request Input Monitoring
        // access even though FlowMod receives mouse input through CGEvent taps.
        
        refreshDevices()
    }
    
    func refreshDevices() {
        guard let manager = hidManager else { return }
        
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            connectedDevices = []
            updateConnectionState()
            return
        }
        
        let newDevices = deviceSet
            .compactMap { device -> HIDDevice? in
                return createHIDDevice(from: device)
            }
            .sorted { lhs, rhs in
                if lhs.registryID != rhs.registryID {
                    return lhs.registryID < rhs.registryID
                }
                if lhs.vendorID != rhs.vendorID {
                    return lhs.vendorID < rhs.vendorID
                }
                if lhs.productID != rhs.productID {
                    return lhs.productID < rhs.productID
                }
                if lhs.vendorName != rhs.vendorName {
                    return lhs.vendorName < rhs.vendorName
                }
                return lhs.productName < rhs.productName
            }
        
        if newDevices != connectedDevices {
            connectedDevices = newDevices
            // Publish the snapshot the event-tap thread reads, and drop the
            // now-stale sender→device cache, under the attribution lock.
            attributionLock.lock()
            attributionDevices = newDevices
            senderIDCache.removeAll()
            attributionLock.unlock()
            updateConnectionState()
        }
    }

    // MARK: - Event Sender Attribution (CGEvent field 87)

    /// Resolve the device that produced a CGEvent, given the event's sender ID
    /// (undocumented CGEvent field 87 — the IORegistry entry ID of the HID event
    /// service that generated it). Returns nil for synthesized events (sender 0)
    /// or when the sender can't be matched to an enumerated device.
    /// Resolves the device for a sender ID entirely on the calling thread
    /// (the event tap runs on a background run-loop thread). All state it
    /// touches is either lock-protected (`senderIDCache`, `attributionDevices`)
    /// or thread-safe IOKit registry calls — it never hops to the main actor.
    nonisolated func device(forEventSenderID senderID: UInt64) -> HIDDevice? {
        guard senderID != 0 else { return nil }

        attributionLock.lock()
        if let cached = senderIDCache[senderID] {
            attributionLock.unlock()
            return cached
        }
        let devices = attributionDevices
        attributionLock.unlock()

        let resolved = DeviceManager.resolveDevice(forSenderID: senderID, in: devices)

        attributionLock.lock()
        // `Dictionary` subscript assignment treats a nil value as removal, even
        // when the value type itself is Optional. `updateValue` preserves the
        // outer "key exists" state so unresolved senders are negatively cached.
        senderIDCache.updateValue(resolved, forKey: senderID)
        attributionLock.unlock()

        // Intentionally no logging here: this runs on the event-tap thread and
        // both LogManager and HIDDevice.displayName are main-actor isolated, so
        // logging would force a cross-actor access on the hot path.
        return resolved
    }

    private nonisolated static func resolveDevice(forSenderID senderID: UInt64, in devices: [HIDDevice]) -> HIDDevice? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(senderID))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        // The sender is usually an IOHIDEventService that lives below the
        // IOHIDDevice we enumerated, so walk up the parent chain comparing
        // registry IDs against known devices.
        var current = entry
        IOObjectRetain(current)
        while current != 0 {
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(current, &entryID)
            if let match = devices.first(where: { $0.registryID == entryID }) {
                IOObjectRelease(current)
                return match
            }
            var parent: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            current = result == KERN_SUCCESS ? parent : 0
        }

        // Fallback: some service layouts don't have the IOHIDDevice as a direct
        // ancestor. Preserve physical-device attribution when those properties
        // are available; vendor/product alone is only the last resort.
        let searchOptions = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        if let vendorID = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, kIOHIDVendorIDKey as CFString, kCFAllocatorDefault, searchOptions) as? Int,
           let productID = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, kIOHIDProductIDKey as CFString, kCFAllocatorDefault, searchOptions) as? Int {
            let candidates = devices.filter { $0.vendorID == vendorID && $0.productID == productID }
            if candidates.count <= 1 { return candidates.first }

            let physicalDeviceUniqueID = IORegistryEntrySearchCFProperty(
                entry,
                kIOServicePlane,
                kIOHIDPhysicalDeviceUniqueIDKey as CFString,
                kCFAllocatorDefault,
                searchOptions
            ) as? String
            if let physicalDeviceUniqueID,
               let match = candidates.first(where: { $0.physicalDeviceUniqueID == physicalDeviceUniqueID }) {
                return match
            }

            let serialNumber = IORegistryEntrySearchCFProperty(
                entry,
                kIOServicePlane,
                kIOHIDSerialNumberKey as CFString,
                kCFAllocatorDefault,
                searchOptions
            ) as? String
            if let serialNumber,
               let match = candidates.first(where: { $0.serialNumber == serialNumber }) {
                return match
            }

            let locationID = IORegistryEntrySearchCFProperty(
                entry,
                kIOServicePlane,
                kIOHIDLocationIDKey as CFString,
                kCFAllocatorDefault,
                searchOptions
            ) as? Int
            if let locationID,
               let match = candidates.first(where: { $0.locationID == locationID }) {
                return match
            }

            return candidates.first
        }
        return nil
    }
    
    private func createHIDDevice(from device: IOHIDDevice) -> HIDDevice? {
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let vendorName = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? ""
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        let physicalDeviceUniqueID =
            IOHIDDeviceGetProperty(device, kIOHIDPhysicalDeviceUniqueIDKey as CFString) as? String ?? ""
        let serialNumber = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""
        let locationID = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        
        let isMouse = usagePage == kHIDPage_GenericDesktop && (usage == kHIDUsage_GD_Mouse || usage == kHIDUsage_GD_Pointer)
        
        guard isMouse else { return nil }
        
        let isAppleDevice = appleVendorIDs.contains(vendorID) ||
            productName.lowercased().contains("apple") ||
            vendorName.lowercased().contains("apple")
        
        var registryID: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        if service != 0 {
            IORegistryEntryGetRegistryEntryID(service, &registryID)
        }
        
        return HIDDevice(
            vendorID: vendorID,
            productID: productID,
            vendorName: vendorName,
            productName: productName,
            physicalDeviceUniqueID: physicalDeviceUniqueID,
            serialNumber: serialNumber,
            locationID: locationID,
            isMouse: isMouse,
            isAppleDevice: isAppleDevice,
            registryID: registryID
        )
    }
    
    private func updateConnectionState() {
        let prevMouse = externalMouseConnected
        
        externalMouseConnected = connectedDevices.contains { $0.isMouse && !$0.isAppleDevice }
        
        if externalMouseConnected != prevMouse {
            LogManager.shared.log("External mouse: \(externalMouseConnected ? "connected" : "disconnected")", category: "Device")
        }
    }
}
