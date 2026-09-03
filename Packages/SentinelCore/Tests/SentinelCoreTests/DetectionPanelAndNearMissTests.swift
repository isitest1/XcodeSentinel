import XCTest
@testable import SentinelCore

final class DetectionPanelAndNearMissTests: XCTestCase {
    private func engine(
        patterns: [DetectionPattern],
        hints: PanelHints = .init(),
        now: Date = makeDate(2026, 8, 30, 13, 0)
    ) -> DetectionEngine {
        DetectionEngine(
            patterns: PatternSet(version: 1, patterns: patterns, panelHints: hints),
            clock: TestClock(now: now, timeZone: TimeZone(identifier: "America/New_York")!)
        )
    }

    // MARK: - Panel location

    /// Synthetic whole-window snapshot: an outer AXWindow containing an editor
    /// group with unrelated text AND a Claude chat group identified by
    /// AXOpaqueProviderGroup, where the limit message lives.
    private func syntheticWholeWindowWithLimit() -> AXSnapshot {
        let chatPanel = AXNode(
            role: "AXOpaqueProviderGroup",
            children: [
                AXNode(role: "AXStaticText", value: "You've hit your usage limit. Resets at 2:15 PM."),
            ]
        )
        let chatScrollArea = AXNode(role: "AXScrollArea", children: [chatPanel])
        let chatGroup = AXNode(role: "AXGroup", children: [chatScrollArea])
        let editorGroup = AXNode(role: "AXGroup", children: [
            AXNode(role: "AXStaticText", value: "func myFunc() -> Int { 42 }"),
            AXNode(role: "AXStaticText", value: "// some editor content"),
        ])
        let root = AXNode(role: "AXWindow", children: [editorGroup, chatGroup])
        return AXSnapshot(root: root)
    }

    func testLocatesPanelInsideAWholeWindowSnapshot() {
        let snapshot = syntheticWholeWindowWithLimit()
        let e = engine(
            patterns: [DetectionPattern(id: "session-limit", outcome: .sessionLimited, anyOf: ["usage limit"])],
            hints: PanelHints(containerRoles: ["AXOpaqueProviderGroup"])
        )
        let result = e.classify(snapshot)
        XCTAssertTrue(result.panelLocated)
        XCTAssertEqual(result.state, .sessionLimited(resetAt: makeDate(2026, 8, 30, 14, 15)))
        // Editor text must have been excluded — only the chat panel was scanned.
        XCTAssertLessThan(result.scannedTextCount, snapshot.allTexts.count)
    }

    func testFallsBackToWholeTreeWhenHintsAreEmpty() {
        let snapshot = syntheticWholeWindowWithLimit()
        let e = engine(
            patterns: [DetectionPattern(id: "session-limit", outcome: .sessionLimited, anyOf: ["usage limit"])]
        )
        let result = e.classify(snapshot)
        XCTAssertFalse(result.panelLocated)
        // Whole tree is scanned → limit text is found even without hints.
        XCTAssertEqual(result.state, .sessionLimited(resetAt: makeDate(2026, 8, 30, 14, 15)))
    }

    func testIdentifierHintTakesPrecedence() {
        let tree = AXNode(role: "AXWindow", children: [
            AXNode(role: "AXGroup", identifier: "claude-panel-v2", children: [
                AXNode(role: "AXStaticText", value: "Generating…")
            ]),
            AXNode(role: "AXGroup", children: [AXNode(role: "AXStaticText", value: "unrelated")])
        ])
        let e = engine(
            patterns: [DetectionPattern(id: "working", outcome: .working, anyOf: ["generating"])],
            hints: PanelHints(identifiers: ["claude-panel-v2"])
        )
        let result = e.classify(AXSnapshot(root: tree))
        XCTAssertTrue(result.panelLocated)
        XCTAssertEqual(result.state, .working)
    }

    // MARK: - Near misses

    func testDisabledPatternIsReportedAsNearMiss() {
        let e = engine(patterns: [
            DetectionPattern(id: "completed", outcome: .completed, anyOf: ["changes applied"], enabled: false)
        ])
        let snap = AXSnapshot(root: AXNode(role: "AXGroup", children: [
            AXNode(role: "AXStaticText", value: "All changes applied successfully")
        ]))
        let result = e.classify(snap)
        XCTAssertEqual(result.state, .unknown)
        XCTAssertEqual(result.nearMisses.map(\.patternID), ["completed"])
        XCTAssertEqual(result.nearMisses.first?.reason, .wouldMatchIfEnabled)
    }

    func testNoneOfBlockIsReportedAsNearMiss() {
        let e = engine(patterns: [
            DetectionPattern(id: "session", outcome: .sessionLimited, anyOf: ["limit"], noneOf: ["weekly"])
        ])
        let snap = AXSnapshot(root: AXNode(role: "AXGroup", children: [
            AXNode(role: "AXStaticText", value: "weekly limit reached")
        ]))
        let result = e.classify(snap)
        XCTAssertEqual(result.state, .unknown)
        XCTAssertEqual(result.nearMisses.first?.reason, .blockedByNoneOf("weekly"))
    }

    func testRoleMismatchIsReportedAsNearMiss() {
        let e = engine(patterns: [
            DetectionPattern(id: "q", outcome: .awaitingUserAnswer, anyOf: ["which option"], role: "AXStaticText")
        ])
        let snap = AXSnapshot(root: AXNode(role: "AXGroup", children: [
            AXNode(role: "AXButton", title: "which option?")
        ]))
        let result = e.classify(snap)
        XCTAssertEqual(result.state, .unknown)
        XCTAssertEqual(result.nearMisses.first?.reason, .blockedByRole)
    }

    func testCleanMatchHasNoNearMisses() {
        let e = engine(patterns: [
            DetectionPattern(id: "working", outcome: .working, anyOf: ["generating"])
        ])
        let snap = AXSnapshot(root: AXNode(role: "AXGroup", children: [
            AXNode(role: "AXStaticText", value: "generating response")
        ]))
        XCTAssertEqual(e.classify(snap).nearMisses, [])
    }
}
