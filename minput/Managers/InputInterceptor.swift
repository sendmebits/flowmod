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
        
        // Check if scroll reversal is enabled and external mouse is connected (or assumed)
        let shouldReverse = onMain {
            settings.reverseScrollEnabled && (settings.assumeExternalMouse || (deviceManager?.externalMouseConnected ?? false))
        }
        
        guard shouldReverse else { return event }
        
        // Check if this is a continuous (trackpad) or discrete (mouse wheel) scroll
        // Note: Many modern mice (especially Logitech) report as continuous scroll
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        
        // Momentum phase: non-zero means trackpad momentum scrolling (fingers lifted)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        
        // Scroll phase: indicates active trackpad gesture phases
        // 0 = none (mouse), 1 = began, 2 = changed, 4 = ended, 8 = cancelled, 128 = may begin
        let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        
        // Skip reversal for:
        // 1. Momentum scrolling (fingers lifted from trackpad, coasting)
        // 2. Active trackpad gestures (scrollPhase indicates trackpad touch activity)
        // 
        // Mouse scrolling characteristics:
        // - isContinuous may be 0 (discrete wheel) OR 1 (smooth scroll mice like Logitech MX)
        // - momentumPhase is always 0 (mice don't have momentum)
        // - scrollPhase is always 0 (mice don't have gesture phases)
        //
        // Trackpad scrolling characteristics:
        // - isContinuous is always 1
        // - scrollPhase cycles: 128 (may begin) -> 1 (began) -> 2 (changed) -> 4 (ended)
        // - momentumPhase: 0 during gesture, then 1/2/3 during momentum
        
        if isContinuous {
            // For continuous scrolling, only reverse if both phases are 0 (mouse-like behavior)
            if momentumPhase != 0 || scrollPhase != 0 {
                return event
            }
        }
        
        // Get all the delta values BEFORE modification
        let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let pixelDeltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let pixelDeltaX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let pointDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let pointDeltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        
        // IMPORTANT: Order matters! Setting the integer delta fields causes macOS to
        // internally recalculate the point/fixed-pt fields. So we must either:
        // 1. Set integer delta LAST, or
        // 2. Set integer delta first, then set the others to override
        // We use approach #2 (same as Scroll Reverser)
        
        // First, set the integer deltas (this may reset the other fields)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -deltaY)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -deltaX)
        
        // Then override with the correct reversed values for smooth scrolling
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -pixelDeltaY)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -pixelDeltaX)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -pointDeltaY)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -pointDeltaX)
        
        return event
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
