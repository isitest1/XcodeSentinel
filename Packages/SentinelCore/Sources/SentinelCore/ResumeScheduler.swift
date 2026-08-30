import Foundation

/// A nightly (or custom) window during which the app notifies but never
/// resumes (CLAUDE.md section 7.3, "Quiet Hours").
public struct QuietHours: Sendable, Equatable, Codable {
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int

    public init(startHour: Int, startMinute: Int = 0, endHour: Int, endMinute: Int = 0) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    private var startMinutes: Int { startHour * 60 + startMinute }
    private var endMinutes: Int { endHour * 60 + endMinute }

    /// Whether `date` falls inside the window. Windows that cross midnight
    /// (start > end, e.g. 01:00 is written as 25:00? no — 23:00→07:00) are
    /// handled: such a window is "after start OR before end".
    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if startMinutes == endMinutes { return false } // empty / disabled
        if startMinutes < endMinutes {
            return minutes >= startMinutes && minutes < endMinutes
        } else {
            return minutes >= startMinutes || minutes < endMinutes
        }
    }

    /// The next instant at or after `date` when the window ends.
    public func end(after date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let todayEnd = calendar.date(
            byAdding: .minute, value: endMinutes, to: startOfDay
        ) ?? date
        if todayEnd > date { return todayEnd }
        return calendar.date(byAdding: .day, value: 1, to: todayEnd) ?? todayEnd
    }
}

/// One target waiting to be resumed.
public struct QueuedResume: Sendable, Equatable {
    public var targetID: UUID
    /// Lower runs first (CLAUDE.md section 5.2 / 7.3).
    public var priority: Int
    /// When the target was detected as stalled — tie-breaker, oldest first.
    public var stalledAt: Date
    /// When it entered the queue.
    public var enqueuedAt: Date

    public init(targetID: UUID, priority: Int, stalledAt: Date, enqueuedAt: Date) {
        self.targetID = targetID
        self.priority = priority
        self.stalledAt = stalledAt
        self.enqueuedAt = enqueuedAt
    }
}

/// What the caller should do when it asks the scheduler for work.
public enum ResumeDispatch: Sendable, Equatable {
    /// Start this target now, then call `markStarted`.
    case start(QueuedResume)
    /// Nothing is queued.
    case empty
    /// The concurrency cap is full; wait for a `markFinished`.
    case atCapacity
    /// Spacing gate: do not start anything before this instant.
    case waitSpacing(until: Date)
    /// Inside quiet hours: only notify until this instant.
    case waitQuietHours(until: Date)
}

/// The queue and pacing gate for automatic resumes. This is the ONLY component
/// that decides a resume may fire (CLAUDE.md sections 4.2 and 7.3), and it is a
/// plain value type so the dev-container tests can exercise every branch.
public struct ResumeScheduler: Sendable {
    public struct Configuration: Sendable, Equatable, Codable {
        /// Simultaneous in-flight resumes. Default 1, hard-clamped to 1...3.
        public var maxConcurrent: Int
        /// Minimum gap between two starts. Default 90s.
        public var minSpacingBetweenStarts: TimeInterval
        /// Optional quiet-hours window.
        public var quietHours: QuietHours?

        public init(
            maxConcurrent: Int = 1,
            minSpacingBetweenStarts: TimeInterval = 90,
            quietHours: QuietHours? = nil
        ) {
            self.maxConcurrent = min(3, max(1, maxConcurrent))
            self.minSpacingBetweenStarts = minSpacingBetweenStarts
            self.quietHours = quietHours
        }
    }

    public private(set) var configuration: Configuration
    public private(set) var queue: [QueuedResume] = []
    public private(set) var running: Set<UUID> = []
    public private(set) var lastStartAt: Date?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public mutating func updateConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
    }

    /// Add a target to the queue. No-op if it is already queued or running.
    /// Keeps the queue sorted by (priority asc, stalledAt asc).
    public mutating func enqueue(_ entry: QueuedResume) {
        guard !running.contains(entry.targetID) else { return }
        guard !queue.contains(where: { $0.targetID == entry.targetID }) else { return }
        queue.append(entry)
        queue.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.stalledAt < rhs.stalledAt
        }
    }

    /// Remove a target from the queue without starting it (e.g. it recovered on
    /// its own, or the user disabled it).
    public mutating func cancel(targetID: UUID) {
        queue.removeAll { $0.targetID == targetID }
    }

    /// Ask what to do now. Does not mutate state; call `markStarted` if it
    /// returns `.start`.
    public func nextDispatch(now: Date, calendar: Calendar) -> ResumeDispatch {
        guard let head = queue.first else { return .empty }

        if let quiet = configuration.quietHours, quiet.contains(now, calendar: calendar) {
            return .waitQuietHours(until: quiet.end(after: now, calendar: calendar))
        }

        if running.count >= configuration.maxConcurrent {
            return .atCapacity
        }

        if let last = lastStartAt {
            let ready = last.addingTimeInterval(configuration.minSpacingBetweenStarts)
            if now < ready { return .waitSpacing(until: ready) }
        }

        return .start(head)
    }

    /// Move a target from the queue to the running set and arm the spacing gate.
    public mutating func markStarted(targetID: UUID, now: Date) {
        queue.removeAll { $0.targetID == targetID }
        running.insert(targetID)
        lastStartAt = now
    }

    /// Remove a target from the running set (its resume attempt concluded,
    /// success or failure).
    public mutating func markFinished(targetID: UUID) {
        running.remove(targetID)
    }

    public var isIdle: Bool { queue.isEmpty && running.isEmpty }
}
