import XCTest
@testable import SentinelCore

/// Regression tests that run the bundled `PatternSet` against exported AX
/// snapshots. This is the payoff of splitting `SentinelCore` out as a
/// Linux-buildable package (CLAUDE.md sections 10 and 15.2): when Xcode changes
/// its panel wording, a refreshed fixture here fails fast.
final class DetectionEngineFixtureTests: XCTestCase {
    private func engine(now: Date = makeDate(2026, 8, 30, 13, 0)) throws -> DetectionEngine {
        try DetectionEngine(
            patterns: PatternSet.bundled(),
            clock: TestClock(now: now, timeZone: TimeZone(identifier: "America/New_York")!)
        )
    }

    func testSessionLimitedFixture() throws {
        let snapshot = try Fixture.snapshot("session-limited")
        let result = try engine().classify(snapshot)
        XCTAssertEqual(result.state, .sessionLimited(resetAt: makeDate(2026, 8, 30, 14, 15)))
        XCTAssertEqual(result.matchedPatternID, "session-limit")
    }

    func testWorkingFixture() throws {
        let snapshot = try Fixture.snapshot("working")
        let result = try engine().classify(snapshot)
        XCTAssertEqual(result.state, .working)
        XCTAssertEqual(result.matchedPatternID, "working")
    }

    func testAwaitingApprovalFixtureIsNeverAutoResumed() throws {
        let snapshot = try Fixture.snapshot("awaiting-approval")
        let result = try engine().classify(snapshot)
        XCTAssertEqual(result.state, .awaitingApproval)
        XCTAssertFalse(result.state.isAutoResumeEligible)
    }

    func testFixturesCarryNoObviousPII() throws {
        for name in ["session-limited", "working", "awaiting-approval"] {
            let raw = try String(data: Fixture.data(name), encoding: .utf8) ?? ""
            XCTAssertFalse(raw.contains("/Users/"), "\(name).json leaks a home path")
            XCTAssertFalse(raw.lowercased().contains(".xcodeproj/users"), "\(name).json leaks user data")
        }
    }
}
