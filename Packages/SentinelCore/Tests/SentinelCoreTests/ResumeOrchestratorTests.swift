import XCTest
@testable import SentinelCore

final class ResumeOrchestratorTests: XCTestCase {
    private let cal = fixedCalendar("America/New_York")
    private let now = makeDate(2026, 8, 30, 12, 0)
    private let targetID = UUID()

    private func detection(
        _ state: SessionState,
        reset: ResetTimeParseResult? = nil
    ) -> DetectionEngine.Result {
        DetectionEngine.Result(
            state: state,
            matchedPatternID: nil,
            resetParse: reset,
            scannedTextCount: 3,
            panelLocated: true,
            nearMisses: []
        )
    }

    private func observation(
        _ state: SessionState,
        reset: ResetTimeParseResult? = nil,
        priority: Int = 0
    ) -> TargetObservation {
        TargetObservation(
            targetID: targetID,
            priority: priority,
            resumePrompt: "continue please",
            detection: detection(state, reset: reset)
        )
    }

    // MARK: - Notify-only states never enqueue a resume

    func testApprovalNotifiesAndDoesNotEnqueue() {
        var orch = ResumeOrchestrator()
        let effects = orch.ingest(observation(.awaitingApproval), now: now, calendar: cal)
        XCTAssertTrue(effects.contains(.notify(.init(targetID: targetID, reason: .awaitingApproval))))
        XCTAssertTrue(orch.scheduler.queue.isEmpty)
        XCTAssertTrue(orch.pump(now: now, calendar: cal).isEmpty)
    }

    func testUserAnswerAndErrorAreNotifyOnly() {
        var orch = ResumeOrchestrator()
        _ = orch.ingest(observation(.awaitingUserAnswer), now: now, calendar: cal)
        _ = orch.ingest(observation(.errored(message: "boom")), now: now, calendar: cal)
        XCTAssertTrue(orch.scheduler.queue.isEmpty)
    }

    // MARK: - Unknown streak → pause

    func testThreeConsecutiveUnknownsPausesMonitoring() {
        var orch = ResumeOrchestrator()
        _ = orch.ingest(observation(.unknown), now: now, calendar: cal)
        _ = orch.ingest(observation(.unknown), now: now, calendar: cal)
        let third = orch.ingest(observation(.unknown), now: now, calendar: cal)
        XCTAssertTrue(third.contains(.pauseMonitoring(targetID: targetID, .repeatedUnknown)))
        XCTAssertTrue(third.contains(.notify(.init(targetID: targetID, reason: .monitoringPaused(.repeatedUnknown)))))
        XCTAssertTrue(orch.pausedTargets.contains(targetID))
    }

    func testWorkingResetsUnknownStreak() {
        var orch = ResumeOrchestrator()
        _ = orch.ingest(observation(.unknown), now: now, calendar: cal)
        _ = orch.ingest(observation(.unknown), now: now, calendar: cal)
        _ = orch.ingest(observation(.working), now: now, calendar: cal)
        let effects = orch.ingest(observation(.unknown), now: now, calendar: cal)
        XCTAssertFalse(effects.contains(.pauseMonitoring(targetID: targetID, .repeatedUnknown)))
        XCTAssertEqual(orch.unknownStreak[targetID], 1)
    }

    // MARK: - awaitingContinue → enqueue → pump → performResume

    func testAwaitingContinueEnqueuesThenPumpsAResume() {
        var orch = ResumeOrchestrator()
        _ = orch.ingest(observation(.awaitingContinue), now: now, calendar: cal)
        XCTAssertEqual(orch.scheduler.queue.map(\.targetID), [targetID])

        let pumped = orch.pump(now: now, calendar: cal)
        XCTAssertEqual(
            pumped,
            [.performResume(targetID: targetID, prompt: "continue please", dryRun: false)]
        )
        XCTAssertTrue(orch.scheduler.running.contains(targetID))
    }

    func testDryRunProducesDryRunResume() {
        var orch = ResumeOrchestrator(limits: SafetyLimits(dryRun: true))
        _ = orch.ingest(observation(.awaitingContinue), now: now, calendar: cal)
        let pumped = orch.pump(now: now, calendar: cal)
        XCTAssertEqual(
            pumped,
            [.performResume(targetID: targetID, prompt: "continue please", dryRun: true)]
        )
    }

