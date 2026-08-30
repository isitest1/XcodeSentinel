import XCTest
@testable import SentinelCore

final class PollingIntervalTests: XCTestCase {
    private let now = makeDate(2026, 8, 30, 12, 0)

    func testWorkingAndContinueCadence() {
        XCTAssertEqual(PollingInterval.seconds(for: .working, now: now), 30)
        XCTAssertEqual(PollingInterval.seconds(for: .awaitingContinue, now: now), 10)
    }

    func testWeeklyLimitedIsHalfHourly() {
        XCTAssertEqual(PollingInterval.seconds(for: .weeklyLimited(resetAt: nil), now: now), 30 * 60)
    }

    func testSessionLimitedSlowUntilTenMinutesBeforeReset() {
        let reset = now.addingTimeInterval(3600)
        XCTAssertEqual(
            PollingInterval.seconds(for: .sessionLimited(resetAt: reset), now: now),
            5 * 60
        )
    }

    func testSessionLimitedFastInsideFinalTenMinutes() {
        let reset = now.addingTimeInterval(5 * 60)
        XCTAssertEqual(
            PollingInterval.seconds(for: .sessionLimited(resetAt: reset), now: now),
            30
        )
    }

    func testSessionLimitedWithoutResetTimeUsesFiveMinutes() {
        XCTAssertEqual(
            PollingInterval.seconds(for: .sessionLimited(resetAt: nil), now: now),
            5 * 60
        )
    }

    func testUnknownCadenceAndPauseThreshold() {
        XCTAssertEqual(PollingInterval.seconds(for: .unknown, now: now), 60)
        XCTAssertFalse(PollingInterval.shouldPauseAfterUnknown(consecutiveUnknownCount: 2))
        XCTAssertTrue(PollingInterval.shouldPauseAfterUnknown(consecutiveUnknownCount: 3))
    }
}
