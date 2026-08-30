import Foundation

/// The detected state of a single Claude coding session inside an Xcode window.
///
/// The cases are defined in CLAUDE.md section 6.1 and must not be reinterpreted.
/// `unknown` means detection failed; it must never be treated as `working`
/// (CLAUDE.md sections 6.2 and 17).
public enum SessionState: Sendable, Equatable {
    /// No active task.
    case idle
    /// Claude is generating text or running tools.
    case working
    /// A "Continue" affordance is present (output was truncated).
    case awaitingContinue
    /// The rolling 5-hour session limit was hit. `resetAt` is the parsed reset
    /// time when the UI exposed one, otherwise `nil`.
    case sessionLimited(resetAt: Date?)
    /// The weekly limit was hit. Waiting 5 hours does not clear this.
    case weeklyLimited(resetAt: Date?)
    /// A permission / tool-approval prompt is waiting for the user.
    case awaitingApproval
    /// Claude asked the user a question and is waiting for an answer.
    case awaitingUserAnswer
    /// The session ended with an error.
    case errored(message: String)
    /// The task finished normally.
    case completed
    /// Detection could not classify the session.
    case unknown
}

extension SessionState {
    /// Stable identifier used in logs, metrics and notifications. Never includes
    /// the `errored` message, so it is safe to send to a webhook.
    public var kind: String {
        switch self {
        case .idle: return "idle"
        case .working: return "working"
        case .awaitingContinue: return "awaitingContinue"
        case .sessionLimited: return "sessionLimited"
        case .weeklyLimited: return "weeklyLimited"
        case .awaitingApproval: return "awaitingApproval"
        case .awaitingUserAnswer: return "awaitingUserAnswer"
        case .errored: return "errored"
        case .completed: return "completed"
        case .unknown: return "unknown"
        }
    }

    /// Whether the scheduler is even allowed to consider an automatic resume for
    /// this state. Approval prompts, questions, and `unknown` are deliberately
    /// excluded (CLAUDE.md sections 7.2 and 17): those are notify-only.
    public var isAutoResumeEligible: Bool {
        switch self {
        case .awaitingContinue, .sessionLimited, .weeklyLimited:
            return true
        case .idle, .working, .completed,
             .awaitingApproval, .awaitingUserAnswer, .errored, .unknown:
            return false
        }
    }

    /// A state the user probably wants to hear about while away from the Mac.
    public var isStall: Bool {
        switch self {
        case .awaitingContinue, .sessionLimited, .weeklyLimited,
             .awaitingApproval, .awaitingUserAnswer, .errored:
            return true
        case .idle, .working, .completed, .unknown:
            return false
        }
    }

    /// Whether this state represents forward progress (used to confirm that a
    /// resume attempt actually took, CLAUDE.md section 7.1 step 4).
    public var isProgressing: Bool {
        self == .working
    }

    /// The reset instant carried by a limit state, if any.
    public var resetAt: Date? {
        switch self {
        case let .sessionLimited(resetAt), let .weeklyLimited(resetAt):
            return resetAt
        default:
            return nil
        }
    }
}
