// macOS only. Build on the host with Xcode (see App/README.md).
#if canImport(ApplicationServices) && os(macOS)
import ApplicationServices
import Foundation
import SentinelCore

/// Performs a single resume against one Xcode window: put the resume prompt into
/// the chat field, press Send, then confirm the session moved to `.working`
/// within 15s (CLAUDE.md section 7.1). Never called directly by the monitor
/// loop — only via `ResumeScheduler` dispatch.
@AccessibilityActor
public struct ResumeController {
    public enum Outcome: Sendable, Equatable {
        case sent
        case couldNotFindInput
        case couldNotConfirmProgress
        case dryRun
    }

    public init() {}

    public func resume(
        window: AXUIElement,
        prompt: String,
        dryRun: Bool
    ) async -> Outcome {
        guard !dryRun else {
            // TODO(host): log the intended action, do not touch the UI.
            return .dryRun
        }
        // TODO(host):
        //  1. locate the chat AXTextArea/AXTextField in `window`
        //  2. set AXValue to `prompt`
        //  3. AXPress the Send AXButton; fall back to Return only if focused
        //  4. poll for `.working` for up to 15s; return .couldNotConfirmProgress otherwise
        //  Never synthesize keystrokes unless the target window holds focus.
        return .couldNotFindInput
    }
}
#endif
