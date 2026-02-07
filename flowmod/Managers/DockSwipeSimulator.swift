import Foundation
import CoreGraphics
import AppKit

/// Simulates macOS trackpad DockSwipe gestures via synthesized CGEvents.
/// This enables continuous, drag-following animations for Mission Control,
/// App Exposé, Switch Spaces, Show Desktop, and Launchpad — identical to
/// three-finger trackpad swipes.
///
/// Based on reverse-engineered DockSwipe event format:
/// - Event type 29 (NSEventTypeGesture) — companion event
/// - Event type 30 (NSEventTypeMagnify, subtype kIOHIDEventTypeDockSwipe) — data carrier
///
/// The animation tracks the cumulative `originOffset` field, making macOS
/// position the Spaces/Mission Control UI proportionally to the drag.
class DockSwipeSimulator {
    
    // MARK: - Types
    
    /// The type of DockSwipe gesture to simulate
    enum SwipeType: Int {
        case horizontal = 1  // Switch Spaces left/right
        case vertical = 2    // Mission Control (up) / App Exposé (down)
        case pinch = 3       // Show Desktop / Launchpad
    }
    
    /// IOHIDEvent phase values
    private enum Phase: Int64 {
        case began = 1
        case changed = 2
        case ended = 4
        case cancelled = 8
    }
    
    // MARK: - State
    
    private var isActive = false
    private var currentType: SwipeType = .horizontal
    private var originOffset: Double = 0
    private var lastDelta: Double = 0
    private var invertedFromDevice: Bool = false
    
    /// Timer for resending end events to prevent "stuck" gesture bug
    private var endRetryTimer1: DispatchWorkItem?
    private var endRetryTimer2: DispatchWorkItem?
    
    /// Magic type-dependent constants used in CGEvent fields 119 and 139.
    /// These are extremely small floats that encode the swipe type.
    private static let typeConstants: [SwipeType: Double] = [
        .horizontal: 1.401298464324817e-45,
        .vertical:   2.802596928649634e-45,
        .pinch:      4.203895392974451e-45,
    ]
    
    // MARK: - Public Interface
    
    /// Begin a new DockSwipe gesture.
    /// - Parameters:
    ///   - type: The gesture type (horizontal/vertical/pinch)
    ///   - delta: Initial delta in DockSwipe units
    ///   - invertedFromDevice: Whether natural scrolling direction is active
    func begin(type: SwipeType, delta: Double, invertedFromDevice: Bool = false) {
        cancelRetryTimers()
        
        self.currentType = type
        self.invertedFromDevice = invertedFromDevice
        self.originOffset = delta
        self.lastDelta = delta
        self.isActive = true
        
        postDockSwipeEvent(delta: delta, phase: .began)
    }
    
    /// Update an ongoing DockSwipe gesture with a new delta.
    /// - Parameter delta: The incremental delta to add in DockSwipe units
    func update(delta: Double) {
        guard isActive else { return }
        
        originOffset += delta
        lastDelta = delta
        
        postDockSwipeEvent(delta: delta, phase: .changed)
    }
    
