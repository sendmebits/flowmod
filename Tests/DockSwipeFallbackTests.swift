import XCTest
@testable import FlowModInput

final class DockSwipeFallbackTests: XCTestCase {
    private func makeFallback() -> (DockSwipeHotkeyFallback, () -> [SymbolicHotKey]) {
        var posted: [SymbolicHotKey] = []
        let fallback = DockSwipeHotkeyFallback { posted.append($0) }
        return (fallback, { posted })
    }

    func testNothingFiresBelowThreshold() {
        for type in [DockSwipeSimulator.SwipeType.horizontal, .vertical] {
            var (fallback, posted) = makeFallback()
            fallback.begin(type: type, delta: 0.2, stepSize: 1)
            fallback.update(delta: 0.5)
            fallback.update(delta: -1.4)
            fallback.end()
            XCTAssertEqual(posted(), [], "\(type)")
        }
    }

    func testHorizontalStepsAtEachMultipleInBothDirections() {
        var (fallback, posted) = makeFallback()
        fallback.begin(type: .horizontal, delta: 0.5, stepSize: 1)
        fallback.update(delta: 0.6)   // 1.1 -> one step right
        fallback.update(delta: 1.0)   // 2.1 -> second step right
        XCTAssertEqual(posted(), [.moveRightASpace, .moveRightASpace])

        fallback.update(delta: -1.2)  // 0.9 -> dragging back undoes both steps
        fallback.update(delta: -2.0)  // -1.1 -> one step left of the origin
        XCTAssertEqual(posted(), [.moveRightASpace, .moveRightASpace,
                                  .moveLeftASpace, .moveLeftASpace, .moveLeftASpace])
    }

    func testLargeDeltaStepsThroughSeveralSpaces() {
        var (fallback, posted) = makeFallback()
        fallback.begin(type: .horizontal, delta: -3.5, stepSize: 1)
        XCTAssertEqual(posted(), [.moveLeftASpace, .moveLeftASpace, .moveLeftASpace])
    }

    func testVerticalFiresOncePerDragWithDirection() {
        var (up, upPosted) = makeFallback()
        up.begin(type: .vertical, delta: 0.6, stepSize: 1)
        up.update(delta: 0.6)
        up.update(delta: 5)
        up.update(delta: -10)
        up.end()
        XCTAssertEqual(upPosted(), [.missionControl])

        var (down, downPosted) = makeFallback()
        down.begin(type: .vertical, delta: -1.5, stepSize: 1)
        down.update(delta: -2)
        down.end()
        XCTAssertEqual(downPosted(), [.applicationWindows])
    }

    func testNewDragResetsState() {
        var (fallback, posted) = makeFallback()
        fallback.begin(type: .vertical, delta: 2, stepSize: 1)
        fallback.end()
        fallback.begin(type: .vertical, delta: 2, stepSize: 1)
        fallback.end()
        fallback.begin(type: .horizontal, delta: 1.5, stepSize: 1)
        fallback.end()
        XCTAssertEqual(posted(), [.missionControl, .missionControl, .moveRightASpace])
    }

    func testSimulatorRoutesFallbackBackendWithoutPostingEvents() {
        var posted: [SymbolicHotKey] = []
        let simulator = DockSwipeSimulator(backend: .hotkeyFallback,
                                           hotkeyFallback: DockSwipeHotkeyFallback { posted.append($0) })
        let step = simulator.pixelToDockSwipeScaled(DockSwipeHotkeyFallback.verticalTriggerPixels, type: .vertical)
        // begin() re-reads the real display size, so keep wide margins around the step.
        simulator.begin(type: .vertical, delta: step * 0.1)
        XCTAssertEqual(posted, [])
        simulator.update(delta: step * 3)
        simulator.end()
        XCTAssertEqual(posted, [.missionControl])
    }
}
