import Foundation

/// One detection cycle for a single target, handed to the orchestrator.
public struct TargetObservation: Sendable, Equatable {
    public var targetID: UUID
    /// Lower runs first in the resume queue.
    public var priority: Int
    /// Text to send when resuming this target.
    public var resumePrompt: String
    /// The classification produced by `DetectionEngine` this cycle.
    public var detection: DetectionEngine.Result

    public init(
        targetID: UUID,
        priority: Int,
        resumePrompt: String,
        detection: DetectionEngine.Result
    ) {
        self.targetID = targetID
        self.priority = priority
        self.resumePrompt = resumePrompt
        self.detection = detection
    }
}

/// The result the app reports after actually performing a resume send.
public enum ResumeSendOutcome: Sendable, Equatable {
    case sent
    case couldNotFindInput
    case couldNotConfirmProgress
    case dryRun
}

/// Why monitoring of a target was paused.
public enum MonitorPauseReason: String, Sendable, Equatable {
    case repeatedUnknown
    case retryBudgetExhausted
}

/// A user-facing notification the app should raise. Carries no chat text or
/// code — only the target, a reason, and an optional time (CLAUDE.md 8.2).
public struct OrchestratorNotification: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case sessionLimit(resumeAt: Date)
        case weeklyLimit
        case awaitingApproval
        case awaitingUserAnswer
        case errored
        case resumedWorking
        case resumeFailedNeedsAttention
        case monitoringPaused(MonitorPauseReason)
        case retryLimitReached
    }
    public var targetID: UUID
    public var reason: Reason
}

/// Something the app must carry out. The orchestrator itself never touches the
/// AX API, the network, or notification centre — it only decides.
public enum OrchestratorEffect: Sendable, Equatable {
    /// Raise this notification (local + optional webhook).
    case notify(OrchestratorNotification)
    /// Perform an actual resume send against the target's window. Report back
    /// via `recordSendOutcome`. `dryRun` means: log the intended action only.
    case performResume(targetID: UUID, prompt: String, dryRun: Bool)
    /// Schedule the next detection pass for this target at `at`.
    case recheck(targetID: UUID, at: Date)
    /// Ask the orchestrator again (via `pump`) no later than `at` — the queue is
    /// holding on spacing, quiet hours or a limit reset time.
    case recheckQueue(at: Date)
    /// Stop polling this target until the user intervenes.
    case pauseMonitoring(targetID: UUID, MonitorPauseReason)
    /// Resume polling a previously paused target.
    case resumeMonitoring(targetID: UUID)
}

/// Ties detection, safety limits and the resume queue into one testable
/// pipeline (CLAUDE.md M3). The app calls:
///   - `ingest(_:now:calendar:)` every detection cycle,
///   - `pump(now:calendar:)` to get the next queued resume to perform,
///   - `recordSendOutcome(...)` after performing one,
/// and executes the returned effects.
public struct ResumeOrchestrator: Sendable {
    public var scheduler: ResumeScheduler
    public var limits: SafetyLimits
    public private(set) var histories: [UUID: ResumeHistory] = [:]
    public private(set) var unknownStreak: [UUID: Int] = [:]
    public private(set) var pausedTargets: Set<UUID> = []
    /// Prompts remembered from the last observation, so `pump` can emit
    /// `performResume` with the right text.
    private var prompts: [UUID: String] = [:]

    public init(
        scheduler: ResumeScheduler = .init(),
        limits: SafetyLimits = .default
    ) {
        self.scheduler = scheduler
        self.limits = limits
    }

    private func history(for id: UUID) -> ResumeHistory {
        histories[id] ?? ResumeHistory()
    }

    // MARK: - Ingest one detection cycle