    /// End the DockSwipe gesture.
    /// macOS will decide whether to commit the transition based on the
    /// accumulated offset and exit speed.
    /// - Parameter cancel: If true, sends cancelled phase (animation reverts)
    func end(cancel: Bool = false) {
        guard isActive else { return }
        isActive = false
        
        let phase: Phase = cancel ? .cancelled : .ended
        postDockSwipeEvent(delta: 0, phase: phase)
        
        // Schedule retry sends to prevent the "stuck" animation bug.
        // macOS occasionally drops the end event, leaving the UI frozen.
        let retryPhase = phase
        let retryType = currentType
        let retryOffset = originOffset
        let retryInverted = invertedFromDevice
        
        endRetryTimer1 = DispatchWorkItem { [weak self] in
            self?.postDockSwipeEventDirect(
                type: retryType, offset: retryOffset, delta: 0,
                phase: retryPhase, invertedFromDevice: retryInverted
            )
        }
        endRetryTimer2 = DispatchWorkItem { [weak self] in
            self?.postDockSwipeEventDirect(
                type: retryType, offset: retryOffset, delta: 0,
                phase: retryPhase, invertedFromDevice: retryInverted
            )
        }
        
        if let t1 = endRetryTimer1, let t2 = endRetryTimer2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: t1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: t2)
        }
    }
    
    /// Whether a gesture is currently in progress
    var gestureActive: Bool { isActive }
    
    /// Force-cancel any active gesture (e.g. when interceptor stops)
    func forceCancel() {
        if isActive {
            end(cancel: true)
        }
        cancelRetryTimers()
    }
    
    // MARK: - CGEvent Posting
    
    private func postDockSwipeEvent(delta: Double, phase: Phase) {
        postDockSwipeEventDirect(
            type: currentType,
            offset: originOffset,
            delta: delta,
            phase: phase,
            invertedFromDevice: invertedFromDevice
        )
    }
    
    /// Post a pair of DockSwipe CGEvents (type 29 + type 30).
    private func postDockSwipeEventDirect(
        type: SwipeType,
        offset: Double,
        delta: Double,
        phase: Phase,
        invertedFromDevice: Bool
    ) {
        let weirdTypeOrSum = DockSwipeSimulator.typeConstants[type] ?? 0
        
        // --- Event 1: Type 29 (NSEventTypeGesture) - companion ---
        guard let e29 = CGEvent(source: nil) else { return }
        
        // Set event type to NSEventTypeGesture (29)
        e29.setDoubleValueField(CGEventField(rawValue: 55)!, value: 29)
        // Magic constant observed in Mac Mouse Fix
        e29.setDoubleValueField(CGEventField(rawValue: 41)!, value: 33231)
        
        // --- Event 2: Type 30 (NSEventTypeMagnify) with DockSwipe subtype ---
        guard let e30 = CGEvent(source: nil) else { return }
        
        // Set event type to NSEventTypeMagnify (30) — confusingly named but required
        e30.setDoubleValueField(CGEventField(rawValue: 55)!, value: 30)
        
        // Magic constant (same as e29 — Mac Mouse Fix sets this on both events)
        e30.setDoubleValueField(CGEventField(rawValue: 41)!, value: 33231)
        
        // Subtype = kIOHIDEventTypeDockSwipe (value 23 in IOHIDEventTypes.h)
        // Standard enum: ...Zoom=8, ...NavigationSwipe=16, ...ZoomToggle=22, DockSwipe=23
        // (14 is kIOHIDEventTypeProximity — NOT DockSwipe!)
        e30.setDoubleValueField(CGEventField(rawValue: 110)!, value: 23)
        
        // Phase fields
        e30.setDoubleValueField(CGEventField(rawValue: 132)!, value: Double(phase.rawValue))
        e30.setDoubleValueField(CGEventField(rawValue: 134)!, value: Double(phase.rawValue))
        
        // Cumulative origin offset — THIS is what makes the animation follow the drag
        e30.setDoubleValueField(CGEventField(rawValue: 124)!, value: offset)
        
        // Float32-in-Int64 encoded origin offset (field 135)
        var ofsFloat32 = Float32(offset)
        var ofsUInt32: UInt32 = 0
        memcpy(&ofsUInt32, &ofsFloat32, MemoryLayout<Float32>.size)
        e30.setIntegerValueField(CGEventField(rawValue: 135)!, value: Int64(ofsUInt32))
        
        // Natural scrolling flag
        e30.setIntegerValueField(CGEventField(rawValue: 136)!, value: invertedFromDevice ? 1 : 0)
        
        // DockSwipe type fields
        e30.setDoubleValueField(CGEventField(rawValue: 123)!, value: Double(type.rawValue))
        e30.setDoubleValueField(CGEventField(rawValue: 165)!, value: Double(type.rawValue))
        
        // Encoded type constants
        e30.setDoubleValueField(CGEventField(rawValue: 119)!, value: weirdTypeOrSum)
        e30.setDoubleValueField(CGEventField(rawValue: 139)!, value: weirdTypeOrSum)
        
        // Exit speed — only set on end/cancelled phase for kinetic completion
        if phase == .ended || phase == .cancelled {
            let exitSpeed = lastDelta * 100
            e30.setDoubleValueField(CGEventField(rawValue: 129)!, value: exitSpeed)
            e30.setDoubleValueField(CGEventField(rawValue: 130)!, value: exitSpeed)
        }
        
        // Post events at kCGSessionEventTap (required for system-level gesture handling)
        e30.post(tap: .cgSessionEventTap)
        e29.post(tap: .cgSessionEventTap)
    }
    
    // MARK: - Helpers
    
    private func cancelRetryTimers() {
        endRetryTimer1?.cancel()
        endRetryTimer1 = nil
        endRetryTimer2?.cancel()
        endRetryTimer2 = nil
    }
    
    deinit {
        cancelRetryTimers()
    }
}
