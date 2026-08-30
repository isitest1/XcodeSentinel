// macOS only. Build on the host with Xcode (see App/README.md).
#if os(macOS)
import Foundation

/// Generic outbound webhook for away-from-Mac notifications (CLAUDE.md 8.2).
/// The payload carries only the target name, a short status line and a
/// timestamp. It must never include chat text or source code.
public struct WebhookSender {
    public enum Preset: String, CaseIterable, Sendable {
        case ntfy, pushover, discord, slack, custom
    }

    public var endpoint: URL
    public var preset: Preset
    /// For `.custom`: a JSON template where `{{title}}`, `{{message}}` and
    /// `{{timestamp}}` are substituted.
    public var customTemplate: String?

    public init(endpoint: URL, preset: Preset, customTemplate: String? = nil) {
        self.endpoint = endpoint
        self.preset = preset
        self.customTemplate = customTemplate
    }

    public func send(targetName: String, line: String, now: Date = Date()) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let title = "XcodeSentinel — \(targetName)"
        let ts = ISO8601DateFormatter().string(from: now)

        switch preset {
        case .ntfy:
            request.setValue(title, forHTTPHeaderField: "Title")
            request.httpBody = Data(line.utf8)
        case .slack, .discord:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["text": "*\(title)*\n\(line)"]
            )
        case .pushover:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["title": title, "message": line]
            )
        case .custom:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = (customTemplate ?? #"{"title":"{{title}}","message":"{{message}}"}"#)
                .replacingOccurrences(of: "{{title}}", with: title)
                .replacingOccurrences(of: "{{message}}", with: line)
                .replacingOccurrences(of: "{{timestamp}}", with: ts)
            request.httpBody = Data(body.utf8)
        }

        _ = try await URLSession.shared.data(for: request)
    }
}
#endif
