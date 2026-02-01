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
    
    // Middle button drag tracking
    private var middleButtonDown = false
    private var middleButtonStartPoint: CGPoint = .zero
    private var middleDragTriggered = false
    
    // Smooth scrolling state - physics engine for trackpad-like feel
    private var smoothScrollVelocityY: Double = 0
    private var smoothScrollVelocityX: Double = 0
    private var displayLink: CADisplayLink?
    private var smoothScrollPhase: SmoothScrollPhase = .idle
    private let smoothScrollLock = NSLock()
    private var lastFrameTime: CFTimeInterval = 0
    private var lastInputTime: CFTimeInterval = 0
    private var needsScrollBegan: Bool = true  // Track if we need to send began phase
    
    // Physics parameters (from Mac Mouse Fix)
    // Uses a hybrid approach: base animation for initial scroll + drag physics for momentum
    private let pxPerTick: Double = 60.0           // Pixels per wheel tick
    private let baseMsPerStep: Double = 140.0      // Base animation duration per tick (ms) - lowInertia
    private let baseMsPerStepSmooth: Double = 220.0 // For verySmooth mode - highInertia
    private let dragCoefficient: Double = 23.0     // Drag for lowInertia (exp=1.0)
    private let dragCoefficientSmooth: Double = 40.0 // Drag for highInertia (exp=0.7)
    private let dragExponent: Double = 1.0         // For lowInertia
    private let dragExponentSmooth: Double = 0.7   // For highInertia - slower decel at end
    private let maxVelocity: Double = 3000.0       // Clamp to avoid absurd speeds
    private let stopSpeed: Double = 30.0           // Stop when velocity drops below this (from MMF)
    private let inputTimeoutForMomentum: Double = 0.08 // Seconds after last input before momentum
    
    // Animation state for base curve
    private var animationProgress: Double = 0      // 0 to 1 progress through base animation
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
    
    // Marker for synthetic events we post ourselves (to avoid re-processing)
    private static let syntheticEventMarker: Int64 = 0x4D494E505554  // "MINPUT" in hex
    
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
    
    @MainActor
    func start(settings: Settings, deviceManager: DeviceManager) {
        guard !isRunning else { return }
        
        self.settings = settings
        self.deviceManager = deviceManager
        
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
    }
    
    func stop() {
        // Stop smooth scrolling display link
        stopDisplayLink()
        
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
        
        switch type {
        case .scrollWheel:
            return handleScrollEvent(event)
        case .otherMouseDown:
            return handleOtherMouseDown(event)
        case .otherMouseUp:
            return handleOtherMouseUp(event)
        case .otherMouseDragged:
            return handleOtherMouseDragged(event)
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        default:
            return event
        }
    }
    
    // MARK: - Scroll Handling
    
    private func handleScrollEvent(_ event: CGEvent) -> CGEvent? {
        guard let settings = settings else { return event }
        
        // Get settings on main thread
        let (shouldReverse, smoothScrolling, shiftHorizontal, optionPrecision, precisionMultiplier) = onMain {
            let reverse = settings.reverseScrollEnabled && (settings.assumeExternalMouse || (deviceManager?.externalMouseConnected ?? false))
            return (reverse, settings.smoothScrolling, settings.shiftHorizontalScroll, settings.optionPrecisionScroll, settings.precisionScrollMultiplier)
        }
        
        // Check modifier keys
        let flags = event.flags
        let shiftHeld = flags.contains(.maskShift)
        let optionHeld = flags.contains(.maskAlternate)
        
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
        
        // Apply Option modifier: slow down scroll for precision (applies to both X and Y)
        let precisionScale: Double = (optionHeld && optionPrecision && isMouseScroll) ? precisionMultiplier : 1.0
        
        // Apply reversal if enabled - compute AFTER the swap so values are correct
        // Keep as Double for smooth scroll to preserve fractional precision
        // Note: reverseMultiplier flips direction when reverse scrolling is enabled
        let reverseMultiplier: Double = shouldReverse ? -1.0 : 1.0
        let reversedTicksY = Double(deltaY) * precisionScale * reverseMultiplier
        let reversedTicksX = Double(deltaX) * precisionScale * reverseMultiplier
        pixelDeltaY *= reverseMultiplier * precisionScale
        pixelDeltaX *= reverseMultiplier * precisionScale
        pointDeltaY *= reverseMultiplier * precisionScale
        pointDeltaX *= reverseMultiplier * precisionScale
        
        // Determine if this is a horizontal scroll (Shift held)
        let isHorizontalScroll = shiftHeld && shiftHorizontal && isMouseScroll
        
        // If smooth scrolling is enabled for mouse events, use the smooth scroll system
        // BUT: horizontal scroll (Shift+Scroll) always bypasses smooth scrolling
        if smoothScrolling != .off && isMouseScroll && !isHorizontalScroll {
            smoothScrollLock.lock()
            
            // Calculate pixels to scroll for this tick
            let pxMultiplier = smoothScrolling == .verySmooth ? 1.3 : 1.0
            let ticksY = reversedTicksY
            let pxToAddY = ticksY * pxPerTick * pxMultiplier
            
            // Get animation duration based on smoothness level
            let duration = (smoothScrolling == .verySmooth ? baseMsPerStepSmooth : baseMsPerStep) / 1000.0
            
            let currentTime = CACurrentMediaTime()
            
            if smoothScrollPhase == .idle || smoothScrollPhase == .momentum {
                // Start fresh animation
                targetScrollDistance = pxToAddY
                alreadyScrolledDistance = 0
                animationStartTime = currentTime
                animationDuration = duration
                smoothScrollVelocityY = 0
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
        let needsModification = shouldReverse || isHorizontalScroll || (optionHeld && optionPrecision && isMouseScroll)
        
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
        
        // Check if we should transition from animating to momentum
        let timeSinceInput = currentTime - lastInputTime
        if smoothScrollPhase == .animating && timeSinceInput > inputTimeoutForMomentum {
            // Transition to momentum phase - calculate exit velocity
            // Exit velocity = remaining distance / remaining time (approximation)
            let remainingDistance = targetScrollDistance - alreadyScrolledDistance
            if abs(remainingDistance) > 1 {
                // Set velocity based on current scroll rate
                smoothScrollVelocityY = remainingDistance / max(dt * 3, 0.016)
                smoothScrollVelocityY = max(min(smoothScrollVelocityY, maxVelocity), -maxVelocity)
            }
            smoothScrollPhase = .momentum
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
                // Animation complete, transition to momentum
                deltaY = targetScrollDistance - alreadyScrolledDistance
                alreadyScrolledDistance = targetScrollDistance
                
                // Calculate exit velocity for momentum
                smoothScrollVelocityY = deltaY / dt
                smoothScrollVelocityY = max(min(smoothScrollVelocityY, maxVelocity), -maxVelocity)
                smoothScrollPhase = .momentum
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
            // Mac Mouse Fix formula: velocity -= |velocity|^exp * coeff * dt * sign(velocity)
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
            // Post "ended" phase to trigger elastic bounce if at boundary
            postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: .ended, momentumPhase: 0)
            
            smoothScrollLock.lock()
            smoothScrollVelocityY = 0
            smoothScrollVelocityX = 0
            targetScrollDistance = 0
            alreadyScrolledDistance = 0
            smoothScrollPhase = .idle
            needsScrollBegan = true  // Next scroll needs a began phase
            smoothScrollLock.unlock()
            
            stopDisplayLink()
            return
        }
        
        // Determine momentum phase for the event
        let momentumPhaseValue: Int64 = phase == .momentum ? 1 : 0
        
        // Check if we need to send began phase
        var shouldSendBegan = false
        smoothScrollLock.lock()
        if needsScrollBegan {
            shouldSendBegan = true
            needsScrollBegan = false
        }
        smoothScrollLock.unlock()
        
        if shouldSendBegan {
            postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: .began, momentumPhase: 0)
        }
        
        // Post scroll event with the calculated delta
        // We emit the delta directly - each frame moves by velocity * dt pixels
        postSmoothScrollEvent(deltaY: deltaY, deltaX: deltaX, phase: .changed, momentumPhase: momentumPhaseValue)
    }
    
    // Scroll phases matching CGScrollPhase
    private enum ScrollEventPhase: Int64 {
        case began = 1
        case changed = 2
        case ended = 4
    }
    
    private func postSmoothScrollEvent(deltaY: Double, deltaX: Double, phase: ScrollEventPhase, momentumPhase: Int64) {
        guard let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) else {
            return
        }
        
        // Mark as synthetic so we don't re-process
        scrollEvent.setIntegerValueField(.eventSourceUserData, value: InputInterceptor.syntheticEventMarker)
        
        // Set as continuous scroll (like trackpad) - required for smooth scrolling and elastic bounce
        scrollEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        
        // Set scroll phase - this triggers proper handling in apps (including elastic bounce)
        scrollEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
        
        // Set momentum phase if in momentum
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
            
            // Check if middle click has a mapping
            let action: MouseAction = onMain {
                settings?.getAction(for: .middleClick) ?? .middleClick
            }
            
            // If action is just middle click, pass through
            if action == .middleClick {
                return event
            }
            
            // Otherwise, suppress the event (we'll handle on mouse up or drag)
            return nil
        }
        
        // Back button (button 3)
        if buttonNumber == 3 {
            return handleMouseButtonAction(for: .back, originalEvent: event)
        }
        
        // Forward button (button 4)
        if buttonNumber == 4 {
            return handleMouseButtonAction(for: .forward, originalEvent: event)
        }
        
        // Check for custom button mappings (buttons 5+)
        if buttonNumber >= 5 {
            return handleCustomMouseButtonAction(buttonNumber: buttonNumber, originalEvent: event)
        }
        
        return event
    }
    
    private func handleOtherMouseUp(_ event: CGEvent) -> CGEvent? {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        
        if buttonNumber == 2 {
            defer {
                middleButtonDown = false
                middleDragTriggered = false
            }
            
            // If drag gesture was triggered, suppress the mouse up
            if middleDragTriggered {
                return nil
            }
            
            // Otherwise, check middle click action
            let action: MouseAction = onMain {
                settings?.getAction(for: .middleClick) ?? .middleClick
            }
            
            if action == .middleClick {
                return event
            }
            
            // Execute the action on mouse up (for click-style actions)
            executeAction(action)
            return nil
        }
        
        // Suppress up events for back/forward buttons since we handle them on mouse down
        if buttonNumber == 3 || buttonNumber == 4 {
            return nil
        }
        
        // Suppress up events for custom buttons that have mappings
        if buttonNumber >= 5 {
            let hasMapping: Bool = onMain {
                settings?.getAction(forButtonNumber: buttonNumber) != nil
            }
            if hasMapping {
                return nil
            }
        }
        
        return event
    }
    
    private func handleOtherMouseDragged(_ event: CGEvent) -> CGEvent? {
        guard middleButtonDown && !middleDragTriggered else { return event }
        
        let currentPoint = event.location
        let deltaX = currentPoint.x - middleButtonStartPoint.x
        let deltaY = currentPoint.y - middleButtonStartPoint.y
        
        let threshold: Double = onMain {
            settings?.dragThreshold ?? 40
        }
        
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
    
    private func handleMouseButtonAction(for button: MouseButton, originalEvent: CGEvent) -> CGEvent? {
        let action: MouseAction = onMain {
            settings?.getAction(for: button) ?? .none
        }
        
        // For .none, suppress the event entirely
        if action == .none {
            return nil
        }
        
        // Execute the action - even for .back/.forward we need to send the keyboard shortcut
        // because macOS apps don't respond to raw mouse button 3/4 events for navigation
        executeAction(action)
        return nil  // Always suppress the original mouse button event
    }
    
    private func handleCustomMouseButtonAction(buttonNumber: Int64, originalEvent: CGEvent) -> CGEvent? {
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
        let (hasExternalKeyboard, isExcludedApp, action): (Bool, Bool, KeyboardAction?) = onMain {
            let hasKeyboard = settings?.assumeExternalKeyboard ?? false || (deviceManager?.externalKeyboardConnected ?? false)
            
            // Check if frontmost app is excluded
            var excluded = false
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleID = frontApp.bundleIdentifier {
                excluded = settings?.isAppExcluded(bundleID) ?? false
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
            
        case .customShortcut(let combo):
            sendKeyCombo(combo)
        }
    }
    
    private func sendKeyCombo(_ combo: KeyCombo) {
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
}
