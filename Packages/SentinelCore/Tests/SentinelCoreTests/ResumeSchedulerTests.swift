import XCTest
@testable import SentinelCore

final class ResumeSchedulerTests: XCTestCase {
    private let cal = fixedCalendar("America/New_York")
    private let t0 = makeDate(2026, 8, 30, 12, 0)

    private func entry(_ id: UUID, priority: Int, stalledAt: Date) -> QueuedResume {
        QueuedResume(targetID: id, priority: priority, stalledAt: stalledAt, enqueuedAt: stalledAt)
    }

    func testQueueOrdersByPriorityThenStallTime() {
        var s = ResumeScheduler()
        let a = UUID(), b = UUID(), c = UUID()
        s.enqueue(entry(a, priority: 5, stalledAt: t0))
        s.enqueue(entry(b, priority: 1, stalledAt: t0.addingTimeInterval(60)))
        s.enqueue(entry(c, priority: 1, stalledAt: t0))
        XCTAssertEqual(s.queue.map(\.targetID), [c, b, a])
    }

    func testEnqueueIsIdempotentPerTarget() {
        var s = ResumeScheduler()
        let a = UUID()
        s.enqueue(entry(a, priority: 1, stalledAt: t0))
        s.enqueue(entry(a, priority: 0, stalledAt: t0))
        XCTAssertEqual(s.queue.count, 1)
    }

    func testStartsOneAtATimeByDefault() {
        var s = ResumeScheduler()
        let a = UUID(), b = UUID()
        s.enqueue(entry(a, priority: 1, stalledAt: t0))
        s.enqueue(entry(b, priority: 2, stalledAt: t0))

        guard case let .start(first) = s.nextDispatch(now: t0, calendar: cal) else {
            return XCTFail("expected a start")
        }
        XCTAssertEqual(first.targetID, a)
        s.markStarted(targetID: a, now: t0)

        // Second is blocked by the concurrency cap of 1.
        XCTAssertEqual(s.nextDispatch(now: t0.addingTimeInterval(1000), calendar: cal), .atCapacity)

        s.markFinished(targetID: a)
        // Now only the spacing gate applies (90s since last start).
        XCTAssertEqual(
            s.nextDispatch(now: t0.addingTimeInterval(10), calendar: cal),
            .waitSpacing(until: t0.addingTimeInterval(90))
        )
        guard case let .start(second) = s.nextDispatch(now: t0.addingTimeInterval(90), calendar: cal) else {
            return XCTFail("expected second start after spacing")
        }
        XCTAssertEqual(second.targetID, b)
    }

    func testConcurrencyCapIsClampedToThree() {
        let cfg = ResumeScheduler.Configuration(maxConcurrent: 99)
        XCTAssertEqual(cfg.maxConcurrent, 3)
        XCTAssertEqual(ResumeScheduler.Configuration(maxConcurrent: 0).maxConcurrent, 1)
    }

    func testHigherConcurrencyAllowsParallelStarts() {
        var s = ResumeScheduler(configuration: .init(maxConcurrent: 2, minSpacingBetweenStarts: 0))
        let a = UUID(), b = UUID()
        s.enqueue(entry(a, priority: 1, stalledAt: t0))
        s.enqueue(entry(b, priority: 2, stalledAt: t0))
        s.markStarted(targetID: a, now: t0)
        guard case let .start(next) = s.nextDispatch(now: t0, calendar: cal) else {
            return XCTFail("expected a parallel start")
        }
        XCTAssertEqual(next.targetID, b)
    }

    func testQuietHoursSuppressResumes() {
        // 23:00 -> 07:00 window.
        let quiet = QuietHours(startHour: 23, endHour: 7)
        var s = ResumeScheduler(configuration: .init(quietHours: quiet))
        let a = UUID()
        s.enqueue(entry(a, priority: 1, stalledAt: makeDate(2026, 8, 30, 2, 0)))

        let inWindow = makeDate(2026, 8, 30, 2, 0)
        XCTAssertEqual(
            s.nextDispatch(now: inWindow, calendar: cal),
            .waitQuietHours(until: makeDate(2026, 8, 30, 7, 0))
        )

        let afterWindow = makeDate(2026, 8, 30, 7, 1)
        guard case .start = s.nextDispatch(now: afterWindow, calendar: cal) else {
            return XCTFail("should resume once quiet hours end")
        }
    }

    func testQuietHoursLateNightRollsToNextMorning() {
        let quiet = QuietHours(startHour: 23, endHour: 7)
        var s = ResumeScheduler(configuration: .init(quietHours: quiet))
        s.enqueue(entry(UUID(), priority: 1, stalledAt: makeDate(2026, 8, 30, 23, 30)))
        XCTAssertEqual(
            s.nextDispatch(now: makeDate(2026, 8, 30, 23, 30), calendar: cal),
            .waitQuietHours(until: makeDate(2026, 8, 31, 7, 0))
        )
    }

    func testEmptyQueueReturnsEmpty() {
        let s = ResumeScheduler()
        XCTAssertEqual(s.nextDispatch(now: t0, calendar: cal), .empty)
    }

    func testCancelRemovesFromQueue() {
        var s = ResumeScheduler()
        let a = UUID()
        s.enqueue(entry(a, priority: 1, stalledAt: t0))
        s.cancel(targetID: a)
        XCTAssertTrue(s.isIdle)
    }
}
