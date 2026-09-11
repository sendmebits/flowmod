import CoreGraphics
import XCTest
@testable import FlowModInput

final class MiddleClickTests: XCTestCase {
    private func event(_ type: CGEventType, x: Double = 100, y: Double = 100,
                       button: UInt32 = 2, clicks: Int64 = 1,
                       timestamp: UInt64 = 1_000_000_000,
                       flags: CGEventFlags = [], number: Int64 = 1) -> CGEvent {
        let source = CGEventSource(stateID: .privateState)!
        let event = CGEvent(mouseEventSource: source, mouseType: type,
                            mouseCursorPosition: CGPoint(x: x, y: y),
                            mouseButton: CGMouseButton(rawValue: button)!)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        event.setIntegerValueField(.mouseEventClickState, value: clicks)
        event.setIntegerValueField(.mouseEventNumber, value: number)
        event.timestamp = timestamp
        event.flags = flags
        return event
    }

    @discardableResult
    private func send(_ event: CGEvent, to interceptor: InputInterceptor) -> CGEvent? {
        interceptor.handleEvent(event, type: event.type, proxy: nil)
    }

    func testClickIsCompleteBeforeReleaseCallbackReturns() {
        var delivered: [CGEvent] = []
        let interceptor = InputInterceptor.makeForTesting { event, _ in delivered.append(event) }
        XCTAssertNil(send(event(.otherMouseDown, clicks: 0, flags: .maskShift), to: interceptor))
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertNil(send(event(.otherMouseUp, x: 104, timestamp: 1_090_000_000,
                                flags: .maskCommand), to: interceptor))
        XCTAssertEqual(delivered.map(\.type), [.otherMouseDown, .otherMouseUp])
        guard delivered.count == 2 else { return }
        XCTAssertEqual(delivered[0].timestamp, 1_000_000_000)
        XCTAssertEqual(delivered[1].timestamp, 1_090_000_000)
        XCTAssertEqual(delivered[0].flags, .maskShift)
        XCTAssertEqual(delivered[1].flags, .maskCommand)
        for e in delivered {
            XCTAssertEqual(e.location, CGPoint(x: 104, y: 100))
            XCTAssertEqual(e.getIntegerValueField(.mouseEventButtonNumber), 2)
            XCTAssertEqual(e.getIntegerValueField(.mouseEventClickState), 1)
            XCTAssertEqual(e.getIntegerValueField(.eventSourceUserData), MiddleClick.eventMarker)
            // Re-entry must never synthesize a second click.
            XCTAssertTrue(send(e, to: interceptor) === e)
        }
        XCTAssertEqual(delivered.count, 2)
    }

    func testJitterAndThresholdBoundaryRemainClicks() {
        for distance in [0.0, 1.0, 5.0, 9.9, 10.0] {
            var delivered: [CGEventType] = []
            let interceptor = InputInterceptor.makeForTesting { e, _ in delivered.append(e.type) }
            send(event(.otherMouseDown), to: interceptor)
            let move = send(event(.otherMouseDragged, x: 100 + distance), to: interceptor)
            XCTAssertEqual(move?.type, .mouseMoved)
            send(event(.otherMouseUp, x: 100 + distance), to: interceptor)
            XCTAssertEqual(delivered, [.otherMouseDown, .otherMouseUp], "distance=\(distance)")
        }
    }

    func testGestureConsumesClickAndNextPressRecovers() {
        var config = InputInterceptor.RuntimeConfig.default
        config.continuousGestures = false
        // Exercise gesture commitment without sending a real desktop shortcut.
        config.middleDragMappings = [.right: MouseAction.none]
        var delivered: [CGEventType] = []
        let interceptor = InputInterceptor.makeForTesting(runtimeConfig: config) { e, _ in delivered.append(e.type) }
        send(event(.otherMouseDown), to: interceptor)
        XCTAssertNil(send(event(.otherMouseDragged, x: 111), to: interceptor))
        XCTAssertNil(send(event(.otherMouseUp, x: 111), to: interceptor))
        XCTAssertTrue(delivered.isEmpty)
        send(event(.otherMouseDown), to: interceptor)
        send(event(.otherMouseUp), to: interceptor)
        XCTAssertEqual(delivered, [.otherMouseDown, .otherMouseUp])
    }

    func testSideButtonDragDoesNotConsumeMiddleClick() {
        var delivered: [CGEventType] = []
        let interceptor = InputInterceptor.makeForTesting { e, _ in delivered.append(e.type) }
        send(event(.otherMouseDown), to: interceptor)
        let sideDrag = event(.otherMouseDragged, x: 300, button: 4)
        XCTAssertTrue(send(sideDrag, to: interceptor) === sideDrag)
        send(event(.otherMouseUp), to: interceptor)
        XCTAssertEqual(delivered, [.otherMouseDown, .otherMouseUp])
    }

