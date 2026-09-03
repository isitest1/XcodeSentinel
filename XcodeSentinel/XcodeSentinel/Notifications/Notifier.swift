import Foundation
import SentinelCore
import UserNotifications

/// Raises a local notification and optionally sends a webhook.
/// Content is state + target name only — never chat text (CLAUDE.md §8.2).
public struct Notifier: Sendable {
    private let webhook: WebhookSender?

    public init(webhook: WebhookSender? = nil) {
        self.webhook = webhook
    }

    public func notify(targetName: String, line: String) async {
        await postLocal(title: "[\(targetName)]", body: line)
        try? await webhook?.send(targetName: targetName, line: line)
    }

    private func postLocal(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
