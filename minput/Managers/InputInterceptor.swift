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
        
        // Check if external mouse is connected and scroll reversal is enabled
        let shouldReverse = onMain {
            settings.reverseScrollEnabled && (deviceManager?.externalMouseConnected ?? false)
        }
        
        guard shouldReverse else { return event }
        
        // Check if this is a continuous (trackpad) or discrete (mouse wheel) scroll
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        
        // Only reverse discrete scrolling (mouse wheel), not trackpad
        guard !isContinuous else { return event }
        
        // Reverse both axes
        let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -deltaY)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -deltaX)
        
        // Also reverse the pixel deltas for smooth scrolling
        let pixelDeltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let pixelDeltaX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -pixelDeltaY)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -pixelDeltaX)
        
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
        
        // Suppress up events for remapped buttons
        if buttonNumber == 3 || buttonNumber == 4 {
            let button: MouseButton = buttonNumber == 3 ? .back : .forward
            let action: MouseAction = onMain {
                settings?.getAction(for: button) ?? .none
            }
            
            if action != .back && action != .forward {
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
        
        switch action {
        case .back where button == .back:
            return originalEvent  // Pass through native back
        case .forward where button == .forward:
            return originalEvent  // Pass through native forward
        case .none:
            return nil  // Suppress the event
        default:
            executeAction(action)
            return nil
        }
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
        
        // Check if external keyboard is connected
        let (hasExternalKeyboard, isExcludedApp, action): (Bool, Bool, KeyboardAction?) = onMain {
            let hasKeyboard = deviceManager?.externalKeyboardConnected ?? false
            
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
            
        case .copy:
            sendKeyCombo(KeyCombo(keyCode: 0x08, modifiers: CGEventFlags.maskCommand.rawValue)) // ⌘C
            
        case .paste:
            sendKeyCombo(KeyCombo(keyCode: 0x09, modifiers: CGEventFlags.maskCommand.rawValue)) // ⌘V
            
        case .spacesLeft:
            sendKeyCombo(KeyCombo(keyCode: 0x7B, modifiers: CGEventFlags.maskControl.rawValue)) // ⌃←
            
        case .spacesRight:
            sendKeyCombo(KeyCombo(keyCode: 0x7C, modifiers: CGEventFlags.maskControl.rawValue)) // ⌃→
            
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
            keyDown.post(tap: .cghidEventTap)
        }
        
        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false) {
            keyUp.flags = flags
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
        // F11 or the Show Desktop key
        let source = CGEventSource(stateID: .hidSystemState)
        
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0xA1, keyDown: true) {
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0xA1, keyDown: false) {
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
        // Control + Down Arrow triggers App Exposé
        sendKeyCombo(KeyCombo(keyCode: 0x7D, modifiers: CGEventFlags.maskControl.rawValue))
    }
}
