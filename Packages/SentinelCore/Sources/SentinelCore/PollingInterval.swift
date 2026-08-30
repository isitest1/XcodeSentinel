import Foundation

/// How often to re-check a target, as a function of its current state.
///
/// Values are from CLAUDE.md section 6.4. The interval is deliberately not a
/// fixed number: a limited session is polled slowly until its reset time
/// approaches, then quickly.
public enum PollingInterval {
    /// Seconds until the next detection pass.
    public static func seconds(
        for state: SessionState,
        now: Date,
        consecutiveUnknownCount: Int = 0
    ) -> TimeInterval {
        switch state {
        case .working:
            return 30
        case .awaitingContinue:
            return 10
        case let .sessionLimited(resetAt):
            guard let resetAt else { return 5 * 60 }
            let tenMinutesBefore = resetAt.addingTimeInterval(-10 * 60)
            return now < tenMinutesBefore ? 5 * 60 : 30
        case .weeklyLimited:
            return 30 * 60
        case .unknown:
            return 60
        case .idle, .completed, .errored, .awaitingApproval, .awaitingUserAnswer:
            // Not covered explicitly by section 6.4. These are notify-only
            // states with nothing to poll for aggressively; use a calm cadence.
            return 60
        }
    }

    /// After this many consecutive `unknown` results, monitoring of the target
    /// is paused and the user is notified (CLAUDE.md section 6.4).
    public static let unknownPauseThreshold = 3

    public static func shouldPauseAfterUnknown(consecutiveUnknownCount: Int) -> Bool {
        consecutiveUnknownCount >= unknownPauseThreshold
    }
}
