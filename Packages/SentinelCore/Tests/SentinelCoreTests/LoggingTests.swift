import XCTest
@testable import SentinelCore

final class LoggingTests: XCTestCase {
    func testRespectsMinimumLevel() {
        let sink = CollectingLogSink()
        let logger = Logger(
            subsystem: "test",
            sink: sink,
            clock: TestClock(now: makeDate(2026, 8, 30, 12, 0)),
            minimumLevel: .warning
        )
        logger.info("dropped")
        logger.warning("kept")
        logger.error("kept too")
        XCTAssertEqual(sink.records.map(\.message), ["kept", "kept too"])
    }

    func testStampsSubsystemAndTimestamp() {
        let sink = CollectingLogSink()
        let now = makeDate(2026, 8, 30, 12, 0)
        let logger = Logger(subsystem: "detector", sink: sink, clock: TestClock(now: now))
        logger.notice("state changed", ["target": "SampleApp", "state": "sessionLimited"])
        let record = try! XCTUnwrap(sink.records.first)
        XCTAssertEqual(record.metadata["subsystem"], "detector")
        XCTAssertEqual(record.metadata["target"], "SampleApp")
        XCTAssertEqual(record.timestamp, now)
    }
}
