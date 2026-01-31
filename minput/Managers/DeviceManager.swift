import Foundation
import IOKit
import IOKit.hid
import Observation

/// Manages detection of external HID devices (mice and keyboards)
@MainActor
@Observable
class DeviceManager {
    static let shared = DeviceManager()
    
    private(set) var externalMouseConnected = false
    private(set) var externalKeyboardConnected = false
    private(set) var connectedDevices: [HIDDevice] = []
    
    private var hidManager: IOHIDManager?
    private let appleVendorID: Int = 0x05AC
    private var refreshTimer: Timer?
    
    struct HIDDevice: Identifiable, Equatable {
        let id: UUID = UUID()
        let vendorID: Int
        let productID: Int
        let vendorName: String
        let productName: String
        let isKeyboard: Bool
        let isMouse: Bool
        let isAppleDevice: Bool
        
        var displayName: String {
            if !productName.isEmpty {
                return productName
            }
            if !vendorName.isEmpty {
                return "\(vendorName) Device"
            }
            return "Unknown Device"
        }
    }
    
    private init() {
        setupHIDManager()
        // Also poll periodically for device changes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
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
        
        // Match mice and keyboards
        let mouseMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
        ]
        
        let keyboardMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ]
        
        let matchingArray = [mouseMatch, keyboardMatch] as CFArray
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingArray)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("Failed to open HID Manager: \(result)")
        }
        
        // Initial device scan
        refreshDevices()
    }
    
    func refreshDevices() {
        guard let manager = hidManager else { return }
        
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            connectedDevices = []
            updateConnectionState()
            return
        }
        
        connectedDevices = deviceSet.compactMap { device -> HIDDevice? in
            return createHIDDevice(from: device)
        }
        
        updateConnectionState()
    }
    
    private func createHIDDevice(from device: IOHIDDevice) -> HIDDevice? {
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let vendorName = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? ""
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        
        let isMouse = usagePage == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Mouse
        let isKeyboard = usagePage == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Keyboard
        let isAppleDevice = vendorID == appleVendorID
        
        // Skip if neither mouse nor keyboard
        guard isMouse || isKeyboard else { return nil }
        
        return HIDDevice(
            vendorID: vendorID,
            productID: productID,
            vendorName: vendorName,
            productName: productName,
            isKeyboard: isKeyboard,
            isMouse: isMouse,
            isAppleDevice: isAppleDevice
        )
    }
    
    private func updateConnectionState() {
        externalMouseConnected = connectedDevices.contains { $0.isMouse && !$0.isAppleDevice }
        externalKeyboardConnected = connectedDevices.contains { $0.isKeyboard && !$0.isAppleDevice }
    }
}
