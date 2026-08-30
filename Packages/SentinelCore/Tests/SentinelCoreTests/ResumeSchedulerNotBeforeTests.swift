import XCTest
@testable import SentinelCore

final class ResumeSchedulerNotBeforeTests: XCTestCase {
    private let cal = fixedCalendar("America/New_York")
    private let t0 = makeDate(2026, 8, 30, 12, 0)

    func testEntryHoldsUntilItsNotBefore() {
        var s = ResumeScheduler()
        let id = UUID()
        s.enqueue(QueuedResume(
            targetID: id, priority: 1, stalledAt: t0, enqueuedAt: t0,
            notBefore: t0.addingTimeInterval(3600)
        ))
        XCTAssertEqual(
            s.nextDispatch(now: t0, calendar: cal),
            .waitUntilReady(until: t0.addingTimeInterval(3600))
        )
        guard case let .start(entry) = s.nextDispatch(now: t0.addingTimeInterval(3600), calendar: cal) else {
            return XCTFail("expected start at notBefore")
        }
        XCTAssertEqual(entry.targetID, id)
    }

    func testReadyLowerPriorityIsSkippedForHeldHigherPriority() {
        // A high-priority entry is still holding; a ready lower-priority entry
        // should run rather than the whole queue stalling.
        var s = ResumeScheduler(configuration: .init(minSpacingBetweenStarts: 0))
        let held = UUID(), ready = UUID()
        s.enqueue(QueuedResume(
            targetID: held, priority: 0, stalledAt: t0, enqueuedAt: t0,
            notBefore: t0.addingTimeInterval(7200)
        ))
        s.enqueue(QueuedResume(targetID: ready, priority: 5, stalledAt: t0, enqueuedAt: t0))
        guard case let .start(entry) = s.nextDispatch(now: t0, calendar: cal) else {
            return XCTFail("expected the ready entry to start")
        }
        XCTAssertEqual(entry.targetID, ready)
    }

    func testWaitUntilReadyReportsSoonestHold() {
        var s = ResumeScheduler()
        s.enqueue(QueuedResume(
            targetID: UUID(), priority: 0, stalledAt: t0, enqueuedAt: t0,
            notBefore: t0.addingTimeInterval(9000)
        ))
        s.enqueue(QueuedResume(
            targetID: UUID(), priority: 1, stalledAt: t0, enqueuedAt: t0,
            notBefore: t0.addingTimeInterval(1800)
        ))
        XCTAssertEqual(
            s.nextDispatch(now: t0, calendar: cal),
            .waitUntilReady(until: t0.addingTimeInterval(1800))
        )
    }

    func testNilNotBeforeIsAlwaysReady() {
        var s = ResumeScheduler()
        let id = UUID()
        s.enqueue(QueuedResume(targetID: id, priority: 1, stalledAt: t0, enqueuedAt: t0))
        guard case .start = s.nextDispatch(now: t0, calendar: cal) else {
            return XCTFail("expected start")
        }
    }
}
