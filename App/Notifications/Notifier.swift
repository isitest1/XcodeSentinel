// macOS only. Build on the host with Xcode (see App/README.md).
#if canImport(UserNotifications) && os(macOS)
import Foundation
import SentinelCore
import UserNotifications

/// One place to raise a notification, local and (optionally) remote. Message
/// bodies are English and one line (CLAUDE.md section 8.1). They contain only
/// the target name, state and time — never chat text or code (section 8.2).
public struct Notifier {
    private let webhook: WebhookSender?

    public init(webhook: WebhookSender? = nil) {
        self.webhook = webhook
    }

    public func notify(targetName: String, line: String) async {
        await postLocal(title: targetName, body: line)
        try? await webhook?.send(targetName: targetName, line: line)
    }

    /// Builds the standard one-liner for a state.
    public static func line(for state: SessionState, targetName: String, nextActionAt: Date?) -> String {
        let when = nextActionAt.map { " Auto-resume at \(Self.hhmm($0))." } ?? ""
        switch state {
        case .sessionLimited: return "Session limit reached.\(when)"
        case .weeklyLimited: return "Weekly limit reached. Auto-resume is paused."
        case .awaitingApproval: return "Stopped: waiting for your approval. No action taken."
        case .awaitingUserAnswer: return "Stopped: Claude asked a question. No action taken."
        case .awaitingContinue: return "Waiting on \"Continue\".\(when)"
        case .errored: return "Stopped with an error. No action taken."
        case .working: return "Resumed automatically. Working."
        default: return "State: \(state.kind)."
        }
    }

    private static func hhmm(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func postLocal(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = "[\(title)]"
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
#endif
