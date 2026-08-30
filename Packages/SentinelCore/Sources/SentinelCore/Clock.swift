import Foundation

/// A source of "now" that can be injected in tests.
///
/// Production code must never call `Date()` directly (CLAUDE.md section 12).
/// Anything that reasons about time takes a `SentinelClock` so that reset-time
/// math, cooldowns and quiet hours can be tested deterministically.
public protocol SentinelClock: Sendable {
    /// The current wall-clock instant.
    var now: Date { get }

    /// The calendar used for day boundaries, quiet-hour windows and time-of-day
    /// comparisons. Carries its own time zone.
    var calendar: Calendar { get }
}

extension SentinelClock {
    /// Start of the calendar day that contains `now`, in the clock's time zone.
    public var startOfToday: Date {
        calendar.startOfDay(for: now)
    }
}

/// The real clock, backed by the system time and the current calendar.
public struct SystemClock: SentinelClock {
    public var now: Date { Date() }

    public let calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }
}

/// A clock whose "now" is fixed until a test advances it.
///
/// Not thread-safe by design: tests drive it from a single task.
public final class TestClock: SentinelClock, @unchecked Sendable {
    private var instant: Date
    public let calendar: Calendar

    public init(now: Date, timeZone: TimeZone = TimeZone(identifier: "UTC")!) {
        self.instant = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public var now: Date { instant }

    /// Move the clock forward by `interval` seconds.
    public func advance(by interval: TimeInterval) {
        instant = instant.addingTimeInterval(interval)
    }

    /// Jump the clock to an absolute instant.
    public func set(to date: Date) {
        instant = date
    }
}
