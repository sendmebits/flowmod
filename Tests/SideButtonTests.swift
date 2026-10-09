import CoreGraphics
import XCTest
@testable import FlowModInput

final class SideButtonTests: XCTestCase {
    private func event(_ type: CGEventType, button: Int64) -> CGEvent {
        let event = CGEvent(mouseEventSource: CGEventSource(stateID: .privateState),
                            mouseType: type, mouseCursorPosition: CGPoint(x: 100, y: 100),
                            mouseButton: CGMouseButton(rawValue: UInt32(button))!)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: button)
        return event
    }

    @discardableResult
    private func send(_ event: CGEvent, to interceptor: InputInterceptor) -> CGEvent? {
        interceptor.handleEvent(event, type: event.type, proxy: nil)
    }

    func testConsumedButtonsSuppressOneReleaseEachAfterMappingsAreRemoved() {
        var config = InputInterceptor.RuntimeConfig.default
        config.buttonMappings = [3: MouseAction.none, 4: MouseAction.none]
        let interceptor = InputInterceptor.makeForTesting(runtimeConfig: config) { _, _ in
            XCTFail("Disabled button actions must not synthesize clicks")
        }
        for button in [Int64(3), 4] {
            XCTAssertNil(send(event(.otherMouseDown, button: button), to: interceptor))
        }

        config.buttonMappings = [:]
        interceptor.setRuntimeConfigForTesting(config)

        // An unrelated button must not consume another button's release state.
        let unrelatedUp = event(.otherMouseUp, button: 5)
        XCTAssertTrue(send(unrelatedUp, to: interceptor) === unrelatedUp)
        for button in [Int64(4), 3] {
            XCTAssertNil(send(event(.otherMouseUp, button: button), to: interceptor))
            let duplicateUp = event(.otherMouseUp, button: button)
            XCTAssertTrue(send(duplicateUp, to: interceptor) === duplicateUp)
            let nextDown = event(.otherMouseDown, button: button)
            let nextUp = event(.otherMouseUp, button: button)
            XCTAssertTrue(send(nextDown, to: interceptor) === nextDown)
            XCTAssertTrue(send(nextUp, to: interceptor) === nextUp)
        }
    }

    func testUnmappedNewPressClearsStaleConsumedButton() {
        var config = InputInterceptor.RuntimeConfig.default
        config.buttonMappings = [3: MouseAction.none]
        let interceptor = InputInterceptor.makeForTesting(runtimeConfig: config) { _, _ in
            XCTFail("Unexpected synthetic click")
        }
        XCTAssertNil(send(event(.otherMouseDown, button: 3), to: interceptor))
        config.buttonMappings = [:]
        interceptor.setRuntimeConfigForTesting(config)

        // The previous release was lost; a new unmapped press must pass through.
        let down = event(.otherMouseDown, button: 3)
        let up = event(.otherMouseUp, button: 3)
        XCTAssertTrue(send(down, to: interceptor) === down)
        XCTAssertTrue(send(up, to: interceptor) === up)
    }
}
