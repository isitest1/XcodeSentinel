import XCTest
@testable import SentinelCore

final class ResetTimeParserTests: XCTestCase {
    private let cal = fixedCalendar("America/New_York")

    // MARK: - Absolute 12-hour clock

    func testResetsAtTwelveHourPMLaterToday() {
        let now = makeDate(2026, 8, 30, 13, 0)
        let result = ResetTimeParser.parse("Limit resets at 2:15 PM.", now: now, calendar: cal)
        XCTAssertEqual(result?.source, .absoluteClock)
        XCTAssertEqual(result?.date, makeDate(2026, 8, 30, 14, 15))
        XCTAssertEqual(result?.matchedText, "2:15 PM")
    }

    func testTwelveHourWithoutMinutes() {
        let now = makeDate(2026, 8, 30, 9, 0)
        let result = ResetTimeParser.parse("resets at 11 am", now: now, calendar: cal)
        XCTAssertEqual(result?.date, makeDate(2026, 8, 30, 11, 0))
    }

    func testTwelveHourNoonAndMidnight() {
        let now = makeDate(2026, 8, 30, 6, 0)
        XCTAssertEqual(
            ResetTimeParser.parse("resets at 12:00 pm", now: now, calendar: cal)?.date,
            makeDate(2026, 8, 30, 12, 0)
        )
        // 12:30 AM already passed today at 06:00 -> rolls to next day
        let midnight = ResetTimeParser.parse("resets 12:30 am", now: now, calendar: cal)
        XCTAssertEqual(midnight?.source, .absoluteClockNextDay)
        XCTAssertEqual(midnight?.date, makeDate(2026, 8, 31, 0, 30))
    }

    // MARK: - Absolute 24-hour clock

    func testTwentyFourHourClock() {
        let now = makeDate(2026, 8, 30, 10, 0)
        let result = ResetTimeParser.parse("resets 14:15", now: now, calendar: cal)
        XCTAssertEqual(result?.date, makeDate(2026, 8, 30, 14, 15))
    }

    func testAbsoluteTimeAlreadyPassedRollsToNextDay() {
        let now = makeDate(2026, 8, 30, 16, 0)
        let result = ResetTimeParser.parse("resets at 2:15 PM", now: now, calendar: cal)
        XCTAssertEqual(result?.source, .absoluteClockNextDay)
        XCTAssertEqual(result?.date, makeDate(2026, 8, 31, 14, 15))
    }

    // MARK: - Relative

    func testRelativeHours() {
        let now = makeDate(2026, 8, 30, 10, 0)
        let result = ResetTimeParser.parse("Try again in 3 hours.", now: now, calendar: cal)
        XCTAssertEqual(result?.source, .relative)
        XCTAssertEqual(result?.date, now.addingTimeInterval(3 * 3600))
    }

    func testRelativeHoursAndMinutes() {
        let now = makeDate(2026, 8, 30, 10, 0)
        let result = ResetTimeParser.parse("resets in 2 hours 30 minutes", now: now, calendar: cal)
        XCTAssertEqual(result?.date, now.addingTimeInterval(2 * 3600 + 30 * 60))
    }

    func testRelativeMinutesOnly() {
        let now = makeDate(2026, 8, 30, 10, 0)
        let result = ResetTimeParser.parse("available again in 45 minutes", now: now, calendar: cal)
        XCTAssertEqual(result?.date, now.addingTimeInterval(45 * 60))
    }

    func testRelativeAnHour() {
        let now = makeDate(2026, 8, 30, 10, 0)
        let result = ResetTimeParser.parse("resets in about an hour", now: now, calendar: cal)
        XCTAssertEqual(result?.date, now.addingTimeInterval(3600))
    }

    // MARK: - Tomorrow

    func testTomorrowAtClock() {
        let now = makeDate(2026, 8, 30, 22, 0)
        let result = ResetTimeParser.parse("Weekly limit resets tomorrow at 9 AM", now: now, calendar: cal)
        XCTAssertEqual(result?.source, .tomorrowClock)
        XCTAssertEqual(result?.date, makeDate(2026, 8, 31, 9, 0))
    }

    // MARK: - Time zones / DST

    func testParsesInCallerTimeZone() {
        let tokyo = fixedCalendar("Asia/Tokyo")
        let now = makeDate(2026, 8, 30, 13, 0, timeZone: "Asia/Tokyo")
        let result = ResetTimeParser.parse("resets at 6 pm", now: now, calendar: tokyo)
        XCTAssertEqual(result?.date, makeDate(2026, 8, 30, 18, 0, timeZone: "Asia/Tokyo"))
    }

    func testSpringForwardGapIsHandled() {
        // US DST 2026: clocks jump 02:00 -> 03:00 on Mar 8. "resets at 2:30 am"
        // names a wall time that does not exist; Calendar should still yield a
        // concrete instant rather than nil.
        let now = makeDate(2026, 3, 8, 1, 0)
        let result = ResetTimeParser.parse("resets at 2:30 am", now: now, calendar: cal)
        XCTAssertNotNil(result?.date)
    }

    // MARK: - Non-matches

    func testNoTimeReturnsNil() {
        let now = makeDate(2026, 8, 30, 10, 0)
        XCTAssertNil(ResetTimeParser.parse("You've hit your usage limit.", now: now, calendar: cal))
        XCTAssertNil(ResetTimeParser.parse("", now: now, calendar: cal))
        XCTAssertNil(ResetTimeParser.parse("about 5 files changed", now: now, calendar: cal))
    }

    // MARK: - Retry-time policy (CLAUDE.md 6.3)

    func testRetryTimeAddsSixtySecondsToParsedTime() {
        let now = makeDate(2026, 8, 30, 13, 0)
        let parsed = ResetTimeParser.parse("resets at 2:15 PM", now: now, calendar: cal)
        let retry = ResetTimeParser.retryTime(detectedAt: now, limit: .session, parsed: parsed)
        XCTAssertEqual(retry, makeDate(2026, 8, 30, 14, 16))
    }

    func testRetryTimeFallbackSession() {
        let now = makeDate(2026, 8, 30, 13, 0)
        let retry = ResetTimeParser.retryTime(detectedAt: now, limit: .session, parsed: nil)
        XCTAssertEqual(retry, now.addingTimeInterval(5 * 3600 + 5 * 60))
    }

    func testRetryTimeFallbackWeekly() {
        let now = makeDate(2026, 8, 30, 13, 0)
        let retry = ResetTimeParser.retryTime(detectedAt: now, limit: .weekly, parsed: nil)
        XCTAssertEqual(retry, now.addingTimeInterval(6 * 3600))
    }
}
