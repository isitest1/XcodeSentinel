import XCTest
@testable import SentinelCore

final class SessionStateTests: XCTestCase {
    func testKindNeverLeaksErrorMessage() {
        XCTAssertEqual(SessionState.errored(message: "secret path /Users/x").kind, "errored")
    }

    func testAutoResumeEligibility() {
        let eligible: [SessionState] = [.awaitingContinue, .sessionLimited(resetAt: nil), .weeklyLimited(resetAt: nil)]
        let notEligible: [SessionState] = [
            .idle, .working, .completed, .unknown,
            .awaitingApproval, .awaitingUserAnswer, .errored(message: "x")
        ]
        for s in eligible { XCTAssertTrue(s.isAutoResumeEligible, "\(s)") }
        for s in notEligible { XCTAssertFalse(s.isAutoResumeEligible, "\(s)") }
    }

    func testUnknownIsNotProgressing() {
        XCTAssertFalse(SessionState.unknown.isProgressing)
        XCTAssertTrue(SessionState.working.isProgressing)
    }

    func testStallClassification() {
        XCTAssertTrue(SessionState.awaitingApproval.isStall)
        XCTAssertTrue(SessionState.weeklyLimited(resetAt: nil).isStall)
        XCTAssertFalse(SessionState.working.isStall)
        XCTAssertFalse(SessionState.unknown.isStall)
    }

    func testResetAtAccessor() {
        let d = makeDate(2026, 8, 30, 14, 15)
        XCTAssertEqual(SessionState.sessionLimited(resetAt: d).resetAt, d)
        XCTAssertEqual(SessionState.weeklyLimited(resetAt: d).resetAt, d)
        XCTAssertNil(SessionState.working.resetAt)
    }
}
