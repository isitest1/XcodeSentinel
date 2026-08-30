import XCTest
@testable import SentinelCore

final class SafetyPolicyTests: XCTestCase {
    private let cal = fixedCalendar("America/New_York")
    private let now = makeDate(2026, 8, 30, 12, 0)

    private func decide(
        state: SessionState,
        history: ResumeHistory,
        limits: SafetyLimits = .default,
        at date: Date? = nil
    ) -> ResumeDecision {
        SafetyPolicy.evaluate(
            state: state, history: history, limits: limits, now: date ?? now, calendar: cal
        )
    }

    func testApprovalAndQuestionAndUnknownAreNeverEligible() {
        for state in [SessionState.awaitingApproval, .awaitingUserAnswer, .unknown, .errored(message: "x")] {
            XCTAssertEqual(decide(state: state, history: ResumeHistory()), .deny(.stateNotEligible))
        }
    }

    func testAwaitingContinueIsEligible() {
        XCTAssertEqual(decide(state: .awaitingContinue, history: ResumeHistory()), .allow)
    }

    func testLimitStatesAreEligible() {
        XCTAssertEqual(decide(state: .sessionLimited(resetAt: nil), history: ResumeHistory()), .allow)
        XCTAssertEqual(decide(state: .weeklyLimited(resetAt: nil), history: ResumeHistory()), .allow)
    }

    func testDailyCapReached() {
        let today = cal.startOfDay(for: now)
        let attempts = (0..<12).map { today.addingTimeInterval(Double($0) * 600) }
        let history = ResumeHistory(attempts: attempts)
        XCTAssertEqual(
            decide(state: .sessionLimited(resetAt: nil), history: history),
            .deny(.dailyCapReached)
        )
    }

    func testYesterdaysAttemptsDoNotCountTowardTodaysCap() {
        let yesterday = cal.startOfDay(for: now).addingTimeInterval(-3600)
        let history = ResumeHistory(attempts: Array(repeating: yesterday, count: 20))
        XCTAssertEqual(decide(state: .sessionLimited(resetAt: nil), history: history), .allow)
    }

    func testCooldownActiveWithinMinInterval() {
        let history = ResumeHistory(attempts: [now.addingTimeInterval(-60)])
        XCTAssertEqual(
            decide(state: .awaitingContinue, history: history),
            .deny(.cooldownActive)
        )
    }

    func testCooldownClearsAfterMinInterval() {
        let history = ResumeHistory(attempts: [now.addingTimeInterval(-121)])
        XCTAssertEqual(decide(state: .awaitingContinue, history: history), .allow)
    }

    func testStallRetryLimit() {
        var history = ResumeHistory()
        history.observeStall(kind: "sessionLimited")
        history.recordAttempt(at: now.addingTimeInterval(-3600))   // attempt 1
        history.recordAttempt(at: now.addingTimeInterval(-1800))   // attempt 2
        // Third attempt for the same stall is refused.
        XCTAssertEqual(
            decide(state: .sessionLimited(resetAt: nil), history: history),
            .deny(.stallRetryLimitReached)
        )
    }

    func testStallCounterResetsWhenStallKindChanges() {
        var history = ResumeHistory()
        history.observeStall(kind: "sessionLimited")
        history.recordAttempt(at: now.addingTimeInterval(-7200))
        history.recordAttempt(at: now.addingTimeInterval(-3600))
        history.observeStall(kind: "awaitingContinue")   // different reason
        XCTAssertEqual(history.attemptsForCurrentStall, 0)
        XCTAssertEqual(decide(state: .awaitingContinue, history: history), .allow)
    }

    func testRecoveryClearsStallCounter() {
        var history = ResumeHistory()
        history.observeStall(kind: "sessionLimited")
        history.recordAttempt(at: now.addingTimeInterval(-7200))
        history.recordAttempt(at: now.addingTimeInterval(-3600))
        history.observeRecovery()
        XCTAssertNil(history.currentStallKind)
        XCTAssertEqual(history.attemptsForCurrentStall, 0)
    }

    func testDryRunOverridesAllow() {
        let limits = SafetyLimits(dryRun: true)
        XCTAssertEqual(decide(state: .awaitingContinue, history: ResumeHistory(), limits: limits), .dryRun)
    }

    func testDryRunStillDeniesIneligibleStates() {
        let limits = SafetyLimits(dryRun: true)
        XCTAssertEqual(
            decide(state: .awaitingApproval, history: ResumeHistory(), limits: limits),
            .deny(.stateNotEligible)
        )
    }
}
