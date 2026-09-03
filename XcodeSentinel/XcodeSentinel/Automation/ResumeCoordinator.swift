import ApplicationServices
import Foundation
import SentinelCore

/// Drives ResumeOrchestrator: feeds detection results, executes effects
/// (notify / perform-resume / reschedule / pause). All policy lives in
/// SentinelCore; this type only performs macOS side-effects.
@MainActor
public final class ResumeCoordinator {
    private var orchestrator: ResumeOrchestrator
    /// Replaceable so AppModel can swap in a webhook-enabled Notifier when the
    /// user saves a new webhook configuration in Settings.
    public var notifier: Notifier
    private let resumeController = ResumeController()
    private let calendar: Calendar

    /// Returns the live AXUIElement for the given target, or nil if unresolvable.
    /// Called asynchronously so the caller can hop to @AccessibilityActor.
    public var windowForTarget: (UUID) async -> AXUIElement? = { _ in nil }
    /// Returns the human-readable display name for a target UUID.
    public var targetNameForID: (UUID) -> String = { id in String(id.uuidString.prefix(8)) }
    public var scheduleRecheck: (UUID, Date) -> Void = { _, _ in }
    public var scheduleQueuePump: (Date) -> Void = { _ in }
    public var onMonitoringPaused: (UUID, MonitorPauseReason) -> Void = { _, _ in }
    public var onMonitoringResumed: (UUID) -> Void = { _ in }

    // MARK: - Exposed settings (forwarded to the internal orchestrator)

    public var limits: SafetyLimits {
        get { orchestrator.limits }
        set { orchestrator.limits = newValue }
    }

    public init(
        scheduler: ResumeScheduler = .init(),
        limits: SafetyLimits = .default,
        notifier: Notifier = .init(),
        calendar: Calendar = .current
    ) {
        self.orchestrator = ResumeOrchestrator(scheduler: scheduler, limits: limits)
        self.notifier = notifier
        self.calendar = calendar
    }

    public func handle(_ observation: TargetObservation, now: Date = Date()) async {
        await run(orchestrator.ingest(observation, now: now, calendar: calendar), now: now)
        await run(orchestrator.pump(now: now, calendar: calendar), now: now)
    }

    private func run(_ effects: [OrchestratorEffect], now: Date) async {
        for effect in effects {
            switch effect {
            case let .notify(note):
                await notifier.notify(
                    targetName: targetNameForID(note.targetID),
                    line: Self.line(for: note.reason)
                )
            case let .recheck(id, at):
                scheduleRecheck(id, at)
            case let .recheckQueue(at):
                scheduleQueuePump(at)
            case let .pauseMonitoring(id, reason):
                onMonitoringPaused(id, reason)
            case let .resumeMonitoring(id):
                onMonitoringResumed(id)
            case let .performResume(id, prompt, dryRun):
                await performResume(targetID: id, prompt: prompt, dryRun: dryRun, now: now)
            }
        }
    }

    private func performResume(targetID: UUID, prompt: String, dryRun: Bool, now: Date) async {
        let outcome: ResumeSendOutcome
        if let window = await windowForTarget(targetID) {
            switch await resumeController.resume(window: window, prompt: prompt, dryRun: dryRun) {
            case .sent:                   outcome = .sent
            case .dryRun:                 outcome = .dryRun
            case .couldNotFindInput:      outcome = .couldNotFindInput
            case .couldNotConfirmProgress: outcome = .couldNotConfirmProgress
            }
        } else {
            outcome = .couldNotFindInput
        }
        await run(orchestrator.recordSendOutcome(targetID: targetID, outcome: outcome, now: now), now: now)
    }

    public func resumeMonitoring(_ targetID: UUID, now: Date = Date()) async {
        await run(orchestrator.resumeMonitoring(targetID: targetID), now: now)
    }

    /// Drives the resume queue without an observation. Called by AppModel when
    /// the coordinator previously emitted a `recheckQueue(at:)` effect.
    public func pumpQueue(now: Date = Date()) async {
        await run(orchestrator.pump(now: now, calendar: calendar), now: now)
    }

    static func line(for reason: OrchestratorNotification.Reason) -> String {
        switch reason {
        case let .sessionLimit(resumeAt):
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return "Session limit reached. Auto-resume at \(f.string(from: resumeAt))."
        case .weeklyLimit:        return "Weekly limit reached. Auto-resume is paused."
        case .awaitingApproval:   return "Stopped: waiting for your approval. No action taken."
        case .awaitingUserAnswer: return "Stopped: Claude asked a question. No action taken."
        case .errored:            return "Stopped with an error. No action taken."
        case .resumedWorking:     return "Resumed automatically. Working."
        case .resumeFailedNeedsAttention: return "Auto-resume did not take. Needs your attention."
        case let .monitoringPaused(r): return "Monitoring paused (\(r.rawValue))."
        case .retryLimitReached:  return "Stopped again for the same reason. Auto-resume paused."
        }
    }
}