    func testNativeMiddleClickWhenGesturesAreDisabled() {
        var config = InputInterceptor.RuntimeConfig.default
        config.middleDragMappings = [:]
        let interceptor = InputInterceptor.makeForTesting(runtimeConfig: config) { _, _ in XCTFail("Unexpected synthetic click") }
        for type in [CGEventType.otherMouseDown, .otherMouseDragged, .otherMouseUp] {
            let e = event(type)
            XCTAssertTrue(send(e, to: interceptor) === e)
        }
    }

    func testExplicitNoneConsumesBothEventsButOrphanUpPassesThrough() {
        var config = InputInterceptor.RuntimeConfig.default
        config.buttonMappings = [2: MouseAction.none]
        let interceptor = InputInterceptor.makeForTesting(runtimeConfig: config) { _, _ in XCTFail("Unexpected click") }
        let orphanUp = event(.otherMouseUp)
        XCTAssertTrue(send(orphanUp, to: interceptor) === orphanUp)
        XCTAssertNil(send(event(.otherMouseDown), to: interceptor))
        XCTAssertNil(send(event(.otherMouseUp), to: interceptor))
    }

    func testMissingReleaseIsDiscardedByNextPress() {
        var delivered: [CGEvent] = []
        let interceptor = InputInterceptor.makeForTesting { e, _ in delivered.append(e) }
        send(event(.otherMouseDown, x: 100), to: interceptor)
        send(event(.otherMouseDown, x: 400, clicks: 2), to: interceptor)
        send(event(.otherMouseUp, x: 400), to: interceptor)
        XCTAssertEqual(delivered.count, 2)
        XCTAssertTrue(delivered.allSatisfy { $0.location.x == 400 && $0.getIntegerValueField(.mouseEventClickState) == 2 })
    }

