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
    private let appleVendorID: Int = 0x05AC
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
        let isMouse: Bool
        let isAppleDevice: Bool
        /// IORegistryEntry ID for this device; used to match CGEvent source (undocumented field 87).
        let registryID: UInt64

        /// Stable identity used to key per-mouse settings profiles.
        /// Survives reconnection/re-enumeration (unlike `registryID`).
        var deviceKey: String {
            "\(vendorID):\(productID)"
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
            lhs.isMouse == rhs.isMouse &&
            lhs.isAppleDevice == rhs.isAppleDevice &&
            lhs.registryID == rhs.registryID
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
        
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("Failed to open HID Manager: \(result)")
        }
        
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
        senderIDCache[senderID] = resolved
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
        // ancestor — match by VendorID/ProductID properties instead.
        let searchOptions = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        if let vendorID = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, kIOHIDVendorIDKey as CFString, kCFAllocatorDefault, searchOptions) as? Int,
           let productID = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, kIOHIDProductIDKey as CFString, kCFAllocatorDefault, searchOptions) as? Int {
            return devices.first { $0.vendorID == vendorID && $0.productID == productID }
        }
        return nil
    }
    
    private func createHIDDevice(from device: IOHIDDevice) -> HIDDevice? {
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let vendorName = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? ""
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        
        let isMouse = usagePage == kHIDPage_GenericDesktop && (usage == kHIDUsage_GD_Mouse || usage == kHIDUsage_GD_Pointer)
        
        guard isMouse else { return nil }
        
        let isAppleDevice = vendorID == appleVendorID ||
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
