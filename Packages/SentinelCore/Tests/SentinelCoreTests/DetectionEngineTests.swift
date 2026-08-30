import XCTest
@testable import SentinelCore

final class DetectionEngineTests: XCTestCase {
    private func engine(
        _ patterns: [DetectionPattern],
        now: Date = makeDate(2026, 8, 30, 13, 0)
    ) -> DetectionEngine {
        DetectionEngine(
            patterns: PatternSet(version: 1, patterns: patterns),
            clock: TestClock(now: now, timeZone: TimeZone(identifier: "America/New_York")!)
        )
    }

    private func snapshot(_ texts: [(role: String, text: String)]) -> AXSnapshot {
        AXSnapshot(root: AXNode(
            role: "AXGroup",
            children: texts.map { AXNode(role: $0.role, value: $0.text) }
        ))
    }

    func testFirstMatchingPatternWins() {
        let engine = engine([
            DetectionPattern(id: "weekly", outcome: .weeklyLimited, anyOf: ["weekly limit"]),
            DetectionPattern(id: "session", outcome: .sessionLimited, anyOf: ["limit"])
        ])
        let result = engine.classify(snapshot([("AXStaticText", "You hit the weekly limit")]))
        XCTAssertEqual(result.state, .weeklyLimited(resetAt: nil))
        XCTAssertEqual(result.matchedPatternID, "weekly")
    }

    func testNoMatchYieldsUnknownNotWorking() {
        let engine = engine([
            DetectionPattern(id: "working", outcome: .working, anyOf: ["generating"])
        ])
        let result = engine.classify(snapshot([("AXStaticText", "some unrelated chat content")]))
        XCTAssertEqual(result.state, .unknown)
        XCTAssertNil(result.matchedPatternID)
    }

    func testEmptyTreeIsUnknown() {
        let engine = engine([
            DetectionPattern(id: "working", outcome: .working, anyOf: ["generating"])
        ])
        let result = engine.classify(AXSnapshot(root: AXNode(role: "AXGroup")))
        XCTAssertEqual(result.state, .unknown)
        XCTAssertEqual(result.scannedTextCount, 0)
    }

    func testRoleConstraintIsEnforced() {
        let engine = engine([
            DetectionPattern(id: "q", outcome: .awaitingUserAnswer, anyOf: ["?"], role: "AXStaticText")
        ])
        // "?" only appears on a button title, not static text -> no match
        let result = engine.classify(snapshot([("AXButton", "Why not?")]))
        XCTAssertEqual(result.state, .unknown)
    }

    func testNoneOfRejectsMatch() {
        let engine = engine([
            DetectionPattern(
                id: "session", outcome: .sessionLimited, anyOf: ["limit"], noneOf: ["weekly"]
            )
        ])
        let result = engine.classify(snapshot([("AXStaticText", "weekly limit reached")]))
        XCTAssertEqual(result.state, .unknown)
    }

    func testSessionLimitExtractsResetTime() {
        let engine = engine([
            DetectionPattern(id: "session", outcome: .sessionLimited, anyOf: ["usage limit"])
        ])
        let result = engine.classify(snapshot([
            ("AXStaticText", "You've hit your usage limit. Resets at 2:15 PM.")
        ]))
        XCTAssertEqual(result.state, .sessionLimited(resetAt: makeDate(2026, 8, 30, 14, 15)))
        XCTAssertEqual(result.resetParse?.matchedText, "2:15 PM")
    }

    func testSessionLimitWithNoParsableTimeStillClassifies() {
        let engine = engine([
            DetectionPattern(id: "session", outcome: .sessionLimited, anyOf: ["usage limit"])
        ])
        let result = engine.classify(snapshot([("AXStaticText", "You've hit your usage limit.")]))
        XCTAssertEqual(result.state, .sessionLimited(resetAt: nil))
        XCTAssertNil(result.resetParse)
    }

    func testErroredCapturesMessage() {
        let engine = engine([
            DetectionPattern(id: "err", outcome: .errored, anyOf: ["an error occurred"])
        ])
        let result = engine.classify(snapshot([("AXStaticText", "an error occurred while applying edits")]))
        XCTAssertEqual(result.state, .errored(message: "an error occurred while applying edits"))
    }

    func testDisabledPatternIsSkipped() {
        let engine = engine([
            DetectionPattern(id: "working", outcome: .working, anyOf: ["generating"], enabled: false)
        ])
        let result = engine.classify(snapshot([("AXStaticText", "generating response")]))
        XCTAssertEqual(result.state, .unknown)
    }
}
