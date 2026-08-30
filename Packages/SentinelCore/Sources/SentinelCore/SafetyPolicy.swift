import Foundation

/// Hard limits on automatic resumes for a single target (CLAUDE.md section 7.2).
///
/// This type makes no decisions on its own — it is the configuration half.
/// `SafetyPolicy.evaluate` combines it with a `ResumeHistory`.
public struct SafetyLimits: Sendable, Equatable, Codable {
    /// Upper bound on automatic resumes per calendar day, per target.
    public var maxAutoResumesPerDay: Int
    /// Minimum gap between two resume attempts for the same target.
    public var minIntervalBetweenResumes: TimeInterval
    /// How many times the same stall may be retried before the app gives up and
    /// only notifies. Section 7.2: one attempt, a second if the stall recurs for
    /// the same reason, stop at the third.
    public var maxConsecutiveAttemptsPerStall: Int
    /// When true, detection still runs but nothing is ever sent; the intended
    /// action is logged instead (section 7.2, "Dry-run モード").
    public var dryRun: Bool

    public init(
        maxAutoResumesPerDay: Int = 12,
        minIntervalBetweenResumes: TimeInterval = 120,
        maxConsecutiveAttemptsPerStall: Int = 2,
        dryRun: Bool = false
    ) {
        self.maxAutoResumesPerDay = maxAutoResumesPerDay
        self.minIntervalBetweenResumes = minIntervalBetweenResumes
        self.maxConsecutiveAttemptsPerStall = maxConsecutiveAttemptsPerStall
        self.dryRun = dryRun
    }

    public static let `default` = SafetyLimits()
}

/// Mutable per-target record of what has been attempted.
public struct ResumeHistory: Sendable, Equatable {
    /// Timestamps of every resume the app has issued (including dry-run), newest
    /// last.
    public private(set) var attempts: [Date]
    /// `SessionState.kind` of the stall currently being retried, or `nil` if the
    /// last observation was not a stall.
    public private(set) var currentStallKind: String?
    /// Consecutive attempts made against `currentStallKind`.
    public private(set) var attemptsForCurrentStall: Int

    public init(
        attempts: [Date] = [],
        currentStallKind: String? = nil,
        attemptsForCurrentStall: Int = 0
    ) {
        self.attempts = attempts
        self.currentStallKind = currentStallKind
        self.attemptsForCurrentStall = attemptsForCurrentStall
    }

    /// Number of attempts on or after `dayStart`.
    public func attemptsSince(_ dayStart: Date) -> Int {
        attempts.filter { $0 >= dayStart }.count
    }

    public var lastAttempt: Date? { attempts.last }

    /// Call when a new stall is observed, before asking the policy. If the stall
    /// kind changed, the per-stall counter resets; a recurrence of the same kind
    /// keeps counting.
    public mutating func observeStall(kind: String) {
        if currentStallKind != kind {
            currentStallKind = kind
            attemptsForCurrentStall = 0
        }
    }

    /// Call when the target is seen to be progressing again — clears the
    /// per-stall retry counter so the next stall starts fresh.
    public mutating func observeRecovery() {
        currentStallKind = nil
        attemptsForCurrentStall = 0
    }

    /// Call right after a resume is issued (or would have been, in dry-run).
    public mutating func recordAttempt(at date: Date) {
        attempts.append(date)
        attemptsForCurrentStall += 1
    }
}

/// Why a resume was refused.
public enum ResumeDenyReason: String, Sendable, Equatable {
    /// The state is not one the app auto-resumes (approval, question, unknown…).
    case stateNotEligible
    /// The per-day cap for this target has been reached.
    case dailyCapReached
    /// Not enough time has passed since the last attempt.
    case cooldownActive
    /// This stall has already been retried the maximum number of times.
    case stallRetryLimitReached
}

/// The decision for a single resume opportunity.
public enum ResumeDecision: Sendable, Equatable {
    /// Safe to send the resume now.
    case allow
    /// Would be allowed, but dry-run is on: log the intended action only.
    case dryRun
    /// Do not send; notify according to the reason.
    case deny(ResumeDenyReason)
}

/// Applies `SafetyLimits` to a `ResumeHistory` for one resume opportunity.
public enum SafetyPolicy {
    public static func evaluate(
        state: SessionState,
        history: ResumeHistory,
        limits: SafetyLimits,
        now: Date,
        calendar: Calendar
    ) -> ResumeDecision {
        guard state.isAutoResumeEligible else {
            return .deny(.stateNotEligible)
        }

        let dayStart = calendar.startOfDay(for: now)
        if history.attemptsSince(dayStart) >= limits.maxAutoResumesPerDay {
            return .deny(.dailyCapReached)
        }

        if let last = history.lastAttempt,
           now.timeIntervalSince(last) < limits.minIntervalBetweenResumes {
            return .deny(.cooldownActive)
        }

        if history.attemptsForCurrentStall >= limits.maxConsecutiveAttemptsPerStall {
            return .deny(.stallRetryLimitReached)
        }

        return limits.dryRun ? .dryRun : .allow
    }
}