    public mutating func ingest(
        _ observation: TargetObservation,
        now: Date,
        calendar: Calendar
    ) -> [OrchestratorEffect] {
        let id = observation.targetID
        let state = observation.detection.state
        prompts[id] = observation.resumePrompt

        // Track the consecutive-unknown streak (CLAUDE.md 6.4).
        if case .unknown = state {
            let streak = (unknownStreak[id] ?? 0) + 1
            unknownStreak[id] = streak
            if PollingInterval.shouldPauseAfterUnknown(consecutiveUnknownCount: streak) {
                pausedTargets.insert(id)
                scheduler.cancel(targetID: id)
                return [
                    .notify(.init(targetID: id, reason: .monitoringPaused(.repeatedUnknown))),
                    .pauseMonitoring(targetID: id, .repeatedUnknown),
                ]
            }
            return [.recheck(targetID: id, at: now.addingTimeInterval(
                PollingInterval.seconds(for: state, now: now)
            ))]
        }
        unknownStreak[id] = 0

        var effects: [OrchestratorEffect] = []

        switch state {
        case .working, .idle, .completed:
            var h = history(for: id)
            h.observeRecovery()
            histories[id] = h
            scheduler.cancel(targetID: id)

        case .awaitingApproval:
            recordStall(id: id, kind: state.kind)
            effects.append(.notify(.init(targetID: id, reason: .awaitingApproval)))

        case .awaitingUserAnswer:
            recordStall(id: id, kind: state.kind)
            effects.append(.notify(.init(targetID: id, reason: .awaitingUserAnswer)))

        case .errored:
            recordStall(id: id, kind: state.kind)
            effects.append(.notify(.init(targetID: id, reason: .errored)))

        case .awaitingContinue:
            effects.append(contentsOf: considerResume(
                observation: observation, state: state, limitKind: nil, now: now, calendar: calendar
            ))

        case .sessionLimited:
            let resumeAt = ResetTimeParser.retryTime(
                detectedAt: now, limit: .session, parsed: observation.detection.resetParse
            )
            effects.append(.notify(.init(targetID: id, reason: .sessionLimit(resumeAt: resumeAt))))
            effects.append(contentsOf: considerResume(
                observation: observation, state: state, limitKind: .session,
                notBefore: resumeAt, now: now, calendar: calendar
            ))

        case .weeklyLimited:
            effects.append(.notify(.init(targetID: id, reason: .weeklyLimit)))
            let resumeAt = ResetTimeParser.retryTime(
                detectedAt: now, limit: .weekly, parsed: observation.detection.resetParse
            )
            effects.append(contentsOf: considerResume(
                observation: observation, state: state, limitKind: .weekly,
                notBefore: resumeAt, now: now, calendar: calendar
            ))

        case .unknown:
            break // handled above
        }

        effects.append(.recheck(
            targetID: id,
            at: now.addingTimeInterval(PollingInterval.seconds(for: state, now: now))
        ))
        return effects
    }

    private mutating func recordStall(id: UUID, kind: String) {
        var h = history(for: id)
        h.observeStall(kind: kind)
        histories[id] = h
    }

    /// Common path for auto-resume-eligible states: check the safety policy,
    /// then either queue the resume or explain why not.
    private mutating func considerResume(
        observation: TargetObservation,
        state: SessionState,
        limitKind: LimitKind?,
        notBefore: Date? = nil,
        now: Date,
        calendar: Calendar
    ) -> [OrchestratorEffect] {
        let id = observation.targetID
        recordStall(id: id, kind: state.kind)

        let decision = SafetyPolicy.evaluate(
            state: state, history: history(for: id),
            limits: limits, now: now, calendar: calendar
        )
        switch decision {
        case .deny(.stateNotEligible):
            return []
        case .deny(.stallRetryLimitReached):
            return [.notify(.init(targetID: id, reason: .retryLimitReached))]
        case .deny(.dailyCapReached), .deny(.cooldownActive):
            // Try again later; the recheck the caller appends covers this.
            return []
        case .allow, .dryRun:
            scheduler.enqueue(QueuedResume(
                targetID: id,
                priority: observation.priority,
                stalledAt: now,
                enqueuedAt: now,
                notBefore: notBefore
            ))
            return []
        }
    }

    // MARK: - Pump the queue

    /// Ask the scheduler for the next resume to perform. Returns at most one
    /// `performResume` effect, plus a `recheck` when the app should ask again
    /// later.
    public mutating func pump(now: Date, calendar: Calendar) -> [OrchestratorEffect] {
        switch scheduler.nextDispatch(now: now, calendar: calendar) {
        case .empty:
            return []
        case let .start(entry):
            scheduler.markStarted(targetID: entry.targetID, now: now)
            let prompt = prompts[entry.targetID] ?? "Please continue from where you stopped."
            return [.performResume(targetID: entry.targetID, prompt: prompt, dryRun: limits.dryRun)]
        case let .waitSpacing(until), let .waitQuietHours(until), let .waitUntilReady(until):
            return [.recheckQueue(at: until)]
        case .atCapacity:
            return []
        }
    }

    // MARK: - Report a completed send

    public mutating func recordSendOutcome(
        targetID id: UUID,
        outcome: ResumeSendOutcome,
        now: Date
    ) -> [OrchestratorEffect] {
        var h = history(for: id)
        h.recordAttempt(at: now)
        histories[id] = h
        scheduler.markFinished(targetID: id)

        switch outcome {
        case .sent, .dryRun:
            // Success is confirmed by a later `.working` observation; nothing to
            // announce yet beyond the resume itself.
            return [.recheck(targetID: id, at: now.addingTimeInterval(15))]
        case .couldNotFindInput, .couldNotConfirmProgress:
            return [.notify(.init(targetID: id, reason: .resumeFailedNeedsAttention))]
        }
    }

    /// The app calls this when a paused target should be watched again (the user
    /// fixed whatever caused the pause).
    public mutating func resumeMonitoring(targetID id: UUID) -> [OrchestratorEffect] {
        pausedTargets.remove(id)
        unknownStreak[id] = 0
        return [.resumeMonitoring(targetID: id)]
    }
}
