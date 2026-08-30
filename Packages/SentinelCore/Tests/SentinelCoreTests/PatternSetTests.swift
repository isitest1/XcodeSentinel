import XCTest
@testable import SentinelCore

final class PatternSetTests: XCTestCase {
    func testBundledPatternsLoad() throws {
        let set = try PatternSet.bundled()
        XCTAssertGreaterThan(set.patterns.count, 0)
        XCTAssertEqual(set.version, 1)
    }

    func testBundledPatternsHaveUniqueIDs() throws {
        let set = try PatternSet.bundled()
        XCTAssertEqual(set.duplicateIDs, [])
    }

    func testWeeklyRulePrecedesSessionRule() throws {
        let set = try PatternSet.bundled()
        let weekly = set.patterns.firstIndex { $0.id == "weekly-limit" }
        let session = set.patterns.firstIndex { $0.id == "session-limit" }
        XCTAssertNotNil(weekly)
        XCTAssertNotNil(session)
        XCTAssertLessThan(weekly!, session!, "weekly limit must be checked before session limit")
    }

    func testRoundTripEncoding() throws {
        let set = try PatternSet.bundled()
        let data = try set.encoded()
        let decoded = try PatternSet.decode(from: data)
        XCTAssertEqual(decoded, set)
    }

    func testEveryOutcomeCaseMapsToASessionState() {
        // Guards against adding a DetectionOutcome without wiring it up.
        for outcome in DetectionOutcome.allCases {
            let engine = DetectionEngine(
                patterns: PatternSet(version: 1, patterns: [
                    DetectionPattern(id: "x", outcome: outcome, anyOf: ["marker"])
                ]),
                clock: TestClock(now: makeDate(2026, 8, 30, 12, 0))
            )
            let result = engine.classify(AXSnapshot(root: AXNode(role: "AXGroup", children: [
                AXNode(role: "AXStaticText", value: "marker text resets at 2:15 PM")
            ])))
            XCTAssertNotEqual(result.state, .unknown, "outcome \(outcome) did not resolve")
        }
    }
}
