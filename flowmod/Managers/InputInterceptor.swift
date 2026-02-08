import Foundation
import CoreGraphics
import AppKit
import Observation
import QuartzCore

/// Intercepts and modifies mouse and keyboard events
@Observable
class InputInterceptor {
    static let shared = InputInterceptor()
    
    private(set) var isRunning = false
    
    // Made internal for callback access
    var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
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
    
    // Continuous gesture (DockSwipe) state
    private let dockSwipeSimulator = DockSwipeSimulator()
    private var continuousGestureActive = false
    private var continuousGestureAxisLocked = false
    private var continuousGestureAxis: ContinuousAxis = .horizontal
    
    private enum ContinuousAxis {
        case horizontal, vertical
    }
    
    // Smooth scrolling state - physics engine for trackpad-like feel
    private var smoothScrollVelocityY: Double = 0
    private var smoothScrollVelocityX: Double = 0
    private var displayLink: CADisplayLink?
    private var smoothScrollPhase: SmoothScrollPhase = .idle
    private let smoothScrollLock = NSLock()
    private var lastFrameTime: CFTimeInterval = 0
    private var lastInputTime: CFTimeInterval = 0
    private var needsScrollBegan: Bool = true  // Track if we need to send began phase
    private var momentumBegan: Bool = false     // Track if we've sent momentum begin phase
    
    // Physics parameters - tuned for trackpad-like smooth scrolling
    // Uses a hybrid approach: base animation for initial scroll + drag physics for momentum
    private let pxPerTick: Double = 60.0           // Pixels per wheel tick
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
    
    // Settings reference (accessed on callback thread, needs care)
    private var settings: Settings?
    private var deviceManager: DeviceManager?
    
    // Cached frontmost app bundle ID (updated via notification, not queried per-event)
    private var cachedFrontmostBundleID: String?
    
    // Command+Scroll zoom gesture state
    private var zoomGestureActive = false
    private var zoomEndTimer: DispatchWorkItem?
    
    // Marker for synthetic events we post ourselves (to avoid re-processing)
    private static let syntheticEventMarker: Int64 = 0x464C4F574D4F44  // "FLOWMOD" in hex
    
    private init() {}
    
    // MARK: - Thread-safe Settings Access
    