    // MARK: - Session limit: notify + hold until reset

    func testSessionLimitNotifiesAndHoldsUntilResetTime() {
        var orch = ResumeOrchestrator()
        let reset = ResetTimeParseResult(
            date: now.addingTimeInterval(3600), source: .absoluteClock, matchedText: "1:00 PM"
        )
        let effects = orch.ingest(observation(.sessionLimited(resetAt: reset.date), reset: reset),
                                  now: now, calendar: cal)

        // Notified with a concrete resume time (reset + 60s).
        XCTAssertTrue(effects.contains(
            .notify(.init(targetID: targetID, reason: .sessionLimit(resumeAt: now.addingTimeInterval(3660))))
        ))
        // Queued, but pump holds until the reset time.
        XCTAssertEqual(orch.scheduler.queue.count, 1)
        XCTAssertEqual(
            orch.pump(now: now, calendar: cal),
            [.recheckQueue(at: now.addingTimeInterval(3660))]
        )
        // At the reset time it dispatches.
        let later = now.addingTimeInterval(3660)
        XCTAssertEqual(
            orch.pump(now: later, calendar: cal),
            [.performResume(targetID: targetID, prompt: "continue please", dryRun: false)]
        )
    }

    func testWeeklyLimitUsesSixHourFallbackHold() {
        var orch = ResumeOrchestrator()
        _ = orch.ingest(observation(.weeklyLimited(resetAt: nil)), now: now, calendar: cal)
        XCTAssertEqual(
            orch.pump(now: now, calendar: cal),
            [.recheckQueue(at: now.addingTimeInterval(6 * 3600))]
        )
    }

    // MARK: - Retry limit

    func testThirdAttemptOnSameStallHitsRetryLimit() {
        var orch = ResumeOrchestrator()
        // attempt 1
        _ = orch.ingest(observation(.awaitingContinue), now: now, calendar: cal)
        _ = orch.pump(now: now, calendar: cal)
        _ = orch.recordSendOutcome(targetID: targetID, outcome: .sent, now: now)
        // attempt 2 (same stall persists)
        let t2 = now.addingTimeInterval(200)
        _ = orch.ingest(observation(.awaitingContinue), now: t2, calendar: cal)
        _ = orch.pump(now: t2, calendar: cal)
        _ = orch.recordSendOutcome(targetID: targetID, outcome: .sent, now: t2)
        // attempt 3 → refused, notified
        let t3 = now.addingTimeInterval(400)
        let effects = orch.ingest(observation(.awaitingContinue), now: t3, calendar: cal)
        XCTAssertTrue(effects.contains(.notify(.init(targetID: targetID, reason: .retryLimitReached))))
        XCTAssertTrue(orch.scheduler.queue.isEmpty)
    }

    // MARK: - Send outcome reporting

    func testFailedSendRaisesAttentionNotification() {
        var orch = ResumeOrchestrator()
        _ = orch.ingest(observation(.awaitingContinue), now: now, calendar: cal)
        _ = orch.pump(now: now, calendar: cal)
        let effects = orch.recordSendOutcome(
            targetID: targetID, outcome: .couldNotConfirmProgress, now: now
        )
        XCTAssertEqual(
            effects,
            [.notify(.init(targetID: targetID, reason: .resumeFailedNeedsAttention))]
        )
        XCTAssertFalse(orch.scheduler.running.contains(targetID))
    }

    func testCooldownBlocksImmediateSecondEnqueue() {
        var orch = ResumeOrchestrator()
        _ = orch.ingest(observation(.awaitingContinue), now: now, calendar: cal)
        _ = orch.pump(now: now, calendar: cal)
        _ = orch.recordSendOutcome(targetID: targetID, outcome: .sent, now: now)
        // 30s later the same stall is still there; cooldown (120s) blocks it.
        _ = orch.ingest(observation(.awaitingContinue), now: now.addingTimeInterval(30), calendar: cal)
        XCTAssertTrue(orch.scheduler.queue.isEmpty)
    }
}
