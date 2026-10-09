import Foundation

/// Discrete stand-in for continuous DockSwipe gestures when the macOS 27 HID
/// path is unavailable. Consumes the same DockSwipe deltas as
/// `DockSwipeSimulator` and fires the system's own symbolic hotkeys instead of
/// driving an interactive animation.
struct DockSwipeHotkeyFallback {
    typealias Sink = (SymbolicHotKey) -> Void

    /// Drag distance per Space switch; long drags step through several Spaces.
    static let horizontalStepPixels: Double = 220
    /// Drag distance before Mission Control / App Exposé opens (once per drag).
    static let verticalTriggerPixels: Double = 150

    private let sink: Sink
    private var type: DockSwipeSimulator.SwipeType = .horizontal
    private var stepSize: Double = 1
    private var offset: Double = 0
    /// Net Space switches posted this drag (positive = right).
    private var spaceSteps = 0
    private var verticalFired = false

    init(sink: @escaping Sink = { SymbolicHotkeys.post($0) }) {
        self.sink = sink
    }

    /// - Parameter stepSize: `horizontalStepPixels` or `verticalTriggerPixels`
    ///   converted to DockSwipe units for `type`.
    mutating func begin(type: DockSwipeSimulator.SwipeType, delta: Double, stepSize: Double) {
        self.type = type
        self.stepSize = max(abs(stepSize), .ulpOfOne)
        offset = 0
        spaceSteps = 0
        verticalFired = false
        update(delta: delta)
    }

    /// Offsets are positive for leftward/upward drags, matching continuous mode:
    /// drag left moves right a Space, drag up opens Mission Control.
    mutating func update(delta: Double) {
        offset += delta
        switch type {
        case .horizontal:
            let target = Int(offset / stepSize)
            while spaceSteps < target {
                spaceSteps += 1
                sink(.moveRightASpace)
            }
            while spaceSteps > target {
                spaceSteps -= 1
                sink(.moveLeftASpace)
            }
        case .vertical:
            guard !verticalFired, abs(offset) >= stepSize else { return }
            verticalFired = true
            sink(offset > 0 ? .missionControl : .applicationWindows)
        }
    }

    mutating func end() {
        offset = 0
        spaceSteps = 0
        verticalFired = false
    }
}
