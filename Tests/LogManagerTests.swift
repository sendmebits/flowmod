import XCTest
@testable import FlowModInput

final class LogManagerTests: XCTestCase {
    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor
    func testClearRemovesVisibleAndQueuedLogs() async {
        let logger = LogManager.makeForTesting()
        logger.setDebugEnabled(true)
        logger.log("visible before clear")
        _ = logger.getLogsAsString()
        DispatchQueue.global().sync {
            for index in 0..<2_000 { logger.log("queued before clear \(index)") }
        }
        logger.clearLogs()
        XCTAssertEqual(logger.entryCount, 0)
        await drainMainQueue()
        XCTAssertEqual(logger.entryCount, 0, "Queued logs must not refill a cleared log")
        XCTAssertTrue(logger.getLogsAsString().hasPrefix("No logs available."))
    }

    @MainActor
    func testNewLogsAfterClearAreRetained() async {
        let logger = LogManager.makeForTesting()
        logger.setDebugEnabled(true)
        logger.log("old entry")
        logger.clearLogs()
        logger.log("new entry")
        await drainMainQueue()
        let output = logger.getLogsAsString()
        XCTAssertEqual(logger.entryCount, 1)
        XCTAssertTrue(output.contains("new entry"))
        XCTAssertFalse(output.contains("old entry"))
    }

    @MainActor
    func testMessageStartedBeforeClearCannotArriveAfterIt() async {
        let logger = LogManager.makeForTesting()
        logger.setDebugEnabled(true)
        func message() -> String {
            logger.clearLogs()
            return "stale in-flight entry"
        }
        logger.log(message())
        await drainMainQueue()
        XCTAssertEqual(logger.entryCount, 0)
    }

    @MainActor
    func testCopyIncludesLatestBoundedBatchBeforeUIUpdate() async {
        let logger = LogManager.makeForTesting()
        logger.setDebugEnabled(true)
        DispatchQueue.global().sync {
            for index in 0..<10_000 { logger.log("record-\(index)-end") }
        }
        let output = logger.getLogsAsString()
        XCTAssertEqual(logger.entryCount, 500)
        XCTAssertTrue(output.contains("record-9999-end"))
        XCTAssertTrue(output.contains("record-9500-end"))
        XCTAssertFalse(output.contains("record-9499-end"))
        await drainMainQueue()
        XCTAssertEqual(logger.entryCount, 500, "Scheduled drain must not duplicate the copied batch")
    }

    @MainActor
    func testDisabledLoggingDoesNotEvaluateMessage() async {
        let logger = LogManager.makeForTesting()
        var evaluated = false
        func message() -> String { evaluated = true; return "unused" }
        logger.log(message())
        await drainMainQueue()
        XCTAssertFalse(evaluated)
        XCTAssertEqual(logger.entryCount, 0)
    }
}
