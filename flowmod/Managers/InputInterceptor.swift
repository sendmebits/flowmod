import Foundation
import CoreGraphics
import AppKit
import Observation
import QuartzCore

/// Intercepts and modifies mouse events (scroll, buttons, gestures)
@Observable
class InputInterceptor {
    static let shared = InputInterceptor()
    
    private(set) var isRunning = false
    /// A user-facing explanation when the required session event tap fails to start.
    /// Kept separate from `isRunning` so an intentional stop doesn't look like an error.
    private(set) var startupError: String?
    
    // Tap lifecycle refs are shared with event-tap callbacks; access through
    // the interactionLock helpers below.
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThreadAttempt: TapRunLoopStartupAttempt?
    private let tapThreadLock = NSLock()

    /// Owns the startup handshake for exactly one event-tap thread. Keeping the
    /// run loop and cancellation decision per attempt prevents a delayed worker
    /// from publishing into, or stopping, a newer retry's lifecycle state.
    private final class TapRunLoopStartupAttempt {
        private enum Decision {
            case pending
            case accepted
            case cancelled
        }

        private let condition = NSCondition()
        private var decision: Decision = .pending
        private var runLoop: CFRunLoop?
        private var preparationFailed = false

        /// Publishes the worker's run loop, then waits until the caller either
        /// accepts this exact attempt or cancels it. A late, timed-out worker
        /// therefore never enters CFRunLoopRun().
        func publishAndWaitForDecision(runLoop: CFRunLoop) -> Bool {
            condition.lock()
            guard decision == .pending else {
                condition.unlock()
                return false
            }

            self.runLoop = runLoop
            condition.broadcast()

            while decision == .pending {
                condition.wait()
            }

            let wasAccepted = decision == .accepted
            condition.unlock()
            return wasAccepted
        }

        /// Waits for the worker to publish its run loop while leaving it paused
        /// so the event-tap sources and lifecycle refs can be installed first.
        func waitUntilReady(timeout: TimeInterval) -> CFRunLoop? {
            let deadline = Date(timeIntervalSinceNow: timeout)

            condition.lock()
            while runLoop == nil && !preparationFailed && decision == .pending {
                guard condition.wait(until: deadline) else { break }
            }

            if let runLoop, decision == .pending {
                condition.unlock()
                return runLoop
            }

            if decision == .pending {
                decision = .cancelled
            }
            condition.broadcast()
            condition.unlock()
            return nil
        }

        func failPreparation() {
            condition.lock()
            preparationFailed = true
            if decision == .pending {
                decision = .cancelled
            }
            condition.broadcast()
            condition.unlock()
        }

        func activate() {
            condition.lock()
            guard decision == .pending, let runLoop else {
                condition.unlock()
                return
            }

            decision = .accepted
            condition.broadcast()
            condition.unlock()
            CFRunLoopWakeUp(runLoop)
        }

        var currentRunLoop: CFRunLoop? {
            condition.lock()
            defer { condition.unlock() }
            return runLoop
        }

        func stop() {
            condition.lock()
            let shouldStopRunLoop: Bool
            switch decision {
            case .pending:
                decision = .cancelled
                shouldStopRunLoop = false
            case .accepted:
                // Keep the accepted decision stable so a worker released by
                // activate() still enters the run loop and drains the queued
                // stop block, even if stop() wins the scheduling race.
                shouldStopRunLoop = true
            case .cancelled:
                shouldStopRunLoop = false
            }
            let runLoop = runLoop
            condition.broadcast()
            condition.unlock()

            if shouldStopRunLoop, let runLoop {
                CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                    CFRunLoopStop(runLoop)
                }
                CFRunLoopWakeUp(runLoop)
            }
        }

