import CoreGraphics
import Foundation

/// Builds DockSwipe events in the form macOS 27 requires.
///
/// macOS 27 ignores the legacy DockSwipe CGEvent fields; the Dock only acts on a
/// type-30 CGEvent that carries a real IOHIDEvent of type DockSwipe. Every function
/// involved is private, so all of them are resolved at runtime and the bridge
/// reports itself unavailable if any symbol is missing.
nonisolated enum DockSwipeHIDBridge {
    private typealias HIDEventRef = UnsafeMutableRawPointer

    private static let dockSwipeEventType: UInt32 = 23   // kIOHIDEventTypeDockSwipe
    private static let motionField: UInt32 = (23 << 16) | 1     // kIOHIDEventFieldDockSwipeMotion
    private static let progressField: UInt32 = (23 << 16) | 2   // kIOHIDEventFieldDockSwipeProgress
    private static let flavorField: UInt32 = (23 << 16) | 5     // kIOHIDEventFieldDockSwipeFlavor
    private static let dockPrimaryFlavor: CFIndex = 3           // kIOHIDGestureFlavorDockPrimary

    private nonisolated struct Functions {
        let create: @convention(c) (CFAllocator?, UInt32, UInt64, UInt32) -> HIDEventRef?
        let setIntegerValue: @convention(c) (HIDEventRef, UInt32, CFIndex) -> Void
        let setDoubleValue: @convention(c) (HIDEventRef, UInt32, Double) -> Void
        let setPhase: @convention(c) (HIDEventRef, UInt16) -> Void
        let createVelocityEvent: @convention(c) (CFAllocator?, UInt64, Double, Double, Double, UInt32) -> HIDEventRef?
        let appendEvent: @convention(c) (HIDEventRef, HIDEventRef, UInt32) -> Void
        /// Copies the payload into the CGEvent; the caller keeps ownership of its IOHIDEvent.
        let attachToCGEvent: @convention(c) (CGEvent, HIDEventRef) -> Void

        static func resolve() -> Functions? {
            guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
                  let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
                  let create = dlsym(iokit, "IOHIDEventCreate"),
                  let setIntegerValue = dlsym(iokit, "IOHIDEventSetIntegerValue"),
                  let setDoubleValue = dlsym(iokit, "IOHIDEventSetDoubleValue"),
                  let setPhase = dlsym(iokit, "IOHIDEventSetPhase"),
                  let createVelocityEvent = dlsym(iokit, "IOHIDEventCreateVelocityEvent"),
                  let appendEvent = dlsym(iokit, "IOHIDEventAppendEvent"),
                  let attachToCGEvent = dlsym(skylight, "SLEventSetIOHIDEvent") else { return nil }
            return Functions(
                create: unsafeBitCast(create, to: (@convention(c) (CFAllocator?, UInt32, UInt64, UInt32) -> HIDEventRef?).self),
                setIntegerValue: unsafeBitCast(setIntegerValue, to: (@convention(c) (HIDEventRef, UInt32, CFIndex) -> Void).self),
                setDoubleValue: unsafeBitCast(setDoubleValue, to: (@convention(c) (HIDEventRef, UInt32, Double) -> Void).self),
                setPhase: unsafeBitCast(setPhase, to: (@convention(c) (HIDEventRef, UInt16) -> Void).self),
                createVelocityEvent: unsafeBitCast(createVelocityEvent, to: (@convention(c) (CFAllocator?, UInt64, Double, Double, Double, UInt32) -> HIDEventRef?).self),
                appendEvent: unsafeBitCast(appendEvent, to: (@convention(c) (HIDEventRef, HIDEventRef, UInt32) -> Void).self),
                attachToCGEvent: unsafeBitCast(attachToCGEvent, to: (@convention(c) (CGEvent, HIDEventRef) -> Void).self)
            )
        }
    }

    private static let functions = Functions.resolve()

    static var isAvailable: Bool { functions != nil }

    /// - Parameters:
    ///   - motion: DockSwipe motion (1 = horizontal, 2 = vertical), matching `DockSwipeSimulator.SwipeType`.
    ///   - progress: Cumulative origin offset in DockSwipe units.
    ///   - phase: IOHIDEvent phase bits (began 1, changed 2, ended 4, cancelled 8).
    ///   - exitVelocity: Attached as a velocity child event; only meaningful for ended/cancelled.
    static func makeDockSwipeEvent(motion: Int, progress: Double, phase: UInt16, exitVelocity: Double?) -> CGEvent? {
        guard let functions,
              let event = CGEvent(source: nil),
              let type = CGEventType(rawValue: 30),
              let hidEvent = functions.create(nil, dockSwipeEventType, 0, 0) else { return nil }
        defer { release(hidEvent) }

        functions.setPhase(hidEvent, phase)
        functions.setIntegerValue(hidEvent, motionField, motion)
        functions.setIntegerValue(hidEvent, flavorField, dockPrimaryFlavor)
        functions.setDoubleValue(hidEvent, progressField, progress)

        if let exitVelocity,
           let velocityEvent = functions.createVelocityEvent(nil, 0, exitVelocity, exitVelocity, 0, 0) {
            functions.appendEvent(hidEvent, velocityEvent, 0)
            release(velocityEvent)
        }

        event.type = type
        functions.attachToCGEvent(event, hidEvent)
        return event
    }

    private static func release(_ hidEvent: HIDEventRef) {
        Unmanaged<AnyObject>.fromOpaque(hidEvent).release()
    }
}
