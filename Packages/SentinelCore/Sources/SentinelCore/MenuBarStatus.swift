import Foundation

/// The single glyph shown in the menu bar, aggregated across every enabled
/// target (CLAUDE.md section 16 item 4).
public enum MenuBarStatus: String, Sendable, Equatable, CaseIterable {
    /// Nothing needs attention (idle / completed / no targets).
    case ok
    /// At least one target is actively generating.
    case working
    /// At least one target is stalled waiting on the user (approval / question
    /// / continue) but none is limited or errored.
    case waiting
    /// At least one target is session- or weekly-limited.
    case limited
    /// At least one target ended with an error.
    case error

    /// SF Symbol name for the menu-bar image.
    public var symbolName: String {
        switch self {
        case .ok: return "checkmark.circle"
        case .working: return "gearshape.2.fill"
        case .waiting: return "pause.circle.fill"
        case .limited: return "hourglass"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    /// Priority when several targets disagree — higher wins.
    private var rank: Int {
        switch self {
        case .ok: return 0
        case .working: return 1
        case .waiting: return 2
        case .limited: return 3
        case .error: return 4
        }
    }

    private static func status(for state: SessionState) -> MenuBarStatus {
        switch state {
        case .idle, .completed, .unknown:
            return .ok
        case .working:
            return .working
        case .awaitingContinue, .awaitingApproval, .awaitingUserAnswer:
            return .waiting
        case .sessionLimited, .weeklyLimited:
            return .limited
        case .errored:
            return .error
        }
    }

    /// Combine the states of all monitored targets into one status.
    public static func aggregate(_ states: [SessionState]) -> MenuBarStatus {
        states.map(status(for:)).max(by: { $0.rank < $1.rank }) ?? .ok
    }
}