        func finish() {
            condition.lock()
            decision = .cancelled
            runLoop = nil
            condition.broadcast()
            condition.unlock()
        }
    }
    
    // HID-level event tap for mouse drags during continuous gestures.
    // When macOS enters DockSwipe gesture mode, the WindowServer stops
    // forwarding otherMouseDragged events to session-level taps. This
    // HID-level tap receives events before the WindowServer processes them.
    private var dragHIDTap: CFMachPort?
    private var dragHIDRunLoopSource: CFRunLoopSource?
    
    // Middle button drag tracking
    private var middleButtonDown = false
    private var middleButtonStartPoint: CGPoint = .zero
    private var middleDragTriggered = false
    private var heldMiddleDownEvent: CGEvent?
    /// Profile key of the mouse that started the current middle-button
    /// press/drag session, so all reads during the session use one profile.
    private var middleDragProfileKey: String?
    
    // Continuous gesture (DockSwipe) state
    private let dockSwipeSimulator = DockSwipeSimulator()
    private var continuousGestureActive = false
    private var continuousGestureAxisLocked = false
    private var continuousGestureAxis: ContinuousAxis = .horizontal
    private var continuousGestureSwipeType: DockSwipeSimulator.SwipeType = .horizontal
    /// Cancels a continuous gesture if mouse-up is lost (tap timeout / secure input).
    private var continuousGestureMaxDurationWatchdog: DispatchWorkItem?
    /// Hard cap so a wedged gesture cannot keep HID drag suppression active indefinitely.
    /// Long enough for intentional Spaces/Mission Control browsing; short enough
    /// to recover from a dropped mouse-up without requiring a relaunch.
    private let continuousGestureMaxDuration: TimeInterval = 15.0

    /// When middle-click is remapped to a non-passthrough action, gesture
    /// tracking is skipped and the action runs on mouse-up instead.
    private var pendingMiddleButtonAction: MouseAction?

    /// Profile key captured at side-button mouse-down so mouse-up uses the
    /// same profile even if field-87 attribution differs.
    private var activeSideButtonProfileKeys: [Int64: String?] = [:]

    /// Guards interaction state shared by the event-tap thread, watchdogs, and
    /// main-thread stop/settings callbacks. Recursive because teardown helpers
    /// intentionally call each other.
    private let interactionLock = NSRecursiveLock()

    // Mouse-button recording happens downstream in AppKit. While a recorder is
    // open, the event tap must pass mouse-button events through instead of
    // executing/suppressing mappings before the recorder can observe them.
    private let mouseButtonRecordingLock = NSLock()
    private var mouseButtonRecordingCount = 0
    
    private enum ContinuousAxis {
        case horizontal, vertical
    }

    // Smooth scrolling state - physics engine for trackpad-like feel
    private var smoothScrollVelocityY: Double = 0
    private var displayLink: CADisplayLink?
    private var smoothScrollPhase: SmoothScrollPhase = .idle
    private let smoothScrollLock = NSLock()
    private var lastFrameTime: CFTimeInterval = 0
    private var lastInputTime: CFTimeInterval = 0
    private var needsScrollBegan: Bool = true  // Track if we need to send began phase
    private var momentumBegan: Bool = false     // Track if we've sent momentum begin phase
    private let precisionScrollTimingLock = NSLock()
    private var lastPrecisionScrollTickTimes: [String: CFTimeInterval] = [:]
    
    // Physics parameters - tuned for trackpad-like smooth scrolling
    // Uses a hybrid approach: base animation for initial scroll + drag physics for momentum
    private let pxPerTick: Double = 60.0           // Pixels per wheel tick
    private let preciseScrollSlowPixelsPerTick: Double = 10.0
    private let preciseScrollSlowTickInterval: CFTimeInterval = 0.160
    private let preciseScrollFastTickInterval: CFTimeInterval = 0.015
    private let baseMsPerStep: Double = 140.0      // Base animation duration per tick (ms) - smooth mode
    private let baseMsPerStepSmooth: Double = 220.0 // For verySmooth mode - longer animation
    private let dragCoefficient: Double = 18.0     // Drag coefficient for smooth mode
    private let dragCoefficientSmooth: Double = 25.0 // Drag coefficient for verySmooth - lower = more coast
    private let dragExponent: Double = 0.85        // Exponent < 1 = gentle decel at low speeds
    private let dragExponentSmooth: Double = 0.65  // Even gentler for verySmooth - like trackpad
    private let maxVelocity: Double = 2500.0       // Clamp to avoid absurd speeds
    private let stopSpeed: Double = 8.0            // Very low stop threshold for gentle stop
    private let inputTimeoutForMomentum: Double = 0.08 // Seconds after last input before momentum
    
    // Animation state for base curve
    private var animationDuration: Double = 0      // Duration of current animation
    private var animationStartTime: CFTimeInterval = 0
    private var targetScrollDistance: Double = 0   // Total distance to scroll this animation
    private var alreadyScrolledDistance: Double = 0 // How much we've scrolled so far
    
    private enum SmoothScrollPhase {
        case idle
        case animating   // Base curve animation (wheel being moved)
        case momentum    // Drag physics after wheel stopped
    }
    
    // Settings is used only to rebuild runtime snapshots on the main actor.
    // Event callbacks read lock-protected snapshots, and copy deviceManager
    // under interactionLock before using its nonisolated attribution API.
    private var settings: Settings?
    private var deviceManager: DeviceManager?
    
    // Lock-protected runtime config snapshot to avoid per-event main-thread sync.
    private let runtimeConfigLock = NSLock()
    private var runtimeConfig = RuntimeConfig.default
    /// Per-mouse config snapshots keyed by `HIDDevice.deviceKey`.
    /// Only populated while per-mouse settings are enabled.
    private var runtimeProfileConfigs: [String: RuntimeConfig] = [:]
    
    private struct RuntimeConfig {
        var mouseEnabled: Bool
        var shouldReverse: Bool
        /// Raw reverseScrollEnabled setting, without the global device-detection
        /// gate. Used when field-87 attribution proves the event came from an
        /// external mouse, making the global gate unnecessary.
        var reverseScrollSetting: Bool
        var smoothScrolling: SmoothScrolling
        var preciseScrolling: Bool
        var shiftHorizontal: Bool
        var optionPrecision: Bool
        var precisionMultiplier: Double
        var controlFast: Bool
        var fastMultiplier: Double
        var commandZoom: Bool
        var dragThreshold: Double
        var continuousGestures: Bool
        var middleDragMappings: [DragDirection: MouseAction]
        var buttonMappings: [Int64: MouseAction]
        
        static let `default` = RuntimeConfig(
            mouseEnabled: true,
            shouldReverse: false,
            reverseScrollSetting: false,
            smoothScrolling: .verySmooth,
            preciseScrolling: true,
            shiftHorizontal: true,
            optionPrecision: true,
            precisionMultiplier: 0.33,
            controlFast: true,
            fastMultiplier: 3.0,
            commandZoom: true,
            dragThreshold: 10.0,
            continuousGestures: true,
            middleDragMappings: [
                .up: .missionControl,
                .down: .appExpose,
                .left: .switchSpaceRight,
                .right: .switchSpaceLeft
            ],
            buttonMappings: [:]
        )
    }
    
    // Command+Scroll zoom gesture state
    private var zoomGestureActive = false
    private var zoomEndTimer: DispatchWorkItem?
    private var zoomPixelResidual: Double = 0
    private let zoomPixelsPerMagnificationUnit: Double = 800.0
    private let minimumZoomPostPixels: Double = 8.0
    /// Observation-tracked lifecycle token. Incrementing it deliberately wakes
    /// and consumes the previous one-shot runtime-config registration.
    private var runtimeObservationGeneration = 0
    
    // Marker for synthetic events we post ourselves (to avoid re-processing)
    private static let syntheticEventMarker: Int64 = 0x464C4F574D4F44  // "FLOWMOD" in hex

    // Undocumented CGEvent field carrying the IORegistry entry ID of the HID
    // event service that produced the event (0 for synthesized events).
    private static let senderIDField = CGEventField(rawValue: 87)!

    /// Which physical device an event came from, per field-87 attribution.
    private enum EventSourceKind {
        case externalMouse  // resolved to a non-Apple pointing device
        case appleDevice    // resolved to an Apple device (trackpad / Magic Mouse)
        case unknown        // synthesized or unresolvable — fall back to heuristics
    }

    /// Attribution result for a single event: the kind of device plus the
    /// settings-profile key ("vendorID:productID") when the event provably
    /// came from an external mouse.
    private struct EventSource {
        let kind: EventSourceKind
        let profileKey: String?

        static let unknown = EventSource(kind: .unknown, profileKey: nil)
    }

    private func source(of event: CGEvent) -> EventSource {
        let senderID = UInt64(bitPattern: event.getIntegerValueField(InputInterceptor.senderIDField))
        guard senderID != 0 else { return .unknown }
        // Attribution is lock-protected and resolves on this (event-tap) thread —
        // no per-event hop to the main actor.
        let manager = currentDeviceManager()
        guard let device = manager?.device(forEventSenderID: senderID) else { return .unknown }
        if device.isAppleDevice {
            return EventSource(kind: .appleDevice, profileKey: nil)
        }
        return EventSource(kind: .externalMouse, profileKey: device.deviceKey)
    }
    
    private init() {}

    private func isLifecycleRunning() -> Bool {
        interactionLock.lock()
        defer { interactionLock.unlock() }
        return isRunning
    }

    private func currentEventTap() -> CFMachPort? {
        interactionLock.lock()
        defer { interactionLock.unlock() }
        return eventTap
    }

    private func currentDragHIDTap() -> CFMachPort? {
        interactionLock.lock()
        defer { interactionLock.unlock() }
        return dragHIDTap
    }

    private func setDeviceManager(_ manager: DeviceManager?) {
        interactionLock.lock()
        deviceManager = manager
        interactionLock.unlock()
    }

    private func currentDeviceManager() -> DeviceManager? {
        interactionLock.lock()
        defer { interactionLock.unlock() }
        return deviceManager
    }

    private func clearTapThreadAttempt(ifCurrent attempt: TapRunLoopStartupAttempt) {
        tapThreadLock.lock()
        if tapThreadAttempt === attempt {
            tapThreadAttempt = nil
        }
        tapThreadLock.unlock()
    }

    private func startTapRunLoopThread() -> (attempt: TapRunLoopStartupAttempt, runLoop: CFRunLoop)? {
        let attempt = TapRunLoopStartupAttempt()
        let thread = Thread { [weak self] in
            guard let runLoop = CFRunLoopGetCurrent() else {
                attempt.failPreparation()
                self?.clearTapThreadAttempt(ifCurrent: attempt)
                return
            }

            var context = CFRunLoopSourceContext()
            guard let keepAliveSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) else {
                attempt.failPreparation()
                self?.clearTapThreadAttempt(ifCurrent: attempt)
                return
            }
            CFRunLoopAddSource(runLoop, keepAliveSource, .commonModes)

            if attempt.publishAndWaitForDecision(runLoop: runLoop) {
                CFRunLoopRun()
            }

            CFRunLoopRemoveSource(runLoop, keepAliveSource, .commonModes)
            attempt.finish()
            self?.clearTapThreadAttempt(ifCurrent: attempt)
        }

        thread.name = "com.flowmod.event-tap"
        thread.qualityOfService = .userInteractive

        tapThreadLock.lock()
        tapThreadAttempt = attempt
        tapThreadLock.unlock()

        thread.start()
        guard let runLoop = attempt.waitUntilReady(timeout: 1.0) else {
            clearTapThreadAttempt(ifCurrent: attempt)
            return nil
        }

        return (attempt, runLoop)
    }

    private func stopTapRunLoopThread() {
        tapThreadLock.lock()
        let attempt = tapThreadAttempt
        tapThreadAttempt = nil
        tapThreadLock.unlock()

        attempt?.stop()
    }

    @MainActor
    func start(settings: Settings, deviceManager: DeviceManager) {
        guard !isLifecycleRunning() else { return }

        startupError = nil
        
        self.settings = settings
        setDeviceManager(deviceManager)
        startObservingRuntimeConfig()
        
        // Define which events we want to tap
        let eventMask: CGEventMask = (
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)
        )
        
        // Create event tap with inline closure that can be converted to C function pointer
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            // Timeout: system paused a slow callback — safe to re-enable.
            // User-input disable usually means secure input / policy; do not fight it.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let userInfo = userInfo {
                    let interceptor = Unmanaged<InputInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                    interceptor.handleTapDisabled(type: type, tap: interceptor.currentEventTap())
                }
                return Unmanaged.passUnretained(event)
            }
            
            guard let userInfo = userInfo else {
                return Unmanaged.passUnretained(event)
            }
            
            let interceptor = Unmanaged<InputInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            
            if let modifiedEvent = interceptor.handleEvent(event, type: type, proxy: proxy) {
                return Unmanaged.passUnretained(modifiedEvent)
            }
            
            return nil  // Suppress event
        }
        
        // Create event tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            startupError = "FlowMod couldn't start mouse interception. Accessibility access may need to be refreshed."
            runtimeObservationGeneration += 1
            self.settings = nil
            setDeviceManager(nil)
            print("Failed to create event tap. Check accessibility permissions.")
            return
        }
        
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            startupError = "FlowMod created its mouse interceptor but couldn't attach it to the app. Try again or restart FlowMod."
            runtimeObservationGeneration += 1
            self.settings = nil
            setDeviceManager(nil)
            print("Failed to create event tap run-loop source")
            return
        }
        
        // Create HID-level event tap for mouse drags during continuous gestures.
        // This tap is at kCGHIDEventTap (before WindowServer), so it receives
        // otherMouseDragged events even during DockSwipe animations.
        // It starts DISABLED and is only enabled during continuous gestures.
        let hidDragMask: CGEventMask = (
            (1 << CGEventType.otherMouseDragged.rawValue)
        )
        var createdDragHIDTap: CFMachPort?
        var createdDragHIDRunLoopSource: CFRunLoopSource?
        
        let hidCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let userInfo = userInfo {
                    let interceptor = Unmanaged<InputInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                    interceptor.handleTapDisabled(type: type, tap: interceptor.currentDragHIDTap())
                }
                return Unmanaged.passUnretained(event)
            }
            
            guard let userInfo = userInfo else {
                return Unmanaged.passUnretained(event)
            }
            
            let interceptor = Unmanaged<InputInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            
            // Only process during active continuous gesture
            guard interceptor.isContinuousGestureActive else {
                return Unmanaged.passUnretained(event)
            }
            
            // Read deltas and feed to DockSwipe simulator
            interceptor.handleHIDDragDuringContinuousGesture(event)
            
            // Suppress the event at HID level so cursor doesn't move
            // and session-level tap doesn't see it
            return nil
        }
        
        if let hidTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: hidDragMask,
            callback: hidCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) {
            if let hidSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, hidTap, 0) {
                createdDragHIDTap = hidTap
                createdDragHIDRunLoopSource = hidSource
            } else {
                print("Warning: Failed to create HID-level drag event tap run-loop source")
            }
        } else {
            print("Warning: Failed to create HID-level drag event tap")
        }

        guard let tapThreadStartup = startTapRunLoopThread() else {
            startupError = "FlowMod created its mouse interceptor but couldn't start its event-processing thread. Try again or restart FlowMod."
            runtimeObservationGeneration += 1
            self.settings = nil
            setDeviceManager(nil)
            dragHIDRunLoopSource = nil
            print("Failed to start event tap run-loop thread")
            return
        }
        let tapRunLoop = tapThreadStartup.runLoop

        runLoopSource = source
        dragHIDRunLoopSource = createdDragHIDRunLoopSource
        CFRunLoopAddSource(tapRunLoop, source, .commonModes)
        if let hidSource = createdDragHIDRunLoopSource {
            CFRunLoopAddSource(tapRunLoop, hidSource, .commonModes)
        }
        CFRunLoopWakeUp(tapRunLoop)

        interactionLock.lock()
        eventTap = tap
        dragHIDTap = createdDragHIDTap
        isRunning = true
        interactionLock.unlock()

        CGEvent.tapEnable(tap: tap, enable: true)
        if let hidTap = createdDragHIDTap {
            // Start DISABLED — enabled only during continuous gestures
            CGEvent.tapEnable(tap: hidTap, enable: false)
            print("HID drag event tap created (disabled)")
        }
        tapThreadStartup.attempt.activate()

        print("Input interceptor started")
    }
    
    @MainActor
    func stop() {
        var wasRunning = false
        var tapToDisable: CFMachPort?
        var hidTapToDisable: CFMachPort?

        runtimeObservationGeneration += 1

        interactionLock.lock()
        wasRunning = isRunning
        isRunning = false
        interactionLock.unlock()

        // Finish synthetic gesture streams before disabling their timers/taps.
        // Leaving a began/changed stream open can make the receiving app treat
        // the next event after re-enabling FlowMod as part of the old gesture.
        finishSmoothScrollingForShutdown()

        interactionLock.lock()
        zoomEndTimer?.cancel()
        zoomEndTimer = nil
        zoomPixelResidual = 0
        if zoomGestureActive {
            postMagnificationEvent(magnification: 0, phase: 4) // ended
            zoomGestureActive = false
        }
        
        cancelContinuousGesture(force: true, reason: "interceptor stopped")
        clearButtonTrackingState()
        tapToDisable = eventTap
        hidTapToDisable = dragHIDTap
        eventTap = nil
        dragHIDTap = nil
        deviceManager = nil
        interactionLock.unlock()
        
        // Disable and clean up HID drag tap
        if let hidTap = hidTapToDisable {
            CGEvent.tapEnable(tap: hidTap, enable: false)
        }
        tapThreadLock.lock()
        let eventRunLoop = tapThreadAttempt?.currentRunLoop
        tapThreadLock.unlock()
        if let hidSource = dragHIDRunLoopSource {
            if let eventRunLoop {
                CFRunLoopRemoveSource(eventRunLoop, hidSource, .commonModes)
            }
        }
        dragHIDRunLoopSource = nil
        
        if let tap = tapToDisable {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            if let eventRunLoop {
                CFRunLoopRemoveSource(eventRunLoop, source, .commonModes)
            }
        }
        stopTapRunLoopThread()
        
        runLoopSource = nil
        settings = nil
        runtimeConfigLock.lock()
        runtimeConfig = .default
        runtimeProfileConfigs = [:]
        runtimeConfigLock.unlock()

        startupError = nil
        if wasRunning {
            print("Input interceptor stopped")
        }
    }
    
    // MARK: - Event Handling
    
    func handleEvent(_ event: CGEvent, type: CGEventType, proxy: CGEventTapProxy?) -> CGEvent? {
        // Pass through synthetic events we posted ourselves
        if event.getIntegerValueField(.eventSourceUserData) == InputInterceptor.syntheticEventMarker {
            return event
        }

        if isMouseButtonRecorderActive,
           type == .otherMouseDown || type == .otherMouseUp || type == .otherMouseDragged {
            return event
        }
        
        let config = currentRuntimeConfig()

        switch type {
        case .scrollWheel:
            guard config.mouseEnabled else { return event }
            return handleScrollEvent(event)
        case .otherMouseDown:
            guard config.mouseEnabled else {
                abandonActiveMouseInteraction(reason: "mouse disabled")
                return event
            }
            return handleOtherMouseDown(event)
        case .otherMouseUp:
            guard config.mouseEnabled else {
                abandonActiveMouseInteraction(reason: "mouse disabled")
                return event
            }
            return handleOtherMouseUp(event, proxy: proxy)
        case .otherMouseDragged:
            guard config.mouseEnabled else {
                abandonActiveMouseInteraction(reason: "mouse disabled")
                return event
            }
            return handleOtherMouseDragged(event)
        default:
            return event
        }
    }

    private var isContinuousGestureActive: Bool {
        interactionLock.lock()
        defer { interactionLock.unlock() }
        return continuousGestureActive
    }
    
    // MARK: - Scroll Handling

    private func precisionScrollTickInterval(forProfileKey key: String?, currentTime: CFTimeInterval) -> CFTimeInterval {
        let timingKey = key ?? "__default__"

        precisionScrollTimingLock.lock()
        defer { precisionScrollTimingLock.unlock() }

        let previousTime = lastPrecisionScrollTickTimes[timingKey]
        lastPrecisionScrollTickTimes[timingKey] = currentTime

        guard let previousTime else {
            return preciseScrollSlowTickInterval
        }

        let interval = currentTime - previousTime
        guard interval > 0 else {
            return preciseScrollFastTickInterval
        }

        return min(max(interval, preciseScrollFastTickInterval), preciseScrollSlowTickInterval)
    }

    private func preciseScrollPixelsPerTick(basePixelsPerTick: Double, tickInterval: CFTimeInterval) -> Double {
        guard basePixelsPerTick > preciseScrollSlowPixelsPerTick else {
            return basePixelsPerTick
        }

        let intervalRange = preciseScrollSlowTickInterval - preciseScrollFastTickInterval
        let rawProgress = (preciseScrollSlowTickInterval - tickInterval) / intervalRange
        let progress = min(max(rawProgress, 0), 1)
        let easedProgress = progress * progress * (3 - 2 * progress)

        return preciseScrollSlowPixelsPerTick + (basePixelsPerTick - preciseScrollSlowPixelsPerTick) * easedProgress
    }

    private func scaledScrollLineDelta(_ value: Double, preserveMinimum: Bool) -> Int64 {
        let rounded = Int64(value.rounded())
        guard preserveMinimum, rounded == 0, value != 0 else {
            return rounded
        }

        return value > 0 ? 1 : -1
    }
    
    private func handleScrollEvent(_ event: CGEvent) -> CGEvent? {
        // Attribute the event to a physical device via field 87. Events that
        // provably come from Apple devices (internal trackpad, Magic Mouse /
        // Trackpad) are never modified, regardless of the phase heuristics below.
        let source = self.source(of: event)
        if source.kind == .appleDevice {
            return event
        }

        // Per-mouse settings: use the device's own config snapshot when one
        // exists; otherwise (default profile, unattributed event, or feature
        // disabled) use the default config.
        let config = runtimeConfig(forProfileKey: source.profileKey)
        // When attribution proves an external mouse, reversal follows the setting
        // directly. Otherwise fall back to the global detection gate
        // (externalMouseConnected / assumeExternalMouse).
        let shouldReverse = source.kind == .externalMouse ? config.reverseScrollSetting : config.shouldReverse
        let smoothScrolling = config.smoothScrolling
        let preciseScrolling = config.preciseScrolling
        let shiftHorizontal = config.shiftHorizontal
        let optionPrecision = config.optionPrecision
        let precisionMultiplier = config.precisionMultiplier
        let controlFast = config.controlFast
        let fastMultiplier = config.fastMultiplier
        let commandZoom = config.commandZoom
        
        let flags = event.flags
        let shiftHeld = flags.contains(.maskShift)
        let optionHeld = flags.contains(.maskAlternate)
        let controlHeld = flags.contains(.maskControl)
        let commandHeld = flags.contains(.maskCommand)
        
        // Check if this is a continuous (trackpad) or discrete (mouse wheel) scroll
        // Note: Many modern mice (especially Logitech) report as continuous scroll
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        
        // Momentum phase: non-zero means trackpad momentum scrolling (fingers lifted)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        
        // Scroll phase: indicates active trackpad gesture phases
        // 0 = none (mouse), 1 = began, 2 = changed, 4 = ended, 8 = cancelled, 128 = may begin
        let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        
        // Determine if this is a mouse event (not trackpad)
        // Mouse scrolling characteristics:
        // - isContinuous may be 0 (discrete wheel) OR 1 (smooth scroll mice like Logitech MX)
        // - momentumPhase is always 0 (mice don't have momentum)
        // - scrollPhase is always 0 (mice don't have gesture phases)
        //
        // Trackpad scrolling characteristics:
        // - isContinuous is always 1
        // - scrollPhase cycles: 128 (may begin) -> 1 (began) -> 2 (changed) -> 4 (ended)
        // - momentumPhase: 0 during gesture, then 1/2/3 during momentum
        
        let isMouseScroll = momentumPhase == 0 && scrollPhase == 0
        
        // Skip processing for trackpad events
        if isContinuous && !isMouseScroll {
            return event
        }
        
        // Get all the delta values BEFORE modification
        var deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        var deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        var pixelDeltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        var pixelDeltaX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        var pointDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        var pointDeltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        
        // Command + Scroll = Zoom: convert scroll to pinch-to-zoom magnification gesture
        // Posts trackpad-style magnification events that work universally across apps
        if commandHeld && commandZoom && isMouseScroll {
            let scrollPixels: Double
            if pointDeltaY != 0 || pointDeltaX != 0 {
                scrollPixels = pointDeltaY != 0 ? pointDeltaY : pointDeltaX
            } else if pixelDeltaY != 0 || pixelDeltaX != 0 {
                scrollPixels = pixelDeltaY != 0 ? pixelDeltaY : pixelDeltaX
            } else if deltaY != 0 || deltaX != 0 {
                scrollPixels = Double(deltaY != 0 ? deltaY : deltaX) * pxPerTick
            } else {
                return nil
            }
            
            interactionLock.lock()
            zoomPixelResidual += scrollPixels
            guard abs(zoomPixelResidual) >= minimumZoomPostPixels else {
                scheduleZoomEnd()
                interactionLock.unlock()
                return nil
            }
            
            let pixelsToPost = zoomPixelResidual
            zoomPixelResidual -= pixelsToPost
            // Negate so wheel direction matches typical “scroll up = zoom in” expectation for external mice.
            let magnification = -pixelsToPost / zoomPixelsPerMagnificationUnit
            
            if !zoomGestureActive {
                zoomGestureActive = true
                postMagnificationEvent(magnification: 0, phase: 1) // began
            }
            postMagnificationEvent(magnification: magnification, phase: 2) // changed
            scheduleZoomEnd()
            interactionLock.unlock()
            return nil // Suppress original scroll event
        }
        
        // If zoom was active but Command is no longer held, end it immediately
        interactionLock.lock()
        if !commandHeld && (zoomGestureActive || zoomPixelResidual != 0) {
            zoomEndTimer?.cancel()
            zoomEndTimer = nil
            if zoomGestureActive {
                postMagnificationEvent(magnification: 0, phase: 4) // ended
                zoomGestureActive = false
            }
            zoomPixelResidual = 0
        }
        interactionLock.unlock()

        let currentTime = CACurrentMediaTime()
        
        // Apply Shift modifier: convert vertical scroll to horizontal
        if shiftHeld && shiftHorizontal && isMouseScroll {
            // Swap Y values to X
            deltaX = deltaY
            deltaY = 0
            pixelDeltaX = pixelDeltaY
            pixelDeltaY = 0
            pointDeltaX = pointDeltaY
            pointDeltaY = 0
        }
        
        // Option bypasses animation for immediate wheel response, but it still
        // applies the advertised precision multiplier.
        let optionForcesPrecision = optionHeld && optionPrecision && isMouseScroll
        let precisionScale: Double = optionForcesPrecision ? precisionMultiplier : 1.0
        
        // Apply Control modifier: speed up scroll (applies to both X and Y)
        let fastScale: Double = (controlHeld && controlFast && isMouseScroll) ? fastMultiplier : 1.0
        
        // Apply reversal if enabled - compute AFTER the swap so values are correct
        // Keep as Double for smooth scroll to preserve fractional precision
        // Note: reverseMultiplier flips direction when reverse scrolling is enabled
        let reverseMultiplier: Double = shouldReverse ? -1.0 : 1.0
        let combinedScale = precisionScale * fastScale * reverseMultiplier
        let reversedTicksY = Double(deltaY) * combinedScale
        let reversedTicksX = Double(deltaX) * combinedScale
        pixelDeltaY *= combinedScale
        pixelDeltaX *= combinedScale
        pointDeltaY *= combinedScale
        pointDeltaX *= combinedScale
        
        // Determine if this is a horizontal scroll (Shift held)
        let isHorizontalScroll = shiftHeld && shiftHorizontal && isMouseScroll
        let hasNativeHorizontalComponent = deltaX != 0 || pixelDeltaX != 0 || pointDeltaX != 0
        let controlBypassesSmooth = controlHeld && controlFast && isMouseScroll
        let hasScrollDelta = deltaY != 0 || deltaX != 0 ||
            pixelDeltaY != 0 || pixelDeltaX != 0 ||
            pointDeltaY != 0 || pointDeltaX != 0
        let autoPrecisionTickInterval: CFTimeInterval?
        if preciseScrolling && isMouseScroll && !optionHeld && !controlBypassesSmooth && hasScrollDelta {
            autoPrecisionTickInterval = precisionScrollTickInterval(
                forProfileKey: source.profileKey,
                currentTime: currentTime
            )
        } else {
            autoPrecisionTickInterval = nil
        }
        
        // If smooth scrolling is enabled for mouse events, use the smooth scroll system
        // BUT: horizontal scroll (Shift+Scroll) always bypasses smooth scrolling
        // BUT: Option held bypasses smooth scrolling (acts as if smooth scrolling is off)
        // Control+Scroll also bypasses smooth scrolling for immediate fast scroll
        if smoothScrolling != .off && isMouseScroll && !isHorizontalScroll &&
            !hasNativeHorizontalComponent && !optionHeld && !controlBypassesSmooth {
            smoothScrollLock.lock()
            
            // Calculate pixels to scroll for this tick
            let pxMultiplier = smoothScrolling == .verySmooth ? 1.3 : 1.0
            let basePixelsPerTick = pxPerTick * pxMultiplier
            let pixelsPerTick = autoPrecisionTickInterval.map {
                preciseScrollPixelsPerTick(basePixelsPerTick: basePixelsPerTick, tickInterval: $0)
            } ?? basePixelsPerTick
            let ticksY = reversedTicksY
            let pxToAddY = ticksY * pixelsPerTick
            
            // Get animation duration based on smoothness level
            let duration = (smoothScrolling == .verySmooth ? baseMsPerStepSmooth : baseMsPerStep) / 1000.0
            
            if smoothScrollPhase == .idle || smoothScrollPhase == .momentum {
                // Start fresh animation - need to send began phase
                targetScrollDistance = pxToAddY
                alreadyScrolledDistance = 0
                animationStartTime = currentTime
                animationDuration = duration
                smoothScrollVelocityY = 0
                momentumBegan = false  // Reset momentum tracking
                needsScrollBegan = true  // New scroll gesture needs began phase
            } else {
                // Accumulate: add remaining distance + new distance
                let remaining = targetScrollDistance - alreadyScrolledDistance
                targetScrollDistance = remaining + pxToAddY
                alreadyScrolledDistance = 0
                animationStartTime = currentTime
                animationDuration = duration
            }
            
            smoothScrollPhase = .animating
            lastInputTime = currentTime
            
            smoothScrollLock.unlock()
            
            // Start display link if not running
            startDisplayLink(smoothLevel: smoothScrolling)
            
            // Suppress original event - we'll post smooth events instead
            return nil
        }
        
        // Non-smooth scroll path - for horizontal scroll, disabled smooth scroll, or modifiers
        // Check if we need to modify the event at all
        let autoPrecisionScale = autoPrecisionTickInterval.map {
            preciseScrollPixelsPerTick(basePixelsPerTick: pxPerTick, tickInterval: $0) / pxPerTick
        } ?? 1.0
        let autoPrecisionModifiesEvent = autoPrecisionScale != 1.0
        let needsModification = shouldReverse || isHorizontalScroll || optionForcesPrecision ||
            (controlHeld && controlFast && isMouseScroll) || autoPrecisionModifiesEvent
        
        guard needsModification else { return event }
        
        // IMPORTANT: Order matters! Setting the integer delta fields causes macOS to
        // internally recalculate the point/fixed-pt fields. So we must either:
        // 1. Set integer delta LAST, or
        // 2. Set integer delta first, then set the others to override
        // We use approach #2: set integer delta first, then override the others
        
        // For precision scroll, we can't really reduce integer deltas below 1,
        // but the pixel/point deltas will be reduced
        let autoPrecisionTicksY = reversedTicksY * autoPrecisionScale
        let autoPrecisionTicksX = reversedTicksX * autoPrecisionScale
        let intDeltaY = scaledScrollLineDelta(
            autoPrecisionTicksY,
            preserveMinimum: autoPrecisionModifiesEvent && reversedTicksY != 0
        )
        let intDeltaX = scaledScrollLineDelta(
            autoPrecisionTicksX,
            preserveMinimum: autoPrecisionModifiesEvent && reversedTicksX != 0
        )
        
        // First, set the integer deltas (this may reset the other fields)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: intDeltaY)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: intDeltaX)
        
        // Then override with the correct modified values
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: pixelDeltaY * autoPrecisionScale)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: pixelDeltaX * autoPrecisionScale)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pointDeltaY * autoPrecisionScale)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pointDeltaX * autoPrecisionScale)
        
        return event
    }
    
    // MARK: - Magnification (Zoom) Gesture
    
    /// Post a trackpad-style magnification (pinch-to-zoom) CGEvent.
    /// Posts NSEventTypeGesture (type 29) events with subtype
    /// kIOHIDEventTypeZoom (8) to simulate trackpad pinch-to-zoom.
    private func postMagnificationEvent(magnification: Double, phase: Int64) {
        guard let event = CGEvent(source: nil) else { return }
        // Set type to NSEventTypeGesture (29)
        event.setDoubleValueField(CGEventField(rawValue: 55)!, value: 29)
        // Set subtype to kIOHIDEventTypeZoom (8)
        event.setIntegerValueField(CGEventField(rawValue: 110)!, value: 8)
        // Set IOHIDEventPhase
        event.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
        // Set magnification amount
        event.setDoubleValueField(CGEventField(rawValue: 113)!, value: magnification)
        // Post at HID level (required for system-level gesture recognition)
        event.post(tap: .cghidEventTap)
    }
    
    /// End an active zoom gesture after a delay (when scrolling stops)
    private func scheduleZoomEnd() {
        interactionLock.lock()
        defer { interactionLock.unlock() }

        zoomEndTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.interactionLock.lock()
            defer { self.interactionLock.unlock() }
            guard self.zoomGestureActive || self.zoomPixelResidual != 0 else { return }
            if self.zoomGestureActive {
                self.postMagnificationEvent(magnification: 0, phase: 4) // ended
                self.zoomGestureActive = false
            }
            self.zoomEndTimer = nil
            self.zoomPixelResidual = 0
        }
        zoomEndTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: timer)
    }
    
    // MARK: - Smooth Scrolling with Display Link
    
    private var currentSmoothLevel: SmoothScrolling = .smooth
    
    private func startDisplayLink(smoothLevel: SmoothScrolling) {
        // Ensure we're on main thread for display link setup
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.startDisplayLink(smoothLevel: smoothLevel)
            }
            return
        }
        
        currentSmoothLevel = smoothLevel
        
        // If display link already running, don't restart
        if displayLink != nil {
            return
        }
        
        // Create display link from main screen for frame-synchronized updates
        guard let screen = NSScreen.main else {
            print("Failed to get main screen for display link")
            return
        }
        
        let link = screen.displayLink(target: self, selector: #selector(displayLinkCallback(_:)))
        link.add(to: .main, forMode: .common)
        
        self.displayLink = link
        self.lastFrameTime = CACurrentMediaTime()
        
        // Don't post began here - it's handled in displayLinkCallback via needsScrollBegan flag
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTime = 0
    }

    /// End and clear the smooth-scroll state when interception stops.
    /// Synthetic end events are only posted if a gesture was actually active.
    private func finishSmoothScrollingForShutdown() {
        stopDisplayLink()

        smoothScrollLock.lock()
        let phase = smoothScrollPhase
        smoothScrollVelocityY = 0
        smoothScrollPhase = .idle
        lastFrameTime = 0
        lastInputTime = 0
        needsScrollBegan = true
        momentumBegan = false
        animationDuration = 0
        animationStartTime = 0
        targetScrollDistance = 0
        alreadyScrolledDistance = 0
        smoothScrollLock.unlock()

        switch phase {
        case .idle:
            break
        case .animating:
            postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: .ended, momentumPhase: 0)
        case .momentum:
            postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: nil, momentumPhase: 3)
            postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: .ended, momentumPhase: 0)
        }
    }
    
    @objc private func displayLinkCallback(_ link: CADisplayLink) {
        let currentTime = CACurrentMediaTime()
        let dt = lastFrameTime > 0 ? currentTime - lastFrameTime : 1.0 / 120.0
        lastFrameTime = currentTime
        
        smoothScrollLock.lock()
        
        var deltaY: Double = 0
        let deltaX: Double = 0
        var shouldSendGestureEnded = false
        
        // Check if we should transition from animating to momentum
        let timeSinceInput = currentTime - lastInputTime
        if smoothScrollPhase == .animating && timeSinceInput > inputTimeoutForMomentum {
            // Transition to momentum phase - first send "gesture ended" event
            shouldSendGestureEnded = true
            
            // Calculate exit velocity based on what we were actually scrolling at
            let elapsed = currentTime - animationStartTime
            let t = min(elapsed / animationDuration, 1.0)
            // Derivative of ease-out curve: 2 * (1 - t)
            let speedFactor = 2.0 * (1.0 - t)
            let baseSpeed = targetScrollDistance / animationDuration
            smoothScrollVelocityY = baseSpeed * speedFactor
            
            // Clamp to reasonable bounds
            let momentumMaxVelocity = maxVelocity * 0.7
            smoothScrollVelocityY = max(min(smoothScrollVelocityY, momentumMaxVelocity), -momentumMaxVelocity)
            
            smoothScrollPhase = .momentum
            momentumBegan = false  // Reset so we send begin on first momentum event
        }
        
        // Get physics params based on smooth level
        let isVerySmooth = currentSmoothLevel == .verySmooth
        let dragCoeff = isVerySmooth ? dragCoefficientSmooth : dragCoefficient
        let dragExp = isVerySmooth ? dragExponentSmooth : dragExponent
        
        if smoothScrollPhase == .animating {
            // Base animation phase - use ease-out curve
            let elapsed = currentTime - animationStartTime
            let duration = animationDuration
            
            if elapsed >= duration {
                // Animation complete, transition to momentum with exit velocity
                deltaY = targetScrollDistance - alreadyScrolledDistance
                alreadyScrolledDistance = targetScrollDistance
                
                // Calculate exit velocity based on current scroll rate
                // Since animation just ended, use a fraction of max to coast smoothly
                let momentumMaxVelocity = maxVelocity * 0.5
                smoothScrollVelocityY = deltaY / max(dt * 3, 0.025)
                smoothScrollVelocityY = max(min(smoothScrollVelocityY, momentumMaxVelocity), -momentumMaxVelocity)
                smoothScrollPhase = .momentum
                momentumBegan = false  // Reset so we send begin on first momentum event
                shouldSendGestureEnded = true  // Need to send gesture ended before momentum
            } else {
                // Ease-out curve: 1 - (1 - t)^2
                let t = elapsed / duration
                let easedT = 1.0 - pow(1.0 - t, 2.0)
                let targetScrolled = targetScrollDistance * easedT
                deltaY = targetScrolled - alreadyScrolledDistance
                alreadyScrolledDistance = targetScrolled
            }
        } else if smoothScrollPhase == .momentum {
            // Momentum phase - apply drag physics
            // Formula: velocity -= |velocity|^exp * coeff * dt * sign(velocity)
            deltaY = smoothScrollVelocityY * dt
            
            let dragY = pow(abs(smoothScrollVelocityY), dragExp) * dragCoeff * dt
            if smoothScrollVelocityY > 0 {
                smoothScrollVelocityY = max(0, smoothScrollVelocityY - dragY)
            } else {
                smoothScrollVelocityY = min(0, smoothScrollVelocityY + dragY)
            }
        }
        
        let velocityY = smoothScrollVelocityY
        let phase = smoothScrollPhase
        
        smoothScrollLock.unlock()
        
        // Stop if velocity is below stop speed (only in momentum phase)
        if phase == .momentum && abs(velocityY) < stopSpeed {
            // Post momentum end (momentumPhase=3, scrollPhase=0) then scroll ended (scrollPhase=4)
            // This sequence signals to apps that momentum has ended, triggering elastic bounce
            postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: nil, momentumPhase: 3)
            postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: .ended, momentumPhase: 0)
            
            smoothScrollLock.lock()
            smoothScrollVelocityY = 0
            targetScrollDistance = 0
            alreadyScrolledDistance = 0
            smoothScrollPhase = .idle
            needsScrollBegan = true  // Next scroll needs a began phase
            momentumBegan = false
            smoothScrollLock.unlock()
            
            stopDisplayLink()
            return
        }
        
        // Determine momentum phase for the event:
        // 0 = none (during active scrolling)
        // 1 = begin momentum
        // 2 = continuing momentum
        // 3 = end momentum
        var momentumPhaseValue: Int64 = 0
        if phase == .momentum {
            smoothScrollLock.lock()
            if !momentumBegan {
                momentumBegan = true
                momentumPhaseValue = 1  // Begin
            } else {
                momentumPhaseValue = 2  // Continuing
            }
            smoothScrollLock.unlock()
        }
        
        // Check if we need to send began phase (only for active scrolling, not momentum)
        var shouldSendBegan = false
        smoothScrollLock.lock()
        if needsScrollBegan && phase != .momentum {
            shouldSendBegan = true
            needsScrollBegan = false
        }
        smoothScrollLock.unlock()
        
        if shouldSendBegan {
            postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: .began, momentumPhase: 0)
        }
        
        // If transitioning from gesture to momentum, send gesture ended first
        // This is critical for elastic bounce - apps need to know the gesture ended before momentum starts
        if shouldSendGestureEnded {
            postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: .ended, momentumPhase: 0)
        }
        
        // Post scroll event with the calculated delta
        // During active scrolling: scrollPhase = changed, momentumPhase = 0
        // During momentum: scrollPhase = none (0), momentumPhase = 1/2/3
        // This is how trackpad events work - elastic bounce depends on this distinction
        let scrollPhase: ScrollEventPhase? = (phase == .momentum) ? nil : .changed
        postSmoothScrollEvent(deltaY: deltaY, deltaX: deltaX, phase: scrollPhase, momentumPhase: momentumPhaseValue)
    }
    
    // Scroll phases matching CGScrollPhase
    private enum ScrollEventPhase: Int64 {
        case began = 1
        case changed = 2
        case ended = 4
    }
    
    private func postSmoothScrollEvent(deltaY: Double, deltaX: Double, phase: ScrollEventPhase?, momentumPhase: Int64) {
        guard let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) else {
            return
        }
        
        // Mark as synthetic so we don't re-process
        scrollEvent.setIntegerValueField(.eventSourceUserData, value: InputInterceptor.syntheticEventMarker)
        
        // Set as continuous scroll (like trackpad) - required for smooth scrolling and elastic bounce
        scrollEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        
        // Set scroll phase - 0 during momentum phase, non-zero during active gesture
        // This distinction is what triggers elastic bounce in apps
        let scrollPhaseValue: Int64 = phase?.rawValue ?? 0
        scrollEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhaseValue)
        
        // Set momentum phase
        scrollEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        
        // Set the delta values
        scrollEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: deltaY)
        scrollEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: deltaX)
        scrollEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: deltaY)
        scrollEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: deltaX)
        
        // Post the event
        scrollEvent.post(tap: .cghidEventTap)
    }
    
    // MARK: - Mouse Button Handling
    
    private func handleOtherMouseDown(_ event: CGEvent) -> CGEvent? {
        // Button mappings target external mice — never remap Apple devices.
        // (Must stay symmetric with handleOtherMouseUp to avoid stuck buttons.)
        let eventSource = source(of: event)
        if eventSource.kind == .appleDevice {
            return event
        }
        let profileKey = eventSource.profileKey

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

        interactionLock.lock()
        defer { interactionLock.unlock() }

        // Middle button (button 2) - start tracking for drag gesture
        if buttonNumber == 2 {
            // Properly end any leftover continuous gesture from a previous interaction
            // (e.g. if a mouseUp was lost due to tap being disabled by timeout)
            cancelContinuousGesture(force: true, reason: "new middle-button press")
            continuousGestureAxisLocked = false
            pendingMiddleButtonAction = nil
            middleDragTriggered = false
            heldMiddleDownEvent = nil
            middleDragProfileKey = profileKey
            middleButtonStartPoint = event.location
            
            // Check if middle click has a mapping AND if drag gestures are configured.
            let config = runtimeConfig(forProfileKey: profileKey)
            let action = config.buttonMappings[2]
            let hasDragGestures = !config.middleDragMappings.isEmpty

            // Remapped middle button (including explicit .none): do not run drag
            // gestures — only the mapped click action (or swallow for .none).
            if let action, action != .middleClick {
                middleButtonDown = false
                heldMiddleDownEvent = nil
                pendingMiddleButtonAction = action
                return nil
            }

            // Passthrough middle click (unmapped or .middleClick): optional gestures
            middleButtonDown = true
            pendingMiddleButtonAction = nil

            if hasDragGestures {
                // Suppress mouseDown: drag gesture detection needs to decide
                // whether this is a click or a gesture. If no gesture triggers,
                // we'll replay this down immediately before the physical up.
                guard let heldDown = event.copy() else {
                    middleButtonDown = false
                    return event
                }
                heldMiddleDownEvent = heldDown
                return nil
            }
            return event
        }
        
        // All other buttons (3, 4, 5+) - check for custom mappings
        return handleMouseButtonAction(buttonNumber: buttonNumber, profileKey: profileKey, originalEvent: event)
    }

    private func handleOtherMouseUp(_ event: CGEvent, proxy: CGEventTapProxy?) -> CGEvent? {
        // Symmetric with handleOtherMouseDown: Apple device events pass through.
        let eventSource = source(of: event)
        if eventSource.kind == .appleDevice {
            return event
        }

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

        interactionLock.lock()
        defer { interactionLock.unlock() }

        if buttonNumber == 2 {
            // Use the profile captured at mouseDown so the up-decision matches
            // the down-decision even if attribution differs.
            let profileKey = middleDragProfileKey
            let pendingAction = pendingMiddleButtonAction
            defer {
                middleButtonDown = false
                middleDragTriggered = false
                heldMiddleDownEvent = nil
                middleDragProfileKey = nil
                continuousGestureAxisLocked = false
                pendingMiddleButtonAction = nil
            }
            
            // End continuous gesture if active
            if continuousGestureActive {
                cancelContinuousGesture(force: false, reason: "middle-button release")
                return nil
            }
            
            // If drag gesture was triggered, suppress the mouse up
            if middleDragTriggered {
                return nil
            }

            // Remapped middle button: execute (or swallow .none) using the
            // action captured at mouse-down.
            if let pendingAction {
                if pendingAction != .none {
                    executeAction(pendingAction, at: event.location)
                }
                return nil
            }
            
            // Otherwise, check middle click action and drag gesture configuration.
            let config = runtimeConfig(forProfileKey: profileKey)
            let action = config.buttonMappings[2]
            let hasDragGestures = !config.middleDragMappings.isEmpty
            
            // If no mapping or action is just middle click
            if action == nil || action == .middleClick {
                if hasDragGestures {
                    if let proxy {
                        // Insert the original down immediately before returning
                        // the physical up. Quartz explicitly guarantees this
                        // ordering for events posted through the tap proxy.
                        guard replayHeldMiddleDown(proxy: proxy) else { return event }
                        return event
                    }

                    // Normal callbacks always supply a proxy. Retain a complete
                    // private synthetic pair for direct/recovery invocation.
                    guard replayHeldMiddleClickFallback(upLocation: event.location) else { return event }
                    return nil
                }
                return event
            }
            
            // Execute the custom action on mouse up (for click-style actions)
            executeAction(action!, at: event.location)
            return nil
        }
        
        // Suppress up events for buttons that had mappings on mouse-down,
        // using the profile captured then so attribution can't desync the pair.
        if activeSideButtonProfileKeys.removeValue(forKey: buttonNumber) != nil {
            return nil
        }

        let hasMapping = runtimeConfig(forProfileKey: eventSource.profileKey).buttonMappings[buttonNumber] != nil
        if hasMapping {
            return nil
        }
        
        return event
    }
    
    private func handleOtherMouseDragged(_ event: CGEvent) -> CGEvent? {
        interactionLock.lock()
        defer { interactionLock.unlock() }

        guard middleButtonDown else { return event }
        
        // If a continuous gesture is already active, the HID-level tap handles updates.
        // The session tap may not receive drags during DockSwipe, so we just suppress here.
        if continuousGestureActive {
            return nil  // Suppress mouse moved events during gesture
        }
        
        // Not yet triggered — check for threshold
        guard !middleDragTriggered else { return event }
        
        let currentPoint = event.location
        let deltaX = currentPoint.x - middleButtonStartPoint.x
        let deltaY = currentPoint.y - middleButtonStartPoint.y
        
        let config = runtimeConfig(forProfileKey: middleDragProfileKey)
        let threshold = config.dragThreshold
        let useContinuous = config.continuousGestures
        
        // For continuous mode, determine axis early with a smaller dead zone,
        // but only commit the gesture once the full drag threshold is crossed.
        if useContinuous {
            let axisThreshold = threshold * 0.5  // Smaller threshold for axis detection
            
            if !continuousGestureAxisLocked,
               abs(deltaX) > axisThreshold || abs(deltaY) > axisThreshold {
                if abs(deltaY) > abs(deltaX) {
                    continuousGestureAxis = .vertical
                } else {
                    continuousGestureAxis = .horizontal
                }
                continuousGestureAxisLocked = true
            }

            guard abs(deltaX) > threshold || abs(deltaY) > threshold else {
                return event
            }

            // Commit using the dominant movement at the full threshold, so a
            // tiny early jitter cannot lock the eventual gesture to the wrong axis.
            if abs(deltaY) > abs(deltaX) {
                continuousGestureAxis = .vertical
            } else {
                continuousGestureAxis = .horizontal
            }
            continuousGestureAxisLocked = true

            // Continuous mode is a fixed three-finger trackpad-swipe
            // simulation. It deliberately ignores the configurable
            // direction actions: horizontal swipes switch Spaces and
            // vertical swipes drive Mission Control/App Exposé.
            let swipeType: DockSwipeSimulator.SwipeType =
                continuousGestureAxis == .horizontal ? .horizontal : .vertical

            // Began must carry the accumulated offset. A zero-offset
            // began + later changed update regresses Mission Control
            // (middle-button swipe up); App Exposé / Spaces are more
            // tolerant. Screen size comes from CGDisplayBounds, not
            // AppKit NSScreen.
            let initialPixels = continuousGestureAxis == .horizontal ? deltaX : deltaY
            let initialDelta = -DockSwipeSimulator.pixelToDockSwipe(
                initialPixels,
                type: swipeType
            )

            continuousGestureActive = true
            continuousGestureSwipeType = swipeType
            middleDragTriggered = true
            heldMiddleDownEvent = nil

            // Enable HID-level event tap to receive drags during gesture
            if let hidTap = dragHIDTap {
                CGEvent.tapEnable(tap: hidTap, enable: true)
            }

            dockSwipeSimulator.begin(type: swipeType, delta: initialDelta, dragThreshold: threshold)
            armContinuousGestureWatchdogs()

            LogManager.shared.log("Continuous gesture began: \(swipeType) axis=\(continuousGestureAxis)", category: "Gesture")
            return nil
        }
        
        // Trigger mode (original behavior) — or continuous not supported for this action
        var direction: DragDirection?
        
        // Determine dominant direction
        if abs(deltaY) > abs(deltaX) {
            if deltaY < -threshold {
                direction = .up  // Note: negative Y is up in screen coordinates
            } else if deltaY > threshold {
                direction = .down
            }
        } else {
            if deltaX < -threshold {
                direction = .left
            } else if deltaX > threshold {
                direction = .right
            }
        }
        
        if let dir = direction {
            middleDragTriggered = true
            heldMiddleDownEvent = nil
            
            let action = config.middleDragMappings[dir] ?? .none
            
            if action != .none {
                executeAction(action, at: currentPoint)
            }
        }
        
        return event
    }
    
    private func handleMouseButtonAction(buttonNumber: Int64, profileKey: String?, originalEvent: CGEvent) -> CGEvent? {
        interactionLock.lock()
        defer { interactionLock.unlock() }

        let action = runtimeConfig(forProfileKey: profileKey).buttonMappings[buttonNumber]
        
        // If no mapping, pass through the event
        guard let action = action else {
            activeSideButtonProfileKeys.removeValue(forKey: buttonNumber)
            return originalEvent
        }

        // Remember that we consumed this button so mouse-up stays paired.
        activeSideButtonProfileKeys[buttonNumber] = profileKey
        
        // For .none, suppress the event entirely
        if action == .none {
            return nil
        }
        
        // Execute the action (including synthesizing a middle click when mapped)
        executeAction(action, at: originalEvent.location)
        return nil  // Suppress the original mouse button event
    }
    
    // MARK: - Action Execution
    
    private func executeAction(_ action: MouseAction, at location: CGPoint = .zero) {
        LogManager.shared.log("Executing action: \(action.debugLabel)", category: "Action")
        
        switch action {
        case .none:
            break
            
        case .missionControl:
            triggerMissionControl()
            
        case .showDesktop:
            triggerShowDesktop()
            
        case .launchpad:
            triggerLaunchpad()
            
        case .back:
            sendKeyCombo(KeyCombo(keyCode: 0x21, modifiers: CGEventFlags.maskCommand.rawValue)) // ⌘[
            
        case .forward:
            sendKeyCombo(KeyCombo(keyCode: 0x1E, modifiers: CGEventFlags.maskCommand.rawValue)) // ⌘]
            
        case .middleClick:
            postSyntheticMiddleClick(at: location)
            
        case .copy:
            sendKeyCombo(KeyCombo(keyCode: 0x08, modifiers: CGEventFlags.maskCommand.rawValue)) // ⌘C
            
        case .cut:
            sendKeyCombo(KeyCombo(keyCode: 0x07, modifiers: CGEventFlags.maskCommand.rawValue)) // ⌘X
            
        case .paste:
            sendKeyCombo(KeyCombo(keyCode: 0x09, modifiers: CGEventFlags.maskCommand.rawValue)) // ⌘V
            
        case .undo:
            sendKeyCombo(KeyCombo(keyCode: 0x06, modifiers: CGEventFlags.maskCommand.rawValue)) // ⌘Z
            
        case .redo:
            sendKeyCombo(KeyCombo(keyCode: 0x06, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)) // ⇧⌘Z
            
        case .selectAll:
            sendKeyCombo(KeyCombo(keyCode: 0x00, modifiers: CGEventFlags.maskCommand.rawValue)) // ⌘A
            
        case .fullscreen:
            sendKeyCombo(KeyCombo(keyCode: 0x03, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue)) // ⌃⌘F
            
        case .switchSpaceLeft:
            triggerSwitchSpaceLeft()
            
        case .switchSpaceRight:
            triggerSwitchSpaceRight()
            
        case .appExpose:
            triggerAppExpose()
            
        case .customShortcut(let combo):
            sendKeyCombo(combo)
        }
    }
    
    private func sendKeyCombo(_ combo: KeyCombo) {
        LogManager.shared.log("Sending key combo: \(combo.debugLabel)", category: "Input")
        
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = CGEventFlags(rawValue: combo.modifiers)
        
        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true) {
            keyDown.flags = flags
            keyDown.setIntegerValueField(.eventSourceUserData, value: InputInterceptor.syntheticEventMarker)
            keyDown.post(tap: .cghidEventTap)
        }
        
        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false) {
            keyUp.flags = flags
            keyUp.setIntegerValueField(.eventSourceUserData, value: InputInterceptor.syntheticEventMarker)
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    private func markMiddleClickEventForPassthrough(_ event: CGEvent, clickState: Int64 = 1) {
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        event.setIntegerValueField(.eventSourceUserData, value: InputInterceptor.syntheticEventMarker)
        event.setIntegerValueField(.mouseEventClickState, value: max(clickState, 1))
    }

    /// Inserts the buffered physical down immediately downstream of this tap.
    /// The callback then returns the physical up, preserving all event metadata
    /// while giving Quartz an explicit down-before-up ordering.
    private func replayHeldMiddleDown(proxy: CGEventTapProxy) -> Bool {
        guard let down = heldMiddleDownEvent else { return false }
        heldMiddleDownEvent = nil
        down.tapPostEvent(proxy)
        return true
    }

    private func replayHeldMiddleClickFallback(upLocation: CGPoint? = nil) -> Bool {
        guard let down = heldMiddleDownEvent else { return false }
        heldMiddleDownEvent = nil
        postSyntheticMiddleClick(
            downAt: down.location,
            upAt: upLocation ?? down.location,
            clickState: down.getIntegerValueField(.mouseEventClickState)
        )
        return true
    }

    /// Post a synthetic middle-click (otherMouseDown + otherMouseUp).
    /// Used when the real middle-down was swallowed for gesture detection, and
    /// when another button is remapped to Middle Click.
    private func postSyntheticMiddleClick(at location: CGPoint) {
        postSyntheticMiddleClick(downAt: location, upAt: location, clickState: 1)
    }

    private func postSyntheticMiddleClick(downAt downLocation: CGPoint, upAt upLocation: CGPoint, clickState: Int64) {
        // privateState keeps this pair independent of the physical middle
        // button, which is already down (swallowed) or going up.
        let source = CGEventSource(stateID: .privateState)

        if let down = CGEvent(mouseEventSource: source, mouseType: .otherMouseDown, mouseCursorPosition: downLocation, mouseButton: .center) {
            markMiddleClickEventForPassthrough(down, clickState: clickState)
            down.post(tap: .cghidEventTap)
        }

        if let up = CGEvent(mouseEventSource: source, mouseType: .otherMouseUp, mouseCursorPosition: upLocation, mouseButton: .center) {
            markMiddleClickEventForPassthrough(up, clickState: clickState)
            up.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - System Triggers
    
    private func triggerMissionControl() {
        // Use the Mission Control virtual key code (0xA0).
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Send Mission Control key
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0xA0, keyDown: true) {
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0xA0, keyDown: false) {
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    private func triggerShowDesktop() {
        // Use Fn+F11 (F11 = 0x67) as Show Desktop trigger
        // On most Macs, F11 is the default Show Desktop key
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Send F11 key with Fn modifier (secondary function)
        // Key code 0x67 = F11
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x67, keyDown: true) {
            keyDown.flags = .maskSecondaryFn
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x67, keyDown: false) {
            keyUp.flags = .maskSecondaryFn
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    private func triggerLaunchpad() {
        // Launchpad key
        let source = CGEventSource(stateID: .hidSystemState)
        
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x83, keyDown: true) {
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x83, keyDown: false) {
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    private func triggerSwitchSpaceLeft() {
        // Use private CGS Symbolic Hotkey API to trigger space switching
        LogManager.shared.log("Sending Switch Space Left via CGS SymbolicHotkeys API", category: "Action")
        SymbolicHotkeys.post(.moveLeftASpace)
    }
    
    private func triggerSwitchSpaceRight() {
        // Use private CGS Symbolic Hotkey API to trigger space switching
        LogManager.shared.log("Sending Switch Space Right via CGS SymbolicHotkeys API", category: "Action")
        SymbolicHotkeys.post(.moveRightASpace)
    }
    
    private func triggerAppExpose() {
        // Use private CGS Symbolic Hotkey API to trigger App Exposé
        LogManager.shared.log("Sending App Exposé via CGS SymbolicHotkeys API", category: "Action")
        SymbolicHotkeys.post(.applicationWindows)
    }
    
    // MARK: - HID-Level Drag Handler (Continuous Gestures)
    
    /// Called from the HID-level event tap callback during active continuous gestures.
    /// This receives otherMouseDragged events even while macOS is in DockSwipe
    /// gesture mode (Spaces animation), which blocks session-level taps.
    func handleHIDDragDuringContinuousGesture(_ event: CGEvent) {
        interactionLock.lock()
        defer { interactionLock.unlock() }

        guard continuousGestureActive else { return }

        let pixelDX = Double(event.getIntegerValueField(.mouseEventDeltaX))
        let pixelDY = Double(event.getIntegerValueField(.mouseEventDeltaY))
        
        guard pixelDX != 0 || pixelDY != 0 else { return }
        
        // Convert pixel deltas to DockSwipe units using cached scaling
        if continuousGestureAxis == .horizontal {
            let swipeDelta = -dockSwipeSimulator.pixelToDockSwipeScaled(pixelDX, type: continuousGestureSwipeType)
            dockSwipeSimulator.update(delta: swipeDelta)
        } else {
            let swipeDelta = -dockSwipeSimulator.pixelToDockSwipeScaled(pixelDY, type: continuousGestureSwipeType)
            dockSwipeSimulator.update(delta: swipeDelta)
        }
    }
    
    // MARK: - Continuous Gesture Helpers

    /// Re-enable after timeout immediately. For user-input disable (secure
    /// input / system policy), cancel any stuck gesture and retry enable
    /// shortly afterward so the session tap is not left permanently dead.
    /// The HID drag tap is only re-enabled while a continuous gesture is active.
    private func handleTapDisabled(type: CGEventType, tap: CFMachPort?) {
        interactionLock.lock()
        let hasActiveInteraction = continuousGestureActive || middleButtonDown || pendingMiddleButtonAction != nil
        interactionLock.unlock()

        if hasActiveInteraction {
            abandonActiveMouseInteraction(
                reason: "event tap disabled (\(type.rawValue))",
                replayPendingMiddleClick: type == .tapDisabledByTimeout
            )
        }

        guard let tap else { return }

        let reenable: () -> Void = { [weak self] in
            guard let self else { return }

            let tapUpdate: (tap: CFMachPort, enable: Bool)?
            self.interactionLock.lock()
            if self.isRunning, let eventTap = self.eventTap, CFEqual(tap, eventTap) {
                tapUpdate = (eventTap, true)
            } else if self.isRunning, let hidTap = self.dragHIDTap, CFEqual(tap, hidTap) {
                // HID tap must stay off except during an active continuous gesture.
                tapUpdate = (hidTap, self.continuousGestureActive)
            } else {
                tapUpdate = nil
            }
            self.interactionLock.unlock()

            if let tapUpdate {
                CGEvent.tapEnable(tap: tapUpdate.tap, enable: tapUpdate.enable)
            }
        }

        if type == .tapDisabledByTimeout {
            reenable()
            return
        }

        if type == .tapDisabledByUserInput {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: reenable)
        }
    }

    private func abandonActiveMouseInteraction(
        reason: String,
        replayPendingMiddleClick: Bool = false
    ) {
        interactionLock.lock()
        defer { interactionLock.unlock() }

        let wasContinuous = continuousGestureActive
        let wasTrackingMiddle = middleButtonDown
        let wasMiddleGesture = middleDragTriggered
        let hadHeldMiddleDown = heldMiddleDownEvent != nil
        let hadPendingMiddleAction = pendingMiddleButtonAction != nil
        let shouldReplayHeldClick =
            replayPendingMiddleClick &&
            wasTrackingMiddle &&
            !wasContinuous &&
            !wasMiddleGesture &&
            !hadPendingMiddleAction &&
            hadHeldMiddleDown

        if shouldReplayHeldClick {
            _ = replayHeldMiddleClickFallback()
        }

        cancelContinuousGesture(force: true, reason: reason)
        clearButtonTrackingState()

        if shouldReplayHeldClick {
            return
        }

        // If middle-down was suppressed for gesture detection, continuous mode,
        // or a remapped middle action, the eventual mouse-up must not click or
        // re-fire the action.
        if wasContinuous || wasMiddleGesture || hadHeldMiddleDown || hadPendingMiddleAction {
            middleDragTriggered = true
        }
    }

    private func clearButtonTrackingState() {
        interactionLock.lock()
        defer { interactionLock.unlock() }

        middleButtonDown = false
        middleButtonStartPoint = .zero
        middleDragTriggered = false
        heldMiddleDownEvent = nil
        middleDragProfileKey = nil
        continuousGestureAxisLocked = false
        continuousGestureAxis = .horizontal
        continuousGestureSwipeType = .horizontal
        pendingMiddleButtonAction = nil
        activeSideButtonProfileKeys.removeAll()
    }

    private func cancelContinuousGesture(force: Bool, reason: String) {
        interactionLock.lock()
        defer { interactionLock.unlock() }

        continuousGestureMaxDurationWatchdog?.cancel()
        continuousGestureMaxDurationWatchdog = nil

        guard continuousGestureActive else { return }

        continuousGestureActive = false
        if force {
            dockSwipeSimulator.forceCancel()
        } else {
            dockSwipeSimulator.end(cancel: false)
        }
        if let hidTap = dragHIDTap {
            CGEvent.tapEnable(tap: hidTap, enable: false)
        }
        LogManager.shared.log(
            force ? "Continuous gesture cancelled (\(reason))" : "Continuous gesture ended (\(reason))",
            category: "Gesture"
        )
    }

    private func armContinuousGestureWatchdogs() {
        interactionLock.lock()
        defer { interactionLock.unlock() }

        continuousGestureMaxDurationWatchdog?.cancel()
        let maxWork = DispatchWorkItem { [weak self] in
            self?.watchdogCancelContinuousGesture(reason: "max duration timeout")
        }
        continuousGestureMaxDurationWatchdog = maxWork
        DispatchQueue.main.asyncAfter(deadline: .now() + continuousGestureMaxDuration, execute: maxWork)
    }

    private func watchdogCancelContinuousGesture(reason: String) {
        interactionLock.lock()
        defer { interactionLock.unlock() }

        guard continuousGestureActive else { return }
        abandonActiveMouseInteraction(reason: reason)
    }

    // MARK: - Mouse Button Recording
    
    @MainActor
    func beginMouseButtonRecording() {
        mouseButtonRecordingLock.lock()
        mouseButtonRecordingCount += 1
        mouseButtonRecordingLock.unlock()
    }

    @MainActor
    func endMouseButtonRecording() {
        mouseButtonRecordingLock.lock()
        mouseButtonRecordingCount = max(0, mouseButtonRecordingCount - 1)
        mouseButtonRecordingLock.unlock()
    }

    private var isMouseButtonRecorderActive: Bool {
        mouseButtonRecordingLock.lock()
        defer { mouseButtonRecordingLock.unlock() }
        return mouseButtonRecordingCount > 0
    }
    
    private func currentRuntimeConfig() -> RuntimeConfig {
        runtimeConfigLock.lock()
        let config = runtimeConfig
        runtimeConfigLock.unlock()
        return config
    }

    /// The config snapshot for a given profile key, falling back to the
    /// default config when the key is nil or has no profile.
    private func runtimeConfig(forProfileKey key: String?) -> RuntimeConfig {
        runtimeConfigLock.lock()
        defer { runtimeConfigLock.unlock() }
        if let key, let config = runtimeProfileConfigs[key] {
            return config
        }
        if let key {
            let legacyKey = Settings.legacyProfileKey(for: key)
            if legacyKey != key, let config = runtimeProfileConfigs[legacyKey] {
                return config
            }
        }
        return runtimeConfig
    }
    
    @MainActor
    private func startObservingRuntimeConfig() {
        runtimeObservationGeneration += 1
        observeRuntimeConfigChanges(generation: runtimeObservationGeneration)
    }
    
    /// Build a RuntimeConfig snapshot from a profile plus the global gates.
    @MainActor
    private static func makeRuntimeConfig(
        profile: ProfileSettings,
        mouseEnabled: Bool,
        assumeExternalMouse: Bool,
        externalMouseConnected: Bool,
        dragThreshold: Double
    ) -> RuntimeConfig {
        let reverse = profile.reverseScrollEnabled && (assumeExternalMouse || externalMouseConnected)
        return RuntimeConfig(
            mouseEnabled: mouseEnabled,
            shouldReverse: reverse,
            reverseScrollSetting: profile.reverseScrollEnabled,
            smoothScrolling: profile.smoothScrolling,
            preciseScrolling: profile.preciseScrolling,
            shiftHorizontal: profile.shiftHorizontalScroll,
            optionPrecision: profile.optionPrecisionScroll,
            precisionMultiplier: profile.precisionScrollMultiplier,
            controlFast: profile.controlFastScroll,
            fastMultiplier: profile.fastScrollMultiplier,
            commandZoom: profile.commandZoomScroll,
            dragThreshold: dragThreshold,
            continuousGestures: profile.continuousGestures,
            middleDragMappings: profile.middleDragMappings,
            buttonMappings: Self.makeButtonMappings(from: profile.customMouseButtonMappings)
        )
    }

    private static func makeButtonMappings(from mappings: [CustomMouseButtonMapping]) -> [Int64: MouseAction] {
        var snapshot: [Int64: MouseAction] = [:]
        for mapping in mappings where snapshot[mapping.buttonNumber] == nil {
            snapshot[mapping.buttonNumber] = mapping.action
        }
        return snapshot
    }

    @MainActor
    private func observeRuntimeConfigChanges(generation: Int) {
        guard generation == runtimeObservationGeneration else { return }

        withObservationTracking {
            // Keep the generation inside the tracked dependency set. Lifecycle
            // invalidation then fires and consumes this one-shot registration;
            // the outer guard prevents its stale callback from rearming.
            guard generation == runtimeObservationGeneration else { return }

            guard let settings else {
                runtimeConfigLock.lock()
                runtimeConfig = .default
                runtimeProfileConfigs = [:]
                runtimeConfigLock.unlock()
                return
            }

            let mouseEnabled = settings.mouseEnabled
            let assumeExternal = settings.assumeExternalMouse
            let externalConnected = currentDeviceManager()?.externalMouseConnected ?? false
            let dragThreshold = settings.dragThreshold

            let snapshot = Self.makeRuntimeConfig(
                profile: settings.defaultProfile,
                mouseEnabled: mouseEnabled,
                assumeExternalMouse: assumeExternal,
                externalMouseConnected: externalConnected,
                dragThreshold: dragThreshold
            )

            // Snapshot each per-mouse profile (only while the feature is on).
            var profileSnapshots: [String: RuntimeConfig] = [:]
            if settings.perMouseSettingsEnabled {
                for (key, profile) in settings.mouseProfiles {
                    profileSnapshots[key] = Self.makeRuntimeConfig(
                        profile: profile,
                        mouseEnabled: mouseEnabled,
                        assumeExternalMouse: assumeExternal,
                        externalMouseConnected: externalConnected,
                        dragThreshold: dragThreshold
                    )
                }
            }

            runtimeConfigLock.lock()
            runtimeConfig = snapshot
            runtimeProfileConfigs = profileSnapshots
            runtimeConfigLock.unlock()

            // mouseEnabled can flip without going through stop(). Clear any
            // active continuous gesture so HID drag suppression cannot stay wedged.
            if !mouseEnabled {
                abandonActiveMouseInteraction(reason: "mouseEnabled turned off")
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeRuntimeConfigChanges(generation: generation)
            }
        }
    }
}
