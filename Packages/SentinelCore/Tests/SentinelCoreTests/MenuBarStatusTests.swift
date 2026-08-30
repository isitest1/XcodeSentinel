import XCTest
@testable import SentinelCore

final class MenuBarStatusTests: XCTestCase {
    func testEmptyIsOk() {
        XCTAssertEqual(MenuBarStatus.aggregate([]), .ok)
    }

    func testSingleStateMapping() {
        XCTAssertEqual(MenuBarStatus.aggregate([.idle]), .ok)
        XCTAssertEqual(MenuBarStatus.aggregate([.completed]), .ok)
        XCTAssertEqual(MenuBarStatus.aggregate([.unknown]), .ok)
        XCTAssertEqual(MenuBarStatus.aggregate([.working]), .working)
        XCTAssertEqual(MenuBarStatus.aggregate([.awaitingContinue]), .waiting)
        XCTAssertEqual(MenuBarStatus.aggregate([.awaitingApproval]), .waiting)
        XCTAssertEqual(MenuBarStatus.aggregate([.awaitingUserAnswer]), .waiting)
        XCTAssertEqual(MenuBarStatus.aggregate([.sessionLimited(resetAt: nil)]), .limited)
        XCTAssertEqual(MenuBarStatus.aggregate([.weeklyLimited(resetAt: nil)]), .limited)
        XCTAssertEqual(MenuBarStatus.aggregate([.errored(message: "x")]), .error)
    }

    func testErrorOutranksEverything() {
        XCTAssertEqual(
            MenuBarStatus.aggregate([.working, .sessionLimited(resetAt: nil), .errored(message: "x")]),
            .error
        )
    }

    func testLimitedOutranksWaitingAndWorking() {
        XCTAssertEqual(
            MenuBarStatus.aggregate([.working, .awaitingApproval, .weeklyLimited(resetAt: nil)]),
            .limited
        )
    }

    func testWaitingOutranksWorking() {
        XCTAssertEqual(MenuBarStatus.aggregate([.working, .awaitingContinue]), .waiting)
    }

    func testAllQuietIsOk() {
        XCTAssertEqual(MenuBarStatus.aggregate([.idle, .completed, .idle]), .ok)
    }

    func testEverySymbolIsNonEmpty() {
        for s in MenuBarStatus.allCases {
            XCTAssertFalse(s.symbolName.isEmpty)
        }
    }
}
