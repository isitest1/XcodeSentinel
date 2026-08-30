// macOS only. Build on the host with Xcode (see App/README.md).
#if canImport(ApplicationServices) && os(macOS)
import ApplicationServices
import Foundation
import SentinelCore

/// Drives the `SentinelCore.ResumeOrchestrator`: feeds it each detection cycle,
/// executes the effects it returns (notify / perform resume / (re)schedule /
/// pause), and reports send outcomes back. All policy lives in SentinelCore;
/// this type only performs side effects.
@MainActor
public final class ResumeCoordinator {
    private var orchestrator: ResumeOrchestrator
    private let notifier: Notifier
    private let resumeController = ResumeController()
    private let calendar: Calendar

    /// Live AX window handles, kept up to date by `TargetBinder`.
    public var windowForTarget: (UUID) -> AXUIElement? = { _ in nil }
    /// Called to (re)arm the per-target polling timer.
    public var scheduleRecheck: (UUID, Date) -> Void = { _, _ in }
    public var scheduleQueuePump: (Date) -> Void = { _ in }
    public var onMonitoringPaused: (UUID, MonitorPauseReason) -> Void = { _, _ in }
    public var onMonitoringResumed: (UUID) -> Void = { _ in }

    public init(
        scheduler: ResumeScheduler = .init(),
        limits: SafetyLimits = .default,
        notifier: Notifier = Notifier(),
        calendar: Calendar = .current
    ) {
        self.orchestrator = ResumeOrchestrator(scheduler: scheduler, limits: limits)
        self.notifier = notifier
        self.calendar = calendar
    }

    /// Feed one detection result for a target.
    public func handle(_ observation: TargetObservation, now: Date = Date()) async {
        await run(orchestrator.ingest(observation, now: now, calendar: calendar), now: now)
        await run(orchestrator.pump(now: now, calendar: calendar), now: now)
    }

    private func run(_ effects: [OrchestratorEffect], now: Date) async {
        for effect in effects {
            switch effect {
            case let .notify(note):
                await notifier.notify(
                    targetName: name(note.targetID),
                    line: Self.line(for: note.reason)
                )
            case let .recheck(targetID, at):
                scheduleRecheck(targetID, at)
            case let .recheckQueue(at):
                scheduleQueuePump(at)
            case let .pauseMonitoring(targetID, reason):
                onMonitoringPaused(targetID, reason)
            case let .resumeMonitoring(targetID):
                onMonitoringResumed(targetID)
            case let .performResume(targetID, prompt, dryRun):
                await performResume(targetID: targetID, prompt: prompt, dryRun: dryRun, now: now)
            }
        }
    }

    private func performResume(targetID: UUID, prompt: String, dryRun: Bool, now: Date) async {
        let outcome: ResumeSendOutcome
        if let window = windowForTarget(targetID) {
            switch await resumeController.resume(window: window, prompt: prompt, dryRun: dryRun) {
            case .sent: outcome = .sent
            case .dryRun: outcome = .dryRun
            case .couldNotFindInput: outcome = .couldNotFindInput
            case .couldNotConfirmProgress: outcome = .couldNotConfirmProgress
            }
        } else {
            outcome = .couldNotFindInput
        }
        await run(
            orchestrator.recordSendOutcome(targetID: targetID, outcome: outcome, now: now),
            now: now
        )
    }

    public func resumeMonitoring(_ targetID: UUID, now: Date = Date()) async {
        await run(orchestrator.resumeMonitoring(targetID: targetID), now: now)
    }

    // MARK: - Presentation

    private func name(_ id: UUID) -> String { id.uuidString.prefix(8).description }

    static func line(for reason: OrchestratorNotification.Reason) -> String {
        switch reason {
        case let .sessionLimit(resumeAt):
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return "Session limit reached. Auto-resume at \(f.string(from: resumeAt))."
        case .weeklyLimit: return "Weekly limit reached. Auto-resume is paused."
        case .awaitingApproval: return "Stopped: waiting for your approval. No action taken."
        case .awaitingUserAnswer: return "Stopped: Claude asked a question. No action taken."
        case .errored: return "Stopped with an error. No action taken."
        case .resumedWorking: return "Resumed automatically. Working."
        case .resumeFailedNeedsAttention: return "Auto-resume did not take. Needs your attention."
        case let .monitoringPaused(r): return "Monitoring paused (\(r.rawValue)ically)."
        case .retryLimitReached: return "Stopped again for the same reason. Auto-resume paused."
        }
    }
}
#endif
