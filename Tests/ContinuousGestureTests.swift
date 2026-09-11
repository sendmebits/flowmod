import CoreGraphics
import XCTest
@testable import FlowModInput

private final class RecordingDockSwipe: DockSwipeSimulator {
    var began: [SwipeType] = []
    var updates: [Double] = []
    var endings: [Bool] = []
    var cancellations = 0

    override func begin(type: SwipeType, delta: Double, dragThreshold: Double, invertedFromDevice: Bool) {
        began.append(type)
    }
    override func update(delta: Double) { updates.append(delta) }
    override func end(cancel: Bool) { endings.append(cancel) }
    override func forceCancel() { cancellations += 1 }
    override func pixelToDockSwipeScaled(_ pixels: Double, type: SwipeType) -> Double { pixels }
}

final class ContinuousGestureTests: XCTestCase {
    private func event(_ type: CGEventType, x: Double = 100, y: Double = 100) -> CGEvent {
        let event = CGEvent(mouseEventSource: CGEventSource(stateID: .privateState),
                            mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .center)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        event.setIntegerValueField(.mouseEventDeltaX, value: 20)
        event.setIntegerValueField(.mouseEventDeltaY, value: 20)
        return event
    }

    @discardableResult
    private func send(_ event: CGEvent, to interceptor: InputInterceptor) -> CGEvent? {
        interceptor.handleEvent(event, type: event.type, proxy: nil)
    }

    func testAllFourContinuousGesturesSurviveStaleDisableNotifications() {
        let directions: [(Double, Double, DockSwipeSimulator.SwipeType)] = [
            (130, 100, .horizontal), (70, 100, .horizontal),
            (100, 130, .vertical), (100, 70, .vertical)
        ]
        for (x, y, axis) in directions {
            let simulator = RecordingDockSwipe()
            let interceptor = InputInterceptor.makeForTesting(dockSwipeSimulator: simulator) { _, _ in XCTFail("Gesture must not click") }
            send(event(.otherMouseDown), to: interceptor)
            XCTAssertNil(send(event(.otherMouseDragged, x: x, y: y), to: interceptor))
            // A disable notification from the previous gesture arrives after
            // this gesture has already enabled the tap. Do not cancel it.
            interceptor.handleHIDTapDisabled(after: .tapDisabledByUserInput,
                isTapEnabled: { true }, reenable: { XCTFail("Tap is already enabled"); return false })
            interceptor.handleHIDDragDuringContinuousGesture(event(.otherMouseDragged))
            XCTAssertNil(send(event(.otherMouseUp, x: x, y: y), to: interceptor))
            XCTAssertEqual(simulator.began, [axis])
            XCTAssertEqual(simulator.updates.count, 1)
            XCTAssertEqual(simulator.endings, [false])
            XCTAssertEqual(simulator.cancellations, 0)
        }
    }

    func testIdleDisableNotificationFloodDoesNotTouchTapOrPendingClick() {
        var clicks = 0
        let interceptor = InputInterceptor.makeForTesting { _, _ in clicks += 1 }
        send(event(.otherMouseDown), to: interceptor)
        for _ in 0..<10_000 {
            interceptor.handleHIDTapDisabled(after: .tapDisabledByUserInput,
                isTapEnabled: { XCTFail("Idle notification should do nothing"); return false },
                reenable: { XCTFail("Idle tap must stay disabled"); return false })
        }
        send(event(.otherMouseUp), to: interceptor)
        XCTAssertEqual(clicks, 2)
    }

    func testActualUserInputDisableRecoversAndContinuesGesture() {
        let simulator = RecordingDockSwipe()
        let interceptor = InputInterceptor.makeForTesting(dockSwipeSimulator: simulator) { _, _ in XCTFail("Gesture must not click") }
        send(event(.otherMouseDown), to: interceptor)
        send(event(.otherMouseDragged, x: 130), to: interceptor)
        var recoveryAttempts = 0
        interceptor.handleHIDTapDisabled(after: .tapDisabledByUserInput, isTapEnabled: { false }) {
            recoveryAttempts += 1
            return true
        }
        interceptor.handleHIDDragDuringContinuousGesture(event(.otherMouseDragged))
        send(event(.otherMouseUp), to: interceptor)
        XCTAssertEqual(recoveryAttempts, 1)
        XCTAssertEqual(simulator.updates.count, 1)
        XCTAssertEqual(simulator.endings, [false])
        XCTAssertEqual(simulator.cancellations, 0)
    }

    func testFailedRecoveryCancelsOnceAndNextGestureWorks() {
        for type in [CGEventType.tapDisabledByUserInput, .tapDisabledByTimeout] {
            let simulator = RecordingDockSwipe()
            let interceptor = InputInterceptor.makeForTesting(dockSwipeSimulator: simulator) { _, _ in XCTFail("Gesture must not click") }
            send(event(.otherMouseDown), to: interceptor)
            send(event(.otherMouseDragged, x: 130), to: interceptor)
            interceptor.handleHIDTapDisabled(after: type, isTapEnabled: { false }, reenable: { false })
            for _ in 0..<100 {
                interceptor.handleHIDTapDisabled(after: .tapDisabledByUserInput,
                    isTapEnabled: { false }, reenable: { XCTFail("Already cancelled"); return false })
            }
            send(event(.otherMouseUp), to: interceptor)
            XCTAssertEqual(simulator.cancellations, 1)
            send(event(.otherMouseDown), to: interceptor)
            send(event(.otherMouseDragged, y: 70), to: interceptor)
            interceptor.handleHIDDragDuringContinuousGesture(event(.otherMouseDragged))
            send(event(.otherMouseUp), to: interceptor)
            XCTAssertEqual(simulator.began, [.horizontal, .vertical])
            XCTAssertEqual(simulator.endings, [false])
        }
    }

    func testEndNotificationDoesNotReenableTapAndNextClickWorks() {
        let simulator = RecordingDockSwipe()
        var clicks = 0
        let interceptor = InputInterceptor.makeForTesting(dockSwipeSimulator: simulator) { _, _ in clicks += 1 }
        send(event(.otherMouseDown), to: interceptor)
        send(event(.otherMouseDragged, x: 130), to: interceptor)
        send(event(.otherMouseUp), to: interceptor)
        interceptor.handleHIDTapDisabled(after: .tapDisabledByUserInput,
            isTapEnabled: { false }, reenable: { XCTFail("Gesture already ended"); return false })
        send(event(.otherMouseDown), to: interceptor)
        send(event(.otherMouseUp), to: interceptor)
        XCTAssertEqual(simulator.endings, [false])
        XCTAssertEqual(simulator.cancellations, 0)
        XCTAssertEqual(clicks, 2)
    }
}
