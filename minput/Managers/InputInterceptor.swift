import Foundation
import CoreGraphics
import AppKit
import Observation

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
    
    // Smooth scrolling state
    private var smoothScrollVelocityY: Double = 0
    private var smoothScrollVelocityX: Double = 0
    private var smoothScrollTimer: Timer?
    private var smoothScrollPhase: SmoothScrollPhase = .idle
    private let smoothScrollLock = NSLock()
    
    private enum SmoothScrollPhase {
        case idle
        case scrolling   // Active scrolling (wheel being moved)
        case momentum    // Coasting after wheel stopped
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
        let (shouldReverse, smoothScrolling) = onMain {
            let reverse = settings.reverseScrollEnabled && (settings.assumeExternalMouse || (deviceManager?.externalMouseConnected ?? false))
            return (reverse, settings.smoothScrolling)
        }
        
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
        let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        var pixelDeltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        var pixelDeltaX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        var pointDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        var pointDeltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        
        // Apply reversal if enabled
        let reverseMultiplier: Double = shouldReverse ? -1.0 : 1.0
        let reversedDeltaY = -deltaY
        let reversedDeltaX = -deltaX
        pixelDeltaY *= reverseMultiplier
        pixelDeltaX *= reverseMultiplier
        pointDeltaY *= reverseMultiplier
        pointDeltaX *= reverseMultiplier
        
        // If smooth scrolling is enabled for mouse events, use the smooth scroll system
        if smoothScrolling != .off && isMouseScroll {
            smoothScrollLock.lock()
            
            // Get the actual scroll delta - use point delta if available, otherwise convert from line delta
            // Mouse wheels typically report 1-3 lines per tick, we need to convert to pixels
            let pixelsPerLine: Double = 10.0  // Standard line height approximation
            let inputDeltaY = pointDeltaY != 0 ? pointDeltaY : Double(reversedDeltaY) * pixelsPerLine
            let inputDeltaX = pointDeltaX != 0 ? pointDeltaX : Double(reversedDeltaX) * pixelsPerLine
            
            // Add to velocity - this accumulates scroll input
            // We DON'T multiply here - the speed stays the same, smoothness comes from interpolation
            smoothScrollVelocityY += inputDeltaY
            smoothScrollVelocityX += inputDeltaX
            smoothScrollPhase = .scrolling
            
            smoothScrollLock.unlock()
            
            // Start timer if not running
            startSmoothScrollTimer(smoothLevel: smoothScrolling)
            
            // Suppress original event - we'll post smooth events instead
            return nil
        }
        
        // No smooth scrolling - just apply reversal if needed
        guard shouldReverse else { return event }
        
        // IMPORTANT: Order matters! Setting the integer delta fields causes macOS to
        // internally recalculate the point/fixed-pt fields. So we must either:
        // 1. Set integer delta LAST, or
        // 2. Set integer delta first, then set the others to override
        // We use approach #2 (same as Scroll Reverser)
        
        // First, set the integer deltas (this may reset the other fields)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: reversedDeltaY)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: reversedDeltaX)
        
        // Then override with the correct reversed values for smooth scrolling
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: pixelDeltaY)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: pixelDeltaX)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pointDeltaY)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pointDeltaX)
        
        return event
    }
    
    // MARK: - Smooth Scrolling
    
    private var currentSmoothLevel: SmoothScrolling = .smooth
    
    private func startSmoothScrollTimer(smoothLevel: SmoothScrolling) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.currentSmoothLevel = smoothLevel
            
            // If timer already running, don't restart
            if self.smoothScrollTimer?.isValid == true {
                return
            }
            
            // Post initial "began" phase
            self.postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: .began, momentumPhase: 0)
            
            // 120 FPS for smooth animation
            self.smoothScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0/120.0, repeats: true) { [weak self] timer in
                self?.processSmoothScroll(timer: timer)
            }
        }
    }
    
    private func processSmoothScroll(timer: Timer) {
        smoothScrollLock.lock()
        
        // Trackpad-like physics:
        // - During active scrolling: emit velocity directly, apply light smoothing
        // - During momentum: apply friction for gradual slowdown
        //
        // macOS trackpad uses roughly 0.95-0.98 friction at 60fps
        // At 120fps, we need sqrt of that: ~0.975-0.99
        let isActivelyScrolling = smoothScrollPhase == .scrolling
        
        // Friction values tuned to feel like trackpad
        // Higher = more momentum (coasts longer)
        let frictionFactor: Double
        if isActivelyScrolling {
            // Light smoothing during active scroll - keeps responsiveness
            frictionFactor = currentSmoothLevel == .verySmooth ? 0.7 : 0.5
        } else {
            // Momentum phase - gradual slowdown like trackpad
            frictionFactor = currentSmoothLevel == .verySmooth ? 0.985 : 0.975
        }
        
        let velocityThreshold: Double = 0.5
        
        // Get current velocity
        var velocityY = smoothScrollVelocityY
        var velocityX = smoothScrollVelocityX
        
        // Calculate delta to emit this frame
        // During active scrolling: emit a portion of accumulated velocity
        // During momentum: emit current velocity and apply friction
        let emitFraction: Double = isActivelyScrolling ? (1.0 - frictionFactor) : 1.0
        let deltaY = velocityY * emitFraction
        let deltaX = velocityX * emitFraction
        
        // Apply friction/consumption
        if isActivelyScrolling {
            // Consume the emitted portion
            smoothScrollVelocityY *= frictionFactor
            smoothScrollVelocityX *= frictionFactor
        } else {
            // Momentum: apply friction
            smoothScrollVelocityY *= frictionFactor
            smoothScrollVelocityX *= frictionFactor
        }
        
        // Check for phase transition
        // If velocity is low and we were scrolling, transition to momentum
        if isActivelyScrolling && abs(smoothScrollVelocityY) < 2.0 && abs(smoothScrollVelocityX) < 2.0 {
            smoothScrollPhase = .momentum
        }
        
        velocityY = smoothScrollVelocityY
        velocityX = smoothScrollVelocityX
        
        smoothScrollLock.unlock()
        
        // Stop if velocity is negligible
        if abs(velocityY) < velocityThreshold && abs(velocityX) < velocityThreshold {
            // Post "ended" phase to trigger elastic bounce if at boundary
            postSmoothScrollEvent(deltaY: 0, deltaX: 0, phase: .ended, momentumPhase: 0)
            
            smoothScrollLock.lock()
            smoothScrollVelocityY = 0
            smoothScrollVelocityX = 0
            smoothScrollPhase = .idle
            smoothScrollLock.unlock()
            
            timer.invalidate()
            smoothScrollTimer = nil
            return
        }
        
        // Determine momentum phase for the event
        let momentumPhase: Int64 = smoothScrollPhase == .momentum ? 1 : 0
        
        // Post a smooth scroll event with the calculated delta
        postSmoothScrollEvent(deltaY: deltaY, deltaX: deltaX, phase: .changed, momentumPhase: momentumPhase)
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
        
        // Always suppress up events for back/forward buttons since we handle them on mouse down
        if buttonNumber == 3 || buttonNumber == 4 {
            return nil
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
    
    // MARK: - Keyboard Handling
    
    private func handleKeyDown(_ event: CGEvent) -> CGEvent? {
        return handleKeyEvent(event, isDown: true)
    }
    
    private func handleKeyUp(_ event: CGEvent) -> CGEvent? {
        return handleKeyEvent(event, isDown: false)
    }
    
    private func handleKeyEvent(_ event: CGEvent, isDown: Bool) -> CGEvent? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        
        // Check if external keyboard is connected (or assumed)
        let (hasExternalKeyboard, isExcludedApp, action): (Bool, Bool, KeyboardAction?) = onMain {
            let hasKeyboard = settings?.assumeExternalKeyboard ?? false || (deviceManager?.externalKeyboardConnected ?? false)
            
            // Check if frontmost app is excluded
            var excluded = false
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleID = frontApp.bundleIdentifier {
                excluded = settings?.isAppExcluded(bundleID) ?? false
            }
            
            let keyAction = settings?.getKeyboardAction(for: keyCode)
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
            
        case .appExpose:
            triggerAppExpose()
            
        case .back:
            sendKeyCombo(KeyCombo(keyCode: 0x21, modifiers: CGEventFlags.maskCommand.rawValue)) // ⌘[
            
        case .forward:
            sendKeyCombo(KeyCombo(keyCode: 0x1E, modifiers: CGEventFlags.maskCommand.rawValue)) // ⌘]
            
        case .middleClick:
            // Shouldn't reach here normally
            break
            
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
    
    private func triggerAppExpose() {
        // App Exposé: Control + Down Arrow
        // We need to simulate the full key sequence: Control down, Arrow down, Arrow up, Control up
        // kVK_Control = 0x3B, kVK_DownArrow = 0x7D
        
        let controlKeyCode: CGKeyCode = 0x3B  // Left Control
        let downArrowKeyCode: CGKeyCode = 0x7D
        
        // Control key down
        if let ctrlDown = CGEvent(keyboardEventSource: nil, virtualKey: controlKeyCode, keyDown: true) {
            ctrlDown.flags = .maskControl
            ctrlDown.setIntegerValueField(.eventSourceUserData, value: InputInterceptor.syntheticEventMarker)
            ctrlDown.post(tap: .cghidEventTap)
        }
        
        // Down arrow key down (with Control held)
        if let arrowDown = CGEvent(keyboardEventSource: nil, virtualKey: downArrowKeyCode, keyDown: true) {
            arrowDown.flags = .maskControl
            arrowDown.setIntegerValueField(.eventSourceUserData, value: InputInterceptor.syntheticEventMarker)
            arrowDown.post(tap: .cghidEventTap)
        }
        
        // Down arrow key up
        if let arrowUp = CGEvent(keyboardEventSource: nil, virtualKey: downArrowKeyCode, keyDown: false) {
            arrowUp.flags = .maskControl
            arrowUp.setIntegerValueField(.eventSourceUserData, value: InputInterceptor.syntheticEventMarker)
            arrowUp.post(tap: .cghidEventTap)
        }
        
        // Control key up
        if let ctrlUp = CGEvent(keyboardEventSource: nil, virtualKey: controlKeyCode, keyDown: false) {
            ctrlUp.flags = []
            ctrlUp.setIntegerValueField(.eventSourceUserData, value: InputInterceptor.syntheticEventMarker)
            ctrlUp.post(tap: .cghidEventTap)
        }
    }
}