    /// Safely execute a closure on the main thread, avoiding deadlock if already on main
    private func onMain<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        } else {
            return DispatchQueue.main.sync { block() }
        }
    }
    
    @objc private func frontmostAppDidChange(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            cachedFrontmostBundleID = app.bundleIdentifier
        }
    }
    
    @MainActor
    func start(settings: Settings, deviceManager: DeviceManager) {
        guard !isRunning else { return }
        
        self.settings = settings
        self.deviceManager = deviceManager
        
        // Cache frontmost app and observe changes (avoids querying per-event)
        cachedFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Define which events we want to tap
        let eventMask: CGEventMask = (
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )
        
        // Create event tap with inline closure that can be converted to C function pointer
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            // Handle tap disabled events (system may disable tap temporarily)
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let userInfo = userInfo {
                    let interceptor = Unmanaged<InputInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                    if let tap = interceptor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                }
                return Unmanaged.passRetained(event)
            }
            
            guard let userInfo = userInfo else {
                return Unmanaged.passRetained(event)
            }
            
            let interceptor = Unmanaged<InputInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            
            if let modifiedEvent = interceptor.handleEvent(event, type: type) {
                return Unmanaged.passRetained(modifiedEvent)
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
            print("Failed to create event tap. Check accessibility permissions.")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isRunning = true
            print("Input interceptor started")
        }
        
        // Create HID-level event tap for mouse drags during continuous gestures.
        // This tap is at kCGHIDEventTap (before WindowServer), so it receives
        // otherMouseDragged events even during DockSwipe animations.
        // It starts DISABLED and is only enabled during continuous gestures.
        let hidDragMask: CGEventMask = (
            (1 << CGEventType.otherMouseDragged.rawValue)
        )
        
        let hidCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let userInfo = userInfo {
                    let interceptor = Unmanaged<InputInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                    if let tap = interceptor.dragHIDTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                }
                return Unmanaged.passRetained(event)
            }
            
            guard let userInfo = userInfo else {
                return Unmanaged.passRetained(event)
            }
            
            let interceptor = Unmanaged<InputInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            
            // Only process during active continuous gesture
            guard interceptor.continuousGestureActive else {
                return Unmanaged.passRetained(event)
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
            dragHIDTap = hidTap
            dragHIDRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, hidTap, 0)
            if let hidSource = dragHIDRunLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), hidSource, .commonModes)
                // Start DISABLED — enabled only during continuous gestures
                CGEvent.tapEnable(tap: hidTap, enable: false)
                print("HID drag event tap created (disabled)")
            }
        } else {
            print("Warning: Failed to create HID-level drag event tap")
        }
    }
    
    @MainActor
    func stop() {
        // Stop smooth scrolling display link
        stopDisplayLink()
        
        // Remove workspace observer
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        cachedFrontmostBundleID = nil
        
        // Cancel any active continuous gesture
        if continuousGestureActive {
            continuousGestureActive = false
            dockSwipeSimulator.forceCancel()
            if let hidTap = dragHIDTap {
                CGEvent.tapEnable(tap: hidTap, enable: false)
            }
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        
        // Disable and clean up HID drag tap
        if let hidTap = dragHIDTap {
            CGEvent.tapEnable(tap: hidTap, enable: false)
        }
        if let hidSource = dragHIDRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), hidSource, .commonModes)
        }
        dragHIDTap = nil
        dragHIDRunLoopSource = nil
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        print("Input interceptor stopped")
    }
    
    // MARK: - Event Handling
    
    func handleEvent(_ event: CGEvent, type: CGEventType) -> CGEvent? {
        // Pass through synthetic events we posted ourselves
        if event.getIntegerValueField(.eventSourceUserData) == InputInterceptor.syntheticEventMarker {
            return event
        }

        // Check master toggles (read on main thread)
        let (mouseEnabled, keyboardEnabled) = onMain {
            (settings?.mouseEnabled ?? true, settings?.keyboardEnabled ?? true)
        }

        switch type {
        case .scrollWheel:
            guard mouseEnabled else { return event }
            return handleScrollEvent(event)
        case .otherMouseDown:
            guard mouseEnabled else { return event }
            return handleOtherMouseDown(event)
        case .otherMouseUp:
            guard mouseEnabled else { return event }
            return handleOtherMouseUp(event)
        case .otherMouseDragged:
            guard mouseEnabled else { return event }
            return handleOtherMouseDragged(event)
        case .keyDown:
            guard keyboardEnabled else { return event }
            return handleKeyDown(event)
        case .keyUp:
            guard keyboardEnabled else { return event }
            return handleKeyUp(event)
        default:
            return event
        }
    }
    
    // MARK: - Scroll Handling
    
    private func handleScrollEvent(_ event: CGEvent) -> CGEvent? {
        guard let settings = settings else { return event }
        
        // Get settings on main thread
        let (shouldReverse, smoothScrolling, shiftHorizontal, optionPrecision, precisionMultiplier, controlFast, fastMultiplier, commandZoom) = onMain {
            let reverse = settings.reverseScrollEnabled && (settings.assumeExternalMouse || (deviceManager?.externalMouseConnected ?? false))
            return (reverse, settings.smoothScrolling, settings.shiftHorizontalScroll, settings.optionPrecisionScroll, settings.precisionScrollMultiplier, settings.controlFastScroll, settings.fastScrollMultiplier, settings.commandZoomScroll)
        }
        
        // Check modifier keys
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
            // End any active zoom from a previous modifier release that hasn't timed out
            let scrollDelta = deltaY != 0 ? deltaY : deltaX
            let magnification = Double(scrollDelta) / 50.0
            
            if !zoomGestureActive {
                zoomGestureActive = true
                postMagnificationEvent(magnification: 0, phase: 1) // began
            }
            postMagnificationEvent(magnification: magnification, phase: 2) // changed
            scheduleZoomEnd()
            return nil // Suppress original scroll event
        }
        
        // If zoom was active but Command is no longer held, end it immediately
        if zoomGestureActive && !commandHeld {
            zoomEndTimer?.cancel()
            postMagnificationEvent(magnification: 0, phase: 4) // ended
            zoomGestureActive = false
        }
        
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
        
        // Determine if Option is being used to bypass smooth scrolling
        let optionBypassesSmooth = optionHeld && smoothScrolling != .off && isMouseScroll
        
        // Apply Option modifier: slow down scroll for precision (applies to both X and Y)
        // Don't apply precision when Option is being used to bypass smooth scrolling
        let precisionScale: Double = (optionHeld && optionPrecision && isMouseScroll && !optionBypassesSmooth) ? precisionMultiplier : 1.0
        
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
        
        // If smooth scrolling is enabled for mouse events, use the smooth scroll system
        // BUT: horizontal scroll (Shift+Scroll) always bypasses smooth scrolling
        // BUT: Option held bypasses smooth scrolling (acts as if smooth scrolling is off)
        // Control+Scroll also bypasses smooth scrolling for immediate fast scroll
        let controlBypassesSmooth = controlHeld && controlFast && isMouseScroll
        
        if smoothScrolling != .off && isMouseScroll && !isHorizontalScroll && !optionHeld && !controlBypassesSmooth {
            smoothScrollLock.lock()
            
            // Calculate pixels to scroll for this tick
            let pxMultiplier = smoothScrolling == .verySmooth ? 1.3 : 1.0
            let ticksY = reversedTicksY
            let pxToAddY = ticksY * pxPerTick * pxMultiplier
            
            // Get animation duration based on smoothness level
            let duration = (smoothScrolling == .verySmooth ? baseMsPerStepSmooth : baseMsPerStep) / 1000.0
            
            let currentTime = CACurrentMediaTime()
            
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
        let needsModification = shouldReverse || isHorizontalScroll || (optionHeld && optionPrecision && isMouseScroll) || (controlHeld && controlFast && isMouseScroll)
        
        guard needsModification else { return event }
        
        // IMPORTANT: Order matters! Setting the integer delta fields causes macOS to
        // internally recalculate the point/fixed-pt fields. So we must either:
        // 1. Set integer delta LAST, or
        // 2. Set integer delta first, then set the others to override
        // We use approach #2 (same as Scroll Reverser)
        
        // For precision scroll, we can't really reduce integer deltas below 1,
        // but the pixel/point deltas will be reduced
        let intDeltaY = Int64(reversedTicksY.rounded())
        let intDeltaX = Int64(reversedTicksX.rounded())
        
        // First, set the integer deltas (this may reset the other fields)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: intDeltaY)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: intDeltaX)
        
        // Then override with the correct modified values
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: pixelDeltaY)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: pixelDeltaX)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pointDeltaY)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pointDeltaX)
        
        return event
    }
    
    // MARK: - Magnification (Zoom) Gesture
    
    /// Post a trackpad-style magnification (pinch-to-zoom) CGEvent.
    /// Uses the same approach as Mac Mouse Fix: NSEventTypeGesture (type 29)
    /// with subtype kIOHIDEventTypeZoom (8).
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
        zoomEndTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            guard let self = self, self.zoomGestureActive else { return }
            self.postMagnificationEvent(magnification: 0, phase: 4) // ended
            self.zoomGestureActive = false
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
    
    @objc private func displayLinkCallback(_ link: CADisplayLink) {
        let currentTime = CACurrentMediaTime()
        let dt = lastFrameTime > 0 ? currentTime - lastFrameTime : 1.0 / 120.0
        lastFrameTime = currentTime
        
        smoothScrollLock.lock()
        
        var deltaY: Double = 0
        var deltaX: Double = 0
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
        
        // Handle X velocity similarly (for any residual horizontal momentum)
        if abs(smoothScrollVelocityX) > 0.1 {
            deltaX = smoothScrollVelocityX * dt
            let dragX = pow(abs(smoothScrollVelocityX), dragExp) * dragCoeff * dt
            if smoothScrollVelocityX > 0 {
                smoothScrollVelocityX = max(0, smoothScrollVelocityX - dragX)
            } else {
                smoothScrollVelocityX = min(0, smoothScrollVelocityX + dragX)
            }
        }
        
        let velocityY = smoothScrollVelocityY
        let velocityX = smoothScrollVelocityX
        let phase = smoothScrollPhase
        
        smoothScrollLock.unlock()
        
        // Stop if velocity is below stop speed (only in momentum phase)
        if phase == .momentum && abs(velocityY) < stopSpeed && abs(velocityX) < stopSpeed {
            // Post momentum end (momentumPhase=3, scrollPhase=0) then scroll ended (scrollPhase=4)
            // This sequence signals to apps that momentum has ended, triggering elastic bounce
            postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: nil, momentumPhase: 3)
            postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: .ended, momentumPhase: 0)
            
            smoothScrollLock.lock()
            smoothScrollVelocityY = 0
            smoothScrollVelocityX = 0
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
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        
        // Middle button (button 2) - start tracking for drag gesture
        if buttonNumber == 2 {
            middleButtonDown = true
            middleButtonStartPoint = event.location
            middleDragTriggered = false
            continuousGestureActive = false
            continuousGestureAxisLocked = false
            
            // Check if middle click has a mapping
            let action: MouseAction? = onMain {
                settings?.getAction(forButtonNumber: 2)
            }
            
            // If no mapping or action is just middle click, pass through
            if action == nil || action == .middleClick {
                return event
            }
            
            // Otherwise, suppress the event (we'll handle on mouse up or drag)
            return nil
        }
        
        // All other buttons (3, 4, 5+) - check for custom mappings
        return handleMouseButtonAction(buttonNumber: buttonNumber, originalEvent: event)
    }
    
    private func handleOtherMouseUp(_ event: CGEvent) -> CGEvent? {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        
        if buttonNumber == 2 {
            defer {
                middleButtonDown = false
                middleDragTriggered = false
                continuousGestureAxisLocked = false
            }
            
            // End continuous gesture if active
            if continuousGestureActive {
                continuousGestureActive = false
                dockSwipeSimulator.end(cancel: false)
                
                // Disable HID-level drag tap
                if let hidTap = dragHIDTap {
                    CGEvent.tapEnable(tap: hidTap, enable: false)
                }
                
                // Unfreeze cursor
                CGAssociateMouseAndMouseCursorPosition(1)
                
                LogManager.shared.log("Continuous gesture ended", category: "Gesture")
                return nil
            }
            
            // If drag gesture was triggered, suppress the mouse up
            if middleDragTriggered {
                return nil
            }
            
            // Otherwise, check middle click action
            let action: MouseAction? = onMain {
                settings?.getAction(forButtonNumber: 2)
            }
            
            // If no mapping or action is just middle click, pass through
            if action == nil || action == .middleClick {
                return event
            }
            
            // Execute the action on mouse up (for click-style actions)
            executeAction(action!)
            return nil
        }
        
        // Suppress up events for buttons that have mappings
        let hasMapping: Bool = onMain {
            settings?.getAction(forButtonNumber: buttonNumber) != nil
        }
        if hasMapping {
            return nil
        }
        
        return event
    }
    
    private func handleOtherMouseDragged(_ event: CGEvent) -> CGEvent? {
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
        
        let (threshold, useContinuous): (Double, Bool) = onMain {
            (settings?.dragThreshold ?? 40, settings?.continuousGestures ?? true)
        }
        
        // For continuous mode, determine axis early with a smaller dead zone
        // and begin the DockSwipe gesture immediately
        if useContinuous {
            let axisThreshold = threshold * 0.5  // Smaller threshold for axis detection
            
            if !continuousGestureAxisLocked {
                // Need enough movement to determine axis
                if abs(deltaX) > axisThreshold || abs(deltaY) > axisThreshold {
                    if abs(deltaY) > abs(deltaX) {
                        continuousGestureAxis = .vertical
                    } else {
                        continuousGestureAxis = .horizontal
                    }
                    continuousGestureAxisLocked = true
                    
                    // Check if the mapped actions for this axis support continuous gestures
                    if axisSupportsContinuous(axis: continuousGestureAxis) {
                        // Determine the initial DockSwipe type from the dominant direction
                        let initialDirection: DragDirection
                        if continuousGestureAxis == .horizontal {
                            initialDirection = deltaX < 0 ? .left : .right
                        } else {
                            initialDirection = deltaY < 0 ? .up : .down
                        }
                        
                        let action: MouseAction = onMain {
                            self.settings?.getAction(for: initialDirection) ?? .none
                        }
                        
                        let swipeType = dockSwipeType(for: initialDirection, action: action)
                        
                        // Calculate initial delta from accumulated movement
                        let initialDelta: Double
                        if continuousGestureAxis == .horizontal {
                            initialDelta = -DockSwipeSimulator.pixelToDockSwipe(deltaX, type: swipeType)
                        } else {
                            initialDelta = -DockSwipeSimulator.pixelToDockSwipe(deltaY, type: swipeType)
                        }
                        
                        continuousGestureActive = true
                        middleDragTriggered = true
                        
                        // Enable HID-level event tap to receive drags during gesture
                        if let hidTap = dragHIDTap {
                            CGEvent.tapEnable(tap: hidTap, enable: true)
                        }
                        
                        // Freeze cursor position during gesture
                        CGAssociateMouseAndMouseCursorPosition(0)
                        
                        dockSwipeSimulator.begin(type: swipeType, delta: initialDelta)
                        
                        LogManager.shared.log("Continuous gesture began: \(swipeType) axis=\(continuousGestureAxis)", category: "Gesture")
                        return nil
                    }
                    // If continuous not supported for this axis, fall through to trigger mode
                }
            }
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
            
            let action: MouseAction = onMain {
                settings?.getAction(for: dir) ?? .none
            }
            
            if action != .none {
                executeAction(action)
            }
        }
        
        return event
    }
    
    private func handleMouseButtonAction(buttonNumber: Int64, originalEvent: CGEvent) -> CGEvent? {
        let action: MouseAction? = onMain {
            settings?.getAction(forButtonNumber: buttonNumber)
        }
        
        // If no mapping, pass through the event
        guard let action = action else {
            return originalEvent
        }
        
        // For .none, suppress the event entirely
        if action == .none {
            return nil
        }
        
        // Execute the action
        executeAction(action)
        return nil  // Suppress the original mouse button event
    }
    
    // MARK: - Keyboard Handling
    
    private func handleKeyDown(_ event: CGEvent) -> CGEvent? {
        return handleKeyEvent(event, isDown: true)
    }
    
    private func handleKeyUp(_ event: CGEvent) -> CGEvent? {
        return handleKeyEvent(event, isDown: false)
    }
    
    private func handleKeyEvent(_ event: CGEvent, isDown: Bool) -> CGEvent? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = event.flags.rawValue
        
        // Check if external keyboard is connected (or assumed)
        // Use cached frontmost app bundle ID instead of querying NSWorkspace per-event
        let cachedBundleID = cachedFrontmostBundleID
        let (hasExternalKeyboard, isExcludedApp, action): (Bool, Bool, KeyboardAction?) = onMain {
            let hasKeyboard = settings?.assumeExternalKeyboard ?? false || (deviceManager?.externalKeyboardConnected ?? false)
            
            // Check if frontmost app is excluded (using cached bundle ID)
            let excluded: Bool
            if let bundleID = cachedBundleID {
                excluded = settings?.isAppExcluded(bundleID) ?? false
            } else {
                excluded = false
            }
            
            let keyAction = settings?.getKeyboardAction(for: keyCode, modifiers: modifiers)
            return (hasKeyboard, excluded, keyAction)
        }
        
        // Pass through if no external keyboard or app is excluded
        guard hasExternalKeyboard && !isExcludedApp else { return event }
        
        // Pass through if no mapping
        guard let targetAction = action, targetAction != .none else { return event }
        
        // Execute the remapped action
        if isDown {
            if let combo = targetAction.keyCombo {
                sendKeyCombo(combo)
            }
        }
        
        return nil  // Suppress original event
    }
    
    // MARK: - Action Execution
    
    private func executeAction(_ action: MouseAction) {
        LogManager.shared.log("Executing action: \(action.displayName)", category: "Action")
        
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
            // Shouldn't reach here normally
            break
            
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
        LogManager.shared.log("Sending key combo: \(combo.displayName)", category: "Keyboard")
        
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
    
    // MARK: - System Triggers
    
    private func triggerMissionControl() {
        // Use the Mission Control key (F3 on Apple keyboards, or dedicated key 0xA0)
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
        let pixelDX = Double(event.getIntegerValueField(.mouseEventDeltaX))
        let pixelDY = Double(event.getIntegerValueField(.mouseEventDeltaY))
        
        guard pixelDX != 0 || pixelDY != 0 else { return }
        
        // Convert pixel deltas to DockSwipe units using cached scaling
        if continuousGestureAxis == .horizontal {
            let swipeDelta = -dockSwipeSimulator.pixelToDockSwipeScaled(pixelDX, type: .horizontal)
            dockSwipeSimulator.update(delta: swipeDelta)
        } else {
            let swipeDelta = -dockSwipeSimulator.pixelToDockSwipeScaled(pixelDY, type: .vertical)
            dockSwipeSimulator.update(delta: swipeDelta)
        }
    }
    
    // MARK: - Continuous Gesture Helpers
    
    /// Whether a mouse action supports continuous DockSwipe gesture simulation.
    /// Only system-level animations that correspond to trackpad three-finger swipes.
    private func actionSupportsContinuousGesture(_ action: MouseAction) -> Bool {
        switch action {
        case .missionControl, .appExpose, .switchSpaceLeft, .switchSpaceRight,
             .showDesktop, .launchpad:
            return true
        default:
            return false
        }
    }
    
    /// Determine the DockSwipe type for a drag direction and its mapped action.
    private func dockSwipeType(for direction: DragDirection, action: MouseAction) -> DockSwipeSimulator.SwipeType {
        switch action {
        case .switchSpaceLeft, .switchSpaceRight:
            return .horizontal
        case .missionControl, .appExpose:
            return .vertical
        case .showDesktop, .launchpad:
            return .pinch
        default:
            return .horizontal
        }
    }
    
    /// Check if any action in the given axis direction supports continuous gestures.
    private func axisSupportsContinuous(axis: ContinuousAxis) -> Bool {
        let (action1, action2): (MouseAction, MouseAction) = onMain {
            guard let s = self.settings else { return (.none, .none) }
            if axis == .horizontal {
                return (s.getAction(for: .left), s.getAction(for: .right))
            } else {
                return (s.getAction(for: .up), s.getAction(for: .down))
            }
        }
        return actionSupportsContinuousGesture(action1) || actionSupportsContinuousGesture(action2)
    }
}