    func testFailedTapRecoveryNeverInventsClickAndConsumesLateRelease() {
        for type in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            var delivered: [CGEventType] = []
            let interceptor = InputInterceptor.makeForTesting { e, _ in delivered.append(e.type) }
            send(event(.otherMouseDown), to: interceptor)
            XCTAssertFalse(interceptor.recoverSessionTap(after: type, reenable: { false }))
            XCTAssertTrue(delivered.isEmpty)
            XCTAssertNil(send(event(.otherMouseUp), to: interceptor))
            XCTAssertTrue(delivered.isEmpty)
            send(event(.otherMouseDown), to: interceptor)
            send(event(.otherMouseUp), to: interceptor)
            XCTAssertEqual(delivered, [.otherMouseDown, .otherMouseUp])
        }
    }

    func testUserInputInterruptionPreservesClickAfterImmediateRecovery() {
        var delivered: [CGEventType] = []
        let interceptor = InputInterceptor.makeForTesting { e, _ in delivered.append(e.type) }
        send(event(.otherMouseDown, number: 42), to: interceptor)
        var attemptedRecovery = false
        XCTAssertTrue(interceptor.recoverSessionTap(after: .tapDisabledByUserInput) {
            attemptedRecovery = true
            return true
        })
        XCTAssertTrue(attemptedRecovery)
        XCTAssertTrue(delivered.isEmpty, "A notification is not a physical release")
        XCTAssertNil(send(event(.otherMouseUp, timestamp: 1_090_000_000, number: 42), to: interceptor))
        XCTAssertEqual(delivered, [.otherMouseDown, .otherMouseUp])
    }

    func testRepeatedUserInputNotificationsDoNotLoseOrDuplicateClick() {
        var delivered: [CGEventType] = []
        let interceptor = InputInterceptor.makeForTesting { e, _ in delivered.append(e.type) }
        send(event(.otherMouseDown), to: interceptor)
        for _ in 0..<3 {
            interceptor.recoverSessionTap(after: .tapDisabledByUserInput, reenable: { true })
        }
        XCTAssertTrue(delivered.isEmpty)
        send(event(.otherMouseUp), to: interceptor)
        XCTAssertEqual(delivered, [.otherMouseDown, .otherMouseUp])
    }

    func testRecoveredClickRejectsUnrelatedRelease() {
        var delivered: [CGEventType] = []
        let interceptor = InputInterceptor.makeForTesting { e, _ in delivered.append(e.type) }
        send(event(.otherMouseDown, number: 42), to: interceptor)
        interceptor.recoverSessionTap(after: .tapDisabledByUserInput, reenable: { true })
        XCTAssertNil(send(event(.otherMouseUp, number: 43), to: interceptor))
        XCTAssertTrue(delivered.isEmpty)
        send(event(.otherMouseDown, number: 44), to: interceptor)
        send(event(.otherMouseUp, number: 44), to: interceptor)
        XCTAssertEqual(delivered, [.otherMouseDown, .otherMouseUp])
    }

    func testRecoveredClickRejectsMovementMissedDuringInterruption() {
        let interceptor = InputInterceptor.makeForTesting { _, _ in XCTFail("Must not turn an interrupted drag into a click") }
        send(event(.otherMouseDown), to: interceptor)
        interceptor.recoverSessionTap(after: .tapDisabledByUserInput, reenable: { true })
        XCTAssertNil(send(event(.otherMouseUp, x: 130), to: interceptor))
    }

    func testRecoveredClickAllowsSmallMovement() {
        var count = 0
        let interceptor = InputInterceptor.makeForTesting { _, _ in count += 1 }
        send(event(.otherMouseDown), to: interceptor)
        interceptor.recoverSessionTap(after: .tapDisabledByUserInput, reenable: { true })
        send(event(.otherMouseUp, x: 105), to: interceptor)
        XCTAssertEqual(count, 2)
    }

    func testRecoveredUnnumberedClickRequiresRecentRelease() {
        for duration: UInt64 in [90_000_000, 2_000_000_000] {
            var count = 0
            let interceptor = InputInterceptor.makeForTesting { _, _ in count += 1 }
            send(event(.otherMouseDown, number: 0), to: interceptor)
            interceptor.recoverSessionTap(after: .tapDisabledByUserInput, reenable: { true })
            send(event(.otherMouseUp, timestamp: 1_000_000_000 + duration, number: 0), to: interceptor)
            XCTAssertEqual(count, duration < 1_000_000_000 ? 2 : 0)
        }
    }

    func testTimeoutStillDiscardsUncertainPressAfterRecovery() {
        let interceptor = InputInterceptor.makeForTesting { _, _ in XCTFail("Timeout must not synthesize a click") }
        send(event(.otherMouseDown), to: interceptor)
        XCTAssertTrue(interceptor.recoverSessionTap(after: .tapDisabledByTimeout, reenable: { true }))
        XCTAssertNil(send(event(.otherMouseUp), to: interceptor))
    }

    func testRecoveryDoesNotConvertCommittedGestureToClick() {
        var config = InputInterceptor.RuntimeConfig.default
        config.continuousGestures = false
        config.middleDragMappings = [.right: MouseAction.none]
        let interceptor = InputInterceptor.makeForTesting(runtimeConfig: config) { _, _ in XCTFail("Gesture must not click") }
        send(event(.otherMouseDown), to: interceptor)
        send(event(.otherMouseDragged, x: 130), to: interceptor)
        interceptor.recoverSessionTap(after: .tapDisabledByUserInput, reenable: { true })
        XCTAssertNil(send(event(.otherMouseUp, x: 130), to: interceptor))
    }

    func testRecoveryDoesNotFirePendingRemapping() {
        var config = InputInterceptor.RuntimeConfig.default
        config.buttonMappings = [2: MouseAction.none]
        let interceptor = InputInterceptor.makeForTesting(runtimeConfig: config) { _, _ in XCTFail("Remapped press must not click") }
        send(event(.otherMouseDown), to: interceptor)
        interceptor.recoverSessionTap(after: .tapDisabledByUserInput, reenable: { true })
        XCTAssertNil(send(event(.otherMouseUp), to: interceptor))
    }

    func testRecoveredClicksDoNotNeedMainQueue() {
        DispatchQueue.global(qos: .userInteractive).sync {
            var count = 0
            let interceptor = InputInterceptor.makeForTesting { _, _ in count += 1 }
            for _ in 0..<1_000 {
                autoreleasepool {
                    send(event(.otherMouseDown), to: interceptor)
                    interceptor.recoverSessionTap(after: .tapDisabledByUserInput, reenable: { true })
                    send(event(.otherMouseUp), to: interceptor)
                }
            }
            XCTAssertEqual(count, 2_000)
        }
    }

    func testSideButtonMappedToMiddleClickProducesOnePair() {
        var config = InputInterceptor.RuntimeConfig.default
        config.buttonMappings = [4: .middleClick]
        var delivered: [CGEventType] = []
        let interceptor = InputInterceptor.makeForTesting(runtimeConfig: config) { e, _ in delivered.append(e.type) }
        XCTAssertNil(send(event(.otherMouseDown, button: 4), to: interceptor))
        XCTAssertNil(send(event(.otherMouseUp, button: 4), to: interceptor))
        XCTAssertEqual(delivered, [.otherMouseDown, .otherMouseUp])
    }

    func testTwentyThousandClicksWithoutServicingMainQueue() {
        // Main thread waits for the worker. A main-queue delayed release cannot
        // complete here; every physical up must synchronously finish its pair.
        DispatchQueue.global(qos: .userInteractive).sync {
            var eventCount = 0
            let interceptor = InputInterceptor.makeForTesting { e, _ in
                XCTAssertEqual(e.type, eventCount.isMultiple(of: 2) ? .otherMouseDown : .otherMouseUp)
                eventCount += 1
            }
            for index in 0..<20_000 {
                autoreleasepool {
                    send(event(.otherMouseDown), to: interceptor)
                    send(event(.otherMouseUp), to: interceptor)
                    XCTAssertEqual(eventCount, (index + 1) * 2)
                }
            }
        }
    }
}
